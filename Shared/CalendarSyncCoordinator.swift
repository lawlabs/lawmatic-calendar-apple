import EventKit
import Foundation
import Observation

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
@Observable
@MainActor
final class CalendarSyncCoordinator {
    private(set) var syncingProviderIDs: Set<ProviderID> = []
    /// Что сейчас делает синхронизация — для индикатора в тулбаре и сайдбаре.
    private(set) var progressText: String?
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
    /// Время последней полностью успешной синхронизации всех включённых аккаунтов.
    private(set) var lastSuccessfulSyncDate: Date?

    @ObservationIgnored private let repository: EventRepository
    @ObservationIgnored private let providers: any CalendarProviderResolving
    @ObservationIgnored private var periodicSyncTask: Task<Void, Never>?
    @ObservationIgnored private var eventStoreChangesTask: Task<Void, Never>?

    /// За сколько до конца окна первичной выборки делать полный ресинк.
    static let syncWindowRefreshThreshold: TimeInterval = 180 * 24 * 3600

    init(repository: EventRepository, providers: any CalendarProviderResolving) {
        self.repository = repository
        self.providers = providers
    }

    var isSyncing: Bool { !syncingProviderIDs.isEmpty }

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

    func syncAllProviders() async {
        syncError = nil
        let enabled = providers.enabledProviders
        guard !enabled.isEmpty else {
            syncError = IdentifiableMessage(
                title: "Синхронизация",
                message: "Включите хотя бы один аккаунт в настройках."
            )
            return
        }
        var failures: [String] = []
        for provider in enabled {
            do {
                try await synchronize(provider)
            } catch {
                failures.append("\(provider.displayName): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            syncError = IdentifiableMessage(
                title: "Синхронизация завершена с ошибками",
                message: failures.joined(separator: "\n\n")
            )
        } else {
            lastSuccessfulSyncDate = Date()
        }
    }

    /// Синхронизировать один провайдер (если он включён).
    func sync(providerID: ProviderID, reportErrors: Bool = true) async {
        guard let provider = providers.provider(providerID), provider.isEnabled else { return }
        if reportErrors { syncError = nil }
        do {
            try await synchronize(provider)
        } catch {
            guard reportErrors else { return }
            syncError = IdentifiableMessage(
                title: provider.displayName,
                message: error.localizedDescription
            )
        }
    }

    /// Синхронизировать, если включён хотя бы один аккаунт (без сообщения
    /// «включите аккаунт» — для автоматических запусков).
    func syncIfEnabled() async {
        guard !providers.enabledProviders.isEmpty, !isSyncing else { return }
        await syncAllProviders()
    }

    /// Автосинк: сразу после запуска и далее каждые `interval`; плюс
    /// точечный синк Apple Calendar по уведомлению EventKit об изменениях.
    func startPeriodicSync(interval: Duration = .seconds(15 * 60), initialDelay: Duration = .seconds(2)) {
        periodicSyncTask?.cancel()
        periodicSyncTask = Task { [weak self] in
            try? await Task.sleep(for: initialDelay)
            while !Task.isCancelled {
                await self?.syncIfEnabled()
                try? await Task.sleep(for: interval)
            }
        }

        eventStoreChangesTask?.cancel()
        eventStoreChangesTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                guard !Task.isCancelled else { return }
                // EventKit шлёт серию уведомлений подряд — ждём паузу.
                try? await Task.sleep(for: .seconds(2))
                await self?.sync(providerID: .apple, reportErrors: false)
            }
        }
    }

    func stopPeriodicSync() {
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
        eventStoreChangesTask?.cancel()
        eventStoreChangesTask = nil
    }

    /// Возврат на передний план: подтянуть изменения, если давно не синкались.
    func handleDidBecomeActive(staleAfter: TimeInterval = 5 * 60) {
        guard let last = lastSuccessfulSyncDate else {
            Task { await syncIfEnabled() }
            return
        }
        if Date().timeIntervalSince(last) > staleAfter {
            Task { await syncIfEnabled() }
        }
    }

    // MARK: - Один цикл провайдера

    private func synchronize(_ provider: any CalendarProvider) async throws {
        guard provider.isEnabled else { throw ProviderError.providerDisabled(provider.id) }
        // Синк можно запустить из тулбара, сайдбара и меню; параллельные
        // прогоны одного провайдера перемешали бы мутации `events` между await.
        guard !syncingProviderIDs.contains(provider.id) else { return }
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
            $0.externalProvider == provider.id && $0.syncState == .pendingUpload
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
