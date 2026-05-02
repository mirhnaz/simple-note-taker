import Testing
@testable import SimpleNoteTaker

struct PermissionsTests {
    @Test func canTranscribeRequiresMicrophoneAndSpeech() {
        #expect(Permissions.Status(microphone: true, speech: true, screenRecording: true).canTranscribe == true)
        #expect(Permissions.Status(microphone: true, speech: true, screenRecording: false).canTranscribe == true)
        #expect(Permissions.Status(microphone: false, speech: true, screenRecording: true).canTranscribe == false)
        #expect(Permissions.Status(microphone: true, speech: false, screenRecording: true).canTranscribe == false)
    }

    @Test func statusEquatable() {
        let a = Permissions.Status(microphone: true, speech: true, screenRecording: true)
        let b = Permissions.Status(microphone: true, speech: true, screenRecording: true)
        let c = Permissions.Status(microphone: true, speech: true, screenRecording: false)
        #expect(a == b)
        #expect(a != c)
    }
}
