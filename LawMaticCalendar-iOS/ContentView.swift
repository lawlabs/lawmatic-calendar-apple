//
//  ContentView.swift
//  LawMaticCalendar-iOS
//
//  Created by Sergey on 19.04.2026.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel = CalendarViewModel()
    @State private var isSettingsPresented = false

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        Group {
            if isCompactLayout {
                compactLayout
            } else {
                regularLayout
            }
        }
        .sheet(item: compactInspectorBinding) { _ in
            NavigationStack {
                EventInspectorView(viewModel: viewModel)
                    .navigationTitle(sheetTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Закрыть") {
                                viewModel.closeInspector()
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Настройки")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Готово") {
                                isSettingsPresented = false
                            }
                        }
                    }
            }
        }
        .alert(item: $viewModel.storageError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $viewModel.legalicSyncError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var compactLayout: some View {
        TabView {
            NavigationStack {
                IOSCalendarWorkspaceView(
                    viewModel: viewModel,
                    isCompactLayout: true,
                    isSettingsPresented: $isSettingsPresented
                )
            }
            .tabItem {
                Label("Календарь", systemImage: "calendar")
            }

            NavigationStack {
                CalendarSidebarView(viewModel: viewModel)
                    .navigationTitle("Календари")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isSettingsPresented = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Списки", systemImage: "sidebar.left")
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            CalendarSidebarView(viewModel: viewModel)
                .navigationTitle("LawMatic")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isSettingsPresented = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        } detail: {
            IOSCalendarWorkspaceView(
                viewModel: viewModel,
                isCompactLayout: false,
                isSettingsPresented: $isSettingsPresented
            )
            .safeAreaInset(edge: .trailing) {
                if viewModel.isInspectorPresented {
                    EventInspectorView(viewModel: viewModel)
                        .frame(width: 320)
                        .background(Color.calendarControlBackground)
                        .overlay(alignment: .leading) {
                            Divider()
                        }
                }
            }
        }
    }

    private var compactInspectorBinding: Binding<EventInspectorState?> {
        Binding(
            get: {
                isCompactLayout ? viewModel.inspectorState : nil
            },
            set: { newValue in
                if newValue == nil {
                    viewModel.closeInspector()
                } else {
                    viewModel.inspectorState = newValue
                }
            }
        )
    }

    private var sheetTitle: String {
        viewModel.isEditingEvent ? "Событие" : "Просмотр"
    }
}

private struct IOSCalendarWorkspaceView: View {
    @ObservedObject var viewModel: CalendarViewModel
    let isCompactLayout: Bool
    @Binding var isSettingsPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isCompactLayout {
                compactModePicker
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }

            contentView
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    viewModel.moveToPreviousPeriod()
                } label: {
                    Image(systemName: "chevron.left")
                }

                if showsYearJump {
                    Button {
                        viewModel.viewMode = .year
                    } label: {
                        Text(viewModel.selectedDate.yearOnlyString())
                    }
                }
            }

            if !isCompactLayout {
                ToolbarItem(placement: .principal) {
                    Picker("Режим", selection: $viewModel.viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if shouldShowTodayShortcut {
                    Button("Сегодня") {
                        viewModel.moveToToday()
                    }
                }

                Button {
                    viewModel.moveToNextPeriod()
                } label: {
                    Image(systemName: "chevron.right")
                }

                Button {
                    viewModel.createNewEvent(referenceDate: viewModel.selectedDate)
                } label: {
                    Image(systemName: "plus")
                }

                Menu {
                    Button {
                        Task { await viewModel.syncAllProviders() }
                    } label: {
                        Label("Синхронизировать календари", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(viewModel.isSyncing)

                    Divider()

                    Button {
                        isSettingsPresented = true
                    } label: {
                        Label("Настройки", systemImage: "gearshape")
                    }
                } label: {
                    if viewModel.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var compactModePicker: some View {
        Picker("Режим", selection: $viewModel.viewMode) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.viewMode {
        case .day:
            DayView(viewModel: viewModel)
        case .week:
            WeekView(viewModel: viewModel)
        case .month:
            MonthView(viewModel: viewModel)
        case .year:
            YearView(viewModel: viewModel)
        }
    }

    private var navigationTitle: String {
        switch viewModel.viewMode {
        case .day:
            if Calendar.current.isDateInToday(viewModel.selectedDate) {
                return "Сегодня"
            }

            return viewModel.selectedDate.dayMonthString()
        case .week:
            return "Неделя"
        case .month:
            if isCompactLayout {
                return ""
            }

            return viewModel.selectedDate.monthYearString()
        case .year:
            if isCompactLayout {
                return ""
            }

            return viewModel.selectedDate.yearOnlyString()
        }
    }

    private var shouldShowTodayShortcut: Bool {
        switch viewModel.viewMode {
        case .day:
            return !Calendar.current.isDateInToday(viewModel.selectedDate)
        case .week:
            return !Calendar.current.isDate(viewModel.selectedDate.startOfWeek(), equalTo: Date().startOfWeek(), toGranularity: .day)
        case .month:
            if isCompactLayout {
                return false
            }

            return !Calendar.current.isDate(viewModel.selectedDate, equalTo: Date(), toGranularity: .month)
        case .year:
            if isCompactLayout {
                return false
            }

            return !Calendar.current.isDate(viewModel.selectedDate, equalTo: Date(), toGranularity: .year)
        }
    }

    private var showsYearJump: Bool {
        isCompactLayout && viewModel.viewMode == .month
    }
}

#Preview {
    ContentView()
}
