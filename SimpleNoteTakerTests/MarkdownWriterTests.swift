import Foundation
import Testing
@testable import SimpleNoteTaker

struct MarkdownWriterTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let meetingDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 2
        components.hour = 14
        components.minute = 30
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    @Test func summaryRendersHeaderAndTimestampLabel() {
        let rendered = MarkdownWriter.renderSummary(meetingDate: meetingDate, summary: nil, timeZone: utc)
        #expect(rendered.contains("# Meeting — 2026-05-02 14:30"))
        #expect(rendered.contains("_Recorded 2026-05-02 14:30_"))
        #expect(rendered.contains("_(no summary available)_"))
        #expect(!rendered.contains("## Transcript"), "summary file must not include the transcript section")
    }

    @Test func summaryRendersAllSectionsWhenProvided() {
        let summary = MeetingSummary(
            title: "Q3 roadmap sync",
            headline: "Team aligned on import refactor.",
            summary: "Discussed pipeline priorities.",
            keyPoints: ["Backlog reviewed", "Import is the bottleneck"],
            actionItems: ["Naz to draft RFC"],
            decisions: ["Ship in Q3"]
        )
        let rendered = MarkdownWriter.renderSummary(meetingDate: meetingDate, summary: summary, timeZone: utc)
        #expect(rendered.contains("# Meeting — Q3 roadmap sync"))
        #expect(rendered.contains("**Team aligned on import refactor."))
        #expect(rendered.contains("## Summary\nDiscussed pipeline priorities."))
        #expect(rendered.contains("## Key Points\n- Backlog reviewed\n- Import is the bottleneck"))
        #expect(rendered.contains("## Action Items\n- Naz to draft RFC"))
        #expect(rendered.contains("## Decisions\n- Ship in Q3"))
        #expect(!rendered.contains("## Transcript"))
    }

    @Test func summaryOmitsHeadlineWhenEmpty() {
        let summary = MeetingSummary(title: "T", headline: "", summary: "S", keyPoints: [], actionItems: [], decisions: [])
        let rendered = MarkdownWriter.renderSummary(meetingDate: meetingDate, summary: summary, timeZone: utc)
        #expect(!rendered.contains("**\n"))
        #expect(rendered.contains("## Key Points\n_(none)_"))
        #expect(rendered.contains("## Action Items\n_(none)_"))
        #expect(rendered.contains("## Decisions\n_(none)_"))
    }

    @Test func transcriptRendersTimestampedLines() {
        let segments: [TranscriptSegment] = [
            .init(kind: .mic, startSeconds: 0, endSeconds: 1, text: "hello"),
            .init(kind: .system, startSeconds: 2, endSeconds: 3, text: "hi")
        ]
        let rendered = MarkdownWriter.renderTranscript(meetingDate: meetingDate, segments: segments, timeZone: utc)
        #expect(rendered.contains("# Meeting Transcript — 2026-05-02 14:30"))
        #expect(rendered.contains("[0:00] me: hello"))
        #expect(rendered.contains("[0:02] them: hi"))
    }

    @Test func transcriptRendersPlaceholderWhenNoSegments() {
        let rendered = MarkdownWriter.renderTranscript(meetingDate: meetingDate, segments: [], timeZone: utc)
        #expect(rendered.contains("_(no speech detected)_"))
    }

    @Test func readingRendersAgentFrontmatter() {
        let segments: [TranscriptSegment] = [
            .init(kind: .mic, startSeconds: 0, endSeconds: 4, text: "Hello there everyone."),
            .init(kind: .system, startSeconds: 5, endSeconds: 90, text: "Hi, glad to join.")
        ]
        let summary = MeetingSummary(title: "Weekly: sync", headline: "", summary: "", keyPoints: [], actionItems: [], decisions: [])
        let rendered = MarkdownWriter.renderReading(meetingDate: meetingDate, segments: segments, summary: summary, timeZone: utc)

        // Frontmatter contract.
        #expect(rendered.hasPrefix("---\n"))
        #expect(rendered.contains("\ntitle: \"Weekly: sync\"\n"), "title must be YAML-quoted so the colon is safe")
        #expect(rendered.contains("\ndate: 2026-05-02T14:30:00Z\n"))
        #expect(rendered.contains("\nduration: \"1:30\"\n"))
        #expect(rendered.contains("\nduration_seconds: 90\n"))
        #expect(rendered.contains("\nspeakers: [me, them]\n"))
        #expect(rendered.contains("\nword_count: 7\n"))
        // Prose body follows, no timestamps or speaker tags.
        #expect(rendered.contains("Hello there everyone."))
        #expect(!rendered.contains("[0:00]"))
        #expect(!rendered.contains("me:"))
    }

    @Test func readingFrontmatterFallsBackToDateTitleAndEmptyBody() {
        let rendered = MarkdownWriter.renderReading(meetingDate: meetingDate, segments: [], summary: nil, timeZone: utc)
        #expect(rendered.contains("title: \"2026-05-02 14:30\""))
        #expect(rendered.contains("duration_seconds: 0\n"))
        #expect(rendered.contains("speakers: []\n"))
        #expect(rendered.contains("_(no speech detected)_"))
    }

    @Test func transcriptJSONHasMetadataAndTurns() throws {
        let segments: [TranscriptSegment] = [
            .init(kind: .mic, startSeconds: 0, endSeconds: 4, text: "Hello."),
            .init(kind: .system, startSeconds: 5, endSeconds: 12, text: "Hi there.")
        ]
        let summary = MeetingSummary(title: "1:1 with Sam", headline: "", summary: "", keyPoints: [], actionItems: [], decisions: [])
        let data = MeetingTranscriptJSON.render(meetingDate: meetingDate, segments: segments, summary: summary, timeZone: utc)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(obj["title"] as? String == "1:1 with Sam")
        #expect(obj["date"] as? String == "2026-05-02T14:30:00Z")
        #expect(obj["duration_seconds"] as? Int == 12)
        #expect(obj["speakers"] as? [String] == ["me", "them"])

        let turns = obj["segments"] as! [[String: Any]]
        #expect(turns.count == 2)
        #expect(turns[0]["speaker"] as? String == "me")
        #expect(turns[0]["text"] as? String == "Hello.")
        #expect(turns[1]["speaker"] as? String == "them")
        #expect((turns[1]["end"] as? Double) == 12.0)
    }

    @Test func writeCreatesBothFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-md-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let segments: [TranscriptSegment] = [
            .init(kind: .mic, startSeconds: 0, endSeconds: 1, text: "test")
        ]
        let written = try MarkdownWriter.write(meetingDate: meetingDate, segments: segments, summary: nil, to: dir)
        #expect(FileManager.default.fileExists(atPath: written.summaryURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: written.transcriptURL.path(percentEncoded: false)))
        #expect(written.summaryURL.lastPathComponent.hasSuffix("-summary.md"))
        #expect(written.transcriptURL.lastPathComponent.hasSuffix("-transcript.md"))
        let summaryContents = try String(contentsOf: written.summaryURL, encoding: .utf8)
        let transcriptContents = try String(contentsOf: written.transcriptURL, encoding: .utf8)
        #expect(summaryContents.contains("# Meeting"))
        #expect(transcriptContents.contains("[0:00] me: test"))
    }
}
