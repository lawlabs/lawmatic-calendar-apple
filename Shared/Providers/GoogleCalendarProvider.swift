import Combine
import Foundation
import GoogleSignIn

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class GoogleCalendarProvider: ObservableObject, CalendarProvider {
    let id: ProviderID = .google
    let displayName = "Google Calendar"

    @Published private(set) var status: ProviderStatus = .signedOut
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled) }
    }

    private let apiClient: GoogleCalendarAPIClient
    private let signIn = GIDSignIn.sharedInstance

    init(apiClient: GoogleCalendarAPIClient = GoogleCalendarAPIClient()) {
        self.apiClient = apiClient
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.isEnabled)
        configureSDKIfPossible()
        if let user = signIn.currentUser {
            updateStatus(for: user)
        } else if isConfigured, signIn.hasPreviousSignIn() {
            Task { [weak self] in await self?.restorePreviousSignIn() }
        }
    }

    var isConfigured: Bool {
        guard let clientID = Self.clientID else { return false }
        return clientID.hasSuffix(".apps.googleusercontent.com") && !clientID.contains("YOUR_")
    }

    var configurationMessage: String? {
        guard !isConfigured else { return nil }
        return "Добавьте GIDClientID и URL scheme обратного client ID в Info.plist. Подробности — Docs/CalendarSync.md."
    }

    func signIn() async throws {
        guard isConfigured else { throw ProviderError.missingCredentials(provider: id) }
        configureSDKIfPossible()
        status = .syncing
        do {
            let user = try await interactiveSignIn()
            guard user.grantedScopes?.contains(Self.calendarScope) == true else {
                throw ProviderError.notAuthorized(provider: id)
            }
            isEnabled = true
            updateStatus(for: user)
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func signOut() async {
        signIn.signOut()
        isEnabled = false
        status = .signedOut
    }

    func listRemoteCalendars() async throws -> [RemoteCalendar] {
        let token = try await accessToken()
        let calendars = try await apiClient.listCalendars(accessToken: token)
        return calendars.map { item in
            RemoteCalendar(
                id: item.id,
                providerID: id,
                title: item.summaryOverride ?? item.summary ?? "Google Calendar",
                colorHex: item.backgroundColor,
                isWritable: item.accessRole == "writer" || item.accessRole == "owner"
            )
        }
    }

    func fetchEvents(calendar: RemoteCalendar, request: SyncRequest) async throws -> SyncBatch {
        let token = try await accessToken()
        return try await apiClient.fetchEvents(
            calendar: calendar,
            request: request,
            accessToken: token
        )
    }

    func proposedRemoteEventID(for localEvent: CalendarEvent) -> String? {
        guard localEvent.externalId == nil else { return nil }
        return GoogleCalendarAPIClient.deterministicGoogleID(for: localEvent)
    }

    func pushUpsert(localEvent: CalendarEvent, to remoteCalendar: RemoteCalendar) async throws -> PushedRemoteEvent {
        guard remoteCalendar.isWritable else {
            throw ProviderError.notImplemented(provider: id, operation: "запись в календарь \(remoteCalendar.title)")
        }
        let token = try await accessToken()
        let saved = try await apiClient.upsert(
            event: localEvent,
            calendarID: remoteCalendar.id,
            accessToken: token
        )
        guard let eventID = saved.id else { throw ProviderError.invalidResponse("Google не вернул id события.") }
        return PushedRemoteEvent(
            remoteRef: RemoteEventRef(providerID: id, remoteCalendarID: remoteCalendar.id, remoteEventID: eventID),
            etag: saved.etag,
            updatedAt: GoogleCalendarAPIClient.parseGoogleDateTime(saved.updated) ?? Date()
        )
    }

    func pushDelete(_ ref: RemoteEventRef, etag: String?) async throws {
        let token = try await accessToken()
        try await apiClient.delete(ref: ref, etag: etag, accessToken: token)
    }

    func handleOpenURL(_ url: URL) -> Bool {
        signIn.handle(url)
    }

    private func configureSDKIfPossible() {
        guard let clientID = Self.clientID, !clientID.isEmpty else { return }
        signIn.configuration = GIDConfiguration(clientID: clientID)
    }

    private func restorePreviousSignIn() async {
        do {
            let user = try await withCheckedThrowingContinuation { continuation in
                signIn.restorePreviousSignIn { user, error in
                    if let user { continuation.resume(returning: user) }
                    else { continuation.resume(throwing: error ?? ProviderError.notAuthorized(provider: self.id)) }
                }
            }
            updateStatus(for: user)
        } catch {
            status = .signedOut
        }
    }

    private func interactiveSignIn() async throws -> GIDGoogleUser {
        #if os(macOS)
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            throw ProviderError.underlying("Не найдено окно для входа в Google.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            signIn.signIn(
                withPresenting: window,
                hint: nil,
                additionalScopes: [Self.calendarScope]
            ) { result, error in
                if let user = result?.user { continuation.resume(returning: user) }
                else { continuation.resume(throwing: error ?? ProviderError.notAuthorized(provider: self.id)) }
            }
        }
        #else
        guard let presenter = Self.presentingViewController() else {
            throw ProviderError.underlying("Не найден экран для входа в Google.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            signIn.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: [Self.calendarScope]
            ) { result, error in
                if let user = result?.user { continuation.resume(returning: user) }
                else { continuation.resume(throwing: error ?? ProviderError.notAuthorized(provider: self.id)) }
            }
        }
        #endif
    }

    private func accessToken() async throws -> String {
        guard let currentUser = signIn.currentUser else {
            status = .signedOut
            throw ProviderError.notAuthorized(provider: id)
        }
        let user: GIDGoogleUser = try await withCheckedThrowingContinuation { continuation in
            currentUser.refreshTokensIfNeeded { user, error in
                if let user { continuation.resume(returning: user) }
                else { continuation.resume(throwing: error ?? ProviderError.notAuthorized(provider: self.id)) }
            }
        }
        updateStatus(for: user)
        return user.accessToken.tokenString
    }

    private func updateStatus(for user: GIDGoogleUser) {
        status = .signedIn(accountLabel: user.profile?.email ?? "Google")
    }

    #if !os(macOS)
    private static func presentingViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
        var presenter = root
        while let next = presenter?.presentedViewController { presenter = next }
        return presenter
    }
    #endif

    private static var clientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
    }

    private static let calendarScope = "https://www.googleapis.com/auth/calendar"

    private enum Keys {
        static let isEnabled = "googleCalendar.isEnabled"
    }
}

