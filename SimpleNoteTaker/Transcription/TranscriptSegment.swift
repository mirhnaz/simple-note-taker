import Foundation

struct TranscriptSegment: Equatable, Sendable {
    let kind: AudioKind
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let text: String
}
