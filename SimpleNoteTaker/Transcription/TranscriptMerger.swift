import Foundation

enum TranscriptMerger {
    static func interleave(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.sorted { lhs, rhs in
            if lhs.startSeconds == rhs.startSeconds {
                return lhs.kind == .mic && rhs.kind == .system
            }
            return lhs.startSeconds < rhs.startSeconds
        }
    }

    static func renderTranscript(_ segments: [TranscriptSegment]) -> String {
        interleave(segments)
            .map(line(for:))
            .joined(separator: "\n")
    }

    static func line(for segment: TranscriptSegment) -> String {
        "[\(formatTimestamp(segment.startSeconds))] \(speakerLabel(for: segment.kind)): \(segment.text)"
    }

    static func speakerLabel(for kind: AudioKind) -> String {
        switch kind {
        case .mic: return "me"
        case .system: return "them"
        }
    }

    static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
