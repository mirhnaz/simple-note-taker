import AVFoundation
import Foundation
import Observation

enum RecordingState: Equatable {
    case idle
    case starting
    case recording(startedAt: Date)
    case transcribing(startedAt: Date)
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
    private let startSession: () async throws -> AudioRecorder
    private let requestPermissions: () async -> Permissions.Status

    init(
        startSession: @escaping () async throws -> AudioRecorder = { try await RecordingSession.start() },
        requestPermissions: @escaping () async -> Permissions.Status = { await Permissions.requestAll() }
    ) {
        self.startSession = startSession
        self.requestPermissions = requestPermissions
    }

    func start() async {
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

    func importRecording(from sourceURL: URL, meetingDate: Date) async {
        guard case .idle = state else { return }
        self.state = .transcribing(startedAt: Date())
        self.lastWarning = nil
        self.importPhase = .transcribing
        do {
            let url = try await ImportSession.run(
                sourceURL: sourceURL,
                meetingDate: meetingDate
            ) { phase in
                self.importPhase = phase
            }
            self.lastTranscriptURL = url
            self.lastError = nil
            applyAppleIntelligenceWarningIfNeeded()
        } catch {
            self.lastError = "Import failed: \(error.localizedDescription)"
        }
        self.importPhase = nil
        self.state = .idle
    }
}
