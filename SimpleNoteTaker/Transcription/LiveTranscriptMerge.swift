import Foundation

/// Merges the mic ("me") and system ("them") live transcripts into a single
/// chronological list of speaker turns for the live UI. Both analyzers start
/// at roughly the same wall-clock moment, so their per-stream timestamps are
/// directly comparable.
enum LiveTranscriptMerge {
    struct Turn: Identifiable, Equatable {
        let id: Int
        let kind: AudioKind
        let speaker: String
        let text: String
    }

    /// Builds the merged turn list. Each transcriber contributes its final
    /// segments plus its in-progress partial (appended only when it adds text
    /// the segments don't already reflect — SpeechAnalyzer often re-emits the
    /// last segment as the partial). Consecutive same-speaker pieces are
    /// coalesced into one turn so the UI shows speaker blocks, not one bubble
    /// per word group.
    static func turns(
        micSegments: [TranscriptSegment],
        micPartial: String,
        systemSegments: [TranscriptSegment],
        systemPartial: String
    ) -> [Turn] {
        var pieces: [TranscriptSegment] = []
        pieces.append(contentsOf: withPartial(segments: micSegments, partial: micPartial, kind: .mic))
        pieces.append(contentsOf: withPartial(segments: systemSegments, partial: systemPartial, kind: .system))

        let ordered = TranscriptMerger.interleave(pieces)

        var turns: [Turn] = []
        var nextID = 0
        for segment in ordered {
            let text = segment.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            if var last = turns.last, last.kind == segment.kind {
                last = Turn(id: last.id, kind: last.kind, speaker: last.speaker, text: last.text + " " + text)
                turns[turns.count - 1] = last
            } else {
                turns.append(Turn(
                    id: nextID,
                    kind: segment.kind,
                    speaker: speakerLabel(for: segment.kind),
                    text: text
                ))
                nextID += 1
            }
        }
        return turns
    }

    private static func withPartial(
        segments: [TranscriptSegment],
        partial: String,
        kind: AudioKind
    ) -> [TranscriptSegment] {
        var result = segments
        let trimmedPartial = partial.trimmingCharacters(in: .whitespaces)
        if !trimmedPartial.isEmpty && trimmedPartial != segments.last?.text.trimmingCharacters(in: .whitespaces) {
            // Place the partial just after the last segment in time so it sorts
            // to the end of this speaker's run.
            let start = (segments.last?.endSeconds ?? 0) + 0.001
            result.append(TranscriptSegment(kind: kind, startSeconds: start, endSeconds: start, text: trimmedPartial))
        }
        return result
    }

    /// User-facing speaker label for the live view. More descriptive than the
    /// terse "me"/"them" used in the saved transcript file.
    static func speakerLabel(for kind: AudioKind) -> String {
        switch kind {
        case .mic: return "You"
        case .system: return "Them"
        }
    }
}
