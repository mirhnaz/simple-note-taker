import Foundation

enum SettingsKeys {
    static let notesDirectoryPath = "notesDirectoryPath"
    static let retainAudioFiles = "retainAudioFiles"
    static let audioDirectoryPath = "audioDirectoryPath"
}

struct AppSettings {
    let defaults: UserDefaults

    nonisolated static let shared = AppSettings(defaults: .standard)

    var notesDirectory: URL {
        let stored = defaults.string(forKey: SettingsKeys.notesDirectoryPath) ?? ""
        return stored.isEmpty ? Paths.defaultNotesDirectory : URL(filePath: stored)
    }

    var retainAudioFiles: Bool {
        defaults.bool(forKey: SettingsKeys.retainAudioFiles)
    }

    var audioDirectory: URL {
        let stored = defaults.string(forKey: SettingsKeys.audioDirectoryPath) ?? ""
        return stored.isEmpty ? Paths.defaultAudioDirectory : URL(filePath: stored)
    }
}
