import Foundation
import Testing
@testable import SimpleNoteTaker

struct MeetingLibraryTests {
    @Test func parsesSummaryFilename() {
        let parsed = MeetingLibrary.parseMeetingFilename("meeting-2026-05-02-143000-summary.md")
        #expect(parsed != nil)
        #expect(parsed?.kind == .summary)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed!.date)
        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 2)
        #expect(components.hour == 14)
        #expect(components.minute == 30)
    }

    @Test func parsesTranscriptFilename() {
        let parsed = MeetingLibrary.parseMeetingFilename("meeting-2026-05-02-143000-transcript.md")
        #expect(parsed?.kind == .transcript)
    }

    @Test func parsesLegacyCombinedFilename() {
        let parsed = MeetingLibrary.parseMeetingFilename("meeting-2026-05-02-143000.md")
        #expect(parsed?.kind == .legacyCombined)
    }

    @Test func returnsNilForNonMeetingFilename() {
        #expect(MeetingLibrary.parseMeetingFilename("random.md") == nil)
        #expect(MeetingLibrary.parseMeetingFilename("meeting-bad.md") == nil)
        #expect(MeetingLibrary.parseMeetingFilename("meeting-bad-summary.md") == nil)
    }

    @Test func parsesTitleFromH1() {
        let content = """
        # Meeting — Q3 roadmap sync

        _Recorded 2026-05-02 14:30_

        ## Summary
        Discussed pipeline priorities.

        ## Key Points
        - Reviewed backlog
        """
        let (title, snippet) = MeetingLibrary.parseTitleAndSnippet(content: content, fallbackDate: Date())
        #expect(title == "Q3 roadmap sync")
        #expect(snippet == "Discussed pipeline priorities.")
    }

    @Test func loadGroupsSummaryAndTranscriptByTimestamp() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let summary = dir.appending(path: "meeting-2026-05-02-100000-summary.md")
        let transcript = dir.appending(path: "meeting-2026-05-02-100000-transcript.md")
        try "# Meeting — Paired\n\n## Summary\nA snippet.".write(to: summary, atomically: true, encoding: .utf8)
        try "# Meeting Transcript — 2026-05-02 10:00\n\n[0:00] me: hi".write(to: transcript, atomically: true, encoding: .utf8)

        let meetings = try await MeetingLibrary.load(from: dir)
        #expect(meetings.count == 1)
        #expect(meetings[0].title == "Paired")
        #expect(meetings[0].summaryURL?.lastPathComponent == summary.lastPathComponent)
        #expect(meetings[0].transcriptURL?.lastPathComponent == transcript.lastPathComponent)
        #expect(meetings[0].legacyCombinedURL == nil)
        #expect(meetings[0].isLegacy == false)
        #expect(meetings[0].primaryURL.lastPathComponent == summary.lastPathComponent)
    }

    @Test func loadHandlesLegacyCombinedAlone() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let legacy = dir.appending(path: "meeting-2026-05-02-100000.md")
        try "# Meeting — Legacy Combined\n\n## Summary\nPre-split file.".write(to: legacy, atomically: true, encoding: .utf8)

        let meetings = try await MeetingLibrary.load(from: dir)
        #expect(meetings.count == 1)
        #expect(meetings[0].isLegacy == true)
        #expect(meetings[0].summaryURL == nil)
        #expect(meetings[0].transcriptURL == nil)
        #expect(meetings[0].legacyCombinedURL?.lastPathComponent == legacy.lastPathComponent)
        #expect(meetings[0].primaryURL.lastPathComponent == legacy.lastPathComponent)
    }

    @Test func loadSortsNewestFirst() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let older = dir.appending(path: "meeting-2026-05-01-100000-summary.md")
        let newer = dir.appending(path: "meeting-2026-05-02-100000-summary.md")
        try "# Meeting — Older".write(to: older, atomically: true, encoding: .utf8)
        try "# Meeting — Newer".write(to: newer, atomically: true, encoding: .utf8)

        let meetings = try await MeetingLibrary.load(from: dir)
        #expect(meetings.map(\.title) == ["Newer", "Older"])
    }

    @Test func parseDurationFindsLastTimestamp() {
        let content = """
        # Meeting Transcript — 2026-05-02 14:30

        [0:00] me: Hi
        [0:03] them: Hello
        [12:45] me: Closing
        """
        let duration = MeetingLibrary.parseDuration(content: content)
        #expect(duration == TimeInterval(12 * 60 + 45))
    }

    @Test func parseDurationReturnsNilWhenNoTimestamps() {
        #expect(MeetingLibrary.parseDuration(content: "no timestamps here") == nil)
    }

    @Test func loadComputesDurationFromTranscript() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let summary = dir.appending(path: "meeting-2026-05-02-100000-summary.md")
        let transcript = dir.appending(path: "meeting-2026-05-02-100000-transcript.md")
        try "# Meeting — Test".write(to: summary, atomically: true, encoding: .utf8)
        try "# Meeting Transcript — t\n[5:30] me: x\n".write(to: transcript, atomically: true, encoding: .utf8)

        let meetings = try await MeetingLibrary.load(from: dir)
        #expect(meetings.first?.durationSeconds == TimeInterval(5 * 60 + 30))
        #expect(meetings.first?.durationLabel == "5 min")
    }

    @Test func loadReturnsEmptyForMissingDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-missing-\(UUID().uuidString)")
        let meetings = try await MeetingLibrary.load(from: dir)
        #expect(meetings.isEmpty)
    }
}
