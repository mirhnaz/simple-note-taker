import Foundation

enum OllamaClientError: LocalizedError {
    case badResponse(status: Int, body: String)
    case decodingFailed(underlying: Error)
    case invalidJSONInResponse(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status, let body):
            return "Ollama HTTP \(status): \(body.prefix(200))"
        case .decodingFailed(let error):
            return "Couldn't decode Ollama response: \(error.localizedDescription)"
        case .invalidJSONInResponse(let raw):
            return "Ollama returned non-JSON content: \(raw.prefix(200))"
        }
    }
}

struct OllamaModel: Decodable, Hashable, Sendable {
    let name: String
}

private struct ModelsListResponse: Decodable {
    let models: [OllamaModel]
}

struct OllamaChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct OllamaClient: Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func listModels() async throws -> [OllamaModel] {
        let url = baseURL.appending(path: "/api/tags")
        let (data, response) = try await session.data(from: url)
        try Self.checkOK(response: response, data: data)
        do {
            return try JSONDecoder().decode(ModelsListResponse.self, from: data).models
        } catch {
            throw OllamaClientError.decodingFailed(underlying: error)
        }
    }

    /// Sends a /api/chat request and returns the assistant's `content` string.
    /// `format` is sent as the structured-output JSON Schema; pass nil to skip.
    func chat(model: String, messages: [OllamaChatMessage], format: [String: Any]? = nil) async throws -> String {
        let url = baseURL.appending(path: "/api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false
        ]
        if let format {
            payload["format"] = format
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try Self.checkOK(response: response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw OllamaClientError.invalidJSONInResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return content
    }

    /// Pulls a model via /api/pull and streams the progress lines. `onStatus`
    /// fires for each NDJSON status update; it runs on the main actor so the
    /// caller can drive a SwiftUI label without bouncing through Task hops.
    func pullModel(
        _ name: String,
        onStatus: @escaping @MainActor @Sendable (String) async -> Void
    ) async throws {
        let url = baseURL.appending(path: "/api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw OllamaClientError.badResponse(status: status, body: "pull failed before stream began")
        }
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let err = dict["error"] as? String {
                throw OllamaClientError.badResponse(status: 0, body: err)
            }
            let status = (dict["status"] as? String) ?? ""
            let message: String
            if let completed = dict["completed"] as? Int,
               let total = dict["total"] as? Int,
               total > 0 {
                let totalMB = total / 1_000_000
                let doneMB = completed / 1_000_000
                message = "\(status) — \(doneMB) / \(totalMB) MB"
            } else {
                message = status
            }
            if !message.isEmpty {
                await onStatus(message)
            }
        }
    }

    private static func checkOK(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OllamaClientError.badResponse(status: http.statusCode, body: body)
        }
    }
}
