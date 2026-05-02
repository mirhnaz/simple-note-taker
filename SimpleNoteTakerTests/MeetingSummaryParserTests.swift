import Foundation
import Testing
@testable import SimpleNoteTaker

struct MeetingSummaryParserTests {
    @Test func parsesAllSectionsFromWrittenSummary() {
        let summary = MeetingSummary(
            title: "Q3 plan",
            headline: "Team aligned on import refactor.",
            summary: "Discussed pipeline priorities and reassigned ownership.",
            keyPoints: ["Backlog reviewed", "Import is the bottleneck"],
            actionItems: ["Naz to draft RFC", "Sam to schedule review"],
            decisions: ["Ship in Q3"]
        )
        let date = Date()
        let rendered = MarkdownWriter.renderSummary(meetingDate: date, summary: summary)
        let parsed = MeetingSummaryParser.parse(content: rendered)
        #expect(parsed?.title == "Q3 plan")
        #expect(parsed?.headline == "Team aligned on import refactor.")
        #expect(parsed?.summary == "Discussed pipeline priorities and reassigned ownership.")
        #expect(parsed?.keyPoints == ["Backlog reviewed", "Import is the bottleneck"])
        #expect(parsed?.actionItems == ["Naz to draft RFC", "Sam to schedule review"])
        #expect(parsed?.decisions == ["Ship in Q3"])
    }

    @Test func returnsEmptyArraysForNonePlaceholders() {
        let summary = MeetingSummary(title: "T", headline: "", summary: "S", keyPoints: [], actionItems: [], decisions: [])
        let rendered = MarkdownWriter.renderSummary(meetingDate: Date(), summary: summary)
        let parsed = MeetingSummaryParser.parse(content: rendered)
        #expect(parsed?.keyPoints.isEmpty == true)
        #expect(parsed?.actionItems.isEmpty == true)
        #expect(parsed?.decisions.isEmpty == true)
    }

    @Test func returnsNilForNonSummaryContent() {
        let parsed = MeetingSummaryParser.parse(content: "Just some random text")
        #expect(parsed == nil)
    }

    @Test func parsesLegacyCombinedFile() {
        let content = """
        # Meeting — Legacy Format

        ## Summary
        Old-style file with transcript inline.

        ## Transcript
        [0:00] me: hi
        """
        let parsed = MeetingSummaryParser.parse(content: content)
        #expect(parsed?.title == "Legacy Format")
        #expect(parsed?.summary == "Old-style file with transcript inline.")
    }
}
