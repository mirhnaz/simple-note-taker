import Foundation

struct WrittenMeeting {
    let summaryURL: URL
    let transcriptURL: URL
    let readingURL: URL
    let transcriptJSONURL: URL
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

    /// Renders a clean reading-friendly version: no timestamps, no speaker
    /// tags. Adjacent segments of the same source with small gaps are
    /// joined into one paragraph; speaker changes or pauses >3s start a
    /// new paragraph.
    ///
    /// This file is consumed almost entirely by downstream agents (e.g. an
    /// interview-feedback extractor), so it leads with a YAML frontmatter
    /// block as a stable, machine-parseable contract — title, ISO-8601 date,
    /// duration, which speakers are present, word count — followed by the
    /// prose body. Treat the frontmatter keys as an API: additive changes are
    /// safe, renames/removals are breaking.
    static func renderReading(
        meetingDate: Date,
        segments: [TranscriptSegment],
        summary: MeetingSummary? = nil,
        timeZone: TimeZone = .current
    ) -> String {
        let dateLabel = Self.formatDateLabel(meetingDate, timeZone: timeZone)
        let titleText = (summary?.title).flatMap { $0.isEmpty ? nil : $0 } ?? dateLabel
        let body = segments.isEmpty ? "_(no speech detected)_" : renderReadingBody(segments: segments)
        let frontmatter = renderReadingFrontmatter(
            title: titleText,
            meetingDate: meetingDate,
            segments: segments,
            proseBody: segments.isEmpty ? "" : body,
            timeZone: timeZone
        )
        return frontmatter + "\n" + body + "\n"
    }

    private static func renderReadingFrontmatter(
        title: String,
        meetingDate: Date,
        segments: [TranscriptSegment],
        proseBody: String,
        timeZone: TimeZone
    ) -> String {
        let durationSeconds = Int((segments.map(\.endSeconds).max() ?? 0).rounded())
        let speakers = orderedSpeakers(in: segments)
        let wordCount = proseBody.split { $0 == " " || $0.isNewline }.count

        var lines = ["---"]
        lines.append("title: \(yamlQuoted(title))")
        lines.append("date: \(iso8601(meetingDate, timeZone: timeZone))")
        lines.append("duration: \(yamlQuoted(TranscriptMerger.formatTimestamp(TimeInterval(durationSeconds))))")
        lines.append("duration_seconds: \(durationSeconds)")
        lines.append("speakers: [\(speakers.joined(separator: ", "))]")
        lines.append("word_count: \(wordCount)")
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Distinct speaker labels (me/them) in first-appearance order.
    private static func orderedSpeakers(in segments: [TranscriptSegment]) -> [String] {
        var seen = Set<AudioKind>()
        var result: [String] = []
        for segment in segments where !seen.contains(segment.kind) {
            seen.insert(segment.kind)
            result.append(TranscriptMerger.speakerLabel(for: segment.kind))
        }
        return result
    }

    /// Minimal YAML double-quoted scalar — escapes backslash and quote so a
    /// title containing `:`/`"`/`#` can't break the frontmatter parse.
    private static func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func iso8601(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static let readingParagraphBreakSeconds: TimeInterval = 3.0

    private static func renderReadingBody(segments: [TranscriptSegment]) -> String {
        let ordered = TranscriptMerger.interleave(segments)
        var paragraphs: [String] = []
        var current: [String] = []
        var lastEnd: TimeInterval?
        var lastKind: AudioKind?

        for segment in ordered {
            let text = segment.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let shouldBreak: Bool = {
                guard let lastKind, let lastEnd else { return false }
                if lastKind != segment.kind { return true }
                return segment.startSeconds - lastEnd > readingParagraphBreakSeconds
            }()
            if shouldBreak && !current.isEmpty {
                paragraphs.append(current.joined(separator: " "))
                current.removeAll(keepingCapacity: true)
            }
            current.append(text)
            lastEnd = max(segment.endSeconds, lastEnd ?? 0)
            lastKind = segment.kind
        }
        if !current.isEmpty {
            paragraphs.append(current.joined(separator: " "))
        }
        return paragraphs.joined(separator: "\n\n")
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

    /// Writes the summary, transcript, and reading files. Returns all three
    /// URLs; `summaryURL` is the canonical "meeting" file users open by
    /// default. The reading file is a clean prose version of the transcript
    /// without timestamps, for end-to-end reading and search.
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
        let readingURL = directory.appending(path: MeetingFiles.readingFilename(for: meetingDate))
        let transcriptJSONURL = directory.appending(path: MeetingFiles.transcriptJSONFilename(for: meetingDate))

        let summaryContent = renderSummary(meetingDate: meetingDate, summary: summary)
        let transcriptContent = renderTranscript(meetingDate: meetingDate, segments: segments)
        let readingContent = renderReading(meetingDate: meetingDate, segments: segments, summary: summary)
        let transcriptJSONData = MeetingTranscriptJSON.render(meetingDate: meetingDate, segments: segments, summary: summary)

        try summaryContent.write(to: summaryURL, atomically: true, encoding: .utf8)
        try transcriptContent.write(to: transcriptURL, atomically: true, encoding: .utf8)
        try readingContent.write(to: readingURL, atomically: true, encoding: .utf8)
        try transcriptJSONData.write(to: transcriptJSONURL)

        return WrittenMeeting(
            summaryURL: summaryURL,
            transcriptURL: transcriptURL,
            readingURL: readingURL,
            transcriptJSONURL: transcriptJSONURL
        )
    }

    static func formatDateLabel(_ date: Date, timeZone: TimeZone) -> String {
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
