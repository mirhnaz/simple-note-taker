import AVFoundation
import CoreGraphics
import Speech

enum Permissions {
    struct Status: Equatable {
        let microphone: Bool
        let speech: Bool
        let screenRecording: Bool

        var canTranscribe: Bool { microphone && speech }
    }

    static func requestAll() async -> Status {
        let mic = await requestMicrophone()
        let speech = await requestSpeech()
        let screen = requestScreenRecording()
        return Status(microphone: mic, speech: speech, screenRecording: screen)
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    static func requestSpeech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    // ScreenCaptureKit gates system-audio capture under Screen Recording permission;
    // calling CGRequestScreenCaptureAccess once up-front avoids a second prompt later
    // when SCShareableContent and SCStream.startCapture run.
    static func requestScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }
}
