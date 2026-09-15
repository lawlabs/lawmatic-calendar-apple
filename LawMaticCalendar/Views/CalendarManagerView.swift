//
//  CalendarManagerView.swift
//  CalendarTest45
//
//  Created by Sergey on 14.01.2026.
//

import SwiftUI

/// Компонент для отображения списка календарей в боковой панели
struct CalendarManagerView: View {
    var viewModel: CalendarViewModel

    private struct AccountGroup: Identifiable {
        let name: String
        let calendars: [CalendarItem]
        var id: String { name }
    }

    private var groupedCalendars: [AccountGroup] {
        Dictionary(grouping: viewModel.calendars) { $0.accountName }
            .map { AccountGroup(name: $0.key, calendars: $0.value) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ForEach(groupedCalendars) { group in
            Section(group.name) {
                ForEach(group.calendars) { calendar in
                    CalendarRowView(
                        calendar: calendar,
                        onToggle: { viewModel.toggleCalendarVisibility(calendar) }
                    )
                }
            }
        }
    }
}

/// Строка календаря с чекбоксом
struct CalendarRowView: View {
    let calendar: CalendarItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                // Чекбокс с цветом календаря
                Image(systemName: calendar.isVisible ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(calendar.isVisible ? calendar.color.color : .gray)

                Text(calendar.name)
                    .foregroundColor(.primary)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendar.name)
        .accessibilityValue(calendar.isVisible ? "показан" : "скрыт")
        .accessibilityAddTraits(.isToggle)
    }
}
