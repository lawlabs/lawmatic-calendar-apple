import Foundation

struct LegalicTasksPageEnvelope: Sendable {
    let tasks: [LegalicTaskImport]
    let page: Int
    let pageCount: Int
    let perPage: Int
    let totalCount: Int
}

enum LegalicTaskJSONParser {
    static func parseTasks(from data: Data) throws -> [LegalicTaskImport] {
        try parseTasksPage(from: data).tasks
    }

    static func parseTasksPage(from data: Data) throws -> LegalicTasksPageEnvelope {
        let object = try JSONSerialization.jsonObject(with: data)
        let rows = try extractRows(from: object)
        let meta = paginationMeta(from: object, fallbackItemCount: rows.count)
        LegalicLogger.line("parseTasks: извлечено строк задач: \(rows.count)")
        if let first = rows.first {
            let keys = first.keys.sorted().joined(separator: ", ")
            let startValue = String(describing: first["start"])
            let finishValue = String(describing: first["finish"])
            let createdValue = String(describing: first["created"])
            LegalicLogger.line("parseTasks: ключи первой задачи: \(keys.prefix(500))")
            LegalicLogger.line(
                "parseTasks: образец сырых полей start=\(startValue) finish=\(finishValue) created=\(createdValue)"
            )
        }
        let parsed = try rows.compactMap { try parseOne($0) }
        LegalicLogger.line("parseTasks: после отбора неудалённых: \(parsed.count)")
        LegalicLogger.line(
            "parseTasks: пагинация API — page=\(meta.page) page_count=\(meta.pageCount) per_page=\(meta.perPage) total_count=\(meta.totalCount)"
        )
        if let task = parsed.first {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.timeZone = TimeZone.current
            LegalicLogger.line(
                "parseTasks: первая в календаре «\(task.title.prefix(50))» → \(formatter.string(from: task.startDate)) — \(formatter.string(from: task.endDate)) (\(TimeZone.current.identifier))"
            )
        }
        return LegalicTasksPageEnvelope(
            tasks: parsed,
            page: meta.page,
            pageCount: meta.pageCount,
            perPage: meta.perPage,
            totalCount: meta.totalCount
        )
    }

    private struct PaginationMeta {
        let page: Int
        let pageCount: Int
        let perPage: Int
        let totalCount: Int
    }

