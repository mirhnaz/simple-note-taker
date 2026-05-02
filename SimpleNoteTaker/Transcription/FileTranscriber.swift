import AVFAudio
import Foundation
import Speech

enum FileTranscriber {
    static func transcribe(audioFile url: URL, kind: AudioKind, locale: Locale = Locale(identifier: "en-US")) async throws -> [TranscriptSegment] {
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let audioFile = try AVAudioFile(forReading: url)
        // The convenience init both configures and starts the analyzer with the
        // file as input; calling analyzer.start(inputAudioFile:) afterwards
        // tries to feed a second input sequence and trips a precondition.
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            finishAfterFile: true
        )
        _ = analyzer  // keep alive until results stream finishes

        var segments: [TranscriptSegment] = []
        for try await result in transcriber.results {
            segments.append(TranscriptSegment(
                kind: kind,
                startSeconds: result.range.start.seconds,
                endSeconds: result.range.end.seconds,
                text: String(result.text.characters)
            ))
        }
        return segments
    }
}
