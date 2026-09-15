//
//  LawMaticCalendarApp.swift
//  LawMaticCalendar
//
//  Created by Sergey on 30.09.2025.
//

#if os(macOS)
import SwiftUI

@main
@MainActor
struct LawMaticCalendarApp: App {
    @State private var viewModel = CalendarViewModel()

    var body: some Scene {
        WindowGroup {
            MacContentView(viewModel: viewModel)
                .onOpenURL { _ = ProviderRegistry.shared.google.handleOpenURL($0) }
        }
        .commands {
            CalendarCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
#endif
