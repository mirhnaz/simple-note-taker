import Foundation

struct MeetingFile: Identifiable, Hashable, Sendable {
    let url: URL
    let title: String
    let recordedAt: Date
    let summarySnippet: String?

    var id: URL { url }

    var displayTitle: String {
        title.isEmpty ? Self.dateFormatter.string(from: recordedAt) : title
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
