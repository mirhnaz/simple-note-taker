import Foundation

enum SettingsKeys {
    static let notesDirectoryPath = "notesDirectoryPath"
    static let retainAudioFiles = "retainAudioFiles"
    static let audioDirectoryPath = "audioDirectoryPath"
    static let llmProvider = "llmProvider"
    static let ollamaBaseURL = "ollamaBaseURL"
    static let ollamaModel = "ollamaModel"
    static let ollamaTemperature = "ollamaTemperature"
    static let transcriptionProvider = "transcriptionProvider"
    static let mlxWhisperModel = "mlxWhisperModel"
    static let mlxWhisperPath = "mlxWhisperPath"
    static let mlxWhisperLanguage = "mlxWhisperLanguage"
    static let defaultMeetingType = "defaultMeetingType"
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
    static let defaultOllamaTemperature: Double = 0.2
    static let defaultMLXWhisperModel = "mlx-community/whisper-large-v3-turbo"
    static let defaultMLXWhisperLanguage = "en"

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

    var ollamaTemperature: Double {
        if defaults.object(forKey: SettingsKeys.ollamaTemperature) == nil {
            return Self.defaultOllamaTemperature
        }
        return defaults.double(forKey: SettingsKeys.ollamaTemperature)
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

    /// Language code passed to mlx_whisper as `--language`. Empty means
    /// auto-detect — slower by ~3–5s since mlx_whisper runs the encoder on
    /// the first 30s of audio to identify the language. Defaults to "en"
    /// because meetings are usually English; users with non-English audio
    /// can clear this in Settings → Transcription → Advanced.
    var mlxWhisperLanguage: String {
        let raw = defaults.string(forKey: SettingsKeys.mlxWhisperLanguage)
        // Distinguishes "never set" (use default "en") from "user set to
        // empty string" (auto-detect requested).
        return raw ?? Self.defaultMLXWhisperLanguage
    }

    /// Meeting type applied to live recordings (and the default the import
    /// sheet pre-selects). Drives the tailored summarization prompt.
    var defaultMeetingType: MeetingType {
        let raw = defaults.string(forKey: SettingsKeys.defaultMeetingType) ?? ""
        return MeetingType(rawValue: raw) ?? .general
    }

    func makeSummarizer() -> any Summarizing {
        switch llmProvider {
        case .apple:
            return FoundationModelsSummarizer()
        case .ollama:
            return OllamaSummarizer(baseURL: ollamaBaseURL, model: ollamaModel, temperature: ollamaTemperature)
        }
    }

    func makeFileTranscriber() -> any FileTranscribing {
        switch transcriptionProvider {
        case .apple:
            return AppleFileTranscriber()
        case .mlxWhisper:
            return MLXWhisperTranscriber(
                model: mlxWhisperModel,
                executablePathOverride: mlxWhisperPath,
                language: mlxWhisperLanguage
            )
        }
    }
}