actor GoogleCalendarAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func listCalendars(accessToken: String) async throws -> [GoogleCalendarListItem] {
        var result: [GoogleCalendarListItem] = []
        var pageToken: String?
        repeat {
            var query = [URLQueryItem(name: "maxResults", value: "250")]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let data = try await request(
                method: "GET",
                path: "/calendar/v3/users/me/calendarList",
                query: query,
                accessToken: accessToken
            )
            let page = try decode(GoogleCalendarListPage.self, from: data)
            result.append(contentsOf: page.items ?? [])
            pageToken = page.nextPageToken
        } while pageToken != nil
        return result
    }

    func fetchEvents(
        calendar: RemoteCalendar,
        request syncRequest: SyncRequest,
        accessToken: String
    ) async throws -> SyncBatch {
        var query = [
            URLQueryItem(name: "maxResults", value: "2500"),
            URLQueryItem(name: "showDeleted", value: "true"),
            URLQueryItem(name: "singleEvents", value: "true"),
        ]
        // Первичная выборка ограничена окном: с singleEvents=true Google
        // разворачивает повторяющиеся события в экземпляры, и без границ
        // «живой» календарь отдаёт десятки тысяч записей. Полученный
        // syncToken сохраняет это окно для инкрементов (timeMin/timeMax
        // вместе с syncToken передавать нельзя).
        var coveredRange: ClosedRange<Date>?
        if let syncToken = syncRequest.syncToken {
            query.append(URLQueryItem(name: "syncToken", value: syncToken))
        } else {
            let window = syncRequest.dateRange ?? Self.defaultSyncWindow
            coveredRange = window
            query.append(URLQueryItem(name: "timeMin", value: Self.isoPlain.string(from: window.lowerBound)))
            query.append(URLQueryItem(name: "timeMax", value: Self.isoPlain.string(from: window.upperBound)))
        }
        if let pageToken = syncRequest.pageToken {
            query.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        let data = try await request(
            method: "GET",
            path: "/calendar/v3/calendars/\(encodedPathComponent(calendar.id))/events",
            query: query,
            accessToken: accessToken
        )
        let page = try decode(GoogleEventsPage.self, from: data)
        var upserts: [ParsedRemoteEvent] = []
        var deletes: [DeletedRemoteEvent] = []
        for item in page.items ?? [] {
            guard let eventID = item.id else { continue }
            let ref = RemoteEventRef(providerID: .google, remoteCalendarID: calendar.id, remoteEventID: eventID)
            let updatedAt = Self.parseDateTime(item.updated) ?? .distantPast
            if item.status == "cancelled" {
                deletes.append(DeletedRemoteEvent(remoteRef: ref, updatedAt: updatedAt))
                continue
            }
            guard let start = Self.parseEventDate(item.start),
                  let remoteEnd = Self.parseEventDate(item.end)
            else { continue }
            let isAllDay = item.start?.date != nil
            // Google хранит all-day end как exclusive. В локальной модели
            // endDate — последний включённый календарный день.
            let end = isAllDay ? remoteEnd.addingTimeInterval(-1) : remoteEnd
            upserts.append(
                ParsedRemoteEvent(
                    remoteRef: ref,
                    title: item.summary ?? "Без названия",
                    start: start,
                    end: end,
                    isAllDay: isAllDay,
                    notes: item.description ?? "",
                    location: item.location ?? "",
                    updatedAt: updatedAt,
                    etag: item.etag
                )
            )
        }
        return SyncBatch(
            upserts: upserts,
            deletes: deletes,
            nextPageToken: page.nextPageToken,
            nextSyncToken: page.nextSyncToken,
            kind: syncRequest.syncToken == nil ? .fullSnapshot : .incremental,
            coveredDateRange: coveredRange
        )
    }

    /// Окно первичной выборки: год назад и три года вперёд.
    nonisolated static var defaultSyncWindow: ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 86_400)
        let end = calendar.date(byAdding: .year, value: 3, to: now) ?? now.addingTimeInterval(3 * 365 * 86_400)
        return start ... end
    }

    func upsert(event: CalendarEvent, calendarID: String, accessToken: String) async throws -> GoogleEvent {
        let body = try JSONSerialization.data(withJSONObject: Self.requestBody(for: event))
        let path: String
        let method: String
        if let eventID = event.externalId {
            method = "PATCH"
            path = "/calendar/v3/calendars/\(encodedPathComponent(calendarID))/events/\(encodedPathComponent(eventID))"
        } else {
            method = "POST"
            path = "/calendar/v3/calendars/\(encodedPathComponent(calendarID))/events"
        }
        var headers: [String: String] = [:]
        if method == "PATCH", let etag = event.externalETag { headers["If-Match"] = etag }
        let data: Data
        do {
            data = try await request(
                method: method,
                path: path,
                body: body,
                accessToken: accessToken,
                additionalHeaders: headers
            )
        } catch ProviderError.httpStatus(409, _) where method == "POST" {
            // events.insert поддерживает клиентский id. Повтор после сбоя
            // локального сохранения получает 409, поэтому читаем уже
            // созданное событие вместо создания дубликата.
            let deterministicID = event.pendingCreateRemoteId ?? Self.deterministicGoogleID(for: event)
            data = try await request(
                method: "GET",
                path: "/calendar/v3/calendars/\(encodedPathComponent(calendarID))/events/\(encodedPathComponent(deterministicID))",
                accessToken: accessToken
            )
        }
        let saved = try decode(GoogleEvent.self, from: data)
        guard saved.id != nil, saved.status != "cancelled" else {
            throw ProviderError.invalidResponse("Google не вернул активное событие после сохранения.")
        }
        return saved
    }

    func delete(ref: RemoteEventRef, etag: String?, accessToken: String) async throws {
        var headers: [String: String] = [:]
        if let etag { headers["If-Match"] = etag }
        _ = try await request(
            method: "DELETE",
            path: "/calendar/v3/calendars/\(encodedPathComponent(ref.remoteCalendarID))/events/\(encodedPathComponent(ref.remoteEventID))",
            accessToken: accessToken,
            acceptedStatusCodes: [200, 204, 404, 410],
            additionalHeaders: headers
        )
    }

    private func request(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        accessToken: String,
        acceptedStatusCodes: Set<Int> = Set(200 ... 299),
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.percentEncodedPath = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw ProviderError.invalidResponse("Некорректный Google API URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Google API вернул не-HTTP ответ.")
        }
        if http.statusCode == 410 && method == "GET" { throw ProviderError.syncTokenExpired }
        if http.statusCode == 412 { throw ProviderError.preconditionFailed }
        guard acceptedStatusCodes.contains(http.statusCode) else {
            throw ProviderError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw ProviderError.invalidResponse("Не удалось разобрать ответ Google: \(error.localizedDescription)") }
    }

    private func encodedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathComponentAllowed) ?? value
    }

    private static func parseEventDate(_ value: GoogleEventDate?) -> Date? {
        if let dateTime = value?.dateTime { return parseDateTime(dateTime) }
        guard let date = value?.date else { return nil }
        return dateOnlyFormatter.date(from: date)
    }

    private static func parseDateTime(_ value: String?) -> Date? {
        guard let value else { return nil }
        return isoFractional.date(from: value) ?? isoPlain.date(from: value)
    }

    nonisolated static func parseGoogleDateTime(_ value: String?) -> Date? {
        parseDateTime(value)
    }

    private static func requestBody(for event: CalendarEvent) -> [String: Any] {
        var result: [String: Any] = ["summary": event.title]
        if event.externalId == nil {
            result["id"] = event.pendingCreateRemoteId ?? deterministicGoogleID(for: event)
        }
        if !event.notes.isEmpty { result["description"] = event.notes }
        if !event.location.isEmpty { result["location"] = event.location }
        if event.isAllDay {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: event.startDate)
            let inclusiveEnd = max(start, calendar.startOfDay(for: event.endDate))
            let end = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd
            result["start"] = ["date": dateOnlyFormatter.string(from: start)]
            result["end"] = ["date": dateOnlyFormatter.string(from: end)]
        } else {
            result["start"] = ["dateTime": isoPlain.string(from: event.startDate)]
            result["end"] = ["dateTime": isoPlain.string(from: event.endDate)]
        }
        return result
    }

    nonisolated static func deterministicGoogleID(for event: CalendarEvent) -> String {
        let uuid = event.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let milliseconds = UInt64(max(0, event.localUpdatedAt.timeIntervalSince1970 * 1_000))
        return uuid + String(milliseconds, radix: 16)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct GoogleCalendarListPage: Decodable {
    let nextPageToken: String?
    let items: [GoogleCalendarListItem]?
}

struct GoogleCalendarListItem: Decodable {
    let id: String
    let summary: String?
    let summaryOverride: String?
    let backgroundColor: String?
    let accessRole: String?
}

struct GoogleEventsPage: Decodable {
    let nextPageToken: String?
    let nextSyncToken: String?
    let items: [GoogleEvent]?
}

struct GoogleEvent: Decodable {
    let id: String?
    let etag: String?
    let status: String?
    let summary: String?
    let description: String?
    let location: String?
    let updated: String?
    let start: GoogleEventDate?
    let end: GoogleEventDate?
}

struct GoogleEventDate: Decodable {
    let date: String?
    let dateTime: String?
}

private extension CharacterSet {
    static let urlPathComponentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()
}
