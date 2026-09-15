import Foundation

/// Задача LEGALIC в том виде, в каком её отдаёт лента `/sync/v1/task`
/// (`Task::toArray()` на сервере). Только поля, нужные календарю.
struct LegalicTaskRecord: Sendable, Equatable {
    let guid: String
    let usn: Int
    let isDeleted: Bool
    let caption: String
    let message: String
    let location: String
    let start: Date?
    let finish: Date?
    let leftBoundary: Date?
    let rightBoundary: Date?
    let isCompleted: Bool
    let updatedAt: Date
}

/// Срок по делу из ленты `/sync/v1/deadline`.
struct LegalicDeadlineRecord: Sendable, Equatable {
    let guid: String
    let usn: Int
    let isDeleted: Bool
    let title: String
    let notes: String
    let dueDate: Date?
    let status: String
    let updatedAt: Date
}

/// Разбор записей ленты и сборка тела для записи обратно.
///
/// Даты сервер отдаёт строкой `Y-m-d H:i:s` без зоны — трактуем их в текущей
/// зоне устройства (так же делает LawMatic B2). Метки времени `created_at` /
/// `updated_at` — unix-секунды.
enum LegalicTaskMapper {
    static let tasksResource = "task"
    static let deadlinesResource = "deadline"

    // MARK: - Разбор ленты

