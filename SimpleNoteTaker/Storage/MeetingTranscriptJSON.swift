import Foundation

/// Structured, machine-addressable transcript for downstream agents that want
/// turn-level data rather than the prose `reading.md`. Mirrors the reading
/// file's frontmatter metadata, then lists every segment with its speaker,
/// start/end (seconds), and text. Treat the field names as a stable contract:
/// additive changes are safe, renames/removals are breaking.
enum MeetingTranscriptJSON {
    struct Document: Encodable {
        let title: String
        let date: String          // ISO-8601
        let durationSeconds: Int
        let speakers: [String]    // distinct speaker labels, first-appearance order
        let segments: [Segment]

        enum CodingKeys: String, CodingKey {
            case title, date, speakers, segments
            case durationSeconds = "duration_seconds"
        }
    }

    struct Segment: Encodable {
        let speaker: String
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    static func render(
        meetingDate: Date,
        segments: [TranscriptSegment],
        summary: MeetingSummary? = nil,
        timeZone: TimeZone = .current
    ) -> Data {
        let ordered = TranscriptMerger.interleave(segments)
        let dateLabel = MarkdownWriter.formatDateLabel(meetingDate, timeZone: timeZone)
        let title = (summary?.title).flatMap { $0.isEmpty ? nil : $0 } ?? dateLabel

        var seenSpeakers = Set<AudioKind>()
        var speakers: [String] = []
        for segment in ordered where !seenSpeakers.contains(segment.kind) {
            seenSpeakers.insert(segment.kind)
            speakers.append(TranscriptMerger.speakerLabel(for: segment.kind))
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = timeZone

        let doc = Document(
            title: title,
            date: isoFormatter.string(from: meetingDate),
            durationSeconds: Int((segments.map(\.endSeconds).max() ?? 0).rounded()),
            speakers: speakers,
            segments: ordered.map {
                Segment(
                    speaker: TranscriptMerger.speakerLabel(for: $0.kind),
                    start: $0.startSeconds,
                    end: $0.endSeconds,
                    text: $0.text.trimmingCharacters(in: .whitespaces)
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Encoding a fixed, non-throwing structure — failure is not reachable.
        return (try? encoder.encode(doc)) ?? Data("{}".utf8)
    }
}
