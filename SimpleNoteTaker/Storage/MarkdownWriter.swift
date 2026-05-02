import Foundation

struct WrittenMeeting {
    let summaryURL: URL
    let transcriptURL: URL
}

enum MarkdownWriter {
    /// Renders the summary file (no transcript section).
    static func renderSummary(
        meetingDate: Date,
        summary: MeetingSummary?,
        timeZone: TimeZone = .current
    ) -> String {
        let dateLabel = Self.formatDateLabel(meetingDate, timeZone: timeZone)
        let title = summary?.title ?? dateLabel

        var sections: [String] = ["# Meeting — \(title)", "_Recorded \(dateLabel)_"]

        if let summary {
            if !summary.headline.isEmpty {
                sections.append("**\(summary.headline)**")
            }
            sections.append("## Summary\n\(summary.summary)")
            sections.append("## Key Points\n\(renderList(summary.keyPoints))")
            sections.append("## Action Items\n\(renderList(summary.actionItems))")
            sections.append("## Decisions\n\(renderList(summary.decisions))")
        } else {
            sections.append("_(no summary available)_")
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    /// Renders the transcript file. Title header + raw timestamped lines.
    static func renderTranscript(
        meetingDate: Date,
        segments: [TranscriptSegment],
        timeZone: TimeZone = .current
    ) -> String {
        let dateLabel = Self.formatDateLabel(meetingDate, timeZone: timeZone)
        let body = segments.isEmpty ? "_(no speech detected)_" : TranscriptMerger.renderTranscript(segments)
        return """
        # Meeting Transcript — \(dateLabel)

        \(body)
        """ + "\n"
    }

    /// Writes JUST the summary file. Used by Regenerate so we don't
    /// clobber the transcript with an empty segments array.
    @discardableResult
    static func writeSummary(
        meetingDate: Date,
        summary: MeetingSummary?,
        to directory: URL
    ) throws -> URL {
        try Paths.ensureDirectoryExists(directory)
        let url = directory.appending(path: MeetingFiles.summaryFilename(for: meetingDate))
        let content = renderSummary(meetingDate: meetingDate, summary: summary)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Writes both the summary and transcript files. Returns both URLs;
    /// `summaryURL` is the canonical "meeting" file users open by default.
    @discardableResult
    static func write(
        meetingDate: Date,
        segments: [TranscriptSegment],
        summary: MeetingSummary? = nil,
        to directory: URL
    ) throws -> WrittenMeeting {
        try Paths.ensureDirectoryExists(directory)
        let summaryURL = directory.appending(path: MeetingFiles.summaryFilename(for: meetingDate))
        let transcriptURL = directory.appending(path: MeetingFiles.transcriptFilename(for: meetingDate))

        let summaryContent = renderSummary(meetingDate: meetingDate, summary: summary)
        let transcriptContent = renderTranscript(meetingDate: meetingDate, segments: segments)

        try summaryContent.write(to: summaryURL, atomically: true, encoding: .utf8)
        try transcriptContent.write(to: transcriptURL, atomically: true, encoding: .utf8)

        return WrittenMeeting(summaryURL: summaryURL, transcriptURL: transcriptURL)
    }

    private static func formatDateLabel(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func renderList(_ items: [String]) -> String {
        guard !items.isEmpty else { return "_(none)_" }
        return items.map { "- \($0)" }.joined(separator: "\n")
    }
}
