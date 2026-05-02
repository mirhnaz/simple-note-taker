import Foundation

enum MeetingLibrary {
    /// Scans the given directory for meeting markdown files (`meeting-*.md`)
    /// and returns them parsed and sorted by recordedAt descending (newest first).
    static func load(from directory: URL) async throws -> [MeetingFile] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }

        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let mdURLs = urls.filter { $0.pathExtension.lowercased() == "md" && $0.lastPathComponent.hasPrefix("meeting-") }

        let files: [MeetingFile] = mdURLs.compactMap { url in
            guard let recordedAt = parseDate(from: url.lastPathComponent) else { return nil }
            let (title, snippet) = parseTitleAndSnippet(at: url, fallbackDate: recordedAt)
            return MeetingFile(url: url, title: title, recordedAt: recordedAt, summarySnippet: snippet)
        }

        return files.sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Parses the timestamp from filenames like `meeting-2026-05-02-143000.md`.
    static func parseDate(from filename: String) -> Date? {
        let stem = (filename as NSString).deletingPathExtension
        guard stem.hasPrefix("meeting-") else { return nil }
        let timestamp = String(stem.dropFirst("meeting-".count))
        return dateParser.date(from: timestamp)
    }

    /// Reads the file (up to a small prefix) and extracts the H1 title and a
    /// short snippet from the `## Summary` body, if present.
    static func parseTitleAndSnippet(content: String, fallbackDate: Date) -> (title: String, snippet: String?) {
        var title = ""
        if let h1 = firstMatch(content, prefix: "# Meeting — ") {
            title = h1.trimmingCharacters(in: .whitespaces)
        }
        // Treat a title that's just the recorded-at timestamp as "no model title".
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
