import Foundation

enum Paths {
    static var defaultNotesDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "Meetings", directoryHint: .isDirectory)
    }

    static var defaultAudioDirectory: URL {
        defaultNotesDirectory
            .appending(path: "Audio_files", directoryHint: .isDirectory)
    }

    /// App-scoped Application Support directory. Durable across crashes and
    /// reboots — used for the in-progress recording marker so a meeting that
    /// was interrupted by a crash can be recovered on the next launch.
    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mir.SimpleNoteTaker"
        return base.appending(path: bundleID, directoryHint: .isDirectory)
    }

    @discardableResult
    static func ensureDirectoryExists(_ url: URL) throws -> URL {
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func displayPath(_ url: URL) -> String {
        let raw = url.path(percentEncoded: false)
        let home = NSHomeDirectory()
        return raw.hasPrefix(home) ? "~" + raw.dropFirst(home.count) : raw
    }
}
