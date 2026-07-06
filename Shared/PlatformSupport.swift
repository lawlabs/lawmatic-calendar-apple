import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension Color {
    static var calendarWindowBackground: Color {
#if os(macOS)
        Color(NSColor.windowBackgroundColor)
#elseif os(iOS)
        Color(uiColor: .systemBackground)
#else
        Color(.systemBackground)
#endif
    }

    static var calendarControlBackground: Color {
#if os(macOS)
        Color(NSColor.controlBackgroundColor)
#elseif os(iOS)
        Color(uiColor: .secondarySystemBackground)
#else
        Color(.secondarySystemBackground)
#endif
    }

    static var calendarSeparator: Color {
#if os(macOS)
        Color(NSColor.separatorColor)
#elseif os(iOS)
        Color(uiColor: .separator)
#else
        Color.gray.opacity(0.2)
#endif
    }
}

extension View {
    @ViewBuilder
    func onHoverIfSupported(_ action: @escaping (Bool) -> Void) -> some View {
#if os(macOS)
        onHover(perform: action)
#else
        self
#endif
    }

    @ViewBuilder
    func resizeCursorIfAvailable() -> some View {
#if os(macOS)
        cursor(.resizeUpDown)
#else
        self
#endif
    }
}

#if os(macOS)
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { isHovering in
            if isHovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
#endif
