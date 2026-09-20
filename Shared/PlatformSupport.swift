import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension Color {
    static var calendarControlBackground: Color {
#if os(macOS)
        Color(NSColor.controlBackgroundColor)
#elseif os(iOS)
        Color(uiColor: .secondarySystemBackground)
#else
        Color(.secondarySystemBackground)
#endif
    }
}
