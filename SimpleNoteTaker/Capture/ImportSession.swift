import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "import")

enum ImportPhase: Equatable, Sendable {
    case transcribing
    case summarizing
    case writing

    var label: String {
        switch self {
        case .transcribing: return "Transcribing audio…"
        case .summarizing: return "Summarizing…"
        case .writing: return "Saving meeting…"
        }
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
        settings: AppSettings = .shared,
        summarizer: (any Summarizing)? = nil,
        fileTranscriber: (any FileTranscribing)? = nil,
        onPhase: @MainActor @Sendable (ImportPhase) async -> Void = { _ in }
    ) async throws -> URL {
        let summarizer = summarizer ?? settings.makeSummarizer()
        let fileTranscriber = fileTranscriber ?? settings.makeFileTranscriber()
        try Paths.ensureDirectoryExists(settings.notesDirectory)

        let meetingDate = meetingDate(for: sourceURL)
        log.info("import starting: \(sourceURL.lastPathComponent, privacy: .public), date \(meetingDate, privacy: .public)")

        await onPhase(.transcribing)
        let segments = try await transcribe(sourceURL: sourceURL, transcriber: fileTranscriber)
        log.info("import segments: \(segments.count, privacy: .public)")

        await onPhase(.summarizing)
        let summary = await summarize(segments: segments, summarizer: summarizer)
        log.info("import summary: \(summary == nil ? "(none)" : "ok", privacy: .public)")

        await onPhase(.writing)
        let written = try MarkdownWriter.write(
            meetingDate: meetingDate,
            segments: segments,
            summary: summary,
            to: settings.notesDirectory
        )
        log.info("import wrote: \(written.summaryURL.lastPathComponent, privacy: .public)")
        return written.summaryURL
    }

    /// Stamp the new meeting with the source file's modification date so
    /// imported recordings show up in the meetings list under the date they
    /// were actually recorded, not under "now".
    private static func meetingDate(for url: URL) -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.modificationDate] as? Date) ?? Date()
    }

    private static func transcribe(
        sourceURL: URL,
        transcriber: any FileTranscribing
    ) async throws -> [TranscriptSegment] {
        try await withTimeout(seconds: fileTranscriptionTimeoutSeconds) {
            try await transcriber.transcribe(audioFile: sourceURL, kind: .mic)
        }
    }

    private static func summarize(
        segments: [TranscriptSegment],
        summarizer: any Summarizing
    ) async -> MeetingSummary? {
        guard !segments.isEmpty else { return nil }
        let transcript = TranscriptMerger.renderTranscript(segments)
        do {
            return try await withTimeout(seconds: summaryTimeoutSeconds) {
                await summarizer.summarize(transcript: transcript)
            }
        } catch {
            log.error("import summarization timed out: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
