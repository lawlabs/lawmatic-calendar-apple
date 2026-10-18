import Combine
import EventKit
import Foundation
import Network
import Observation
#if os(macOS)
import AppKit
#endif

/// Источник провайдеров для синхронизации. Абстракция над `ProviderRegistry`,
/// чтобы координатор можно было тестировать с mock-провайдерами.
@MainActor
protocol CalendarProviderResolving: AnyObject {
    var enabledProviders: [any CalendarProvider] { get }
    func provider(_ id: ProviderID) -> (any CalendarProvider)?
}

extension ProviderRegistry: CalendarProviderResolving {}

/// Оркестрация синхронизации: pull → LWW merge → push, для каждого
/// включённого провайдера. Состояние (события, календари, очередь удалений)
/// живёт в `EventRepository`; координатор его читает и изменяет.
///
/// Синхронизация идёт сама, как в Календаре Apple:
/// - локальная правка уходит в свой аккаунт через `uploadDelay` после
///   сохранения (`scheduleUploadOfLocalChanges()`);
/// - изменения с серверов подтягиваются при запуске, при возврате в
///   приложение, раз в `automaticRefreshInterval`, после сна и когда снова
///   появилась сеть; Apple Calendar — ещё и по уведомлениям EventKit;
/// - вручную — только «Вид → Обновить календари» (⌘R).
@Observable
@MainActor
final class CalendarSyncCoordinator {
    private(set) var syncingProviderIDs: Set<ProviderID> = []
    /// Что сейчас делает синхронизация — для индикатора на панели инструментов.
    private(set) var progressText: String?
    /// Ошибки для значка на панели инструментов. Собирается из ошибок
    /// аккаунтов; «Скрыть» обнуляет его, следующий сбой покажет снова.
    var syncError: IdentifiableMessage?

    struct MassDeletionRequest: Equatable {
        let providerID: ProviderID
        let count: Int
    }

    /// Больше стольких удалений за один прогон одного провайдера не уходит на
    /// сервер без явного подтверждения: это либо осознанное массовое действие,
    /// либо ошибка — и во втором случае цена слишком высока.
    static let massDeletionThreshold = 20
    /// Очередь удалений, которая ждёт подтверждения пользователя.
    private(set) var pendingMassDeletion: MassDeletionRequest?
    @ObservationIgnored private var confirmedMassDeletionProviders: Set<ProviderID> = []

    /// Через сколько после сохранения правка уходит на сервер: серия правок
    /// подряд (перетаскивание, набор в инспекторе) уходит одним прогоном.
    @ObservationIgnored var uploadDelay: Duration = .seconds(2)
    /// Как часто подтягивать изменения, пока приложение открыто.
    static let automaticRefreshInterval: TimeInterval = 5 * 60
    /// Черновик нового события в инспекторе: пока его не сохранили, на сервер
    /// он не уходит.
    @ObservationIgnored var draftEventID: UUID?
    /// Аккаунты, в которые сейчас нельзя отправлять правки: выключены в
    /// настройках или потеряли доступ. Их календари только для чтения.
    private(set) var unavailableProviderIDs: Set<ProviderID> = []
    @ObservationIgnored private var providerObservers: [AnyCancellable] = []

    @ObservationIgnored private let repository: EventRepository
    @ObservationIgnored private let providers: any CalendarProviderResolving
    /// Последняя ошибка каждого аккаунта; успешный прогон аккаунта её снимает.
    @ObservationIgnored private var failures: [ProviderID: String] = [:]
    /// Аккаунты, которым нужен ещё один проход: правку сохранили, пока шла
    /// их синхронизация, и в текущий проход она могла не попасть.
    @ObservationIgnored private var rerunProviderIDs: Set<ProviderID> = []
    @ObservationIgnored private var uploadTasks: [ProviderID: Task<Void, Never>] = [:]
    @ObservationIgnored private var automaticTasks: [Task<Void, Never>] = []

    /// За сколько до конца окна первичной выборки делать полный ресинк.
    static let syncWindowRefreshThreshold: TimeInterval = 180 * 24 * 3600

