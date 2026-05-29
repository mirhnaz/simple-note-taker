import AVFoundation
import Foundation
import Observation

enum RecordingState: Equatable {
    case idle
    case starting
    case recording(startedAt: Date)
    case transcribing(startedAt: Date)
}

enum SummarizerStatus: Equatable, Sendable {
    case checking
    case ready
    case unavailable(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var unavailableMessage: String? {
        if case .unavailable(let msg) = self { return msg }
        return nil
    }
}

@MainActor
@Observable
final class RecordingController {
    static let shared = RecordingController()

    private(set) var state: RecordingState = .idle
    private(set) var lastError: String?
    private(set) var lastWarning: String?
    private(set) var lastTranscriptURL: URL?
    private(set) var session: AudioRecorder?
    private(set) var importPhase: ImportPhase?
    private(set) var summarizerStatus: SummarizerStatus = .checking
    /// Set at launch when a previous recording was interrupted by a crash and
    /// its audio is still recoverable. Drives the recovery prompt.
    private(set) var pendingRecovery: RecordingRecovery.Marker?
    private var cancellingImport = false
    private let startSession: () async throws -> AudioRecorder
    private let requestPermissions: () async -> Permissions.Status
    private let probeSummarizerStatus: () async -> SummarizerStatus

    init(
        startSession: @escaping () async throws -> AudioRecorder = { try await RecordingSession.start() },
        requestPermissions: @escaping () async -> Permissions.Status = { await Permissions.requestAll() },
        probeSummarizerStatus: @escaping () async -> SummarizerStatus = RecordingController.defaultSummarizerProbe
    ) {
        self.startSession = startSession
        self.requestPermissions = requestPermissions
        self.probeSummarizerStatus = probeSummarizerStatus
    }

    /// Re-checks whether a usable summarizer is reachable and publishes the
    /// result. The actual probe is injected (defaults to the real one) so the
    /// recording flow can be tested without a live Apple Intelligence / Ollama
    /// environment.
    func refreshSummarizerStatus() async {
        self.summarizerStatus = await probeSummarizerStatus()
    }

    /// Real summarizer probe. Apple Foundation Models needs Apple Intelligence
    /// enabled and the on-device model downloaded; Ollama needs the server
    /// running and the configured model pulled. Runs off MainActor so neither
    /// the Apple framework access nor the Ollama HTTP call blocks UI rendering.
    static let defaultSummarizerProbe: @Sendable () async -> SummarizerStatus = {
        let settings = AppSettings.shared
        let provider = settings.llmProvider
        let baseURL = settings.ollamaBaseURL
        let modelName = settings.ollamaModel.trimmingCharacters(in: .whitespaces)
        return await Task.detached(priority: .userInitiated) { () -> SummarizerStatus in
            switch provider {
            case .apple:
                if let message = FoundationModelsAvailability.currentMessage() {
                    return .unavailable(message)
                }
                return .ready
            case .ollama:
                guard !modelName.isEmpty else {
                    return .unavailable("No Ollama model selected. Open Settings and pick one.")
                }
                do {
                    // Short timeout for a status probe — localhost should
                    // answer in milliseconds when Ollama is running.
                    let models = try await OllamaClient(baseURL: baseURL).listModels(timeout: 3)
                    if models.contains(where: { $0.name == modelName }) {
                        return .ready
                    } else {
                        return .unavailable("Ollama model '\(modelName)' isn't pulled yet. Run `ollama pull \(modelName)` in a terminal, then click Retry.")
                    }
                } catch {
                    return .unavailable("Can't reach Ollama at \(baseURL.absoluteString). Start Ollama and click Retry, or switch to Apple Foundation Models in Settings.")
                }
            }
        }.value
    }

