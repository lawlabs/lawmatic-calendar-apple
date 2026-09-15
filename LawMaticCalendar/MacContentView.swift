#if os(macOS)
import SwiftUI

@MainActor
struct MacContentView: View {
    @Bindable var viewModel: CalendarViewModel

    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @AppStorage("inspector.isPresented") private var isInspectorPresented = true
    @State private var isSyncErrorPopoverPresented = false

    init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CalendarSidebarView(viewModel: viewModel)
                .frame(minWidth: 200)
        } detail: {
            VStack(spacing: 0) {
                contentView
            }
            .navigationTitle(navigationTitle)
            .navigationSubtitle(navigationSubtitle)
            .toolbar { toolbarContent }
            .onExitCommand {
                viewModel.clearSelection()
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            EventInspectorView(viewModel: viewModel)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
        .alert(item: $viewModel.storageError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .focusedSceneValue(\.calendarViewModel, viewModel)
        .onAppear {
            viewModel.undoManager = undoManager
            viewModel.startPeriodicSync()
        }
        .onChange(of: undoManager) { _, newValue in
            viewModel.undoManager = newValue
        }
        .onChange(of: viewModel.inspectorState) { _, newValue in
            // Выбор события открывает инспектор, если пользователь его скрыл.
            if newValue != nil, !isInspectorPresented {
                isInspectorPresented = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.handleDidBecomeActive()
            case .inactive, .background:
                viewModel.flushPendingSaves()
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            viewModel.prepareForTermination()
        }
    }

    // MARK: - Тулбар

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                viewModel.moveToPreviousPeriod()
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Предыдущий период (⌘←)")
            .accessibilityLabel("Предыдущий период")

            Button("Сегодня") {
                viewModel.moveToToday()
            }
            .help("Перейти к сегодняшнему дню (⌘T)")

            Button {
                viewModel.moveToNextPeriod()
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Следующий период (⌘→)")
            .accessibilityLabel("Следующий период")
        }

        ToolbarItem(placement: .principal) {
            Picker("Режим", selection: $viewModel.viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
            .help("Режим просмотра (⌘1–⌘4)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.createNewEvent(referenceDate: viewModel.selectedDate)
            } label: {
                Image(systemName: "plus")
            }
            .help("Новое событие (⌘N)")
            .accessibilityLabel("Новое событие")

            if viewModel.syncError != nil {
                Button {
                    isSyncErrorPopoverPresented = true
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .help("Ошибка синхронизации — нажмите для подробностей")
                .accessibilityLabel("Ошибка синхронизации")
                .popover(isPresented: $isSyncErrorPopoverPresented, arrowEdge: .bottom) {
                    syncErrorPopover
                }
            }

            Button {
                Task { await viewModel.syncAllProviders() }
            } label: {
                if viewModel.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Синхронизировать", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .help(syncHelpText)
            .accessibilityLabel("Синхронизировать")
            .disabled(viewModel.isSyncing)

            Button {
                isInspectorPresented.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Показать или скрыть инспектор (⌥⌘I)")
            .accessibilityLabel("Инспектор")
        }
    }

    private var syncErrorPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.syncError?.title ?? "Синхронизация")
                .font(.headline)
            Text(viewModel.syncError?.message ?? "")
                .font(.callout)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button("Скрыть") {
                    viewModel.syncError = nil
                    isSyncErrorPopoverPresented = false
                }
                Button("Повторить") {
                    isSyncErrorPopoverPresented = false
                    Task { await viewModel.syncAllProviders() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var syncHelpText: String {
        guard let date = viewModel.lastSuccessfulSyncDate else {
            return "Синхронизировать подключённые календари (⌘R)"
        }
        return "Синхронизировать (⌘R). Последний раз: \(date.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: - Заголовок

    private var navigationTitle: String {
        switch viewModel.viewMode {
        case .day:
            return viewModel.selectedDate.dayMonthString()
        case .week:
            let days = viewModel.selectedDate.getDaysOfWeek()
            guard let first = days.first, let last = days.last else { return "Неделя" }
            if Calendar.current.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(first.shortDayString())–\(last.dayMonthString()) \(last.yearOnlyString())"
            }
            return "\(first.dayMonthString()) – \(last.dayMonthString()) \(last.yearOnlyString())"
        case .month:
            return viewModel.selectedDate.monthYearString()
        case .year:
            return viewModel.selectedDate.yearOnlyString()
        }
    }

    private var navigationSubtitle: String {
        switch viewModel.viewMode {
        case .day:
            return viewModel.selectedDate.weekdayLowerString()
        case .week, .month, .year:
            return ""
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.viewMode {
        case .day:
            MacDayView(viewModel: viewModel)
        case .week:
            WeekView(viewModel: viewModel)
        case .month:
            MacMonthView(viewModel: viewModel)
        case .year:
            MacYearView(viewModel: viewModel)
        }
    }
}

// MARK: - Команды меню и клавиатура

private struct CalendarViewModelFocusedKey: FocusedValueKey {
    typealias Value = CalendarViewModel
}

extension FocusedValues {
    var calendarViewModel: CalendarViewModel? {
        get { self[CalendarViewModelFocusedKey.self] }
        set { self[CalendarViewModelFocusedKey.self] = newValue }
    }
}

struct CalendarCommands: Commands {
    @FocusedValue(\.calendarViewModel) private var viewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Новое событие") {
                viewModel?.createNewEvent()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(viewModel == nil)
        }

        CommandGroup(after: .pasteboard) {
            Button("Удалить событие") {
                viewModel?.deleteSelectedEvent()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel?.selectedEvent == nil)
        }

        CommandMenu("Вид") {
            Button("День") { viewModel?.viewMode = .day }
                .keyboardShortcut("1", modifiers: .command)
            Button("Неделя") { viewModel?.viewMode = .week }
                .keyboardShortcut("2", modifiers: .command)
            Button("Месяц") { viewModel?.viewMode = .month }
                .keyboardShortcut("3", modifiers: .command)
            Button("Год") { viewModel?.viewMode = .year }
                .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Сегодня") { viewModel?.moveToToday() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Предыдущий период") { viewModel?.moveToPreviousPeriod() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Следующий период") { viewModel?.moveToNextPeriod() }
                .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider()

            Button("Синхронизировать") {
                guard let viewModel else { return }
                Task { await viewModel.syncAllProviders() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(viewModel == nil || viewModel?.isSyncing == true)
        }
    }
}

#Preview {
    MacContentView(viewModel: .preview())
}
#endif