    init(repository: EventRepository, providers: any CalendarProviderResolving) {
        self.repository = repository
        self.providers = providers
        unavailableProviderIDs = currentUnavailableProviderIDs()
        for providerID in ProviderID.allCases {
            guard let provider = providers.provider(providerID) else { continue }
            // objectWillChange приходит до изменения — пересчитываем следующим ходом.
            providerObservers.append(provider.stateChanges.sink { [weak self] in
                Task { @MainActor in self?.updateProviderAvailability() }
            })
        }
    }

    /// Можно ли сейчас отправлять правки в аккаунт.
    func isAvailable(_ providerID: ProviderID) -> Bool {
        !unavailableProviderIDs.contains(providerID)
    }

    /// Неотправленные правки и удаления по аккаунтам, которые сейчас
    /// недоступны: им нужно предупреждение, сами они не уйдут.
    var unsentChangeCounts: [ProviderID: Int] {
        guard !unavailableProviderIDs.isEmpty else { return [:] }
        var counts: [ProviderID: Int] = [:]
        for event in repository.events where event.syncState == .pendingUpload && event.id != draftEventID {
            if let providerID = event.externalProvider, unavailableProviderIDs.contains(providerID) {
                counts[providerID, default: 0] += 1
            }
        }
        for deletion in repository.pendingDeletions where unavailableProviderIDs.contains(deletion.remoteRef.providerID) {
            counts[deletion.remoteRef.providerID, default: 0] += 1
        }
        return counts
    }

    var isSyncing: Bool { !syncingProviderIDs.isEmpty }

    /// Когда все включённые аккаунты в последний раз прошли синхронизацию
    /// без ошибок; `nil`, если какой-то ещё не проходил.
    var lastSuccessfulSyncDate: Date? {
        let dates = providers.enabledProviders.map(\.lastSyncDate)
        guard !dates.isEmpty, !dates.contains(nil) else { return nil }
        return dates.compactMap { $0 }.min()
    }

    // MARK: - Публичные входы

    /// Пользователь подтвердил массовое удаление: следующий прогон отправит очередь.
    func confirmMassDeletion(for providerID: ProviderID) {
        confirmedMassDeletionProviders.insert(providerID)
        pendingMassDeletion = nil
    }

    /// Отменить накопленные удаления: tombstones снимаются, на сервере ничего не
    /// трогается, а локальные копии вернёт следующее чтение ленты.
    func discardQueuedDeletions(for providerID: ProviderID) {
        repository.pendingDeletions.removeAll { $0.remoteRef.providerID == providerID }
        repository.save(.pendingDeletions)
        pendingMassDeletion = nil
        confirmedMassDeletionProviders.remove(providerID)
    }

    /// «Обновить календари» (⌘R) и «Повторить»: все включённые аккаунты сейчас.
    func syncAllProviders() async {
        let enabled = providers.enabledProviders
        guard !enabled.isEmpty else {
            syncError = IdentifiableMessage(
                title: "Синхронизация",
                message: "Включите хотя бы один аккаунт в настройках."
            )
            return
        }
        await refresh(enabled)
    }

    /// Синхронизировать один провайдер (если он включён).
    func sync(providerID: ProviderID, reportErrors: Bool = true) async {
        guard let provider = providers.provider(providerID), provider.isEnabled else { return }
        _ = try? await run(provider, rerunIfBusy: false, reportErrors: reportErrors)
    }

    /// Автоматическое обновление: аккаунты, которые не синхронизировались
    /// дольше `interval` секунд. Без сообщений «включите аккаунт».
    func refreshStaleProviders(olderThan interval: TimeInterval) async {
        let now = Date()
        let stale = providers.enabledProviders.filter { provider in
            guard let last = provider.lastSyncDate else { return true }
            return now.timeIntervalSince(last) >= interval
        }
        await refresh(stale)
    }

