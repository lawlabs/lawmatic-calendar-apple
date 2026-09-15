import Foundation
import os

/// Логирование интеграции LEGALIC через `os.Logger`.
///
/// Сообщения помечены `privacy: .private`: в release-логах они видны только
/// при включённом профиле отладки, а тела ответов (в них данные клиентов)
/// пишутся только в DEBUG-сборках.
enum LegalicLogger {
    private static let logger = Logger(subsystem: "com.lawmatic.calendar", category: "legalic")

    static func line(_ message: String) {
        logger.info("\(message, privacy: .private)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .private)")
    }

    static func debugBodyPreview(_ data: Data, maxBytes: Int = 1200) {
        #if DEBUG
        let prefix = data.prefix(maxBytes)
        let text = String(data: prefix, encoding: .utf8) ?? "<не UTF-8, байт: \(data.count)>"
        logger.debug("Тело ответа (первые \(prefix.count) байт):\n\(text, privacy: .private)")
        #endif
    }

    static func maskedApiKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 4 else { return "(пусто или слишком короткий)" }
        return String(trimmed.prefix(4)) + "… (\(trimmed.count) симв.)"
    }

    static func maskedTokenPrefix(_ token: String) -> String {
        guard token.count >= 8 else { return "(короткий)" }
        return String(token.prefix(8)) + "…"
    }
}
