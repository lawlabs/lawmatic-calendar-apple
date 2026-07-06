import Foundation

enum LegalicLogger {
    static func line(_ message: String) {
        print("[LEGALIC] \(message)")
    }

    static func debugBodyPreview(_ data: Data, maxBytes: Int = 1200) {
        let prefix = data.prefix(maxBytes)
        let text = String(data: prefix, encoding: .utf8) ?? "<не UTF-8, байт: \(data.count)>"
        line("Тело ответа (первые \(prefix.count) байт):\n\(text)")
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
