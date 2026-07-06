import Foundation

struct LegalicTaskImport: Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let notes: String
}

enum LegalicAPIError: LocalizedError {
    case invalidURL
    case httpStatus(Int, String?)
    case noData
    case tokenMissing
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный базовый URL LEGALIC."
        case .httpStatus(let code, let body):
            let tail = body.map { "\n\($0.prefix(500))" } ?? ""
            return "Ошибка сервера LEGALIC (\(code)).\(tail)"
        case .noData:
            return "Пустой ответ LEGALIC."
        case .tokenMissing:
            return "В ответе LEGALIC нет access_token."
        case .decodingFailed(let reason):
            return "Не удалось разобрать ответ: \(reason)"
        }
    }
}

actor LegalicAPIClient {
    static let shared = LegalicAPIClient()

    private var cachedAccessToken: String?
    private var tokenExpiresAt: Date?

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func invalidateToken() {
        cachedAccessToken = nil
        tokenExpiresAt = nil
    }

    func fetchTasks(
        baseURL: URL,
        tasksURL: URL,
        apiKey: String,
        apiSecret: String,
        maxPages: Int = 1,
        perPage: Int = 50
    ) async throws -> [LegalicTaskImport] {
        LegalicLogger.line("fetchTasks: старт")
        LegalicLogger.line("fetchTasks: baseURL=\(baseURL.absoluteString)")
        LegalicLogger.line("fetchTasks: tasksURL (без пагинации в логе — см. GET ниже)=\(tasksURL.absoluteString)")
        LegalicLogger.line("fetchTasks: apiKey=\(LegalicLogger.maskedApiKey(apiKey))")
        LegalicLogger.line("fetchTasks: maxPages=\(maxPages) perPage=\(perPage)")
        invalidateToken()
        let token = try await requestAccessToken(baseURL: baseURL, apiKey: apiKey, apiSecret: apiSecret)
        LegalicLogger.line("fetchTasks: токен получен, префикс \(LegalicLogger.maskedTokenPrefix(token))")

        let cap = max(1, maxPages)
        let pageSize = max(1, min(perPage, 500))

        var collected: [LegalicTaskImport] = []
        var seenIds = Set<String>()
        var pageCountFromApi = 1

        for page in 1 ... cap {
            let pageURL = Self.tasksURLAppendingPagination(base: tasksURL, page: page, perPage: pageSize)
            LegalicLogger.line("fetchTasks: загрузка страницы \(page) из ≤\(cap) — \(pageURL.absoluteString)")
            let data = try await downloadTasksData(tasksURL: pageURL, accessToken: token)
            let envelope = try LegalicTaskJSONParser.parseTasksPage(from: data)
            pageCountFromApi = envelope.pageCount
            for task in envelope.tasks where seenIds.insert(task.id).inserted {
                collected.append(task)
            }
            LegalicLogger.line(
                "fetchTasks: страница \(envelope.page)/\(envelope.pageCount), на странице задач: \(envelope.tasks.count), уникальных всего: \(collected.count)"
            )
            if page >= min(envelope.pageCount, cap) {
                break
            }
        }

        LegalicLogger.line(
            "fetchTasks: готово, уникальных задач: \(collected.count) (API сообщило page_count=\(pageCountFromApi), запрошено страниц ≤\(cap))"
        )
        return collected
    }

    private func requestAccessToken(baseURL: URL, apiKey: String, apiSecret: String) async throws -> String {
        if let cachedAccessToken, let tokenExpiresAt, Date() < tokenExpiresAt.addingTimeInterval(-60) {
            LegalicLogger.line("requestAccessToken: используем кэш токена до \(tokenExpiresAt)")
            return cachedAccessToken
        }

        let tokenURL = baseURL.appendingPathComponent("token")
        LegalicLogger.line("requestAccessToken: POST \(tokenURL.absoluteString)")
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "api_secret", value: apiSecret),
        ]
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            LegalicLogger.line("requestAccessToken: ОШИБКА — не собрать тело form-urlencoded")
            throw LegalicAPIError.invalidURL
        }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            LegalicLogger.line("requestAccessToken: сеть/URLSession: \(error.localizedDescription)")
            throw error
        }
        LegalicLogger.line("requestAccessToken: ответ, байт: \(data.count)")
        guard let http = response as? HTTPURLResponse else {
            LegalicLogger.line("requestAccessToken: ОШИБКА — ответ не HTTP")
            throw LegalicAPIError.noData
        }
        LegalicLogger.line("requestAccessToken: HTTP \(http.statusCode)")
        guard (200 ... 299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            LegalicLogger.line("requestAccessToken: ошибка \(http.statusCode), тело: \(bodyText.prefix(600))")
            throw LegalicAPIError.httpStatus(http.statusCode, bodyText)
        }

        let decoder = JSONDecoder()
        let envelope: LegalicTokenEnvelope
        do {
            envelope = try decoder.decode(LegalicTokenEnvelope.self, from: data)
        } catch {
            LegalicLogger.line("requestAccessToken: JSON токена не разобран: \(error.localizedDescription)")
            LegalicLogger.debugBodyPreview(data, maxBytes: 800)
            throw LegalicAPIError.decodingFailed(error.localizedDescription)
        }
        guard let token = envelope.accessToken, !token.isEmpty else {
            LegalicLogger.line("requestAccessToken: в JSON нет access_token")
            LegalicLogger.debugBodyPreview(data, maxBytes: 800)
            throw LegalicAPIError.tokenMissing
        }

        cachedAccessToken = token
        if let expires = envelope.expiresIn {
            tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expires))
            LegalicLogger.line("requestAccessToken: expires_in=\(expires) сек")
        } else {
            tokenExpiresAt = Date().addingTimeInterval(3600)
            LegalicLogger.line("requestAccessToken: expires_in не указан, кэш ~1 ч")
        }

        return token
    }

    private static func tasksURLAppendingPagination(base: URL, page: Int, perPage: Int) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        var items = components.queryItems ?? []
        func setQuery(_ name: String, _ value: String) {
            items.removeAll { $0.name == name }
            items.append(URLQueryItem(name: name, value: value))
        }
        setQuery("page", String(max(1, page)))
        setQuery("per_page", String(max(1, perPage)))
        components.queryItems = items
        return components.url ?? base
    }

    private func downloadTasksData(tasksURL: URL, accessToken: String) async throws -> Data {
        LegalicLogger.line("downloadTasks: GET \(tasksURL.absoluteString)")
        var request = URLRequest(url: tasksURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            LegalicLogger.line("downloadTasks: сеть/URLSession: \(error.localizedDescription)")
            throw error
        }
        LegalicLogger.line("downloadTasks: ответ, байт: \(data.count)")
        guard let http = response as? HTTPURLResponse else {
            LegalicLogger.line("downloadTasks: ОШИБКА — ответ не HTTP")
            throw LegalicAPIError.noData
        }
        LegalicLogger.line("downloadTasks: HTTP \(http.statusCode)")

        if http.statusCode == 401 {
            LegalicLogger.line("downloadTasks: 401 — сброс кэша токена")
            invalidateToken()
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            LegalicLogger.line("downloadTasks: ошибка \(http.statusCode)")
            LegalicLogger.debugBodyPreview(data, maxBytes: 1500)
            throw LegalicAPIError.httpStatus(http.statusCode, bodyText)
        }

        if data.isEmpty {
            LegalicLogger.line("downloadTasks: предупреждение — тело ответа пустое")
        }

        return data
    }
}

private struct LegalicTokenEnvelope: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}
