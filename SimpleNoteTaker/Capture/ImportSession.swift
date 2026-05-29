import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "import")

enum ImportPhase: Equatable, Sendable {
    case transcribing(fraction: Double?)
    case summarizing
    case writing

    var label: String {
        switch self {
        case .transcribing(let fraction):
            if let fraction, fraction > 0 {
                return "Transcribing audio… \(Int(fraction * 100))%"
            }
            // Before the first segment, mlx_whisper is loading the model and
            // detecting language (30–60s on the large model). Spell that out
            // so the spinner doesn't look frozen.
            return "Loading model & detecting language…"
        case .summarizing: return "Summarizing…"
        case .writing: return "Saving meeting…"
        }
    }

    /// 0.0...1.0 for the transcribing phase if known, nil otherwise.
    /// Lets the UI switch between determinate and indeterminate ProgressView.
    var transcriptionFraction: Double? {
        if case .transcribing(let fraction) = self { return fraction }
        return nil
    }
}

/// Transcribes a pre-existing audio file and writes it as a new meeting.
/// Reuses the same FileTranscriber + Summarizer + MarkdownWriter pipeline as
/// `RecordingSession.stop()`, minus the live capture phase.
enum ImportSession {
    private static let fileTranscriptionTimeoutSeconds: TimeInterval = 600
    private static let summaryTimeoutSeconds: TimeInterval = 60

    static func run(
        sourceURL: URL,
        meetingDate: Date? = nil,
        meetingType: MeetingType = .general,
        settings: AppSettings = .shared,
        summarizer: (any Summarizing)? = nil,
        fileTranscriber: (any FileTranscribing)? = nil,
        onPhase: @escaping @MainActor @Sendable (ImportPhase) async -> Void = { _ in }
    ) async throws -> URL {
        let summarizer = summarizer ?? settings.makeSummarizer()
        let fileTranscriber = fileTranscriber ?? settings.makeFileTranscriber()
        try Paths.ensureDirectoryExists(settings.notesDirectory)

        let resolvedDate = meetingDate ?? defaultMeetingDate(for: sourceURL)
        log.info("import starting: \(sourceURL.lastPathComponent, privacy: .public), date \(resolvedDate, privacy: .public)")

        await onPhase(.transcribing(fraction: nil))
        let progressTracker = ProgressTracker()
        let progressCallback: @Sendable (Double) -> Void = { fraction in
            // Throttle: only fire on a meaningful step so we don't flood the
            // MainActor with hundreds of identical updates.
            guard progressTracker.shouldReport(fraction) else { return }
            Task { @MainActor in
                await onPhase(.transcribing(fraction: fraction))
            }
        }
        let (segments, scratchFiles) = try await prepareAndTranscribe(
            sourceURL: sourceURL,
            transcriber: fileTranscriber,
            onProgress: progressCallback
        )
        defer { scratchFiles.forEach { try? FileManager.default.removeItem(at: $0) } }
        log.info("import segments: \(segments.count, privacy: .public)")

        await onPhase(.summarizing)
        let summary = await summarize(segments: segments, summarizer: summarizer, meetingType: meetingType)
        log.info("import summary: \(summary == nil ? "(none)" : "ok", privacy: .public)")

        await onPhase(.writing)
        let written = try MarkdownWriter.write(
            meetingDate: resolvedDate,
            segments: segments,
            summary: summary,
            meetingType: meetingType,
            to: settings.notesDirectory
        )
        log.info("import wrote: \(written.summaryURL.lastPathComponent, privacy: .public)")
        return written.summaryURL
    }

    /// Default stamp when the caller doesn't override: the source file's
    /// modification date, falling back to "now" if unreadable.
    static func defaultMeetingDate(for url: URL) -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.modificationDate] as? Date) ?? Date()
    }

    /// Returns segments plus any temp files the caller must clean up.
    private static func prepareAndTranscribe(
        sourceURL: URL,
        transcriber: any FileTranscribing,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ([TranscriptSegment], [URL]) {
        // Video containers (mp4, mov, …) can never be fed to AVAudioFile and
        // are flaky through AVAssetExportSession, so always pre-extract via
        // ffmpeg before the transcriber sees them.
        if AudioNormalization.isVideoFile(sourceURL) {
            let normalized = try await AudioNormalization.normalize(source: sourceURL)
            let segments = try await runTranscriber(transcriber: transcriber, audioURL: normalized, onProgress: onProgress)
            return (segments, [normalized])
        }

        do {
            let segments = try await runTranscriber(transcriber: transcriber, audioURL: sourceURL, onProgress: onProgress)
            return (segments, [])
        } catch {
            log.warning("initial transcription failed (\(error.localizedDescription, privacy: .public)); retrying after normalize")
            let originalError = error
            do {
                let normalized = try await AudioNormalization.normalize(source: sourceURL)
                let segments = try await runTranscriber(transcriber: transcriber, audioURL: normalized, onProgress: onProgress)
                return (segments, [normalized])
            } catch {
                log.error("retry after normalize also failed: \(error.localizedDescription, privacy: .public)")
                throw originalError
            }
        }
    }

    private static func runTranscriber(
        transcriber: any FileTranscribing,
        audioURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment] {
        try await withTimeout(seconds: fileTranscriptionTimeoutSeconds) {
            try await transcriber.transcribe(audioFile: audioURL, kind: .mic, onProgress: onProgress)
        }
    }

    /// Throttles progress callbacks so we only forward updates after the
    /// fraction has advanced by at least 0.005 (0.5%), keeping the MainActor
    /// dispatch rate reasonable on long files. Also enforces monotonicity —
    /// segment-emitted fractions and the wall-clock fallback ticker race
    /// against each other, and we never want the bar to visibly regress.
    private final class ProgressTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var lastReported: Double = -1

        func shouldReport(_ fraction: Double) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if fraction < lastReported { return false }
            if fraction >= 1.0 || fraction - lastReported >= 0.005 {
                lastReported = fraction
                return true
            }
            return false
        }
    }

    private static func summarize(
        segments: [TranscriptSegment],
        summarizer: any Summarizing,
        meetingType: MeetingType
    ) async -> MeetingSummary? {
        guard !segments.isEmpty else { return nil }
        let transcript = TranscriptMerger.renderTranscript(segments)
        do {
            return try await withTimeout(seconds: summaryTimeoutSeconds) {
                await summarizer.summarize(transcript: transcript, meetingType: meetingType)
            }
        } catch {
            log.error("import summarization timed out: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
