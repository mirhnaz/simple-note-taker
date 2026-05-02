import Foundation
import Testing
@testable import SimpleNoteTaker

@MainActor
struct RecordingSessionCleanupTests {
    @Test func removeAudioFilesDeletesAllProvidedFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-cleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let micURL = dir.appending(path: "mic.m4a")
        let systemURL = dir.appending(path: "system.m4a")
        try Data([0]).write(to: micURL)
        try Data([0]).write(to: systemURL)
        #expect(FileManager.default.fileExists(atPath: micURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: systemURL.path(percentEncoded: false)))

        RecordingSession.removeAudioFiles([.mic: micURL, .system: systemURL])

        #expect(!FileManager.default.fileExists(atPath: micURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: systemURL.path(percentEncoded: false)))
    }

    @Test func removeAudioFilesIsBestEffortForMissingFiles() {
        let bogus = FileManager.default.temporaryDirectory.appending(path: "snt-missing-\(UUID().uuidString).m4a")
        // Should not throw or crash
        RecordingSession.removeAudioFiles([.mic: bogus])
    }
}
