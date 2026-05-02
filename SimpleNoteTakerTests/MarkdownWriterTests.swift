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

    @Test func rendersTitleAndTranscriptSections() {
        let segments: [TranscriptSegment] = [
            .init(kind: .mic, startSeconds: 0, endSeconds: 1, text: "hello"),
            .init(kind: .system, startSeconds: 2, endSeconds: 3, text: "hi")
        ]
        let rendered = MarkdownWriter.render(meetingDate: meetingDate, segments: segments, timeZone: utc)
        #expect(rendered.contains("# Meeting — 2026-05-02 14:30"))
        #expect(rendered.contains("## Transcript"))
        #expect(rendered.contains("[0:00] me: hello"))
        #expect(rendered.contains("[0:02] them: hi"))
    }

    @Test func rendersPlaceholderWhenNoSegments() {
        let rendered = MarkdownWriter.render(meetingDate: meetingDate, segments: [], timeZone: utc)
        #expect(rendered.contains("_(no speech detected)_"))
    }

    @Test func rendersSummarySectionsWhenSummaryProvided() {
        let summary = MeetingSummary(
            title: "Q3 roadmap sync",
            headline: "Team aligned on Q3 import refactor and split RFC ownership.",
            summary: "Discussed pipeline priorities and reassigned ownership of the import workstream.",
            keyPoints: ["Pipeline backlog reviewed", "Import workstream is the bottleneck"],
            actionItems: ["Naz to draft RFC", "Sam to schedule review"],
            decisions: ["Ship import refactor in Q3"]
        )
        let rendered = MarkdownWriter.render(meetingDate: meetingDate, segments: [], summary: summary, timeZone: utc)
        #expect(rendered.contains("# Meeting — Q3 roadmap sync"))
        #expect(rendered.contains("_Recorded 2026-05-02 14:30_"))
        #expect(rendered.contains("**Team aligned on Q3 import refactor"))
        #expect(rendered.contains("## Summary\nDiscussed pipeline priorities"))
        #expect(rendered.contains("## Key Points"))
        #expect(rendered.contains("- Pipeline backlog reviewed"))
        #expect(rendered.contains("- Import workstream is the bottleneck"))
        #expect(rendered.contains("- Naz to draft RFC"))
        #expect(rendered.contains("- Sam to schedule review"))
        #expect(rendered.contains("- Ship import refactor in Q3"))
    }

    @Test func rendersEmptyListPlaceholdersForEmptyArrays() {
        let summary = MeetingSummary(title: "T", headline: "", summary: "S", keyPoints: [], actionItems: [], decisions: [])
        let rendered = MarkdownWriter.render(meetingDate: meetingDate, segments: [], summary: summary, timeZone: utc)
        #expect(rendered.contains("## Key Points\n_(none)_"))
        #expect(rendered.contains("## Action Items\n_(none)_"))
        #expect(rendered.contains("## Decisions\n_(none)_"))
        #expect(!rendered.contains("**\n"), "headline should be omitted when empty")
    }

    @Test func writeCreatesFileAndDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "snt-md-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let segments: [TranscriptSegment] = [
            .init(kind: .mic, startSeconds: 0, endSeconds: 1, text: "test")
        ]
        let url = try MarkdownWriter.write(meetingDate: meetingDate, segments: segments, to: dir)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("[0:00] me: test"))
    }
}
