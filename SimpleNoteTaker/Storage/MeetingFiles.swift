import Foundation

enum AudioKind: String, Sendable {
    case mic
    case system
}

enum MeetingFiles {
    static func audioFilename(for date: Date, kind: AudioKind, timeZone: TimeZone = .current) -> String {
        "meeting-\(timestamp(date, timeZone: timeZone))-\(kind.rawValue).m4a"
    }

    static func transcriptFilename(for date: Date, timeZone: TimeZone = .current) -> String {
        "meeting-\(timestamp(date, timeZone: timeZone)).md"
    }

    static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
