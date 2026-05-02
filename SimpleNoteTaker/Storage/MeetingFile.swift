import Foundation

struct MeetingFile: Identifiable, Hashable, Sendable {
    /// Modern split layout: post-M11.0 meetings have both files.
    let summaryURL: URL?
    let transcriptURL: URL?
    /// Legacy combined file: pre-M11.0 single `meeting-<ts>.md`. When present,
    /// the meeting is treated as summary-only (no separate transcript pane).
    let legacyCombinedURL: URL?

    let title: String
    let recordedAt: Date
    let summarySnippet: String?

    var id: Date { recordedAt }

    /// The file users open by default — modern summary, falling back to the
    /// legacy combined file if that's all we have.
    var primaryURL: URL {
        summaryURL ?? legacyCombinedURL ?? transcriptURL!
    }

    var displayTitle: String {
        title.isEmpty ? Self.dateFormatter.string(from: recordedAt) : title
    }

    /// True for pre-M11.0 meetings that exist as a single combined .md file.
    var isLegacy: Bool { summaryURL == nil && legacyCombinedURL != nil }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
