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

        let session = LanguageModelSession(instructions: """
        You read transcripts of business meetings and extract a brief title, a 2–4 sentence \
        summary of what was discussed, any explicit action items, and any explicit decisions. \
        Use only what is in the transcript; do not invent details. If no action items or \
        decisions were stated, return empty arrays.
        """)

        do {
            let response = try await session.respond(
                to: "Transcript:\n\n\(trimmed)",
                generating: MeetingSummary.self
            )
            return response.content
        } catch {
            log.error("summarization failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
