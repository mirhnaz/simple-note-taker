import SwiftUI
import os

private let startupLog = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "startup")

@main
struct SimpleNoteTakerApp: App {
    init() {
        startupLog.info("app init begin")
        _ = try? Paths.ensureDirectoryExists(AppSettings.shared.notesDirectory)
        _ = try? Paths.ensureDirectoryExists(AppSettings.shared.audioDirectory)
        startupLog.info("app init end")
    }

    var body: some Scene {
        Window("SimpleNoteTaker", id: "main") {
            MainWindow()
        }
        .defaultSize(width: 900, height: 620)

        WindowGroup("Meeting", for: Date.self) { $date in
            if let date {
                MeetingDetailView(meetingDate: date)
            } else {
                Text("No meeting selected").foregroundStyle(.secondary)
            }
        }
        .defaultSize(width: 720, height: 640)

        MenuBarExtra("SimpleNoteTaker", systemImage: "waveform.circle") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindow()
        }
    }
}
