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
}
