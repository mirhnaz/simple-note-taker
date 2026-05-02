import Foundation
import Testing
@testable import SimpleNoteTaker

struct MeetingFilesTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let date: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 2
        components.hour = 14
        components.minute = 30
        components.second = 5
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    @Test func timestampFormat() {
        #expect(MeetingFiles.timestamp(date, timeZone: utc) == "2026-05-02-143005")
    }

    @Test func micAudioFilename() {
        #expect(MeetingFiles.audioFilename(for: date, kind: .mic, timeZone: utc) == "meeting-2026-05-02-143005-mic.m4a")
    }

    @Test func systemAudioFilename() {
        #expect(MeetingFiles.audioFilename(for: date, kind: .system, timeZone: utc) == "meeting-2026-05-02-143005-system.m4a")
    }

    @Test func transcriptFilename() {
        #expect(MeetingFiles.transcriptFilename(for: date, timeZone: utc) == "meeting-2026-05-02-143005.md")
    }
}
