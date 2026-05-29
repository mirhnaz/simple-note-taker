import Foundation

struct MeetingFile: Identifiable, Hashable, Sendable {
    /// Modern split layout: post-M11.0 meetings have both files.
    let summaryURL: URL?
    let transcriptURL: URL?
    /// Clean prose version (no timestamps, no speaker tags) for end-to-end
    /// reading and full-text search. Added in M14.2.
    let readingURL: URL?
    /// Legacy combined file: pre-M11.0 single `meeting-<ts>.md`. When present,
    /// the meeting is treated as summary-only (no separate transcript pane).
    let legacyCombinedURL: URL?

    let title: String
    let recordedAt: Date
    let summarySnippet: String?
    let durationSeconds: TimeInterval?
    /// Lowercased, concatenated searchable text (summary body + reading prose)
    /// built at load time so the library's search box can match the full
    /// meeting content, not just the title and snippet. Empty if neither file
    /// could be read.
    let searchText: String

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

    /// Friendly duration string like "12 min" / "1h 24m". nil if unknown.
    var durationLabel: String? {
        guard let total = durationSeconds, total > 0 else { return nil }
        let minutes = Int(total) / 60
        if minutes < 60 {
            return "\(max(1, minutes)) min"
        }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours)h" : "\(hours)h \(rem)m"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
