import SwiftUI

/// Разделы настроек вида календаря: выходные и отметки производственного
/// календаря. Вкладка «Основные» на Mac и раздел настроек на iPhone и iPad.
struct CalendarDisplaySettingsSections: View {
    @Bindable var display: CalendarDisplaySettings

    var body: some View {
        Section {
            Toggle("Показывать субботу и воскресенье", isOn: $display.showWeekends)
            Toggle("Подсвечивать выходные", isOn: $display.highlightWeekends)
        } header: {
            Text("Выходные")
        } footer: {
            Text("Без субботы и воскресенья день, неделя и месяц показывают только будни. Год и мини-календарь сохраняют все даты.")
        }

        Section {
            Toggle("Подсвечивать праздники и переносы", isOn: $display.highlightHolidays)
            Toggle("Отмечать рабочие переносы и сокращённые дни", isOn: $display.showWorkingDayMarkers)
        } header: {
            Text("Производственный календарь")
        } footer: {
            // Неразрывные пробелы держат каждое обозначение вместе с пояснением.
            Text("Праздники, переносы и сокращённые дни — по производственному календарю РФ. Обозначения: П\u{00A0}— праздник, ↔\u{00A0}— перенесённый выходной, Р\u{00A0}— рабочий перенос, −1ч\u{00A0}— сокращённый день.")
        }
    }
}
