import SwiftUI

@main
struct SimpleNoteTakerApp: App {
    init() {
        _ = try? Paths.ensureDirectoryExists(AppSettings.shared.notesDirectory)
        _ = try? Paths.ensureDirectoryExists(AppSettings.shared.audioDirectory)
    }

    var body: some Scene {
        MenuBarExtra("SimpleNoteTaker", systemImage: "waveform.circle") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Window("Library", id: "library") {
            LibraryWindow()
        }
        .defaultSize(width: 800, height: 560)

        Settings {
            SettingsWindow()
        }
    }
}
