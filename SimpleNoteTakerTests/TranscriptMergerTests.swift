import Foundation
import Testing
@testable import SimpleNoteTaker

struct TranscriptMergerTests {
    @Test func interleavesByStartTimeAcrossKinds() {
        let segments: [TranscriptSegment] = [
            .init(kind: .system, startSeconds: 5.0, endSeconds: 7.0, text: "hello"),
            .init(kind: .mic, startSeconds: 1.0, endSeconds: 3.0, text: "hi"),
            .init(kind: .system, startSeconds: 10.0, endSeconds: 12.0, text: "ok"),
            .init(kind: .mic, startSeconds: 8.0, endSeconds: 9.5, text: "great")
        ]
        let result = TranscriptMerger.interleave(segments)
        #expect(result.map(\.startSeconds) == [1.0, 5.0, 8.0, 10.0])
        #expect(result.map(\.kind) == [.mic, .system, .mic, .system])
    }

    @Test func tieBreaksMicBeforeSystem() {
        let segments: [TranscriptSegment] = [
            .init(kind: .system, startSeconds: 1.0, endSeconds: 2.0, text: "yes"),
            .init(kind: .mic, startSeconds: 1.0, endSeconds: 2.0, text: "no")
        ]
        let result = TranscriptMerger.interleave(segments)
        #expect(result[0].kind == .mic)
        #expect(result[1].kind == .system)
    }

    @Test func speakerLabelMapping() {
        #expect(TranscriptMerger.speakerLabel(for: .mic) == "me")
        #expect(TranscriptMerger.speakerLabel(for: .system) == "them")
    }

    @Test func formatTimestampUnderOneHour() {
        #expect(TranscriptMerger.formatTimestamp(0) == "0:00")
        #expect(TranscriptMerger.formatTimestamp(5) == "0:05")
        #expect(TranscriptMerger.formatTimestamp(65) == "1:05")
        #expect(TranscriptMerger.formatTimestamp(599) == "9:59")
    }

    @Test func formatTimestampOverOneHour() {
        #expect(TranscriptMerger.formatTimestamp(3600) == "1:00:00")
        #expect(TranscriptMerger.formatTimestamp(3725) == "1:02:05")
    }

    @Test func lineRendersTimestampSpeakerAndText() {
        let segment = TranscriptSegment(kind: .mic, startSeconds: 65.0, endSeconds: 70.0, text: "let's begin")
        #expect(TranscriptMerger.line(for: segment) == "[1:05] me: let's begin")
    }

    @Test func renderTranscriptJoinsLinesNewlineSeparated() {
        let segments: [TranscriptSegment] = [
            .init(kind: .mic, startSeconds: 0, endSeconds: 1, text: "hi"),
            .init(kind: .system, startSeconds: 2, endSeconds: 3, text: "hey")
        ]
        let rendered = TranscriptMerger.renderTranscript(segments)
        #expect(rendered == "[0:00] me: hi\n[0:02] them: hey")
    }
}
