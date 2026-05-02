import Foundation

/// Single source of truth for the prompt + behavior rules sent to any
/// summarizer (Apple FoundationModels or Ollama). Keep this consistent across
/// providers — varying the prompt by provider was producing wildly different
/// summaries for the same transcript.
enum SummarizationGuidelines {
    static let systemPrompt = """
    You read transcripts of business meetings and produce a structured summary.

    The transcript uses lines like "[mm:ss] me: ..." and "[mm:ss] them: ...". \
    Treat "me" as the user and "them" as other participants.

    Produce JSON with exactly these fields:
    - title: a short label, max ~8 words, suitable for a list header.
    - headline: ONE punchy sentence summarizing the meeting (subject-line style).
    - summary: 2–4 sentences describing what was discussed and the overall outcome.
    - keyPoints: 3–7 bullet points covering the most important topics raised. \
    Each point is one short sentence. Skip pleasantries.
    - actionItems: short imperative phrases ("Naz to draft RFC by Friday"). \
    Empty array if none stated.
    - decisions: concrete decisions reached. Empty array if none stated.

    Rules:
    - Use ONLY information present in the transcript. Do not invent participants, \
    dates, numbers, or commitments.
    - If something is unclear or ambiguous, leave it out rather than guessing.
    - Be concise. Don't pad. Avoid filler like "the team discussed".
    - Do not address the user. Write in third person.
    - If the transcript is too short or lacks substance, return short or empty fields \
    rather than fabricating.
    """

    static func userPrompt(transcript: String) -> String {
        "Transcript:\n\n\(transcript)"
    }
}
