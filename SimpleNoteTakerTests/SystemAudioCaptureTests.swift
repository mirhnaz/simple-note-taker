import Foundation
import Testing
@testable import SimpleNoteTaker

struct SystemAudioCaptureTests {
    struct DummyError: Error {}

    @Test func permissionDeniedMessageMentionsScreenRecording() {
        let error = SystemAudioCaptureError.permissionDenied(underlying: DummyError())
        #expect(error.errorDescription?.contains("Screen Recording") == true)
        #expect(error.errorDescription?.contains("System Settings") == true)
    }

    @Test func noDisplayMessageMentionsDisplay() {
        let error = SystemAudioCaptureError.noDisplayAvailable
        #expect(error.errorDescription?.contains("display") == true)
    }
}