    func start() async {
        guard summarizerStatus.isReady else {
            lastError = summarizerStatus.unavailableMessage ?? "Summarization isn't set up. Open Settings to configure a provider."
            return
        }
        let permissions = await requestPermissions()
        guard permissions.microphone else {
            lastError = "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."
            return
        }
        guard permissions.speech else {
            lastError = "Speech Recognition access denied. Enable it in System Settings → Privacy & Security → Speech Recognition."
            return
        }
        self.state = .starting
        do {
            let session = try await startSession()
            self.session = session
            self.state = .recording(startedAt: session.startedAt)
            self.lastError = nil
            var warning = (session as? RecordingSession)?.systemAudioWarning
            if !permissions.screenRecording && warning == nil {
                warning = "Screen Recording permission is required to capture meeting audio (other participants). Mic-only recording will continue. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording."
            }
            self.lastWarning = warning
        } catch {
            self.state = .idle
            self.lastError = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    func dismissNotices() {
        lastError = nil
        lastWarning = nil
    }

    func stop() async {
        guard let session, case .recording(let startedAt) = state else {
            self.session = nil
            self.state = .idle
            return
        }
        self.state = .transcribing(startedAt: startedAt)
        do {
            let url = try await session.stop()
            self.lastTranscriptURL = url
            self.lastError = nil
            applyAppleIntelligenceWarningIfNeeded()
        } catch {
            self.lastError = "Transcription failed: \(error.localizedDescription)"
        }
        self.session = nil
        self.state = .idle
    }

    /// When the user has Apple Foundation Models selected but the on-device
    /// model is unavailable, the meeting saves without a summary. Surface the
    /// reason so the user knows to enable Apple Intelligence (or wait for
    /// the download) and re-run Regenerate.
    private func applyAppleIntelligenceWarningIfNeeded() {
        guard AppSettings.shared.llmProvider == .apple,
              let message = FoundationModelsAvailability.currentMessage() else { return }
        if self.lastWarning == nil {
            self.lastWarning = message
        } else if let existing = self.lastWarning, !existing.contains("Apple Intelligence") {
            self.lastWarning = existing + "\n" + message
        }
    }

    func importRecording(from sourceURL: URL, meetingDate: Date, meetingType: MeetingType = .general) async {
        guard case .idle = state else { return }
        guard summarizerStatus.isReady else {
            lastError = summarizerStatus.unavailableMessage ?? "Summarization isn't set up. Open Settings to configure a provider."
            return
        }
        self.state = .transcribing(startedAt: Date())
        self.lastWarning = nil
        self.lastError = nil
        self.cancellingImport = false
        self.importPhase = .transcribing(fraction: nil)
        do {
            let url = try await ImportSession.run(
                sourceURL: sourceURL,
                meetingDate: meetingDate,
                meetingType: meetingType
            ) { phase in
                self.importPhase = phase
            }
            self.lastTranscriptURL = url
            self.lastError = nil
            applyAppleIntelligenceWarningIfNeeded()
        } catch {
            if cancellingImport {
                self.lastWarning = "Import cancelled."
            } else {
                self.lastError = "Import failed: \(error.localizedDescription)"
            }
        }
        self.cancellingImport = false
        self.importPhase = nil
        self.state = .idle
    }

    /// User-initiated cancel for an in-progress import. Sends SIGTERM to any
    /// running child process (mlx_whisper / ffmpeg); the resulting non-zero
    /// exit unwinds the await chain in `importRecording` and the catch block
    /// turns the thrown error into the "Import cancelled." warning.
    func cancelImport() {
        guard case .transcribing = state else { return }
        guard importPhase != nil else { return }
        cancellingImport = true
        SubprocessRegistry.shared.interruptAll()
    }

    /// Checks at launch whether a previous recording was interrupted by a
    /// crash and left recoverable audio. Idempotent — safe to call on each
    /// window appear. Never runs while a recording/import is active.
    func checkForCrashRecovery() {
        guard case .idle = state, pendingRecovery == nil else { return }
        pendingRecovery = RecordingRecovery.pending()
    }

    /// Rebuilds the interrupted meeting from its surviving audio and clears the
    /// pending state. Routes the result through the same UI signal as an
    /// import (lastTranscriptURL).
    func recoverPendingMeeting() async {
        guard let marker = pendingRecovery, case .idle = state else { return }
        pendingRecovery = nil
        state = .transcribing(startedAt: Date())
        importPhase = .transcribing(fraction: nil)
        lastError = nil
        lastWarning = nil
        do {
            let url = try await CrashRecovery.recover(marker: marker)
            lastTranscriptURL = url
            applyAppleIntelligenceWarningIfNeeded()
        } catch {
            lastError = "Couldn't recover the interrupted meeting: \(error.localizedDescription)"
        }
        importPhase = nil
        state = .idle
    }

    /// Throws away the interrupted recording's audio and marker.
    func discardPendingRecovery() {
        guard let marker = pendingRecovery else { return }
        pendingRecovery = nil
        CrashRecovery.discard(marker: marker)
    }

    /// Dismisses the recovery prompt for this session without touching the
    /// on-disk marker, so it re-prompts on the next launch.
    func dismissRecoveryForNow() {
        pendingRecovery = nil
    }
}
