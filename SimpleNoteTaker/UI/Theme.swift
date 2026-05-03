import AppKit
import SwiftUI

extension Color {
    /// Window background — cream/wheat in light mode (matches the meetily
    /// look the user picked as inspiration), system default in dark mode.
    static var appWindowBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if isDark {
                return NSColor.windowBackgroundColor
            }
            return NSColor(srgbRed: 0.962, green: 0.933, blue: 0.871, alpha: 1.0)
        }))
    }

    /// Card background — sits on top of `appWindowBackground`. Slightly off-
    /// white in light mode for separation, system secondary in dark mode.
    static var appCardBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if isDark {
                return NSColor.controlBackgroundColor
            }
            return NSColor(srgbRed: 0.992, green: 0.984, blue: 0.965, alpha: 1.0)
        }))
    }
}
