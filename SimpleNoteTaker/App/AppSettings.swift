import Foundation

enum SettingsKeys {
    static let notesDirectoryPath = "notesDirectoryPath"
    static let retainAudioFiles = "retainAudioFiles"
    static let audioDirectoryPath = "audioDirectoryPath"
    static let llmProvider = "llmProvider"
    static let ollamaBaseURL = "ollamaBaseURL"
    static let ollamaModel = "ollamaModel"
}

enum LLMProvider: String, CaseIterable, Identifiable, Sendable {
    case apple = "apple"
    case ollama = "ollama"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple Foundation Models"
        case .ollama: return "Ollama (local)"
        }
    }
}

struct AppSettings {
    let defaults: UserDefaults

    nonisolated static let shared = AppSettings(defaults: .standard)

    static let defaultOllamaBaseURL = "http://localhost:11434"

    var notesDirectory: URL {
        let stored = defaults.string(forKey: SettingsKeys.notesDirectoryPath) ?? ""
        return stored.isEmpty ? Paths.defaultNotesDirectory : URL(filePath: stored)
    }

    var retainAudioFiles: Bool {
        defaults.bool(forKey: SettingsKeys.retainAudioFiles)
    }

    var audioDirectory: URL {
        let stored = defaults.string(forKey: SettingsKeys.audioDirectoryPath) ?? ""
        return stored.isEmpty ? Paths.defaultAudioDirectory : URL(filePath: stored)
    }

    var llmProvider: LLMProvider {
        let raw = defaults.string(forKey: SettingsKeys.llmProvider) ?? ""
        return LLMProvider(rawValue: raw) ?? .apple
    }

    var ollamaBaseURL: URL {
        let raw = defaults.string(forKey: SettingsKeys.ollamaBaseURL) ?? ""
        let stored = raw.isEmpty ? Self.defaultOllamaBaseURL : raw
        return URL(string: stored) ?? URL(string: Self.defaultOllamaBaseURL)!
    }

    var ollamaModel: String {
        defaults.string(forKey: SettingsKeys.ollamaModel) ?? ""
    }

    func makeSummarizer() -> any Summarizing {
        switch llmProvider {
        case .apple:
            return FoundationModelsSummarizer()
        case .ollama:
            return OllamaSummarizer(baseURL: ollamaBaseURL, model: ollamaModel)
        }
    }
}
