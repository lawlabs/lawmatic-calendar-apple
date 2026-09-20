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
    @State private var viewModel = DemoMode.makeAppViewModel()

    var body: some Scene {
        WindowGroup {
            MacContentView(viewModel: viewModel)
                .onOpenURL { _ = ProviderRegistry.shared.google.handleOpenURL($0) }
                // Интерфейс приложения русскоязычный; календарь Kalends берёт
                // язык подписей и формат дат из этой локали.
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .preferredColorScheme(DemoMode.colorScheme)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CalendarCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
#endif
