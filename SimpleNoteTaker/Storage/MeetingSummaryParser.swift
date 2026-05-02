import Foundation

/// Parses a written summary.md (or a legacy combined .md) back into a
/// MeetingSummary. Used by the Summary tab to round-trip what the
/// LLM produced into structured fields, without needing a JSON sidecar.
enum MeetingSummaryParser {
    static func parse(content: String) -> MeetingSummary? {
        let title = extractTitle(content) ?? ""
        let headline = extractHeadline(content) ?? ""
        let summaryText = extractSection(content, heading: "## Summary")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keyPoints = extractListSection(content, heading: "## Key Points") ?? []
        let actionItems = extractListSection(content, heading: "## Action Items") ?? []
        let decisions = extractListSection(content, heading: "## Decisions") ?? []

        // If we have nothing meaningful, return nil so the UI can show the empty state.
        if title.isEmpty && summaryText.isEmpty && headline.isEmpty
            && keyPoints.isEmpty && actionItems.isEmpty && decisions.isEmpty {
            return nil
        }

        return MeetingSummary(
            title: title,
            headline: headline,
            summary: summaryText,
            keyPoints: keyPoints,
            actionItems: actionItems,
            decisions: decisions
        )
    }

    static func extractTitle(_ content: String) -> String? {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("# Meeting — ") {
                return String(line.dropFirst("# Meeting — ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func extractHeadline(_ content: String) -> String? {
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4 {
                return String(trimmed.dropFirst(2).dropLast(2))
            }
        }
        return nil
    }

    static func extractSection(_ content: String, heading: String) -> String? {
        guard let range = content.range(of: heading + "\n") else { return nil }
        let after = content[range.upperBound...]
        if let nextHeading = after.range(of: "\n## ") {
            return String(after[..<nextHeading.lowerBound])
        }
        return String(after)
    }

    /// Pulls bullet items from a `- item` list inside the named section.
    /// Returns `[]` for `_(none)_` placeholders, nil if the section is missing.
    static func extractListSection(_ content: String, heading: String) -> [String]? {
        guard let body = extractSection(content, heading: heading) else { return nil }
        if body.contains("_(none)_") { return [] }
        let items = body
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") {
                    return String(trimmed.dropFirst(2))
                }
                return nil
            }
        return items
    }
}
