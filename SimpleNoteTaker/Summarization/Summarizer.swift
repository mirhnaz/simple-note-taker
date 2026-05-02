import FoundationModels
import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "summarizer")

protocol Summarizing: Sendable {
    func summarize(transcript: String) async -> MeetingSummary?
}

struct FoundationModelsSummarizer: Summarizing {
    func summarize(transcript: String) async -> MeetingSummary? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            log.warning("system language model unavailable: \(String(describing: model.availability), privacy: .public)")
            return nil
        }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: SummarizationGuidelines.systemPrompt)

        do {
            let response = try await session.respond(
                to: SummarizationGuidelines.userPrompt(transcript: trimmed),
                generating: MeetingSummary.self
            )
            return response.content
        } catch {
            log.error("summarization failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
