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
