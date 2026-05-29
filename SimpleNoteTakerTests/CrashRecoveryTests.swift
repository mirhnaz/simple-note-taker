import Foundation
import Testing
@testable import SimpleNoteTaker

struct CrashRecoveryTests {
    // MARK: - Stubs

    final class StubFileTranscriber: FileTranscribing, @unchecked Sendable {
        let textByKind: [AudioKind: String]
        init(textByKind: [AudioKind: String]) { self.textByKind = textByKind }
        func transcribe(audioFile url: URL, kind: AudioKind, onProgress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
            guard let text = textByKind[kind] else { return [] }
            return [TranscriptSegment(kind: kind, startSeconds: 0, endSeconds: 5, text: text)]
        }
    }

    struct StubSummarizer: Summarizing {
        let result: MeetingSummary?
        func summarize(transcript: String, meetingType: MeetingType) async -> MeetingSummary? { result }
    }

    private func writeDummyAudio(_ url: URL) throws {
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
    }

    // MARK: - Marker

    @Test func markerRoundTripsAndDetectsRecoverableAudio() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-rec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mic = dir.appending(path: "mic.m4a")
        try writeDummyAudio(mic)

        let marker = RecordingRecovery.Marker(
            micPath: mic.path(percentEncoded: false),
            systemPath: nil,
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            meetingTypeRaw: MeetingType.interview.rawValue,
            retainAudio: false
        )
        #expect(marker.meetingType == .interview)
        #expect(marker.hasRecoverableAudio == true)

        let data = try JSONEncoder().encode(marker)
        let decoded = try JSONDecoder().decode(RecordingRecovery.Marker.self, from: data)
        #expect(decoded == marker)
    }

    @Test func markerWithMissingAudioIsNotRecoverable() {
        let marker = RecordingRecovery.Marker(
            micPath: "/tmp/does-not-exist-\(UUID().uuidString).m4a",
            systemPath: nil,
            startedAt: Date(),
            meetingTypeRaw: MeetingType.general.rawValue
        )
        #expect(marker.hasRecoverableAudio == false)
    }

    // MARK: - Recovery

    @Test func recoverWritesMeetingFromBothStreamsAndCleansUp() async throws {
        let notes = FileManager.default.temporaryDirectory.appending(path: "snt-notes-\(UUID().uuidString)")
        let audio = FileManager.default.temporaryDirectory.appending(path: "snt-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: notes)
            try? FileManager.default.removeItem(at: audio)
        }

        let micURL = audio.appending(path: "mic.m4a")
        let systemURL = audio.appending(path: "system.m4a")
        try writeDummyAudio(micURL)
        try writeDummyAudio(systemURL)

        let suite = UserDefaults(suiteName: "snt-recovery-\(UUID().uuidString)")!
        suite.set(notes.path(percentEncoded: false), forKey: SettingsKeys.notesDirectoryPath)
        let settings = AppSettings(defaults: suite)

        let marker = RecordingRecovery.Marker(
            micPath: micURL.path(percentEncoded: false),
            systemPath: systemURL.path(percentEncoded: false),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            meetingTypeRaw: MeetingType.standup.rawValue,
            retainAudio: false
        )

        let transcriber = StubFileTranscriber(textByKind: [.mic: "My update.", .system: "Their update."])
        let summary = MeetingSummary(title: "Standup", headline: "", summary: "", keyPoints: [], actionItems: [], decisions: [])

        let summaryURL = try await CrashRecovery.recover(
            marker: marker,
            settings: settings,
            summarizer: StubSummarizer(result: summary),
            fileTranscriber: transcriber
        )

        // Meeting written with both speakers, typed as standup.
        #expect(FileManager.default.fileExists(atPath: summaryURL.path(percentEncoded: false)))
        let readingURL = notes.appending(path: MeetingFiles.readingFilename(for: marker.startedAt))
        let reading = try String(contentsOf: readingURL, encoding: .utf8)
        #expect(reading.contains("type: standup"))
        let transcriptText = try String(contentsOf: notes.appending(path: MeetingFiles.transcriptFilename(for: marker.startedAt)), encoding: .utf8)
        #expect(transcriptText.contains("My update."))
        #expect(transcriptText.contains("Their update."))

        // Orphaned audio removed (retainAudio == false).
        #expect(!FileManager.default.fileExists(atPath: micURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: systemURL.path(percentEncoded: false)))
    }

    @Test func discardRemovesAudio() throws {
        let audio = FileManager.default.temporaryDirectory.appending(path: "snt-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: audio) }
        let micURL = audio.appending(path: "mic.m4a")
        try writeDummyAudio(micURL)

        let marker = RecordingRecovery.Marker(
            micPath: micURL.path(percentEncoded: false),
            systemPath: nil,
            startedAt: Date(),
            meetingTypeRaw: MeetingType.general.rawValue
        )
        CrashRecovery.discard(marker: marker)
        #expect(!FileManager.default.fileExists(atPath: micURL.path(percentEncoded: false)))
    }
}
