import Foundation

enum MeetingFileKind: Sendable {
    case summary
    case transcript
    case reading
    case legacyCombined
}

enum MeetingLibrary {
    /// Scans the directory for `meeting-*.md` files, groups by base timestamp,
    /// and returns one MeetingFile per meeting (regardless of how many of its
    /// files exist). Sorted newest first.
    static func load(from directory: URL) async throws -> [MeetingFile] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }

        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let mdURLs = urls.filter { $0.pathExtension.lowercased() == "md" && $0.lastPathComponent.hasPrefix("meeting-") }

        var byDate: [Date: (summary: URL?, transcript: URL?, reading: URL?, legacy: URL?)] = [:]
        for url in mdURLs {
            guard let parsed = parseMeetingFilename(url.lastPathComponent) else { continue }
            var entry = byDate[parsed.date] ?? (nil, nil, nil, nil)
            switch parsed.kind {
            case .summary: entry.summary = url
            case .transcript: entry.transcript = url
            case .reading: entry.reading = url
            case .legacyCombined: entry.legacy = url
            }
            byDate[parsed.date] = entry
        }

        let files: [MeetingFile] = byDate.compactMap { date, urls in
            // Need a content source for the title/snippet — prefer summary, then legacy.
            // Pure transcript-only meetings still appear, with transcript URL only.
            let contentURL = urls.summary ?? urls.legacy
            let (title, snippet): (String, String?) = contentURL.map {
                parseTitleAndSnippet(at: $0, fallbackDate: date)
            } ?? ("", nil)
            // Duration comes from the last `[mm:ss]` timestamp in the
            // transcript (or legacy combined) file.
            let duration = parseDuration(at: urls.transcript ?? urls.legacy)
            return MeetingFile(
                summaryURL: urls.summary,
                transcriptURL: urls.transcript,
                readingURL: urls.reading,
                legacyCombinedURL: urls.legacy,
                title: title,
                recordedAt: date,
                summarySnippet: snippet,
                durationSeconds: duration
            )
        }

        return files.sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Parses `meeting-YYYY-MM-DD-HHMMSS-summary.md`,
    /// `meeting-YYYY-MM-DD-HHMMSS-transcript.md`, or the legacy
    /// `meeting-YYYY-MM-DD-HHMMSS.md`. Returns nil for non-matching names.
    static func parseMeetingFilename(_ filename: String) -> (date: Date, kind: MeetingFileKind)? {
        let stem = (filename as NSString).deletingPathExtension
        guard stem.hasPrefix("meeting-") else { return nil }
        let body = String(stem.dropFirst("meeting-".count))

        if body.hasSuffix("-summary"),
           let date = dateParser.date(from: String(body.dropLast("-summary".count))) {
            return (date, .summary)
        }
        if body.hasSuffix("-transcript"),
           let date = dateParser.date(from: String(body.dropLast("-transcript".count))) {
            return (date, .transcript)
        }
        if body.hasSuffix("-reading"),
           let date = dateParser.date(from: String(body.dropLast("-reading".count))) {
            return (date, .reading)
        }
        if let date = dateParser.date(from: body) {
            return (date, .legacyCombined)
        }
        return nil
    }

    /// Back-compat shim — returns the timestamp regardless of suffix.
    static func parseDate(from filename: String) -> Date? {
        parseMeetingFilename(filename)?.date
    }

    /// Reads a file (prefix-only is fine for this purpose) and extracts the
    /// H1 title and a short snippet from the `## Summary` body, if present.
    static func parseTitleAndSnippet(content: String, fallbackDate: Date) -> (title: String, snippet: String?) {
        var title = ""
        if let h1 = firstMatch(content, prefix: "# Meeting — ") {
            title = h1.trimmingCharacters(in: .whitespaces)
        }
        if title == fallbackDateString(fallbackDate) {
            title = ""
        }

        var snippet: String?
        if let summarySection = section(content, heading: "## Summary") {
            let paragraph = summarySection
                .components(separatedBy: "\n\n")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            snippet = paragraph?.isEmpty == false ? paragraph : nil
        }

        return (title, snippet)
    }

    private static func parseTitleAndSnippet(at url: URL, fallbackDate: Date) -> (title: String, snippet: String?) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return ("", nil) }
        return parseTitleAndSnippet(content: content, fallbackDate: fallbackDate)
    }

    /// Last `[mm:ss]` timestamp in the file, in seconds. Used for the meeting
    /// card's duration label.
    static func parseDuration(content: String) -> TimeInterval? {
        var lastSeconds: TimeInterval = 0
        for raw in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let inside = line[line.index(after: line.startIndex)..<close]
            let parts = inside.split(separator: ":")
            guard parts.count == 2,
                  let mins = Int(parts[0]),
                  let secs = Int(parts[1]) else { continue }
            let total = TimeInterval(mins * 60 + secs)
            if total > lastSeconds { lastSeconds = total }
        }
        return lastSeconds > 0 ? lastSeconds : nil
    }

    private static func parseDuration(at url: URL?) -> TimeInterval? {
        guard let url, let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parseDuration(content: content)
    }

    private static func firstMatch(_ content: String, prefix: String) -> String? {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func section(_ content: String, heading: String) -> String? {
        guard let range = content.range(of: heading + "\n") else { return nil }
        let after = content[range.upperBound...]
        if let nextHeading = after.range(of: "\n## ") {
            return String(after[..<nextHeading.lowerBound])
        }
        return String(after)
    }

    private static func fallbackDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()
}
