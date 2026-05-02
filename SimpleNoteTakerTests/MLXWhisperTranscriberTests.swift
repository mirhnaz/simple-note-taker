import Foundation
import Testing
@testable import SimpleNoteTaker

struct MLXWhisperTranscriberTests {
    @Test func parsesSegmentsFromWhisperJSON() throws {
        let json = """
        {
          "text": "Hello world. Action item: Naz to write the doc.",
          "segments": [
            {"start": 0.0, "end": 1.5, "text": "Hello world."},
            {"start": 1.5, "end": 5.2, "text": " Action item: Naz to write the doc."}
          ],
          "language": "en"
        }
        """.data(using: .utf8)!

        let segments = try MLXWhisperTranscriber.parseSegments(jsonData: json, kind: .system)
        #expect(segments.count == 2)
        #expect(segments[0].kind == .system)
        #expect(segments[0].startSeconds == 0.0)
        #expect(segments[0].endSeconds == 1.5)
        #expect(segments[0].text == "Hello world.")
        #expect(segments[1].text == "Action item: Naz to write the doc.")
    }

    @Test func fallsBackToSingleSegmentWhenSegmentsArrayMissing() throws {
        let json = """
        {"text": "  just a sentence  ", "language": "en"}
        """.data(using: .utf8)!
        let segments = try MLXWhisperTranscriber.parseSegments(jsonData: json, kind: .mic)
        #expect(segments.count == 1)
        #expect(segments[0].text == "just a sentence")
        #expect(segments[0].kind == .mic)
        #expect(segments[0].startSeconds == 0)
    }

    @Test func returnsEmptyWhenTextIsEmptyAndNoSegments() throws {
        let json = """
        {"text": "   ", "language": "en"}
        """.data(using: .utf8)!
        let segments = try MLXWhisperTranscriber.parseSegments(jsonData: json, kind: .mic)
        #expect(segments.isEmpty)
    }

    @Test func throwsOnMalformedJSON() {
        let json = "not json".data(using: .utf8)!
        do {
            _ = try MLXWhisperTranscriber.parseSegments(jsonData: json, kind: .mic)
            Issue.record("expected throw")
        } catch {
            // expected
        }
    }
}
