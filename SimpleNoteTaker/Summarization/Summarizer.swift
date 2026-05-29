import FoundationModels
import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "summarizer")

protocol Summarizing: Sendable {
    func summarize(transcript: String, meetingType: MeetingType) async -> MeetingSummary?
}

extension Summarizing {
    /// Convenience for callers that don't care about the meeting type.
    func summarize(transcript: String) async -> MeetingSummary? {
        await summarize(transcript: transcript, meetingType: .general)
    }
}

struct FoundationModelsSummarizer: Summarizing {
    func summarize(transcript: String, meetingType: MeetingType) async -> MeetingSummary? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            log.warning("system language model unavailable: \(String(describing: model.availability), privacy: .public)")
            return nil
        }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: SummarizationGuidelines.systemPrompt(for: meetingType))

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
