import FoundationModels

@Generable(description: "Structured summary of a meeting transcript")
struct MeetingSummary: Equatable, Sendable {
    @Guide(description: "Short label (max ~8 words) for the meeting, suitable as a list header")
    let title: String

    @Guide(description: "ONE punchy sentence summarizing the meeting, subject-line style")
    let headline: String

    @Guide(description: "2–4 sentence summary of what was discussed and the overall outcome")
    let summary: String

    @Guide(description: "3–7 bullet points covering the most important topics raised, each one short sentence")
    let keyPoints: [String]

    @Guide(description: "Action items as short imperative phrases. Empty array if none were stated.")
    let actionItems: [String]

    @Guide(description: "Concrete decisions reached during the meeting. Empty array if none were stated.")
    let decisions: [String]
}
