import AppKit
import Foundation

@MainActor
final class AppActivation {
    static let shared = AppActivation()

    private(set) var openWindowCount: Int = 0

    /// Call this BEFORE opening a SwiftUI window from the menu bar so the
    /// app's own menu appears at the top of the screen the moment the window
    /// shows up. Doing this in .onAppear is too late — by then SwiftUI has
    /// already created the window with us still in .accessory, leaving the
    /// previous app's menu in the global menu bar.
    func prepareToOpenWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidAppear() {
        openWindowCount += 1
    }

    func windowDidDisappear() {
        openWindowCount = max(0, openWindowCount - 1)
        if openWindowCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
