import Foundation

/// Учётная запись LEGALIC, как её видит сервер (`GET /sync/v1/me/info`).
struct LegalicAccountInfo: Equatable, Sendable {
    let guid: String
    let fullName: String
    let isActive: Bool
}

/// Страница курсорной ленты `/sync/v1/<ресурс>`, уже разобранная в записи.
struct LegalicFeedPage<Record: Sendable>: Sendable {
    let items: [Record]
    /// Отзыв доступа: guid записей, которые перестали быть видны этому пользователю.
    let revokedGuids: [String]
    let nextCursor: String?
    let hasMore: Bool
}

/// Итог записи `POST /sync/v1/<ресурс>`.
struct LegalicWriteResult<Record: Sendable>: Sendable {
    let status: Int
    let item: Record?
}

enum LegalicAPIError: LocalizedError, Equatable {
    case invalidServer(String)
    case authenticationFailed(String)
    case accountDeactivated
    case httpStatus(Int, String?)
    case malformedResponse(String)
    case forbidden
    case validationFailed(String)
    case dependencyMissing(String)

    var errorDescription: String? {
        switch self {
        case .invalidServer(let server):
            return "Непонятный адрес сервера LEGALIC: \(server)"
        case .authenticationFailed(let reason):
            return "Вход в LEGALIC не удался: \(reason)"
        case .accountDeactivated:
            return "Учётная запись LEGALIC деактивирована."
        case .httpStatus(let code, let body):
            let tail = body.flatMap { $0.isEmpty ? nil : "\n\($0.prefix(300))" } ?? ""
            return "Сервер LEGALIC вернул HTTP \(code).\(tail)"
        case .malformedResponse(let reason):
            return "Непонятный ответ LEGALIC: \(reason)"
        case .forbidden:
            return "LEGALIC: нет прав на изменение этой записи."
        case .validationFailed(let message):
            return "LEGALIC отклонил запись: \(message)"
        case .dependencyMissing(let message):
            return "LEGALIC: в записи есть ссылка на неизвестный объект. \(message)"
        }
    }
}

