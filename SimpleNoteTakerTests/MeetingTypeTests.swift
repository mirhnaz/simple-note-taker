import Testing
@testable import SimpleNoteTaker

struct MeetingTypeTests {
    @Test func generalUsesBasePromptUnchanged() {
        #expect(SummarizationGuidelines.systemPrompt(for: .general) == SummarizationGuidelines.systemPrompt)
    }

    @Test func typedPromptAppendsGuidance() {
        let interview = SummarizationGuidelines.systemPrompt(for: .interview)
        #expect(interview.hasPrefix(SummarizationGuidelines.systemPrompt))
        #expect(interview.contains("job interview"))
        #expect(interview.count > SummarizationGuidelines.systemPrompt.count)

        let standup = SummarizationGuidelines.systemPrompt(for: .standup)
        #expect(standup.contains("standup"))
        #expect(standup.contains("blocker"))
    }

    @Test func allTypesHaveDistinctDisplayNames() {
        let names = Set(MeetingType.allCases.map(\.displayName))
        #expect(names.count == MeetingType.allCases.count)
    }
}