    private static func paginationMeta(from object: Any, fallbackItemCount: Int) -> PaginationMeta {
        guard let dict = object as? [String: Any] else {
            return PaginationMeta(page: 1, pageCount: 1, perPage: fallbackItemCount, totalCount: fallbackItemCount)
        }
        let page = intValue(dict["page"]) ?? 1
        let pageCount = intValue(dict["page_count"]) ?? 1
        let perPage = intValue(dict["per_page"]) ?? fallbackItemCount
        let totalCount = intValue(dict["total_count"]) ?? fallbackItemCount
        return PaginationMeta(page: page, pageCount: max(1, pageCount), perPage: max(1, perPage), totalCount: max(0, totalCount))
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    private static func extractRows(from object: Any) throws -> [[String: Any]] {
        if let array = object as? [[String: Any]] {
            return array
        }
        guard let dict = object as? [String: Any] else {
            throw LegalicAPIError.decodingFailed("Корень JSON не объект и не массив.")
        }

        let rootKeys = dict.keys.sorted().joined(separator: ", ")
        LegalicLogger.line("extractRows: ключи корня объекта: \(rootKeys.prefix(800))")

        if let data = dict["data"] as? [[String: Any]] { return data }
        if let tasks = dict["tasks"] as? [[String: Any]] { return tasks }
        if let items = dict["items"] as? [[String: Any]] { return items }
        if let members = dict["hydra:member"] as? [[String: Any]] { return members }
        if let members = dict["member"] as? [[String: Any]] { return members }

        LegalicLogger.line("extractRows: не найден массив задач — см. ключи корня выше")
        throw LegalicAPIError.decodingFailed(
            "Ожидался массив задач или ключи data / tasks / items / hydra:member."
        )
    }

    private static func parseOne(_ dict: [String: Any]) throws -> LegalicTaskImport? {
        if isTaskDeleted(dict) { return nil }

        let id = stringValue(dict["guid"])
            ?? stringValue(dict["id"])
            ?? stringValue(dict["uuid"])
            ?? stringValue(dict["@id"])
            ?? UUID().uuidString

        let title = extractTitle(dict) ?? shortLabel(for: id)

        let start = firstDate(dict, keys: [
            "start", "left_task_boundary", "starts_at", "start_at", "begin_at", "start_date", "from", "scheduled_at",
            "planned_at", "execution_at", "opened_at", "remind_start", "begin",
        ])
        let end = firstDate(dict, keys: [
            "finish", "right_task_boundary", "finish_at", "ends_at", "end_at", "end_date", "to", "completed_at", "closed_at", "end",
        ])
        let due = firstDate(dict, keys: [
            "due_at", "due_date", "deadline", "deadline_at", "due", "limit_date",
        ])
        let created = firstDate(dict, keys: ["created_at", "createdAt", "created"])
        let updated = firstDate(dict, keys: ["updated_at", "updatedAt", "updated"])

        let notes = extractNotes(dict)

        let (startDate, endDate, isAllDay) = resolveRange(
            start: start,
            end: end,
            due: due,
            created: created,
            updated: updated,
            id: id
        )

        return LegalicTaskImport(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            notes: notes,
            updatedAt: updated ?? created ?? .distantPast
        )
    }

    private static func isTaskDeleted(_ dict: [String: Any]) -> Bool {
        if let b = dict["is_deleted"] as? Bool { return b }
        if let i = dict["is_deleted"] as? Int { return i != 0 }
        if let s = dict["is_deleted"] as? String {
            let text = s.lowercased()
            return text == "1" || text == "true" || text == "yes"
        }
        return false
    }

    private static func shortLabel(for id: String) -> String {
        if id.count > 12 { return "Задача \(id.prefix(8))…" }
        return "Задача \(id)"
    }

    private static func extractTitle(_ dict: [String: Any]) -> String? {
        let directKeys = [
            "title", "name", "subject", "label", "caption", "summary", "headline",
            "taskTitle", "displayName", "text",
        ]
        for key in directKeys {
            if let text = dict[key] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let nestedContainers = ["case", "matter", "deal", "lawsuit", "project", "client", "contact"]
        for key in nestedContainers {
            guard let inner = dict[key] as? [String: Any] else { continue }
            if let title = extractTitle(inner) { return title }
            if let name = inner["title"] as? String ?? inner["name"] as? String, !name.isEmpty {
                return name
            }
        }

        return nil
    }

    private static func extractNotes(_ dict: [String: Any]) -> String {
        let keys = ["message", "description", "body", "comment", "notes", "details"]
        for key in keys {
            if let text = dict[key] as? String, !text.isEmpty { return text }
        }
        return ""
    }

    private static func firstDate(_ dict: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let date = parseDateValue(dict[key]) { return date }
        }
        return nil
    }

    private static func stringValue(_ any: Any?) -> String? {
        switch any {
        case let s as String:
            return s
        case let i as Int:
            return String(i)
        case let i64 as Int64:
            return String(i64)
        default:
            return nil
        }
    }

    private static func parseDateValue(_ any: Any?) -> Date? {
        switch any {
        case let s as String:
            return parseStringAsDate(s)
        case let t as TimeInterval:
            return dateFromUnixNumber(t)
        case let n as NSNumber:
            return dateFromUnixNumber(n.doubleValue)
        case let i as Int:
            return dateFromUnixNumber(Double(i))
        case let i64 as Int64:
            return dateFromUnixNumber(Double(i64))
        case let dict as [String: Any]:
            if let date = parseDateValue(dict["date"] ?? dict["datetime"] ?? dict["time"]) { return date }
            return nil
        default:
            return nil
        }
    }

    private static func dateFromUnixNumber(_ d: Double) -> Date? {
        guard d.isFinite, d > 0 else { return nil }
        if d >= 1e15 { return Date(timeIntervalSince1970: d / 1_000_000.0) }
        if d >= 1e12 { return Date(timeIntervalSince1970: d / 1000.0) }
        if d >= 1e8 { return Date(timeIntervalSince1970: d) }
        return nil
    }

    private static func parseStringAsDate(_ raw: String) -> Date? {
        let string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }
        if let date = parseISO8601(string) { return date }
        if let date = parseRussianDate(string) { return date }
        let numeric = string.filter { $0.isNumber || $0 == "." || $0 == "-" || $0 == "e" || $0 == "E" }
        if numeric == string, let value = Double(string) { return dateFromUnixNumber(value) }
        for formatter in flexibleDateFormatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    private static let flexibleDateFormatters: [DateFormatter] = {
        let zones: [TimeZone?] = [nil, TimeZone(secondsFromGMT: 0)]
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ]
        var list: [DateFormatter] = []
        for pattern in patterns {
            for timeZone in zones {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone ?? TimeZone.current
                formatter.dateFormat = pattern
                list.append(formatter)
            }
        }
        return list
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseISO8601(_ s: String) -> Date? {
        iso8601Fractional.date(from: s) ?? iso8601Plain.date(from: s)
    }

    private static func parseRussianDate(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 10, trimmed.contains("-") else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }

    private static func resolveRange(
        start: Date?,
        end: Date?,
        due: Date?,
        created: Date?,
        updated: Date?,
        id: String
    ) -> (Date, Date, Bool) {
        let calendar = Calendar.current

        if let start, let end, end > start {
            let allDay = calendar.isDate(start, inSameDayAs: end) &&
                calendar.component(.hour, from: start) == 0 &&
                calendar.component(.minute, from: start) == 0 &&
                calendar.component(.hour, from: end) == 23 &&
                calendar.component(.minute, from: end) >= 59
            return (start, end, allDay)
        }

        if let start {
            let resolvedEnd = end ?? calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
            return (start, max(resolvedEnd, start.addingTimeInterval(15 * 60)), false)
        }

        if let due {
            let dayStart = calendar.startOfDay(for: due)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? due
            return (dayStart, dayEnd, true)
        }

        if let end {
            let start = calendar.date(byAdding: .hour, value: -1, to: end) ?? end.addingTimeInterval(-3600)
            return (start, end, false)
        }

        let anchor = created ?? updated ?? Date()
        let dayStart = calendar.startOfDay(for: anchor)
        let minutesOffset = stableMinutesOffset(from: id, range: 8 * 60 ..< 19 * 60)
        let start = calendar.date(byAdding: .minute, value: minutesOffset, to: dayStart) ?? anchor
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        return (start, max(end, start.addingTimeInterval(15 * 60)), false)
    }

    private static func stableMinutesOffset(from id: String, range: Range<Int>) -> Int {
        var hash: UInt32 = 5381
        for byte in id.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt32(byte)
        }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return range.lowerBound }
        return range.lowerBound + Int(hash % UInt32(span))
    }
}
