import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "session")

@MainActor
final class RecordingSession: AudioRecorder {
    let startedAt: Date
    let audioFiles: [AudioKind: URL]
    let systemAudioWarning: String?

    private let mic: MicCapture
    private let system: SystemAudioCapture?
    let micTranscriber: LiveTranscriber
    private let notesDirectory: URL
    private let retainAudioFiles: Bool
    private let summarizer: any Summarizing

    private static let stopTimeoutSeconds: TimeInterval = 30
    private static let summaryTimeoutSeconds: TimeInterval = 60

    static func start(settings: AppSettings = .shared, summarizer: (any Summarizing)? = nil) async throws -> RecordingSession {
        let summarizer = summarizer ?? settings.makeSummarizer()
        let startedAt = Date()
        let directory = settings.retainAudioFiles
            ? settings.audioDirectory
            : FileManager.default.temporaryDirectory
        try Paths.ensureDirectoryExists(directory)
        try Paths.ensureDirectoryExists(settings.notesDirectory)

        let micURL = directory.appending(path: MeetingFiles.audioFilename(for: startedAt, kind: .mic))
        let systemURL = directory.appending(path: MeetingFiles.audioFilename(for: startedAt, kind: .system))

        let micTranscriber = try await LiveTranscriber.start(kind: .mic)
        let mic = try MicCapture.start(outputURL: micURL, transcriber: micTranscriber)

        var files: [AudioKind: URL] = [.mic: micURL]
        var system: SystemAudioCapture?
        var warning: String?

        do {
            system = try await SystemAudioCapture.start(outputURL: systemURL)
            files[.system] = systemURL
        } catch {
            log.warning("system audio capture failed: \(error.localizedDescription, privacy: .public)")
            warning = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        log.info("session started; mic + \(system == nil ? "no system audio" : "system audio", privacy: .public)")
        return RecordingSession(
            startedAt: startedAt,
            audioFiles: files,
            systemAudioWarning: warning,
            mic: mic,
            system: system,
            micTranscriber: micTranscriber,
            notesDirectory: settings.notesDirectory,
            retainAudioFiles: settings.retainAudioFiles,
            summarizer: summarizer
        )
    }

    private init(
        startedAt: Date,
        audioFiles: [AudioKind: URL],
        systemAudioWarning: String?,
        mic: MicCapture,
        system: SystemAudioCapture?,
        micTranscriber: LiveTranscriber,
        notesDirectory: URL,
        retainAudioFiles: Bool,
        summarizer: any Summarizing
    ) {
        self.startedAt = startedAt
        self.audioFiles = audioFiles
        self.systemAudioWarning = systemAudioWarning
        self.mic = mic
        self.system = system
        self.micTranscriber = micTranscriber
        self.notesDirectory = notesDirectory
        self.retainAudioFiles = retainAudioFiles
        self.summarizer = summarizer
    }

    func stop() async throws -> URL {
        log.info("session stopping")
        mic.stop()
        await system?.stop()
        log.info("audio captures stopped, finalizing transcripts")

        let micSegments = await stopMicTranscriber()
        log.info("mic segments: \(micSegments.count, privacy: .public)")

        let systemSegments = await transcribeSystemAudio()
        log.info("system segments: \(systemSegments.count, privacy: .public)")

        let allSegments = micSegments + systemSegments
        let summary = await summarize(allSegments)
        log.info("summary: \(summary == nil ? "(none)" : "ok", privacy: .public)")

        let url = try MarkdownWriter.write(
            meetingDate: startedAt,
            segments: allSegments,
            summary: summary,
            to: notesDirectory
        )
        log.info("wrote markdown: \(url.lastPathComponent, privacy: .public)")

        if !retainAudioFiles {
            cleanupAudioFiles()
        }
        return url
    }

    private func cleanupAudioFiles() {
        Self.removeAudioFiles(audioFiles)
    }

    /// Best-effort delete every audio URL. Logs failures but never throws.
    static func removeAudioFiles(_ files: [AudioKind: URL]) {
        let fm = FileManager.default
        for (kind, url) in files {
            do {
                try fm.removeItem(at: url)
                log.info("removed temp \(kind.rawValue, privacy: .public) audio: \(url.lastPathComponent, privacy: .public)")
            } catch {
                log.warning("couldn't remove temp \(kind.rawValue, privacy: .public) audio: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func summarize(_ segments: [TranscriptSegment]) async -> MeetingSummary? {
        guard !segments.isEmpty else { return nil }
        let transcript = TranscriptMerger.renderTranscript(segments)
        let summarizer = self.summarizer
        do {
            return try await withTimeout(seconds: Self.summaryTimeoutSeconds) {
                await summarizer.summarize(transcript: transcript)
            }
        } catch {
            log.error("summarization timed out: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func stopMicTranscriber() async -> [TranscriptSegment] {
        let transcriber = micTranscriber
        do {
            return try await withTimeout(seconds: Self.stopTimeoutSeconds) {
                await transcriber.stop()
            }
        } catch {
            log.error("mic transcriber stop timed out: \(error.localizedDescription, privacy: .public)")
            return await MainActor.run { transcriber.segments }
        }
    }

    private func transcribeSystemAudio() async -> [TranscriptSegment] {
        guard let systemURL = audioFiles[.system] else { return [] }
        do {
            return try await withTimeout(seconds: Self.stopTimeoutSeconds) {
                try await FileTranscriber.transcribe(audioFile: systemURL, kind: .system)
            }
        } catch {
            log.error("system audio transcription failed/timed out: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
