import AVFAudio
import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "session")

@MainActor
final class RecordingSession: AudioRecorder {
    let startedAt: Date
    let audioFiles: [AudioKind: URL]
    let systemAudioWarning: String?

    /// Non-nil when the mic opened in a degraded low-sample-rate mode
    /// (Bluetooth HFP). Read by the controller to warn the user so garbled
    /// live partials read as expected, not as a bug.
    static func micQualityWarning(for inputFormat: AVAudioFormat) -> String? {
        guard inputFormat.sampleRate > 0, inputFormat.sampleRate <= 16_000 else { return nil }
        return "Your mic is in low-quality Bluetooth call mode (\(Int(inputFormat.sampleRate / 1000)) kHz) — common with AirPods once a meeting app uses the mic. Your own speech may transcribe poorly. For best results use the built-in mic or a wired headset. Other participants are captured separately at full quality."
    }

    private let mic: MicCapture
    private let system: SystemAudioCapture?
    let micTranscriber: LiveTranscriber
    let systemTranscriber: LiveTranscriber?
    private let notesDirectory: URL
    private let retainAudioFiles: Bool
    private let summarizer: any Summarizing
    private let fileTranscriber: any FileTranscribing
    private let useFilePassForMic: Bool

    private static let stopTimeoutSeconds: TimeInterval = 30
    private static let fileTranscriptionTimeoutSeconds: TimeInterval = 600
    private static let summaryTimeoutSeconds: TimeInterval = 60

    static func start(
        settings: AppSettings = .shared,
        summarizer: (any Summarizing)? = nil,
        fileTranscriber: (any FileTranscribing)? = nil
    ) async throws -> RecordingSession {
        let summarizer = summarizer ?? settings.makeSummarizer()
        let fileTranscriber = fileTranscriber ?? settings.makeFileTranscriber()
        let useFilePassForMic = settings.transcriptionProvider != .apple
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
        var systemTranscriber: LiveTranscriber?
        var warning: String?

        do {
            // Live transcriber for other participants. Captured via system
            // audio, which comes through at full quality even when the user's
            // own mic is degraded by Bluetooth (e.g. AirPods in HFP mode).
            let liveSystem = try await LiveTranscriber.start(kind: .system)
            system = try await SystemAudioCapture.start(outputURL: systemURL, transcriber: liveSystem)
            systemTranscriber = liveSystem
            files[.system] = systemURL
        } catch {
            log.warning("system audio capture failed: \(error.localizedDescription, privacy: .public)")
            warning = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if let micWarning = micQualityWarning(for: mic.inputFormat) {
            log.warning("low-quality mic input: \(mic.inputFormat.sampleRate, privacy: .public) Hz")
            warning = [warning, micWarning].compactMap { $0 }.joined(separator: "\n")
        }

        log.info("session started; mic + \(system == nil ? "no system audio" : "system audio", privacy: .public)")
        return RecordingSession(
            startedAt: startedAt,
            audioFiles: files,
            systemAudioWarning: warning,
            mic: mic,
            system: system,
            micTranscriber: micTranscriber,
            systemTranscriber: systemTranscriber,
            notesDirectory: settings.notesDirectory,
            retainAudioFiles: settings.retainAudioFiles,
            summarizer: summarizer,
            fileTranscriber: fileTranscriber,
            useFilePassForMic: useFilePassForMic
        )
    }

    private init(
        startedAt: Date,
        audioFiles: [AudioKind: URL],
        systemAudioWarning: String?,
        mic: MicCapture,
        system: SystemAudioCapture?,
        micTranscriber: LiveTranscriber,
        systemTranscriber: LiveTranscriber?,
        notesDirectory: URL,
        retainAudioFiles: Bool,
        summarizer: any Summarizing,
        fileTranscriber: any FileTranscribing,
        useFilePassForMic: Bool
    ) {
        self.startedAt = startedAt
        self.audioFiles = audioFiles
        self.systemAudioWarning = systemAudioWarning
        self.mic = mic
        self.system = system
        self.micTranscriber = micTranscriber
        self.systemTranscriber = systemTranscriber
        self.notesDirectory = notesDirectory
        self.retainAudioFiles = retainAudioFiles
        self.summarizer = summarizer
        self.fileTranscriber = fileTranscriber
        self.useFilePassForMic = useFilePassForMic
    }

    func stop() async throws -> URL {
        log.info("session stopping")
        mic.stop()
        await system?.stop()
        log.info("audio captures stopped, finalizing transcripts")

        // Always drain the live transcribers so their analyzers release. The
        // system transcriber is display-only — the final "them" transcript is
        // a fresh pass over the recorded file below — so discard its segments.
        let liveMicSegments = await stopMicTranscriber()
        log.info("live mic segments: \(liveMicSegments.count, privacy: .public)")
        if let systemTranscriber {
            _ = await systemTranscriber.stop()
        }

        let micSegments: [TranscriptSegment]
        if useFilePassForMic, let micURL = audioFiles[.mic] {
            micSegments = await transcribeFromFile(url: micURL, kind: .mic)
        } else {
            micSegments = liveMicSegments
        }
        log.info("final mic segments: \(micSegments.count, privacy: .public)")

        let systemSegments = await transcribeSystemAudio()
        log.info("system segments: \(systemSegments.count, privacy: .public)")

        let allSegments = micSegments + systemSegments
        let summary = await summarize(allSegments)
        log.info("summary: \(summary == nil ? "(none)" : "ok", privacy: .public)")

        let written = try MarkdownWriter.write(
            meetingDate: startedAt,
            segments: allSegments,
            summary: summary,
            to: notesDirectory
        )
        let url = written.summaryURL
        log.info("wrote summary + transcript: \(written.summaryURL.lastPathComponent, privacy: .public), \(written.transcriptURL.lastPathComponent, privacy: .public)")

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
        return await transcribeFromFile(url: systemURL, kind: .system)
    }

    private func transcribeFromFile(url: URL, kind: AudioKind) async -> [TranscriptSegment] {
        let transcriber = fileTranscriber
        do {
            return try await withTimeout(seconds: Self.fileTranscriptionTimeoutSeconds) {
                try await transcriber.transcribe(audioFile: url, kind: kind)
            }
        } catch {
            log.error("\(kind.rawValue, privacy: .public) file transcription failed/timed out: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
