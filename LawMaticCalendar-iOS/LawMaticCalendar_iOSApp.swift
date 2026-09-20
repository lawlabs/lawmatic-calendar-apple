//
//  LawMaticCalendar_iOSApp.swift
//  LawMaticCalendar-iOS
//
//  Created by Sergey on 19.04.2026.
//

import SwiftUI

@main
@MainActor
struct LawMaticCalendar_iOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { _ = ProviderRegistry.shared.google.handleOpenURL($0) }
                // Интерфейс приложения русскоязычный; календарь Kalends берёт
                // язык подписей и формат дат из этой локали.
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .preferredColorScheme(DemoMode.colorScheme)
        }
    }
}
