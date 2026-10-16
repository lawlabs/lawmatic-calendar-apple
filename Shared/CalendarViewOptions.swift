import SwiftUI

/// Общие параметры отображения в меню macOS, iPhone и iPad.
struct CalendarViewOptions: View {
    @Bindable var viewModel: CalendarViewModel

    var body: some View {
        Toggle("Показывать субботу и воскресенье", isOn: $viewModel.showWeekends)
        Toggle("Подсвечивать выходные", isOn: $viewModel.highlightWeekends)
        Toggle("Подсвечивать праздники и переносы", isOn: $viewModel.highlightHolidays)
        Toggle("Отмечать рабочие переносы и сокращённые дни", isOn: $viewModel.showWorkingDayMarkers)
    }
}
