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
