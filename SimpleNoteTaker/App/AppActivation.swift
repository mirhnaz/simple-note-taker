import AppKit
import Foundation

@MainActor
final class AppActivation {
    static let shared = AppActivation()

    /// Activates the app so a window opened from the menu bar comes to the
    /// front. The app stays in `.regular` activation policy at all times, so
    /// no policy switching is needed any more.
    func prepareToOpenWindow() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidAppear() {}

    func windowDidDisappear() {}
}
