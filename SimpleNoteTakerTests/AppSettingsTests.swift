import Foundation
import Testing
@testable import SimpleNoteTaker

struct AppSettingsTests {
    private func makeSettings() -> AppSettings {
        let suiteName = "snt-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    @Test func defaultNotesDirectoryWhenUnset() {
        let settings = makeSettings()
        #expect(settings.notesDirectory == Paths.defaultNotesDirectory)
    }

    @Test func defaultAudioDirectoryWhenUnset() {
        let settings = makeSettings()
        #expect(settings.audioDirectory == Paths.defaultAudioDirectory)
    }

    @Test func retainAudioDefaultsToFalse() {
        let settings = makeSettings()
        #expect(settings.retainAudioFiles == false)
    }

    @Test func customNotesPathOverridesDefault() {
        let settings = makeSettings()
        settings.defaults.set("/tmp/MyMeetings", forKey: SettingsKeys.notesDirectoryPath)
        #expect(settings.notesDirectory == URL(filePath: "/tmp/MyMeetings"))
    }

    @Test func customAudioPathOverridesDefault() {
        let settings = makeSettings()
        settings.defaults.set("/tmp/MyAudio", forKey: SettingsKeys.audioDirectoryPath)
        #expect(settings.audioDirectory == URL(filePath: "/tmp/MyAudio"))
    }

    @Test func emptyStringFallsBackToDefault() {
        let settings = makeSettings()
        settings.defaults.set("", forKey: SettingsKeys.notesDirectoryPath)
        settings.defaults.set("", forKey: SettingsKeys.audioDirectoryPath)
        #expect(settings.notesDirectory == Paths.defaultNotesDirectory)
        #expect(settings.audioDirectory == Paths.defaultAudioDirectory)
    }

    @Test func retainAudioFlagToggles() {
        let settings = makeSettings()
        settings.defaults.set(true, forKey: SettingsKeys.retainAudioFiles)
        #expect(settings.retainAudioFiles == true)
        settings.defaults.set(false, forKey: SettingsKeys.retainAudioFiles)
        #expect(settings.retainAudioFiles == false)
    }

    @Test func llmProviderDefaultsToApple() {
        let settings = makeSettings()
        #expect(settings.llmProvider == .apple)
    }

    @Test func llmProviderRoundTrips() {
        let settings = makeSettings()
        settings.defaults.set("ollama", forKey: SettingsKeys.llmProvider)
        #expect(settings.llmProvider == .ollama)
        settings.defaults.set("apple", forKey: SettingsKeys.llmProvider)
        #expect(settings.llmProvider == .apple)
    }

    @Test func llmProviderUnknownStringFallsBackToApple() {
        let settings = makeSettings()
        settings.defaults.set("anthropic-cloud", forKey: SettingsKeys.llmProvider)
        #expect(settings.llmProvider == .apple)
    }

    @Test func ollamaBaseURLDefaultsToLocalhost() {
        let settings = makeSettings()
        #expect(settings.ollamaBaseURL.absoluteString == AppSettings.defaultOllamaBaseURL)
    }

    @Test func ollamaBaseURLRespectsCustom() {
        let settings = makeSettings()
        settings.defaults.set("http://192.168.1.10:11434", forKey: SettingsKeys.ollamaBaseURL)
        #expect(settings.ollamaBaseURL.absoluteString == "http://192.168.1.10:11434")
    }

    @Test func ollamaBaseURLEmptyFallsBackToDefault() {
        let settings = makeSettings()
        settings.defaults.set("", forKey: SettingsKeys.ollamaBaseURL)
        #expect(settings.ollamaBaseURL.absoluteString == AppSettings.defaultOllamaBaseURL)
    }

    @Test func ollamaModelDefaultsToEmpty() {
        let settings = makeSettings()
        #expect(settings.ollamaModel == "")
    }

    @Test func transcriptionProviderDefaultsToApple() {
        let settings = makeSettings()
        #expect(settings.transcriptionProvider == .apple)
    }

    @Test func transcriptionProviderRoundTrips() {
        let settings = makeSettings()
        settings.defaults.set("mlxWhisper", forKey: SettingsKeys.transcriptionProvider)
        #expect(settings.transcriptionProvider == .mlxWhisper)
        settings.defaults.set("apple", forKey: SettingsKeys.transcriptionProvider)
        #expect(settings.transcriptionProvider == .apple)
    }

    @Test func transcriptionProviderUnknownStringFallsBackToApple() {
        let settings = makeSettings()
        settings.defaults.set("mystery-engine", forKey: SettingsKeys.transcriptionProvider)
        #expect(settings.transcriptionProvider == .apple)
    }

    @Test func mlxWhisperModelDefaultsToConstant() {
        let settings = makeSettings()
        #expect(settings.mlxWhisperModel == AppSettings.defaultMLXWhisperModel)
    }

    @Test func mlxWhisperModelEmptyFallsBackToDefault() {
        let settings = makeSettings()
        settings.defaults.set("", forKey: SettingsKeys.mlxWhisperModel)
        #expect(settings.mlxWhisperModel == AppSettings.defaultMLXWhisperModel)
    }

    @Test func mlxWhisperModelCustom() {
        let settings = makeSettings()
        settings.defaults.set("mlx-community/whisper-tiny", forKey: SettingsKeys.mlxWhisperModel)
        #expect(settings.mlxWhisperModel == "mlx-community/whisper-tiny")
    }

    @Test func mlxWhisperPathDefaultsToEmpty() {
        let settings = makeSettings()
        #expect(settings.mlxWhisperPath == "")
    }
}
