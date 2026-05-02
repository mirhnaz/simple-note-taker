import Foundation
import Testing
@testable import SimpleNoteTaker

struct MeetingLibraryTests {
    @Test func parsesDateFromMeetingFilename() {
        let date = MeetingLibrary.parseDate(from: "meeting-2026-05-02-143000.md")
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date!)
        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 2)
        #expect(components.hour == 14)
        #expect(components.minute == 30)
        #expect(components.second == 0)
    }

    @Test func returnsNilForNonMeetingFilename() {
        #expect(MeetingLibrary.parseDate(from: "random.md") == nil)
        #expect(MeetingLibrary.parseDate(from: "meeting-bad.md") == nil)
    }

    @Test func parsesTitleFromH1() {
        let content = """
        # Meeting — Q3 roadmap sync

        _Recorded 2026-05-02 14:30_

        ## Summary
        Discussed pipeline priorities.

        ## Transcript
        ...
        """
        let (title, snippet) = MeetingLibrary.parseTitleAndSnippet(content: content, fallbackDate: Date())
        #expect(title == "Q3 roadmap sync")
        #expect(snippet == "Discussed pipeline priorities.")
    }

    @Test func returnsBlankTitleWhenH1MatchesFallbackDate() {
        let date = Date(timeIntervalSince1970: 1_746_198_600) // 2026-05-02 14:30 UTC
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = f.string(from: date)
        let content = """
        # Meeting — \(timestamp)

        ## Transcript
        body
        """
        let (title, _) = MeetingLibrary.parseTitleAndSnippet(content: content, fallbackDate: date)
        #expect(title.isEmpty)
    }

    @Test func returnsNilSnippetWhenSummarySectionMissing() {
        let content = """
        # Meeting — Standup

        ## Transcript
        [0:00] me: hi
        """
        let (_, snippet) = MeetingLibrary.parseTitleAndSnippet(content: content, fallbackDate: Date())
        #expect(snippet == nil)
    }

    @Test func loadScansDirectoryAndSortsNewestFirst() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let older = dir.appending(path: "meeting-2026-05-01-100000.md")
        let newer = dir.appending(path: "meeting-2026-05-02-100000.md")
        try "# Meeting — Older\n\n## Transcript\nx".write(to: older, atomically: true, encoding: .utf8)
        try "# Meeting — Newer\n\n## Summary\nA snippet.\n\n## Transcript\nx".write(to: newer, atomically: true, encoding: .utf8)

        // Bystander files should be ignored.
        try "ignore me".write(to: dir.appending(path: "notes.md"), atomically: true, encoding: .utf8)
        try "also ignore".write(to: dir.appending(path: "meeting-bad.md"), atomically: true, encoding: .utf8)

        let meetings = try await MeetingLibrary.load(from: dir)
        #expect(meetings.count == 2)
        #expect(meetings[0].title == "Newer")
        #expect(meetings[0].summarySnippet == "A snippet.")
        #expect(meetings[1].title == "Older")
    }

    @Test func loadReturnsEmptyForMissingDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-missing-\(UUID().uuidString)")
        let meetings = try await MeetingLibrary.load(from: dir)
        #expect(meetings.isEmpty)
    }
}
