import Foundation
import Kalends

/// Офлайн-снимки производственного календаря РФ на 2022-2027 годы.
/// Файлы те же, что в LawMatic B2: их собирает BusinessCalendar-site, здесь они только читаются.
/// Правила праздников заново не вычисляются.
struct ProductionCalendar: Sendable {
    struct DayKey: Hashable, Sendable {
        var year: Int
        var month: Int
        var day: Int
    }

    private struct Record: Sendable {
        var kind: KalendsDayKind
        var isShortened: Bool
        var description: String?
    }

    private let days: [DayKey: Record]
    let years: Set<Int>
    /// Год файла, который не удалось прочитать. Ключ берётся из имени `2024.json`.
    let failures: [Int: String]
    /// Заполняется, если в приложении не оказалось ни одного годного снимка.
    let loadError: String?

    func contains(year: Int) -> Bool {
        years.contains(year)
    }

    /// Гражданская дата в календаре представления. `nil`, если этого года нет в снимках.
    func info(on date: Date, calendar: Calendar) -> KalendsDayInfo? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let record = days[DayKey(year: year, month: month, day: day)]
        else { return nil }
        return KalendsDayInfo(kind: record.kind, isShortened: record.isShortened, description: record.description)
    }

    /// Снимки лежат в ресурсах приложения. Тесты видят их, потому что идут внутри host-приложения.
    static let current: ProductionCalendar = load(bundle: .main)

    static func load(bundle: Bundle) -> ProductionCalendar {
        load(urls: snapshotURLs(in: bundle))
    }

    static func load(urls: [URL]) -> ProductionCalendar {
        var days: [DayKey: Record] = [:]
        var years = Set<Int>()
        var failures: [Int: String] = [:]
        if urls.isEmpty {
            return ProductionCalendar(
                days: [:],
                years: [],
                failures: [:],
                loadError: "Справочник праздников и переносов не найден. Показаны обычные суббота и воскресенье."
            )
        }
        for url in urls {
            do {
                let year = try addYear(Data(contentsOf: url), into: &days)
                years.insert(year)
            } catch {
                if let year = yearNumber(in: url) {
                    failures[year] = error.localizedDescription
                }
            }
        }
        let loadError: String? = years.isEmpty
            ? (failures.values.first ?? "Справочник праздников и переносов недоступен. Показаны обычные суббота и воскресенье.")
            : nil
        return ProductionCalendar(days: days, years: years, failures: failures, loadError: loadError)
    }

    /// Текст над сеткой. Год без файла и год с битым файлом объясняются по-разному.
    func notice(for visibleYears: [Int]) -> String? {
        let missing = visibleYears.filter { !years.contains($0) }.sorted()
        guard !missing.isEmpty else { return nil }
        let broken = missing.filter { failures[$0] != nil }
        if !broken.isEmpty {
            let details = broken.compactMap { failures[$0] }.joined(separator: " ")
            if broken.count == 1 {
                return "Снимок производственного календаря на \(broken[0]) год не прочитан. \(details) Для этих дат показаны обычные суббота и воскресенье."
            }
            let list = broken.map(String.init).joined(separator: ", ")
            return "Снимки производственного календаря на \(list) годы не прочитаны. \(details) Для этих дат показаны обычные суббота и воскресенье."
        }
        if years.isEmpty {
            return loadError ?? "Справочник праздников и переносов недоступен. Показаны обычные суббота и воскресенье."
        }
        let list = missing.map(String.init).joined(separator: ", ")
        let yearWord = missing.count == 1 ? "год" : "годы"
        return "Праздники и переносы на \(list) \(yearWord) не загружены. Для этих дат показаны обычные суббота и воскресенье."
    }

    /// Имя файла и есть год: `2028.json` подхватится без правки диапазона.
    /// Чужие json в бандле не берём, вложенные фреймворки не обходим.
    private static func snapshotURLs(in bundle: Bundle) -> [URL] {
        guard let root = bundle.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else { return [] }

        var byYear: [Int: URL] = [:]
        let skipped = Set(["Frameworks", "PlugIns", "Extensions", "XPCServices"])
        while let item = enumerator.nextObject() as? URL {
            if skipped.contains(item.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let year = yearNumber(in: item), byYear[year] == nil else { continue }
            byYear[year] = item
        }
        return byYear.keys.sorted().compactMap { byYear[$0] }
    }

    private static func yearNumber(in url: URL) -> Int? {
        guard url.pathExtension == "json" else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        guard name.count == 4, let year = Int(name), (1...9998).contains(year) else { return nil }
        return year
    }

    private static func addYear(_ data: Data, into days: inout [DayKey: Record]) throws -> Int {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.calendar == "RU-FEDERAL" else {
            throw ProductionCalendarError("Неверный код производственного календаря.")
        }
        let year = snapshot.version.year
        guard (1...9998).contains(year) else {
            throw ProductionCalendarError("Неверный год производственного календаря.")
        }
        guard snapshot.version.status == "OFFICIAL" || snapshot.version.status == "PRELIMINARY" else {
            throw ProductionCalendarError("Неизвестный статус календаря \(year).")
        }
        let preliminary = snapshot.version.status == "PRELIMINARY"
        let versionId = snapshot.version.versionId
        guard !versionId.isEmpty else {
            throw ProductionCalendarError("Нет версии календаря \(year).")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let dayCount = calendar.range(of: .day, in: .year, for: first)?.count
        else {
            throw ProductionCalendarError("Не удалось разобрать год \(year).")
        }
        guard snapshot.days.count == dayCount else {
            throw ProductionCalendarError("Неполный календарь \(year).")
        }

        var loaded: [DayKey: Record] = [:]
        loaded.reserveCapacity(dayCount)
        for (offset, day) in snapshot.days.enumerated() {
            guard let key = DayKey(iso: day.date),
                  let date = calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day)),
                  calendar.component(.year, from: date) == key.year,
                  calendar.component(.month, from: date) == key.month,
                  calendar.component(.day, from: date) == key.day,
                  let expected = calendar.date(byAdding: .day, value: offset, to: first),
                  calendar.isDate(date, inSameDayAs: expected)
            else {
                throw ProductionCalendarError("Нарушен порядок дат календаря \(year).")
            }
            let kind = try kind(for: day.type, date: day.date)
            let working = kind == .working || kind == .transferredWorking
            guard day.isWorking == working, !day.shortened || day.isWorking else {
                throw ProductionCalendarError("Несогласованный тип дня \(day.date).")
            }
            let shortened = day.shortened && working
            loaded[key] = Record(
                kind: kind,
                isShortened: shortened,
                description: explanation(
                    kind: kind,
                    shortened: shortened,
                    holidayName: day.holidayName,
                    transferredFrom: day.transferredFrom,
                    transferredTo: day.transferredTo,
                    trace: day.trace ?? [],
                    versionId: versionId,
                    preliminary: preliminary
                )
            )
        }
        days.merge(loaded) { _, new in new }
        return year
    }

    private static func kind(for type: String, date: String) throws -> KalendsDayKind {
        switch type {
        case "WORKING", "SHORTENED_WORKING":
            return .working
        case "TRANSFERRED_WORKING":
            return .transferredWorking
        case "WEEKEND":
            return .weekend
        case "PUBLIC_HOLIDAY", "SPECIAL_NON_WORKING":
            return .holiday
        case "TRANSFERRED_DAY_OFF":
            return .transferredDayOff
        default:
            throw ProductionCalendarError("Неизвестный тип дня \(date).")
        }
    }

    /// Текст для подсказки и VoiceOver. У обычного рабочего дня и обычной субботы/воскресенья
    /// его нет: Kalends подписывает их сам. Праздник, перенос и сокращение объясняются здесь.
    private static func explanation(
        kind: KalendsDayKind,
        shortened: Bool,
        holidayName: String?,
        transferredFrom: String?,
        transferredTo: String?,
        trace: [Snapshot.Trace],
        versionId: String,
        preliminary: Bool
    ) -> String? {
        var lines: [String] = []
        switch kind {
        case .holiday:
            let name = holidayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            lines.append(name.isEmpty ? "Нерабочий день" : name)
        case .transferredDayOff:
            if let transferredFrom {
                lines.append("Выходной перенесён с \(civil(transferredFrom)).")
            } else {
                lines.append("Перенесённый выходной.")
            }
        case .transferredWorking:
            if let transferredTo {
                lines.append("Рабочий день: выходной перенесён на \(civil(transferredTo)).")
            } else {
                lines.append("Рабочий день вследствие переноса.")
            }
        case .working, .weekend:
            break
        }
        if shortened {
            lines.append("Сокращённый рабочий день (−1 час).")
        }
        // В подсказку попадают только юридические основания переноса.
        // BASE_GRID, PUBLIC_HOLIDAY и PRE_HOLIDAY_SHORTENING уже видны в типе дня,
        // названии праздника и признаке сокращения. Новый шаг трассировки сам
        // сюда не попадёт: его нужно добавить явно, иначе в подсказке окажется служебный текст сетки.
        for step in trace where step.step == "GOV_TRANSFER" || step.step == "AUTO_TRANSFER_112" {
            let note = step.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                lines.append(note)
            }
        }
        guard !lines.isEmpty else { return nil }
        lines.append("Производственный календарь РФ, пятидневка · \(versionId)")
        if preliminary {
            lines.append("Предварительные данные.")
        }
        return lines.joined(separator: "\n")
    }

    private static func civil(_ iso: String) -> String {
        guard let key = DayKey(iso: iso) else { return iso }
        return String(format: "%02d.%02d.%04d", key.day, key.month, key.year)
    }
}

private struct ProductionCalendarError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

private struct Snapshot: Decodable {
    var calendar: String
    var version: Version
    var days: [Day]

    struct Version: Decodable {
        var versionId: String
        var year: Int
        var status: String
    }

    struct Day: Decodable {
        var date: String
        var type: String
        var isWorking: Bool
        var shortened: Bool
        var holidayName: String?
        var transferredFrom: String?
        var transferredTo: String?
        var trace: [Trace]?
    }

    struct Trace: Decodable {
        var step: String
        var note: String
    }
}

private extension ProductionCalendar.DayKey {
    init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }
}
