import Foundation

enum ProviderStatus: Equatable {
    case signedOut
    case syncing
    case signedIn(accountLabel: String)
    case error(String)
}

enum ProviderError: LocalizedError {
    case notImplemented(provider: ProviderID, operation: String)
    case unknownProvider(ProviderID)
    case providerDisabled(ProviderID)
    case missingCredentials(provider: ProviderID)
    case notAuthorized(provider: ProviderID)
    case remoteCalendarNotFound(remoteID: String)
    case syncTokenExpired
    case preconditionFailed
    case invalidResponse(String)
    case httpStatus(Int, String?)
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let provider, let operation):
            return "\(provider.displayName): операция «\(operation)» не поддерживается."
        case .unknownProvider(let provider):
            return "Провайдер \(provider.displayName) не зарегистрирован."
        case .providerDisabled(let provider):
            return "Синхронизация с \(provider.displayName) выключена."
        case .missingCredentials(let provider):
            return "\(provider.displayName) не настроен. Откройте настройки аккаунтов."
        case .notAuthorized(let provider):
            return "Нет доступа к \(provider.displayName). Подключите аккаунт в настройках."
        case .remoteCalendarNotFound(let id):
            return "Удалённый календарь не найден: \(id)."
        case .syncTokenExpired:
            return "Курсор синхронизации устарел; требуется полная синхронизация."
        case .preconditionFailed:
            return "Событие изменилось на сервере во время синхронизации. Локальная операция сохранена и будет повторена после следующего чтения."
        case .invalidResponse(let message), .underlying(let message):
            return message
        case .httpStatus(let code, let body):
            let suffix = body.flatMap { $0.isEmpty ? nil : "\n\($0.prefix(500))" } ?? ""
            return "Сервер вернул HTTP \(code).\(suffix)"
        }
    }
}
