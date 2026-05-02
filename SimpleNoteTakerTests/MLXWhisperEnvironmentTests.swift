import Foundation
import Testing
@testable import SimpleNoteTaker

struct MLXWhisperEnvironmentTests {
    @Test func modelCacheURLUsesHFNamingConvention() {
        let url = MLXWhisperEnvironment.modelCacheURL("mlx-community/whisper-large-v3-turbo")
        #expect(url.path(percentEncoded: false).hasSuffix(".cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo"))
    }

    @Test func modelCacheURLHandlesNoSlashName() {
        let url = MLXWhisperEnvironment.modelCacheURL("whisper-tiny")
        #expect(url.lastPathComponent == "models--whisper-tiny")
    }

    @Test func isModelCachedFalseForNonExistentModel() {
        let cached = MLXWhisperEnvironment.isModelCached("definitely-not-installed/\(UUID().uuidString)")
        #expect(cached == false)
    }

    @Test func detectInstallationReturnsNilForBogusOverride() {
        let result = MLXWhisperEnvironment.detectInstallation(overridePath: "/no/such/binary/here")
        #expect(result == nil)
    }

    @Test func candidateBinDirsContainsCommonPipLocations() {
        let dirs = MLXWhisperEnvironment.candidateBinDirs
        #expect(dirs.contains("/opt/homebrew/bin"))
        #expect(dirs.contains("/usr/local/bin"))
        #expect(dirs.contains { $0.hasSuffix("/.local/bin") })
        #expect(dirs.contains { $0.contains("/Library/Python/3.11/bin") })
    }

    @Test func augmentedPATHIncludesCandidateDirs() {
        let path = MLXWhisperEnvironment.augmentedPATH
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains("/.local/bin"))
    }
}
