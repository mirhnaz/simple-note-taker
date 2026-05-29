import Foundation

/// The kind of meeting being summarized. Drives a tailored summarization
/// prompt and is written into the reading.md / transcript.json frontmatter
/// so downstream agents can route on it (e.g. an interview-feedback agent).
enum MeetingType: String, CaseIterable, Identifiable, Sendable {
    case general
    case interview
    case standup
    case oneOnOne

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "General meeting"
        case .interview: return "Interview"
        case .standup: return "Standup"
        case .oneOnOne: return "1:1"
        }
    }

    /// Extra, type-specific guidance appended to the base summarization
    /// system prompt. Empty for `.general` (the base prompt already covers it).
    var summaryGuidance: String {
        switch self {
        case .general:
            return ""
        case .interview:
            return """
            This is a job interview. The user ("me") is the interviewer; "them" \
            is the candidate. Focus the summary on the candidate: notable \
            strengths and weaknesses, how they answered key questions, concrete \
            examples or evidence they gave, and any gaps or concerns. In \
            keyPoints, capture the most telling moments. Use actionItems for \
            interviewer follow-ups (e.g. "Check references", "Schedule system \
            design round"). Use decisions for any hiring lean stated in the \
            conversation — never invent a verdict that wasn't said.
            """
        case .standup:
            return """
            This is a team standup. Organize keyPoints by what each person \
            reported. Pull every stated blocker into keyPoints explicitly. Use \
            actionItems for who-will-do-what next, attributed to a person where \
            the transcript makes it clear. Keep it terse.
            """
        case .oneOnOne:
            return """
            This is a 1:1. Focus on feedback exchanged, growth and career topics, \
            concerns raised, and commitments made by either side. Use actionItems \
            for follow-ups owned by either person; use decisions for anything \
            explicitly agreed.
            """
        }
    }
}