    static func taskRecord(from object: [String: Any]) -> LegalicTaskRecord? {
        guard let guid = stringValue(object["guid"]), !guid.isEmpty else { return nil }
        let completePercent = intValue(object["task_complete"]) ?? 0
        let gtdStatus = (stringValue(object["gtd_status"]) ?? "").lowercased()
        return LegalicTaskRecord(
            guid: guid,
            usn: intValue(object["usn"]) ?? 0,
            isDeleted: boolValue(object["is_deleted"]) ?? false,
            caption: (stringValue(object["caption"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            message: stringValue(object["message"]) ?? "",
            location: stringValue(object["location"]) ?? "",
            start: dateValue(object["start"]),
            finish: dateValue(object["finish"]),
            leftBoundary: dateValue(object["left_task_boundary"]),
            rightBoundary: dateValue(object["right_task_boundary"]),
            isCompleted: completePercent >= 100 || gtdStatus == "done",
            updatedAt: dateValue(object["updated_at"]) ?? dateValue(object["updated"])
                ?? dateValue(object["created_at"]) ?? .distantPast
        )
    }

    static func deadlineRecord(from object: [String: Any]) -> LegalicDeadlineRecord? {
        guard let guid = stringValue(object["guid"]), !guid.isEmpty else { return nil }
        let typeTitle = (object["deadline_type"] as? [String: Any]).flatMap { stringValue($0["value"]) ?? stringValue($0["title"]) }
        let title = stringValue(object["title"]) ?? stringValue(object["label"]) ?? typeTitle ?? "Срок по делу"
        return LegalicDeadlineRecord(
            guid: guid,
            usn: intValue(object["usn"]) ?? 0,
            isDeleted: boolValue(object["is_deleted"]) ?? false,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: stringValue(object["notes"]) ?? "",
            dueDate: dateValue(object["due_date"]),
            status: (stringValue(object["status"]) ?? "open").lowercased(),
            updatedAt: dateValue(object["updated_at"]) ?? dateValue(object["updated"]) ?? .distantPast
        )
    }

    // MARK: - В события календаря

    /// Задача → событие календаря. `nil` — у задачи нет ни одной даты (в
    /// календаре ей нечего показывать, а выдумывать дату по `created` нельзя)
    /// либо она закончилась раньше `horizon`: рабочая база хранит десятки тысяч
    /// закрытых задач за годы, календарю нужны только недавние и будущие.
    static func remoteEvent(
        from task: LegalicTaskRecord,
        providerID: ProviderID,
        remoteCalendarID: String,
        horizon: Date? = nil
    ) -> ParsedRemoteEvent? {
        guard let range = displayRange(for: task) else { return nil }
        if let horizon, range.end < horizon { return nil }
        return ParsedRemoteEvent(
            remoteRef: RemoteEventRef(providerID: providerID, remoteCalendarID: remoteCalendarID, remoteEventID: task.guid),
            title: task.caption.isEmpty ? "Задача" : task.caption,
            start: range.start,
            end: range.end,
            isAllDay: range.isAllDay,
            notes: task.message,
            location: task.location,
            updatedAt: task.updatedAt,
            etag: String(task.usn)
        )
    }

    /// Срок → целодневное событие на дату срока. Отменённые и старее `horizon` не показываем.
    static func remoteEvent(
        from deadline: LegalicDeadlineRecord,
        providerID: ProviderID,
        remoteCalendarID: String,
        horizon: Date? = nil
    ) -> ParsedRemoteEvent? {
        guard let dueDate = deadline.dueDate, deadline.status != "cancelled" else { return nil }
        if let horizon, dueDate < horizon { return nil }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: dueDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? dayStart
        let prefix: String
        switch deadline.status {
        case "met": prefix = "✓ "
        case "missed": prefix = "⚠︎ "
        default: prefix = ""
        }
        return ParsedRemoteEvent(
            remoteRef: RemoteEventRef(providerID: providerID, remoteCalendarID: remoteCalendarID, remoteEventID: deadline.guid),
            title: prefix + deadline.title,
            start: dayStart,
            end: dayEnd,
            isAllDay: true,
            notes: deadline.notes,
            location: "",
            updatedAt: deadline.updatedAt,
            etag: String(deadline.usn)
        )
    }

    struct DisplayRange: Equatable {
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    /// Правила: есть начало и конец — как есть (целодневное, если полночь → конец
    /// дня); только начало — час; только конец — целодневное на день конца;
    /// нет ни того ни другого, но есть границы — целодневный интервал границ.
    static func displayRange(for task: LegalicTaskRecord) -> DisplayRange? {
        let calendar = Calendar.current
        let minimumDuration: TimeInterval = 15 * 60

        if let start = task.start, let finish = task.finish {
            let (lo, hi) = start <= finish ? (start, finish) : (finish, start)
            if isMidnight(lo, calendar) && (isMidnight(hi, calendar) || isEndOfDay(hi, calendar)) {
                let endDay = isMidnight(hi, calendar) && hi > lo
                    ? calendar.date(byAdding: .day, value: -1, to: hi) ?? hi
                    : hi
                return DisplayRange(start: lo, end: endOfDay(endDay, calendar), isAllDay: true)
            }
            return DisplayRange(start: lo, end: max(hi, lo.addingTimeInterval(minimumDuration)), isAllDay: false)
        }
        if let start = task.start {
            if isMidnight(start, calendar) {
                return DisplayRange(start: start, end: endOfDay(start, calendar), isAllDay: true)
            }
            return DisplayRange(start: start, end: start.addingTimeInterval(3600), isAllDay: false)
        }
        if let finish = task.finish {
            if isMidnight(finish, calendar) || isEndOfDay(finish, calendar) {
                let day = calendar.startOfDay(for: finish)
                return DisplayRange(start: day, end: endOfDay(day, calendar), isAllDay: true)
            }
            return DisplayRange(start: finish.addingTimeInterval(-3600), end: finish, isAllDay: false)
        }
        if task.leftBoundary != nil || task.rightBoundary != nil {
            let lo = calendar.startOfDay(for: task.leftBoundary ?? task.rightBoundary!)
            let hi = calendar.startOfDay(for: task.rightBoundary ?? task.leftBoundary!)
            return DisplayRange(start: min(lo, hi), end: endOfDay(max(lo, hi), calendar), isAllDay: true)
        }
        return nil
    }

    // MARK: - Тело записи

    /// Поля задачи для `POST /sync/v1/task`. Правка — с `base_usn`; создание — без.
    static func requestBody(for event: CalendarEvent, remoteGuid: String, baseUsn: Int?) -> [String: any Sendable] {
        let calendar = Calendar.current
        var body: [String: any Sendable] = [
            "guid": remoteGuid,
            "caption": event.title,
            "message": event.notes,
            "location": event.location,
        ]
        if event.isAllDay {
            let start = calendar.startOfDay(for: event.startDate)
            let end = endOfDay(max(start, calendar.startOfDay(for: event.endDate)), calendar)
            body["start"] = dateTimeString(start)
            body["finish"] = dateTimeString(end)
        } else {
            body["start"] = dateTimeString(event.startDate)
            body["finish"] = dateTimeString(event.endDate)
        }
        if let baseUsn { body["base_usn"] = baseUsn }
        return body
    }

    static func deletionBody(remoteGuid: String, baseUsn: Int?) -> [String: any Sendable] {
        var body: [String: any Sendable] = ["guid": remoteGuid, "is_deleted": true]
        if let baseUsn { body["base_usn"] = baseUsn }
        return body
    }

    /// guid задачи для новой записи: сервер принимает клиентский ключ, а формат
    /// у него — UUID строчными буквами.
    static func remoteGuid(for event: CalendarEvent) -> String {
        event.id.uuidString.lowercased()
    }

    // MARK: - Даты

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
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

    static func dateTimeString(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    /// Разумные границы дат. В рабочей базе встречаются «нулевые» даты MySQL
    /// (`0000-00-00 00:00:00` → год −1) и Delphi (`1899-12-30`): это отсутствие
    /// даты, а не дата. Пропустить их дальше нельзя — `JSONDecoder` не читает
    /// отрицательный год, и один такой файл ронял загрузку всей базы.
    static let plausibleDateRange: ClosedRange<Date> = {
        let calendar = Calendar(identifier: .gregorian)
        let lower = calendar.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 1970, month: 1, day: 1))!
        let upper = calendar.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2200, month: 1, day: 1))!
        return lower ... upper
    }()

    static func dateValue(_ any: Any?) -> Date? {
        let parsed: Date?
        switch any {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("0000-"), !trimmed.hasPrefix("-") else { return nil }
            parsed = dateTimeFormatter.date(from: trimmed)
                ?? dateOnlyFormatter.date(from: trimmed)
                ?? iso8601Fractional.date(from: trimmed)
                ?? iso8601Plain.date(from: trimmed)
                ?? Double(trimmed).flatMap(unixDate)
        case let number as NSNumber:
            parsed = unixDate(number.doubleValue)
        case let int as Int:
            parsed = unixDate(Double(int))
        case let double as Double:
            parsed = unixDate(double)
        default:
            parsed = nil
        }
        guard let parsed, plausibleDateRange.contains(parsed) else { return nil }
        return parsed
    }

    private static func unixDate(_ value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        if value >= 1e12 { return Date(timeIntervalSince1970: value / 1000) }
        return Date(timeIntervalSince1970: value)
    }

    private static func isMidnight(_ date: Date, _ calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return components.hour == 0 && components.minute == 0 && components.second == 0
    }

    private static func isEndOfDay(_ date: Date, _ calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return components.hour == 23 && (components.minute ?? 0) >= 59
    }

    private static func endOfDay(_ date: Date, _ calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? dayStart
    }

    // MARK: - Значения

    static func stringValue(_ any: Any?) -> String? {
        switch any {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let int as Int: return int
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    static func boolValue(_ any: Any?) -> Bool? {
        switch any {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.intValue != 0
        case let string as String:
            let text = string.lowercased()
            return text == "1" || text == "true" || text == "yes"
        default: return nil
        }
    }
}
