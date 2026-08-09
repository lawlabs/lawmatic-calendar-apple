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
        }
    }
}
