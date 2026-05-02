import Testing
@testable import SimpleNoteTaker

@MainActor
struct AppActivationTests {
    @Test func windowsAddRefThenRelease() {
        let activation = AppActivation()
        #expect(activation.openWindowCount == 0)
        activation.windowDidAppear()
        #expect(activation.openWindowCount == 1)
        activation.windowDidAppear()
        #expect(activation.openWindowCount == 2)
        activation.windowDidDisappear()
        #expect(activation.openWindowCount == 1)
        activation.windowDidDisappear()
        #expect(activation.openWindowCount == 0)
    }

    @Test func disappearDoesNotGoNegative() {
        let activation = AppActivation()
        activation.windowDidDisappear()
        activation.windowDidDisappear()
        #expect(activation.openWindowCount == 0)
    }
}