/// Транспорт курсорного контракта LEGALIC (`/token`, `/sync/v1/*`).
///
/// Вход по логину и паролю (`grant_type=password`), продление по `refresh_token`.
/// Секреты живут только в теле запроса токена: в логах и текстах ошибок их нет.
actor LegalicAPIClient {
    /// Потолок сервера — 500; значения вне диапазона он подрезает молча.
    static let feedPageLimit = 500
    /// За сколько секунд до истечения access-токен считается протухшим.
    private static let expiryMargin: TimeInterval = 60

    private struct TokenState {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
        /// Для каких учётных данных выдан токен.
        var credentialsKey: String
    }

    private let urlSession: URLSession
    private var tokens: TokenState?

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Нормализует адрес: «legalic.ru» → «https://legalic.ru», убирает хвостовой слэш.
    static func serverURL(from raw: String) throws -> URL {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { throw LegalicAPIError.invalidServer(raw) }
        if !trimmed.hasPrefix("http://"), !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed), url.host != nil else {
            throw LegalicAPIError.invalidServer(raw)
        }
        return url
    }

    func invalidateTokens() {
        tokens = nil
    }

    // MARK: - Вход

    /// Проверяет пару логин/пароль и возвращает, кем сервер нас видит.
    func signIn(server: URL, login: String, password: String) async throws -> LegalicAccountInfo {
        tokens = nil
        try await requestTokens(server: server, form: [
            "grant_type": "password",
            "login": login.trimmingCharacters(in: .whitespacesAndNewlines),
            // Пароль не нормализуем: пробел может быть его настоящей частью.
            "password": password,
        ], credentialsKey: Self.credentialsKey(server: server, login: login, password: password))
        return try await fetchAccountInfo(server: server, login: login, password: password)
    }

    func fetchAccountInfo(server: URL, login: String, password: String) async throws -> LegalicAccountInfo {
        let data = try await get(
            server: server, login: login, password: password,
            path: "/sync/v1/me/info", query: []
        )
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let guid = object["guid"] as? String, !guid.isEmpty
        else { throw LegalicAPIError.malformedResponse("в ответе me/info нет guid") }
        return LegalicAccountInfo(
            guid: guid,
            fullName: (object["full_name"] as? String) ?? "",
            isActive: (object["is_active"] as? Bool) ?? true
        )
    }

    // MARK: - Лента

    /// Страница ленты ресурса. `cursor == nil` — лента с начала.
    ///
    /// Испорченный курсор сервер отвечает `400`; для вызывающего это
    /// `ProviderError.syncTokenExpired` — лента перечитывается с начала.
    func fetchFeedPage<Record: Sendable>(
        server: URL, login: String, password: String,
        resource: String, cursor: String?, limit: Int = LegalicAPIClient.feedPageLimit,
        decode: @Sendable ([String: Any]) -> Record?
    ) async throws -> LegalicFeedPage<Record> {
        var query = [URLQueryItem(name: "limit", value: String(max(1, min(limit, Self.feedPageLimit))))]
        if let cursor, !cursor.isEmpty {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let data: Data
        do {
            data = try await get(
                server: server, login: login, password: password,
                path: "/sync/v1/\(resource)", query: query
            )
        } catch LegalicAPIError.httpStatus(400, _) where cursor != nil {
            throw ProviderError.syncTokenExpired
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LegalicAPIError.malformedResponse("тело ответа ленты не объект JSON")
        }
        if root["page_count"] != nil || root["total_count"] != nil {
            throw LegalicAPIError.malformedResponse("сервер отвечает старым постраничным форматом — нужен /sync/v1")
        }
        guard let rawItems = root["items"] as? [[String: Any]] else {
            throw LegalicAPIError.malformedResponse("в ответе ленты нет items")
        }
        let revoked = (root["revoked"] as? [[String: Any]] ?? []).compactMap { $0["entity_guid"] as? String }
        LegalicLogger.line("лента \(resource): записей \(rawItems.count), отзывов \(revoked.count), has_more=\(root["has_more"] ?? "?")")
        return LegalicFeedPage(
            items: rawItems.compactMap(decode),
            revokedGuids: revoked,
            nextCursor: root["next_cursor"] as? String,
            hasMore: (root["has_more"] as? Bool) ?? false
        )
    }

    // MARK: - Запись

    /// `POST /sync/v1/<ресурс>`: создание (без `base_usn`) или правка (с ним).
    ///
    /// `409` возвращается значением с актуальной версией сервера — разбираться с
    /// расхождением должен вызывающий, а не транспорт.
    func save<Record: Sendable>(
        server: URL, login: String, password: String,
        resource: String, body: [String: any Sendable], idempotencyKey: String,
        decode: @Sendable ([String: Any]) -> Record?
    ) async throws -> LegalicWriteResult<Record> {
        try await authorizeIfNeeded(server: server, login: login, password: password)

        var attemptedReauth = false
        while true {
            var request = URLRequest(url: server.appendingPathComponent("sync/v1/\(resource)"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
            if let token = tokens?.accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, http) = try await perform(request)
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            LegalicLogger.line("POST \(resource): HTTP \(http.statusCode)")

            switch http.statusCode {
            case 200, 201:
                return LegalicWriteResult(status: http.statusCode, item: (object?["item"] as? [String: Any]).flatMap(decode))
            case 409:
                if let item = object?["item"] as? [String: Any] {
                    return LegalicWriteResult(status: 409, item: decode(item))
                }
                // Голая 409 — «первый запрос с этим ключом ещё выполняется»: повторим позже.
                throw ProviderError.preconditionFailed
            case 401 where !attemptedReauth:
                attemptedReauth = true
                // Access-токен отозван раньше срока: считаем его истёкшим, но
                // refresh оставляем — продление дешевле повторного входа паролем.
                tokens?.expiresAt = .distantPast
                try await authorizeIfNeeded(server: server, login: login, password: password)
                continue
            case 403:
                throw LegalicAPIError.forbidden
            case 422:
                let message = (object?["message"] as? String) ?? (object?["error"] as? String) ?? ""
                if (object?["error"] as? String) == "dependency_missing" {
                    throw LegalicAPIError.dependencyMissing(message)
                }
                throw LegalicAPIError.validationFailed(message)
            default:
                throw LegalicAPIError.httpStatus(http.statusCode, Self.errorText(from: data))
            }
        }
    }

    // MARK: - Токены

    private static func credentialsKey(server: URL, login: String, password: String) -> String {
        "\(server.absoluteString)|\(login.trimmingCharacters(in: .whitespacesAndNewlines))|\(password.hashValue)"
    }

    private func authorizeIfNeeded(server: URL, login: String, password: String) async throws {
        let key = Self.credentialsKey(server: server, login: login, password: password)
        if let tokens, tokens.credentialsKey == key,
           tokens.expiresAt.timeIntervalSinceNow > Self.expiryMargin {
            return
        }
        if let refresh = tokens?.refreshToken, tokens?.credentialsKey == key, !refresh.isEmpty {
            do {
                try await requestTokens(
                    server: server,
                    form: ["grant_type": "refresh_token", "refresh_token": refresh],
                    credentialsKey: key
                )
                return
            } catch {
                // Протухший refresh — не повод сдаваться: пароль у нас есть.
                tokens = nil
            }
        }
        try await requestTokens(server: server, form: [
            "grant_type": "password",
            "login": login.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
        ], credentialsKey: key)
    }

    private func requestTokens(server: URL, form: [String: String], credentialsKey: String) async throws {
        var request = URLRequest(url: server.appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody(form)

        LegalicLogger.line("POST /token grant_type=\(form["grant_type"] ?? "?")")
        let (data, http) = try await perform(request)
        guard http.statusCode == 200 else {
            if http.statusCode == 403 { throw LegalicAPIError.accountDeactivated }
            throw LegalicAPIError.authenticationFailed(Self.authenticationErrorText(from: data, status: http.statusCode))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String, !accessToken.isEmpty
        else { throw LegalicAPIError.authenticationFailed("в ответе нет access_token") }

        let lifetime = TimeInterval((object["expires_in"] as? Int) ?? 86_400)
        tokens = TokenState(
            accessToken: accessToken,
            refreshToken: (object["refresh_token"] as? String) ?? tokens?.refreshToken,
            expiresAt: Date().addingTimeInterval(lifetime),
            credentialsKey: credentialsKey
        )
        LegalicLogger.line("токен получен, префикс \(LegalicLogger.maskedTokenPrefix(accessToken)), expires_in=\(Int(lifetime))")
    }

    // MARK: - HTTP

    private func get(
        server: URL, login: String, password: String,
        path: String, query: [URLQueryItem]
    ) async throws -> Data {
        try await authorizeIfNeeded(server: server, login: login, password: password)

        var attemptedReauth = false
        while true {
            guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else {
                throw LegalicAPIError.invalidServer(server.absoluteString)
            }
            components.path = (components.path + path).replacingOccurrences(of: "//", with: "/")
            components.queryItems = query.isEmpty ? nil : query
            guard let url = components.url else { throw LegalicAPIError.invalidServer(server.absoluteString) }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token = tokens?.accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, http) = try await perform(request)
            switch http.statusCode {
            case 200 ... 299:
                return data
            case 401 where !attemptedReauth:
                attemptedReauth = true
                // Access-токен отозван раньше срока: считаем его истёкшим, но
                // refresh оставляем — продление дешевле повторного входа паролем.
                tokens?.expiresAt = .distantPast
                try await authorizeIfNeeded(server: server, login: login, password: password)
                continue
            case 403:
                throw LegalicAPIError.forbidden
            default:
                throw LegalicAPIError.httpStatus(http.statusCode, Self.errorText(from: data))
            }
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LegalicAPIError.malformedResponse("ответ не HTTP")
        }
        return (data, http)
    }

    private static func formBody(_ form: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let pairs = form.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static func errorText(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = object["message"] as? String, !message.isEmpty { return message }
            if let error = object["error"] as? String, !error.isEmpty { return error }
        }
        return String(data: data, encoding: .utf8)
    }

    private static func authenticationErrorText(from data: Data, status: Int) -> String {
        let text = errorText(from: data)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch status {
        case 400 where text.lowercased().contains("credential") || text.lowercased().contains("invalid"):
            return "неверная почта или пароль"
        case 400:
            return text.isEmpty ? "сервер отклонил запрос (400)" : text
        default:
            return text.isEmpty ? "HTTP \(status)" : "\(text) (HTTP \(status))"
        }
    }
}
