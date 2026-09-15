import Combine
@preconcurrency import EventKit
import Foundation

@MainActor
final class AppleCalendarProvider: ObservableObject, CalendarProvider {
    let id: ProviderID = .apple
    let displayName = "Apple Calendar"

    @Published private(set) var status: ProviderStatus
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled) }
    }
    /// Разрешить приложению менять и удалять события в системных календарях.
    /// Выключено — календари Apple только читаются, ни одна правка из
    /// приложения в них не уходит.
    @Published var allowsWriteBack: Bool {
        didSet { UserDefaults.standard.set(allowsWriteBack, forKey: Keys.allowsWriteBack) }
    }

    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        let hasFullAccess = Self.hasFullAccess
        self.isEnabled = hasFullAccess && UserDefaults.standard.bool(forKey: Keys.isEnabled)
        self.allowsWriteBack = UserDefaults.standard.object(forKey: Keys.allowsWriteBack) as? Bool ?? true
        self.status = hasFullAccess
            ? .signedIn(accountLabel: "Системные календари")
            : .signedOut
    }

    func signIn() async throws {
        status = .syncing
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            guard granted else { throw ProviderError.notAuthorized(provider: id) }
            isEnabled = true
            status = .signedIn(accountLabel: "Системные календари")
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func signOut() async {
        isEnabled = false
        status = .signedOut
    }

    func listRemoteCalendars() async throws -> [RemoteCalendar] {
        try ensureAuthorized()
        return eventStore.calendars(for: .event).map { calendar in
            RemoteCalendar(
                id: calendar.calendarIdentifier,
                providerID: id,
                title: calendar.title,
                colorHex: Self.hexString(from: calendar.cgColor),
                isWritable: calendar.allowsContentModifications && allowsWriteBack
            )
        }
    }

    func fetchEvents(calendar: RemoteCalendar, request: SyncRequest) async throws -> SyncBatch {
        try ensureAuthorized()
        guard eventStore.calendar(withIdentifier: calendar.id) != nil else {
            throw ProviderError.remoteCalendarNotFound(remoteID: calendar.id)
        }
        let range = request.dateRange ?? Self.defaultSyncRange
        let providerID = id
        let remoteCalendarID = calendar.id
        let eventStore = self.eventStore
        // Выборка за несколько лет может занимать сотни миллисекунд —
        // EventKit потокобезопасен для чтения, поэтому уходим с main actor.
        let upserts: [ParsedRemoteEvent] = await Task.detached(priority: .userInitiated) {
            guard let eventCalendar = eventStore.calendar(withIdentifier: remoteCalendarID) else { return [] }
            let predicate = eventStore.predicateForEvents(
                withStart: range.lowerBound,
                end: range.upperBound,
                calendars: [eventCalendar]
            )
            return eventStore.events(matching: predicate).compactMap { event -> ParsedRemoteEvent? in
                guard let eventID = event.eventIdentifier,
                      let eventStart = event.startDate,
                      let eventEnd = event.endDate
                else { return nil }
                let localEnd = event.isAllDay ? eventEnd.addingTimeInterval(-1) : eventEnd
                // У всех экземпляров повторяющегося события один eventIdentifier.
                // Даём каждому свой ключ, чтобы показать их все, и помечаем
                // только для чтения: правка «этого экземпляра» через EventKit
                // по одному идентификатору попала бы в другой экземпляр.
                let isOccurrence = event.hasRecurrenceRules || event.isDetached
                let remoteEventID = isOccurrence
                    ? Self.occurrenceID(eventID, occurrenceDate: event.occurrenceDate ?? eventStart)
                    : eventID
                return ParsedRemoteEvent(
                    remoteRef: RemoteEventRef(
                        providerID: providerID,
                        remoteCalendarID: remoteCalendarID,
                        remoteEventID: remoteEventID
                    ),
                    title: event.title ?? "Без названия",
                    start: eventStart,
                    end: localEnd,
                    isAllDay: event.isAllDay,
                    notes: event.notes ?? "",
                    location: event.location ?? "",
                    updatedAt: event.lastModifiedDate ?? .distantPast,
                    etag: nil,
                    isReadOnly: isOccurrence
                )
            }
        }.value
        status = .signedIn(accountLabel: "Системные календари")
        return SyncBatch(
            upserts: upserts,
            deletes: [],
            nextPageToken: nil,
            nextSyncToken: nil,
            kind: .fullSnapshot,
            coveredDateRange: range
        )
    }

    func pushUpsert(localEvent: CalendarEvent, to remoteCalendar: RemoteCalendar) async throws -> PushedRemoteEvent {
        try ensureAuthorized()
        guard allowsWriteBack else {
            throw ProviderError.notImplemented(provider: id, operation: "запись (выключена в настройках)")
        }
        guard let calendar = eventStore.calendar(withIdentifier: remoteCalendar.id) else {
            throw ProviderError.remoteCalendarNotFound(remoteID: remoteCalendar.id)
        }
        guard calendar.allowsContentModifications else {
            throw ProviderError.notImplemented(provider: id, operation: "запись в календарь \(calendar.title)")
        }
        if let externalID = localEvent.externalId, Self.isOccurrenceID(externalID) {
            throw ProviderError.notImplemented(provider: id, operation: "изменение экземпляра повторяющегося события")
        }

        let event: EKEvent
        if let externalID = localEvent.externalId,
           let existing = eventStore.event(withIdentifier: externalID) {
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
        }
        event.calendar = calendar
        event.title = localEvent.title
        event.startDate = localEvent.startDate
        event.isAllDay = localEvent.isAllDay
        if localEvent.isAllDay {
            let calendar = Calendar.current
            let inclusiveEnd = max(
                calendar.startOfDay(for: localEvent.startDate),
                calendar.startOfDay(for: localEvent.endDate)
            )
            event.startDate = calendar.startOfDay(for: localEvent.startDate)
            event.endDate = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd
        } else {
            event.endDate = localEvent.endDate
        }
        event.notes = localEvent.notes.isEmpty ? nil : localEvent.notes
        event.location = localEvent.location.isEmpty ? nil : localEvent.location
        try eventStore.save(event, span: .thisEvent, commit: true)
        guard let eventID = event.eventIdentifier else {
            throw ProviderError.invalidResponse("EventKit не вернул идентификатор сохранённого события.")
        }
        return PushedRemoteEvent(
            remoteRef: RemoteEventRef(providerID: id, remoteCalendarID: remoteCalendar.id, remoteEventID: eventID),
            etag: nil,
            updatedAt: event.lastModifiedDate ?? Date()
        )
    }

    /// Удаляет ровно одно событие и только если оно всё ещё лежит в том
    /// календаре, из которого его удалили локально. Повторяющиеся события
    /// из приложения не удаляются вовсе (см. `occurrenceID`).
    func pushDelete(_ ref: RemoteEventRef, etag: String?) async throws {
        try ensureAuthorized()
        guard allowsWriteBack else {
            throw ProviderError.notImplemented(provider: id, operation: "удаление (запись выключена в настройках)")
        }
        guard !Self.isOccurrenceID(ref.remoteEventID) else {
            throw ProviderError.notImplemented(provider: id, operation: "удаление экземпляра повторяющегося события")
        }
        guard let event = eventStore.event(withIdentifier: ref.remoteEventID) else { return }
        guard !event.hasRecurrenceRules else {
            throw ProviderError.notImplemented(provider: id, operation: "удаление повторяющегося события")
        }
        guard event.calendar?.calendarIdentifier == ref.remoteCalendarID else {
            // Событие переехало в другой календарь на стороне Apple: локальное
            // удаление опиралось на устаревшие данные — не трогаем, следующий
            // pull покажет его заново.
            return
        }
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }

    // MARK: - Идентификаторы экземпляров

    nonisolated private static let occurrenceSeparator = "@occ:"

    nonisolated static func occurrenceID(_ eventIdentifier: String, occurrenceDate: Date) -> String {
        "\(eventIdentifier)\(occurrenceSeparator)\(Int(occurrenceDate.timeIntervalSince1970))"
    }

    nonisolated static func isOccurrenceID(_ remoteEventID: String) -> Bool {
        remoteEventID.contains(occurrenceSeparator)
    }

    private func ensureAuthorized() throws {
        guard Self.hasFullAccess else {
            status = .signedOut
            throw ProviderError.notAuthorized(provider: id)
        }
    }

    private static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    private static var defaultSyncRange: ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 86_400)
        let end = calendar.date(byAdding: .year, value: 2, to: now) ?? now.addingTimeInterval(730 * 86_400)
        return start ... end
    }

    private static func hexString(from color: CGColor?) -> String? {
        guard let components = color?.components, components.count >= 3 else { return nil }
        let red = Int((components[0] * 255).rounded())
        let green = Int((components[1] * 255).rounded())
        let blue = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private enum Keys {
        static let isEnabled = "appleCalendar.isEnabled"
        static let allowsWriteBack = "appleCalendar.allowsWriteBack"
    }
}
