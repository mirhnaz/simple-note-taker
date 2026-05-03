import AppKit
import SwiftUI

extension Color {
    /// App window background — uses the system `windowBackgroundColor` in
    /// both light and dark modes so we match Apple HIG. Earlier this was a
    /// custom cream tone but it stood out too much against other macOS apps.
    static var appWindowBackground: Color {
        Color(nsColor: NSColor.windowBackgroundColor)
    }

    /// Card background — sits on top of `appWindowBackground` with subtle
    /// contrast. Uses `controlBackgroundColor` (white in light mode, dark
    /// gray in dark mode) so cards read as raised surfaces by default.
    static var appCardBackground: Color {
        Color(nsColor: NSColor.controlBackgroundColor)
    }
}
