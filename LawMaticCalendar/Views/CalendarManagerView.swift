//
//  CalendarManagerView.swift
//  CalendarTest45
//
//  Created by Sergey on 14.01.2026.
//

import SwiftUI

/// Компонент для отображения списка календарей в боковой панели
struct CalendarManagerView: View {
    @ObservedObject var viewModel: CalendarViewModel

    var groupedCalendars: [String: [CalendarItem]] {
        Dictionary(grouping: viewModel.calendars) { $0.accountName }
    }

    var body: some View {
        ForEach(groupedCalendars.keys.sorted(), id: \.self) { account in
            Section(account) {
                ForEach(groupedCalendars[account] ?? []) { calendar in
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
    }
}
