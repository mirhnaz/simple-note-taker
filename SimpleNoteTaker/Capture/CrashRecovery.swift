import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "recovery")

/// Rebuilds a meeting from the audio left behind by a crashed/force-quit
/// recording. Transcribes whichever of the mic/system files survived, merges
/// them, summarizes with the recording's meeting type, and writes the normal
/// meeting files — then clears the marker and cleans up the orphaned audio.
enum CrashRecovery {
    private static let fileTranscriptionTimeoutSeconds: TimeInterval = 600
    private static let summaryTimeoutSeconds: TimeInterval = 60

    @discardableResult
    static func recover(
        marker: RecordingRecovery.Marker,
        settings: AppSettings = .shared,
        summarizer: (any Summarizing)? = nil,
        fileTranscriber: (any FileTranscribing)? = nil
    ) async throws -> URL {
        let summarizer = summarizer ?? settings.makeSummarizer()
        let fileTranscriber = fileTranscriber ?? settings.makeFileTranscriber()
        try Paths.ensureDirectoryExists(settings.notesDirectory)

        let audioURLs = marker.audioURLs
        log.info("recovering meeting from \(audioURLs.count, privacy: .public) audio file(s), date \(marker.startedAt, privacy: .public)")

        var segments: [TranscriptSegment] = []
        // Deterministic order: mic then system, matching live capture.
        for kind in [AudioKind.mic, .system] {
            guard let url = audioURLs[kind], fileExistsNonEmpty(url) else { continue }
            segments.append(contentsOf: await transcribe(url: url, kind: kind, transcriber: fileTranscriber))
        }
        log.info("recovery segments: \(segments.count, privacy: .public)")

        let summary = await summarize(segments: segments, summarizer: summarizer, meetingType: marker.meetingType)

        let written = try MarkdownWriter.write(
            meetingDate: marker.startedAt,
            segments: segments,
            summary: summary,
            meetingType: marker.meetingType,
            to: settings.notesDirectory
        )
        log.info("recovery wrote: \(written.summaryURL.lastPathComponent, privacy: .public)")

        // Recovery done — drop the marker and, unless the user retains audio,
        // the orphaned files.
        RecordingRecovery.clear()
        if !marker.retainAudio {
            for url in audioURLs.values {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return written.summaryURL
    }

    /// Discards a pending recovery: clears the marker and removes the orphaned
    /// audio (always — the user chose not to keep this meeting).
    static func discard(marker: RecordingRecovery.Marker) {
        RecordingRecovery.clear()
        for url in marker.audioURLs.values {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func fileExistsNonEmpty(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        guard let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int else { return false }
        return (size ?? 0) > 0
    }

    /// Transcribes one recovered file. An interrupted recording's container may
    /// be unfinalized, so on first failure we retry after an ffmpeg normalize
    /// pass (which is tolerant of a missing moov atom), mirroring ImportSession.
    private static func transcribe(url: URL, kind: AudioKind, transcriber: any FileTranscribing) async -> [TranscriptSegment] {
        do {
            return try await withTimeout(seconds: fileTranscriptionTimeoutSeconds) {
                try await transcriber.transcribe(audioFile: url, kind: kind)
            }
        } catch {
            log.warning("recovery transcribe of \(kind.rawValue, privacy: .public) failed (\(error.localizedDescription, privacy: .public)); retrying after normalize")
            do {
                let normalized = try await AudioNormalization.normalize(source: url)
                defer { try? FileManager.default.removeItem(at: normalized) }
                return try await withTimeout(seconds: fileTranscriptionTimeoutSeconds) {
                    try await transcriber.transcribe(audioFile: normalized, kind: kind)
                }
            } catch {
                log.error("recovery transcribe of \(kind.rawValue, privacy: .public) failed after normalize: \(error.localizedDescription, privacy: .public)")
                return []
            }
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
            log.error("recovery summarization timed out: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
