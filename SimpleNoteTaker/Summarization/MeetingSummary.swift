import FoundationModels

@Generable(description: "Concise summary of a meeting transcript")
struct MeetingSummary: Equatable, Sendable {
    @Guide(description: "A short title (max ~8 words) that captures what the meeting was about")
    let title: String

    @Guide(description: "2–4 sentence summary of what was discussed and the overall outcome")
    let summary: String

    @Guide(description: "Action items as short imperative phrases. Empty array if none were stated.")
    let actionItems: [String]

    @Guide(description: "Concrete decisions reached during the meeting. Empty array if none were stated.")
    let decisions: [String]
}
