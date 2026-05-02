import Foundation

enum MarkdownWriter {
    static func render(
        meetingDate: Date,
        segments: [TranscriptSegment],
        summary: MeetingSummary? = nil,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        let dateLabel = formatter.string(from: meetingDate)
        let title = summary?.title ?? dateLabel
        let body = segments.isEmpty ? "_(no speech detected)_" : TranscriptMerger.renderTranscript(segments)

        var sections: [String] = ["# Meeting — \(title)", "_Recorded \(dateLabel)_"]

        if let summary {
            if !summary.headline.isEmpty {
                sections.append("**\(summary.headline)**")
            }
            sections.append("## Summary\n\(summary.summary)")
            sections.append("## Key Points\n\(renderList(summary.keyPoints))")
            sections.append("## Action Items\n\(renderList(summary.actionItems))")
            sections.append("## Decisions\n\(renderList(summary.decisions))")
        }
        sections.append("## Transcript\n\(body)")

        return sections.joined(separator: "\n\n") + "\n"
    }

    @discardableResult
    static func write(
        meetingDate: Date,
        segments: [TranscriptSegment],
        summary: MeetingSummary? = nil,
        to directory: URL
    ) throws -> URL {
        try Paths.ensureDirectoryExists(directory)
        let filename = MeetingFiles.transcriptFilename(for: meetingDate)
        let url = directory.appending(path: filename)
        let content = render(meetingDate: meetingDate, segments: segments, summary: summary)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func renderList(_ items: [String]) -> String {
        guard !items.isEmpty else { return "_(none)_" }
        return items.map { "- \($0)" }.joined(separator: "\n")
    }
}
