import SwiftUI

@main
struct SimpleNoteTakerApp: App {
    init() {
        _ = try? Paths.ensureDirectoryExists(AppSettings.shared.notesDirectory)
        _ = try? Paths.ensureDirectoryExists(AppSettings.shared.audioDirectory)
    }

    var body: some Scene {
        Window("SimpleNoteTaker", id: "main") {
            MainWindow()
        }
        .defaultSize(width: 900, height: 620)

        MenuBarExtra("SimpleNoteTaker", systemImage: "waveform.circle") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindow()
        }
    }
}
