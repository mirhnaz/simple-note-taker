import Foundation
import Testing
@testable import SimpleNoteTaker

@MainActor
struct RecordingControllerTests {
    final class StubRecorder: AudioRecorder {
        let audioFiles: [AudioKind: URL]
        let startedAt: Date
        var stopped = false
        let stopResult: URL

        init(
            files: [AudioKind: URL] = [.mic: URL(filePath: "/tmp/test-mic.m4a")],
            startedAt: Date = Date(),
            stopResult: URL = URL(filePath: "/tmp/test-meeting.md")
        ) {
            self.audioFiles = files
            self.startedAt = startedAt
            self.stopResult = stopResult
        }

        func stop() async throws -> URL {
            stopped = true
            return stopResult
        }
    }

    struct StartFailure: Error {}
    struct StopFailure: Error {}

    static let allGranted = Permissions.Status(microphone: true, speech: true, screenRecording: true)
    static let micOnly = Permissions.Status(microphone: true, speech: true, screenRecording: false)
    static let micDenied = Permissions.Status(microphone: false, speech: true, screenRecording: true)
    static let speechDenied = Permissions.Status(microphone: true, speech: false, screenRecording: true)

    /// Builds a controller whose summarizer probe is stubbed ready and applies
    /// it, so `start()` gets past the summarizer-availability guard and the
    /// permission/recording behavior under test is what actually runs.
    static func makeReadyController(
        startSession: @escaping () async throws -> AudioRecorder,
        requestPermissions: @escaping () async -> Permissions.Status
    ) async -> RecordingController {
        let controller = RecordingController(
            startSession: startSession,
            requestPermissions: requestPermissions,
            probeSummarizerStatus: { .ready }
        )
        await controller.refreshSummarizerStatus()
        return controller
    }

    @Test func startsInIdleState() {
        let controller = RecordingController(
            startSession: { Issue.record("startSession should not be called"); return StubRecorder() },
            requestPermissions: { Self.micDenied }
        )
        #expect(controller.state == .idle)
        #expect(controller.lastError == nil)
        #expect(controller.lastWarning == nil)
        #expect(controller.lastTranscriptURL == nil)
    }

    @Test func startTransitionsToRecordingWhenAllPermissionsGranted() async {
        let recorder = StubRecorder(startedAt: Date(timeIntervalSince1970: 1_000_000))
        let controller = await Self.makeReadyController(
            startSession: { recorder },
            requestPermissions: { Self.allGranted }
        )
        await controller.start()
        #expect(controller.state == .recording(startedAt: recorder.startedAt))
        #expect(controller.lastError == nil)
        #expect(controller.lastWarning == nil)
    }

    @Test func startSetsErrorWhenMicrophoneDenied() async {
        let controller = await Self.makeReadyController(
            startSession: { Issue.record("startSession should not be called"); return StubRecorder() },
            requestPermissions: { Self.micDenied }
        )
        await controller.start()
        #expect(controller.state == .idle)
        #expect(controller.lastError?.contains("Microphone access denied") == true)
    }

    @Test func startSetsErrorWhenSpeechDenied() async {
        let controller = await Self.makeReadyController(
            startSession: { Issue.record("startSession should not be called"); return StubRecorder() },
            requestPermissions: { Self.speechDenied }
        )
        await controller.start()
        #expect(controller.state == .idle)
        #expect(controller.lastError?.contains("Speech Recognition access denied") == true)
    }

    @Test func startSetsWarningWhenScreenRecordingDenied() async {
        let recorder = StubRecorder()
        let controller = await Self.makeReadyController(
            startSession: { recorder },
            requestPermissions: { Self.micOnly }
        )
        await controller.start()
        #expect(controller.state == .recording(startedAt: recorder.startedAt))
        #expect(controller.lastWarning?.contains("Screen Recording") == true)
        #expect(controller.lastError == nil)
    }

    @Test func startSetsErrorWhenSessionFailsToStart() async {
        let controller = await Self.makeReadyController(
            startSession: { throw StartFailure() },
            requestPermissions: { Self.allGranted }
        )
        await controller.start()
        #expect(controller.state == .idle)
        #expect(controller.lastError?.contains("Couldn't start recording") == true)
    }

    @Test func stopReturnsToIdleAndPublishesMarkdownURL() async {
        let url = URL(filePath: "/tmp/expected.md")
        let recorder = StubRecorder(stopResult: url)
        let controller = await Self.makeReadyController(
            startSession: { recorder },
            requestPermissions: { Self.allGranted }
        )
        await controller.start()
        await controller.stop()
        #expect(controller.state == .idle)
        #expect(recorder.stopped == true)
        #expect(controller.lastTranscriptURL == url)
    }

    @Test func stopSetsErrorWhenTranscriptionFails() async {
        final class FailingRecorder: AudioRecorder {
            let startedAt = Date()
            let audioFiles: [AudioKind: URL] = [:]
            func stop() async throws -> URL { throw StopFailure() }
        }
        let controller = await Self.makeReadyController(
            startSession: { FailingRecorder() },
            requestPermissions: { Self.allGranted }
        )
        await controller.start()
        await controller.stop()
        #expect(controller.state == .idle)
        #expect(controller.lastError?.contains("Transcription failed") == true)
    }

    @Test func dismissNoticesClearsErrorAndWarning() async {
        let recorder = StubRecorder()
        let controller = await Self.makeReadyController(
            startSession: { recorder },
            requestPermissions: { Self.micOnly }
        )
        await controller.start()
        #expect(controller.lastWarning != nil)
        // Force an error by stopping when there's no recording.
        await controller.stop() // stops the current
        // Now trigger a stop-time failure
        final class FailingRecorder: AudioRecorder {
            let startedAt = Date()
            let audioFiles: [AudioKind: URL] = [:]
            func stop() async throws -> URL { throw StopFailure() }
        }
        let controller2 = await Self.makeReadyController(
            startSession: { FailingRecorder() },
            requestPermissions: { Self.micOnly }
        )
        await controller2.start()
        await controller2.stop()
        #expect(controller2.lastError != nil)
        #expect(controller2.lastWarning != nil)
        controller2.dismissNotices()
        #expect(controller2.lastError == nil)
        #expect(controller2.lastWarning == nil)
    }

    @Test func successAfterFailureClearsLastError() async {
        var attempt = 0
        let recorder = StubRecorder()
        let controller = await Self.makeReadyController(
            startSession: {
                attempt += 1
                if attempt == 1 { throw StartFailure() }
                return recorder
            },
            requestPermissions: { Self.allGranted }
        )
        await controller.start()
        #expect(controller.lastError != nil)
        await controller.start()
        #expect(controller.lastError == nil)
        #expect(controller.state == .recording(startedAt: recorder.startedAt))
    }
}
