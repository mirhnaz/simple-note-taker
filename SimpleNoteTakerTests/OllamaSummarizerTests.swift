import Foundation
import Testing
@testable import SimpleNoteTaker

struct OllamaSummarizerTests {
    @Test func decodesPlainJSONIntoMeetingSummary() throws {
        let raw = """
        {
          "title": "Q3 plan",
          "headline": "Team committed to ship import refactor in Q3.",
          "summary": "Discussed roadmap.",
          "keyPoints": ["Pipeline backlog", "Import is priority"],
          "actionItems": ["Naz to draft RFC"],
          "decisions": ["Ship in Q3"]
        }
        """
        let summary = try OllamaSummarizer.decode(rawJSON: raw)
        #expect(summary.title == "Q3 plan")
        #expect(summary.headline == "Team committed to ship import refactor in Q3.")
        #expect(summary.summary == "Discussed roadmap.")
        #expect(summary.keyPoints == ["Pipeline backlog", "Import is priority"])
        #expect(summary.actionItems == ["Naz to draft RFC"])
        #expect(summary.decisions == ["Ship in Q3"])
    }

    @Test func extractsJSONWrappedInPreamble() throws {
        let raw = """
        Sure, here's the meeting summary as requested:

        ```json
        {"title": "Standup", "summary": "Daily sync.", "actionItems": [], "decisions": []}
        ```

        Let me know if you need anything else.
        """
        let summary = try OllamaSummarizer.decode(rawJSON: raw)
        #expect(summary.title == "Standup")
        #expect(summary.actionItems.isEmpty)
        #expect(summary.decisions.isEmpty)
    }

    @Test func tolerantOfMissingArraysAndHeadline() throws {
        let raw = """
        {"title": "X", "summary": "Y"}
        """
        let summary = try OllamaSummarizer.decode(rawJSON: raw)
        #expect(summary.headline == "")
        #expect(summary.keyPoints.isEmpty)
        #expect(summary.actionItems.isEmpty)
        #expect(summary.decisions.isEmpty)
    }

    @Test func throwsOnMalformedJSON() {
        let raw = "this is not json at all"
        do {
            _ = try OllamaSummarizer.decode(rawJSON: raw)
            Issue.record("expected throw")
        } catch {
            // expected
        }
    }
}
