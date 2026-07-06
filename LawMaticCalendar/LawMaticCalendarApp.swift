//
//  CalendarTest45App.swift
//  CalendarTest45
//
//  Created by Sergey on 30.09.2025.
//

#if os(macOS)
import SwiftUI

@main
@MainActor
struct LawMaticCalendarApp: App {
    var body: some Scene {
        WindowGroup {
            MacContentView()
        }

        Settings {
            SettingsView()
        }
    }
}
#endif