    /// Локальная правка сохранена: через `uploadDelay` отправить её в свой
    /// аккаунт, не дожидаясь очередного обновления.
    func scheduleUploadOfLocalChanges() {
        for providerID in providerIDsWithLocalChanges() {
            uploadTasks[providerID]?.cancel()
            uploadTasks[providerID] = Task { [weak self, uploadDelay] in
                try? await Task.sleep(for: uploadDelay)
                guard !Task.isCancelled,
                      let self,
                      let provider = self.providers.provider(providerID),
                      provider.isEnabled
                else { return }
                _ = try? await self.run(provider, rerunIfBusy: true, reportErrors: true)
            }
        }
    }

    /// Автоматическая синхронизация на всё время работы приложения: при
    /// запуске, раз в `automaticRefreshInterval`, по изменениям EventKit,
    /// после сна и при появлении сети.
    func startAutomaticSync() {
        stopAutomaticSync()
        let interval = Self.automaticRefreshInterval

        automaticTasks.append(Task { [weak self] in
            // Первое обновление при запуске, если перед выходом его не было
            // только что; дальше — устаревшие аккаунты раз в `interval`.
            try? await Task.sleep(for: .seconds(1))
            await self?.refreshStaleProviders(olderThan: 30)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.refreshStaleProviders(olderThan: interval * 0.8)
            }
        })

        automaticTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                guard !Task.isCancelled else { return }
                // EventKit шлёт серию уведомлений подряд — ждём паузу.
                try? await Task.sleep(for: .seconds(2))
                await self?.sync(providerID: .apple, reportErrors: false)
            }
        })

        automaticTasks.append(Task { [weak self] in
            var wasOnline = true
            for await isOnline in Self.networkAvailability() {
                guard !Task.isCancelled else { return }
                if isOnline, !wasOnline {
                    // Сеть вернулась: забрать изменения и отправить правки,
                    // накопленные без неё.
                    await self?.refreshStaleProviders(olderThan: 0)
                }
                wasOnline = isOnline
            }
        })

        #if os(macOS)
        automaticTasks.append(Task { [weak self] in
            let center = NSWorkspace.shared.notificationCenter
            for await _ in center.notifications(named: NSWorkspace.didWakeNotification) {
                guard !Task.isCancelled else { return }
                // После сна сеть поднимается не сразу.
                try? await Task.sleep(for: .seconds(5))
                await self?.refreshStaleProviders(olderThan: 60)
            }
        })
        #endif
    }

    func stopAutomaticSync() {
        automaticTasks.forEach { $0.cancel() }
        automaticTasks = []
    }

    /// Возврат в приложение: подтянуть изменения, если давно не синхронизировались.
    func handleDidBecomeActive() {
        Task { await refreshStaleProviders(olderThan: 2 * 60) }
    }

    // MARK: - Прогоны

    /// Синхронизирует аккаунты по очереди и собирает их ошибки в `syncError`.
    private func refresh(_ list: [any CalendarProvider]) async {
        for provider in list {
            _ = try? await run(provider, rerunIfBusy: false, reportErrors: true)
        }
    }

    /// Один прогон аккаунта. Если аккаунт уже синхронизируется, обновление
    /// пропускается, а отправка правки (`rerunIfBusy`) ставит ещё один проход
    /// сразу после текущего.
    /// - Returns: прогон выполнен, а не пропущен или отложен.
    @discardableResult
    private func run(
        _ provider: any CalendarProvider,
        rerunIfBusy: Bool,
        reportErrors: Bool
    ) async throws -> Bool {
        // Синк можно запустить таймером, правкой, уведомлением и из меню;
        // параллельные прогоны одного провайдера перемешали бы мутации
        // `events` между await.
        guard !syncingProviderIDs.contains(provider.id) else {
            if rerunIfBusy { rerunProviderIDs.insert(provider.id) }
            return false
        }
        repeat {
            rerunProviderIDs.remove(provider.id)
            do {
                try await synchronize(provider)
                provider.lastSyncDate = Date()
                failures[provider.id] = nil
            } catch {
                if reportErrors {
                    failures[provider.id] = "\(provider.displayName): \(error.localizedDescription)"
                }
                updateSyncError()
                throw error
            }
        } while rerunProviderIDs.contains(provider.id)
        updateSyncError()
        return true
    }

    private func updateSyncError() {
        guard !failures.isEmpty else {
            syncError = nil
            return
        }
        let messages = ProviderID.allCases.compactMap { failures[$0] }
        syncError = IdentifiableMessage(
            title: messages.count == 1 ? "Ошибка синхронизации" : "Синхронизация завершена с ошибками",
            message: messages.joined(separator: "\n\n")
        )
    }

    private func currentUnavailableProviderIDs() -> Set<ProviderID> {
        Set(ProviderID.allCases.filter { !(providers.provider($0)?.isEnabled ?? false) })
    }

    /// Аккаунт включили или вернули ему доступ: сразу синхронизировать его,
    /// чтобы накопленные правки ушли без ожидания.
    private func updateProviderAvailability() {
        let unavailable = currentUnavailableProviderIDs()
        guard unavailable != unavailableProviderIDs else { return }
        let reconnected = unavailableProviderIDs.subtracting(unavailable)
        unavailableProviderIDs = unavailable
        for providerID in reconnected {
            Task { await sync(providerID: providerID) }
        }
    }

    /// Аккаунты, в которые есть что отправить: правки и удаления.
    private func providerIDsWithLocalChanges() -> Set<ProviderID> {
        var providerIDs = Set(repository.pendingDeletions.map(\.remoteRef.providerID))
        for event in repository.events where event.syncState == .pendingUpload && event.id != draftEventID {
            if let providerID = event.externalProvider { providerIDs.insert(providerID) }
        }
        return providerIDs
    }

    /// `true`, когда есть сеть, при каждом изменении её состояния.
    private nonisolated static func networkAvailability() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "LawMaticCalendar.network"))
        }
    }

    // MARK: - Один цикл провайдера

    private func synchronize(_ provider: any CalendarProvider) async throws {
        guard provider.isEnabled else { throw ProviderError.providerDisabled(provider.id) }
        repository.flushPendingSaves()
        syncingProviderIDs.insert(provider.id)
        progressText = "\(provider.displayName): список календарей…"
        defer {
            syncingProviderIDs.remove(provider.id)
            if syncingProviderIDs.isEmpty { progressText = nil }
        }

        let remoteCalendars = try await provider.listRemoteCalendars()
        mergeRemoteCalendars(remoteCalendars, provider: provider)
        let fullResyncRequested = provider.requiresFullResync

        for remoteCalendar in remoteCalendars {
            guard let localIndex = repository.calendars.firstIndex(where: {
                $0.externalProvider == provider.id && $0.externalId == remoteCalendar.id
            }) else { continue }

            // Диапазон дат провайдеры не получают: Google и LEGALIC ведут
            // инкремент курсором, Apple читает своё окно сам.
            let requestedRange: ClosedRange<Date>? = nil
            var syncToken = repository.calendars[localIndex].syncToken
            if fullResyncRequested {
                syncToken = nil
                repository.calendars[localIndex].syncToken = nil
            }
            if let windowEnd = repository.calendars[localIndex].syncWindowEnd,
               windowEnd.timeIntervalSinceNow < Self.syncWindowRefreshThreshold {
                // Окно первичной выборки заканчивается — инкременты по токену
                // больше не покрывают будущее. Делаем полную выборку заново.
                syncToken = nil
                repository.calendars[localIndex].syncToken = nil
            }
            let batch: SyncBatch
            progressText = "\(provider.displayName): \(remoteCalendar.title)…"
            do {
                batch = try await fetchAllEvents(
                    provider: provider,
                    calendar: remoteCalendar,
                    dateRange: requestedRange,
                    syncToken: syncToken
                )
            } catch ProviderError.syncTokenExpired {
                syncToken = nil
                repository.calendars[localIndex].syncToken = nil
                batch = try await fetchAllEvents(
                    provider: provider,
                    calendar: remoteCalendar,
                    dateRange: requestedRange,
                    syncToken: nil
                )
            }

            let deletionResolution = CalendarSyncMerger.resolveDeletionConflicts(
                in: batch,
                pendingDeletions: repository.pendingDeletions
            )
            repository.pendingDeletions = deletionResolution.pendingDeletions
            let resolvedBatch = deletionResolution.batch
            repository.events = await mergeOffMainIfLarge(
                resolvedBatch,
                localCalendar: repository.calendars[localIndex],
                dateRange: requestedRange
            )
            if let nextSyncToken = resolvedBatch.nextSyncToken {
                repository.calendars[localIndex].syncToken = nextSyncToken
            }
            if case .fullSnapshot = resolvedBatch.kind {
                repository.calendars[localIndex].syncWindowEnd = resolvedBatch.coveredDateRange?.upperBound
            }
            // Применённый batch и cursor сохраняем до исходящих операций.
            // Если push упадёт, следующий запуск продолжит с уже сохранённого
            // локального состояния, а dirty/outbox останутся для повтора.
            repository.save(.calendars)
            repository.save(.events)
            repository.save(.pendingDeletions)
        }
        if fullResyncRequested {
            provider.fullResyncDidComplete()
        }

        // Сначала pull + LWW выше, и только затем push тех локальных
        // изменений, которые действительно победили конфликт.
        progressText = "\(provider.displayName): отправка изменений…"
        try await flushPendingDeletions(for: provider)
        try await flushPendingUpserts(for: provider, remoteCalendars: remoteCalendars)

        repository.save(.calendars)
        repository.save(.events)
        repository.save(.pendingDeletions)
    }

    /// Merge — чистая функция; для больших батчей выполняем её вне main actor,
    /// чтобы UI не замирал. Если за это время пользователь изменил `events`,
    /// результат устарел — повторяем на свежем снимке.
    private func mergeOffMainIfLarge(
        _ batch: SyncBatch,
        localCalendar: CalendarItem,
        dateRange: ClosedRange<Date>?
    ) async -> [CalendarEvent] {
        let workload = (batch.upserts.count + batch.deletes.count) * max(repository.events.count, 1)
        guard workload > 50_000 else {
            return CalendarSyncMerger.merge(batch, into: repository.events, localCalendar: localCalendar, dateRange: dateRange)
        }

        for _ in 0 ..< 3 {
            let snapshot = repository.events
            let merged = await Task.detached(priority: .userInitiated) {
                CalendarSyncMerger.merge(batch, into: snapshot, localCalendar: localCalendar, dateRange: dateRange)
            }.value
            if repository.events == snapshot {
                return merged
            }
        }
        return CalendarSyncMerger.merge(batch, into: repository.events, localCalendar: localCalendar, dateRange: dateRange)
    }

    private func fetchAllEvents(
        provider: any CalendarProvider,
        calendar: RemoteCalendar,
        dateRange: ClosedRange<Date>?,
        syncToken: String?
    ) async throws -> SyncBatch {
        var pageToken: String?
        var allUpserts: [ParsedRemoteEvent] = []
        var allDeletes: [DeletedRemoteEvent] = []
        var nextSyncToken: String?
        var kind: SyncBatchKind = syncToken == nil ? .fullSnapshot : .incremental
        var coveredDateRange: ClosedRange<Date>?
        var pageCount = 0
        repeat {
            let page = try await provider.fetchEvents(
                calendar: calendar,
                request: SyncRequest(dateRange: dateRange, pageToken: pageToken, syncToken: syncToken)
            )
            allUpserts.append(contentsOf: page.upserts)
            allDeletes.append(contentsOf: page.deletes)
            pageCount += 1
            if page.nextPageToken != nil || pageCount > 1 {
                progressText = "\(provider.displayName): \(calendar.title) — страница \(pageCount), записей \(allUpserts.count + allDeletes.count)"
            }
            pageToken = page.nextPageToken
            nextSyncToken = page.nextSyncToken ?? nextSyncToken
            kind = page.kind
            coveredDateRange = page.coveredDateRange
        } while pageToken != nil
        return SyncBatch(
            upserts: allUpserts,
            deletes: allDeletes,
            nextPageToken: nil,
            nextSyncToken: nextSyncToken,
            kind: kind,
            coveredDateRange: coveredDateRange
        )
    }

    private func mergeRemoteCalendars(_ remoteCalendars: [RemoteCalendar], provider: any CalendarProvider) {
        // Календари, исчезнувшие на сервере (отписка, удаление), убираем
        // вместе с их событиями и очередью удалений.
        let remoteIDs = Set(remoteCalendars.map(\.id))
        let vanished = repository.calendars.filter {
            $0.externalProvider == provider.id && !($0.externalId.map(remoteIDs.contains) ?? true)
        }
        if !vanished.isEmpty {
            let vanishedIDs = Set(vanished.map(\.id))
            let vanishedRemoteIDs = Set(vanished.compactMap(\.externalId))
            repository.calendars.removeAll { vanishedIDs.contains($0.id) }
            repository.events.removeAll { vanishedIDs.contains($0.calendarId) }
            repository.pendingDeletions.removeAll {
                $0.remoteRef.providerID == provider.id && vanishedRemoteIDs.contains($0.remoteRef.remoteCalendarID)
            }
            repository.save(.events)
            repository.save(.pendingDeletions)
        }

        for remote in remoteCalendars {
            let color = EventColor.nearest(to: remote.colorHex, fallback: provider.id.defaultColor)
            if let index = repository.calendars.firstIndex(where: {
                $0.externalProvider == provider.id && $0.externalId == remote.id
            }) {
                repository.calendars[index].name = remote.title
                repository.calendars[index].color = color
                repository.calendars[index].accountName = provider.displayName
                repository.calendars[index].isWritable = remote.isWritable
            } else {
                repository.calendars.append(
                    CalendarItem(
                        name: remote.title,
                        color: color,
                        accountName: provider.displayName,
                        externalProvider: provider.id,
                        externalId: remote.id,
                        isWritable: remote.isWritable
                    )
                )
            }
        }
        repository.save(.calendars)
    }

    private func flushPendingDeletions(for provider: any CalendarProvider) async throws {
        let queued = repository.pendingDeletions.filter { $0.remoteRef.providerID == provider.id }
        if queued.count > Self.massDeletionThreshold, !confirmedMassDeletionProviders.contains(provider.id) {
            pendingMassDeletion = MassDeletionRequest(providerID: provider.id, count: queued.count)
            throw ProviderError.massDeletionBlocked(provider: provider.id, count: queued.count)
        }
        defer { confirmedMassDeletionProviders.remove(provider.id) }
        if pendingMassDeletion?.providerID == provider.id { pendingMassDeletion = nil }
        for deletion in queued {
            try await provider.pushDelete(deletion.remoteRef, etag: deletion.etag)
            repository.pendingDeletions.removeAll { $0.id == deletion.id }
            repository.save(.pendingDeletions)
        }
    }

    private func flushPendingUpserts(
        for provider: any CalendarProvider,
        remoteCalendars: [RemoteCalendar]
    ) async throws {
        let eventIDs = repository.events.filter {
            $0.externalProvider == provider.id && $0.syncState == .pendingUpload && $0.id != draftEventID
        }.map(\.id)
        for eventID in eventIDs {
            guard let index = repository.events.firstIndex(where: { $0.id == eventID }),
                  let remoteCalendarID = repository.events[index].externalCalendarId,
                  let remoteCalendar = remoteCalendars.first(where: { $0.id == remoteCalendarID })
            else { continue }
            if repository.events[index].externalId == nil,
               repository.events[index].pendingCreateRemoteId == nil {
                repository.events[index].pendingCreateRemoteId = provider.proposedRemoteEventID(for: repository.events[index])
                try repository.saveOrThrow(.events)
            }
            let pushed = try await provider.pushUpsert(localEvent: repository.events[index], to: remoteCalendar)
            guard let currentIndex = repository.events.firstIndex(where: { $0.id == eventID }) else { continue }
            repository.events[currentIndex].externalProvider = pushed.remoteRef.providerID
            repository.events[currentIndex].externalCalendarId = pushed.remoteRef.remoteCalendarID
            repository.events[currentIndex].externalId = pushed.remoteRef.remoteEventID
            repository.events[currentIndex].externalETag = pushed.etag
            repository.events[currentIndex].pendingCreateRemoteId = nil
            repository.events[currentIndex].remoteUpdatedAt = pushed.updatedAt
            repository.events[currentIndex].syncState = .clean
            repository.save(.events)
        }
    }
}
