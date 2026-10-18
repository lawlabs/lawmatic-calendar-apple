import Foundation
import Observation

/// Что показывать в сетке календаря: субботу и воскресенье и отметки
/// производственного календаря. Меняется в настройках, читается календарём.
///
/// В обычном запуске параметры лежат в `UserDefaults` и переживают
/// перезапуск; в демо-режиме, тестах и превью живут только в памяти.
@Observable
@MainActor
final class CalendarDisplaySettings {
    var showWeekends: Bool {
        didSet { store(showWeekends, Keys.showWeekends) }
    }
    var highlightWeekends: Bool {
        didSet { store(highlightWeekends, Keys.highlightWeekends) }
    }
    var highlightHolidays: Bool {
        didSet { store(highlightHolidays, Keys.highlightHolidays) }
    }
    var showWorkingDayMarkers: Bool {
        didSet { store(showWorkingDayMarkers, Keys.showWorkingDayMarkers) }
    }

    @ObservationIgnored private let defaults: UserDefaults?

    /// - Parameter defaults: где хранить параметры; `nil` — только в памяти.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        showWeekends = defaults?.object(forKey: Keys.showWeekends) as? Bool ?? true
        highlightWeekends = defaults?.object(forKey: Keys.highlightWeekends) as? Bool ?? true
        highlightHolidays = defaults?.object(forKey: Keys.highlightHolidays) as? Bool ?? true
        showWorkingDayMarkers = defaults?.object(forKey: Keys.showWorkingDayMarkers) as? Bool ?? true
    }

    /// Параметры обычного запуска, сохранённые между запусками.
    static func persistent() -> CalendarDisplaySettings {
        CalendarDisplaySettings(defaults: .standard)
    }

    private func store(_ value: Bool, _ key: String) {
        defaults?.set(value, forKey: key)
    }

    private enum Keys {
        static let showWeekends = "display.showWeekends"
        static let highlightWeekends = "display.highlightWeekends"
        static let highlightHolidays = "display.highlightHolidays"
        static let showWorkingDayMarkers = "display.showWorkingDayMarkers"
    }
}
