import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "ollama")

/// JSON Schema describing a MeetingSummary; passed to Ollama as `format`.
private let meetingSummarySchema: [String: Any] = [
    "type": "object",
    "properties": [
        "title": ["type": "string"],
        "headline": ["type": "string"],
        "summary": ["type": "string"],
        "keyPoints": ["type": "array", "items": ["type": "string"]],
        "actionItems": ["type": "array", "items": ["type": "string"]],
        "decisions": ["type": "array", "items": ["type": "string"]]
    ],
    "required": ["title", "headline", "summary", "keyPoints", "actionItems", "decisions"]
]

struct OllamaSummarizer: Summarizing {
    let baseURL: URL
    let model: String
    let temperature: Double?
    let session: URLSession

    init(baseURL: URL, model: String, temperature: Double? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.session = session
    }

    func summarize(transcript: String, meetingType: MeetingType) async -> MeetingSummary? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !model.isEmpty else {
            log.warning("ollama model is empty; pick one in Settings")
            return nil
        }

        let client = OllamaClient(baseURL: baseURL, session: session)
        let messages: [OllamaChatMessage] = [
            .init(role: "system", content: SummarizationGuidelines.systemPrompt(for: meetingType) + "\n\nRespond with JSON only."),
            .init(role: "user", content: SummarizationGuidelines.userPrompt(transcript: trimmed))
        ]
        do {
            let raw = try await client.chat(
                model: model,
                messages: messages,
                format: meetingSummarySchema,
                temperature: temperature
            )
            return try Self.decode(rawJSON: raw)
        } catch {
            log.error("ollama summarization failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Decodes a raw JSON string from the model into a MeetingSummary.
    /// Models occasionally wrap JSON in code fences or add prose; this strips
    /// the first balanced `{...}` block before decoding.
    static func decode(rawJSON raw: String) throws -> MeetingSummary {
        let cleaned = extractJSONObject(from: raw) ?? raw
        guard let data = cleaned.data(using: .utf8) else {
            throw OllamaClientError.invalidJSONInResponse(raw)
        }
        return try JSONDecoder().decode(MeetingSummary.self, from: data)
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let firstBrace = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = firstBrace
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[firstBrace...i])
                }
            }
            i = text.index(after: i)
        }
        return nil
    }
}

extension MeetingSummary: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try c.decode(String.self, forKey: .title),
            headline: try c.decodeIfPresent(String.self, forKey: .headline) ?? "",
            summary: try c.decode(String.self, forKey: .summary),
            keyPoints: try c.decodeIfPresent([String].self, forKey: .keyPoints) ?? [],
            actionItems: try c.decodeIfPresent([String].self, forKey: .actionItems) ?? [],
            decisions: try c.decodeIfPresent([String].self, forKey: .decisions) ?? []
        )
    }

    enum CodingKeys: String, CodingKey {
        case title, headline, summary, keyPoints, actionItems, decisions
    }
}
