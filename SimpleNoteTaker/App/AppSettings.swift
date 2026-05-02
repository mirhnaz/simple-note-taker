import Foundation

enum SettingsKeys {
    static let notesDirectoryPath = "notesDirectoryPath"
    static let retainAudioFiles = "retainAudioFiles"
    static let audioDirectoryPath = "audioDirectoryPath"
    static let llmProvider = "llmProvider"
    static let ollamaBaseURL = "ollamaBaseURL"
    static let ollamaModel = "ollamaModel"
    static let transcriptionProvider = "transcriptionProvider"
    static let mlxWhisperModel = "mlxWhisperModel"
    static let mlxWhisperPath = "mlxWhisperPath"
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

enum TranscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case apple = "apple"
    case mlxWhisper = "mlxWhisper"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple SpeechAnalyzer (built-in)"
        case .mlxWhisper: return "MLX Whisper (local)"
        }
    }
}

struct AppSettings {
    let defaults: UserDefaults

    nonisolated static let shared = AppSettings(defaults: .standard)

    static let defaultOllamaBaseURL = "http://localhost:11434"
    static let defaultMLXWhisperModel = "mlx-community/whisper-large-v3-turbo"

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

    var transcriptionProvider: TranscriptionProvider {
        let raw = defaults.string(forKey: SettingsKeys.transcriptionProvider) ?? ""
        return TranscriptionProvider(rawValue: raw) ?? .apple
    }

    var mlxWhisperModel: String {
        let stored = defaults.string(forKey: SettingsKeys.mlxWhisperModel) ?? ""
        return stored.isEmpty ? Self.defaultMLXWhisperModel : stored
    }

    var mlxWhisperPath: String {
        defaults.string(forKey: SettingsKeys.mlxWhisperPath) ?? ""
    }

    func makeSummarizer() -> any Summarizing {
        switch llmProvider {
        case .apple:
            return FoundationModelsSummarizer()
        case .ollama:
            return OllamaSummarizer(baseURL: ollamaBaseURL, model: ollamaModel)
        }
    }

    func makeFileTranscriber() -> any FileTranscribing {
        switch transcriptionProvider {
        case .apple:
            return AppleFileTranscriber()
        case .mlxWhisper:
            return MLXWhisperTranscriber(model: mlxWhisperModel, executablePathOverride: mlxWhisperPath)
        }
    }
}
