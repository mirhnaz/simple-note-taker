import Foundation

/// Final transcription strategy applied to a recorded `.m4a` file post-Stop.
/// Unlike LiveTranscriber, this is batch-only: hand it a file, get segments back.
/// `onProgress` is fired with a 0.0...1.0 fraction as audio is processed; it may
/// never fire if the underlying engine doesn't expose intermediate progress.
protocol FileTranscribing: Sendable {
    func transcribe(
        audioFile url: URL,
        kind: AudioKind,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment]
}

extension FileTranscribing {
    /// Convenience for callers that don't care about progress (live-record path).
    func transcribe(audioFile url: URL, kind: AudioKind) async throws -> [TranscriptSegment] {
        try await transcribe(audioFile: url, kind: kind, onProgress: { _ in })
    }
}

/// Wraps the existing Apple SpeechAnalyzer-based file transcription so it
/// composes with the FileTranscribing protocol used by RecordingSession.
struct AppleFileTranscriber: FileTranscribing {
    let locale: Locale

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    func transcribe(
        audioFile url: URL,
        kind: AudioKind,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment] {
        try await FileTranscriber.transcribe(audioFile: url, kind: kind, locale: locale, onProgress: onProgress)
    }
}
