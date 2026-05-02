import Foundation

/// Final transcription strategy applied to a recorded `.m4a` file post-Stop.
/// Unlike LiveTranscriber, this is batch-only: hand it a file, get segments back.
protocol FileTranscribing: Sendable {
    func transcribe(audioFile url: URL, kind: AudioKind) async throws -> [TranscriptSegment]
}

/// Wraps the existing Apple SpeechAnalyzer-based file transcription so it
/// composes with the FileTranscribing protocol used by RecordingSession.
struct AppleFileTranscriber: FileTranscribing {
    let locale: Locale

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    func transcribe(audioFile url: URL, kind: AudioKind) async throws -> [TranscriptSegment] {
        try await FileTranscriber.transcribe(audioFile: url, kind: kind, locale: locale)
    }
}
