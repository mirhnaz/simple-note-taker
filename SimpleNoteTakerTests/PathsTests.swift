import Foundation
import Testing
@testable import SimpleNoteTaker

struct PathsTests {
    @Test func defaultNotesDirectoryEndsInMeetings() {
        let url = Paths.defaultNotesDirectory
        #expect(url.lastPathComponent == "Meetings")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Documents")
    }

    @Test func defaultAudioDirectoryEndsInAudioFilesUnderMeetings() {
        let url = Paths.defaultAudioDirectory
        #expect(url.lastPathComponent == "Audio_files")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Meetings")
    }

    @Test func displayPathReplacesHomeWithTilde() {
        let url = URL(filePath: NSHomeDirectory()).appending(path: "Documents/Test")
        #expect(Paths.displayPath(url) == "~/Documents/Test")
    }

    @Test func displayPathLeavesNonHomePathAlone() {
        let url = URL(filePath: "/private/tmp/foo")
        #expect(Paths.displayPath(url) == "/private/tmp/foo")
    }

    @Test func ensureDirectoryExistsCreatesNewDirectory() throws {
        let url = uniqueTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Paths.ensureDirectoryExists(url)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func ensureDirectoryExistsCreatesIntermediateDirectories() throws {
        let root = uniqueTempURL()
        let nested = root.appending(path: "a/b/c")
        defer { try? FileManager.default.removeItem(at: root) }
        try Paths.ensureDirectoryExists(nested)
        #expect(FileManager.default.fileExists(atPath: nested.path(percentEncoded: false)))
    }

    @Test func ensureDirectoryExistsIsIdempotent() throws {
        let url = uniqueTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Paths.ensureDirectoryExists(url)
        try Paths.ensureDirectoryExists(url)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    private func uniqueTempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "snt-test-\(UUID().uuidString)")
    }
}
