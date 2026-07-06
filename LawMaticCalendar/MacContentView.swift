#if os(macOS)
import SwiftUI

@MainActor
struct MacContentView: View {
    @StateObject private var viewModel: CalendarViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    init(viewModel: CalendarViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    init() {
        _viewModel = StateObject(wrappedValue: CalendarViewModel())
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CalendarSidebarView(viewModel: viewModel)
                .frame(minWidth: 200)
        } detail: {
            VStack(spacing: 0) {
                contentView
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Режим", selection: $viewModel.viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                ToolbarItem(placement: .navigation) {
                    Button {
                        viewModel.createNewEvent(referenceDate: viewModel.selectedDate)
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await viewModel.syncTasksFromLegalic() }
                    } label: {
                        if viewModel.isLegalicSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("LEGALIC", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .help("Загрузить задачи из LEGALIC")
                    .disabled(viewModel.isLegalicSyncing)
                }
            }
        }
        .inspector(isPresented: .constant(true)) {
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
        .alert(item: $viewModel.legalicSyncError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.viewMode {
        case .day:
            MacDayView(viewModel: viewModel)
        case .week:
            MacWeekView(viewModel: viewModel)
        case .month:
            MacMonthView(viewModel: viewModel)
        case .year:
            MacYearView(viewModel: viewModel)
        }
    }
}

#Preview {
    MacContentView(viewModel: .preview())
}
#endif
