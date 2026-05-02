import AVFAudio
import Foundation
import Speech

@MainActor
@Observable
final class LiveTranscriber {
    let kind: AudioKind
    let analyzerFormat: AVAudioFormat
    private(set) var segments: [TranscriptSegment] = []
    private(set) var currentPartial: String = ""

    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private var resultsTask: Task<Void, Never>?

    static func start(kind: AudioKind, locale: Locale = Locale(identifier: "en-US")) async throws -> LiveTranscriber {
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw LiveTranscriberError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)

        let live = LiveTranscriber(
            kind: kind,
            analyzerFormat: analyzerFormat,
            analyzer: analyzer,
            transcriber: transcriber,
            inputContinuation: continuation
        )
        live.observeResults()
        return live
    }

    private init(
        kind: AudioKind,
        analyzerFormat: AVAudioFormat,
        analyzer: SpeechAnalyzer,
        transcriber: SpeechTranscriber,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    ) {
        self.kind = kind
        self.analyzerFormat = analyzerFormat
        self.analyzer = analyzer
        self.transcriber = transcriber
        self.inputContinuation = inputContinuation
    }

    private func observeResults() {
        let stream = transcriber.results
        let kind = self.kind
        resultsTask = Task { [weak self] in
            do {
                for try await result in stream {
                    let text = String(result.text.characters)
                    let segment = TranscriptSegment(
                        kind: kind,
                        startSeconds: result.range.start.seconds,
                        endSeconds: result.range.end.seconds,
                        text: text
                    )
                    await MainActor.run {
                        guard let self else { return }
                        self.segments.append(segment)
                        self.currentPartial = text
                    }
                }
            } catch {
                // best-effort; transcription errors surface as missing segments
            }
        }
    }

    nonisolated func feed(_ buffer: AVAudioPCMBuffer) {
        inputContinuation.yield(AnalyzerInput(buffer: buffer))
    }

    func stop() async -> [TranscriptSegment] {
        inputContinuation.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        currentPartial = ""
        return segments
    }
}

enum LiveTranscriberError: Error, LocalizedError {
    case noCompatibleAudioFormat

    var errorDescription: String? {
        switch self {
        case .noCompatibleAudioFormat:
            return "No compatible audio format is available for on-device transcription."
        }
    }
}
