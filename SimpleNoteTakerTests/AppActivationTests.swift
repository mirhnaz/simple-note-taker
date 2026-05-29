import Testing
@testable import SimpleNoteTaker

@MainActor
struct AppActivationTests {
    // The app now stays in .regular activation policy at all times, so
    // windowDidAppear/windowDidDisappear no longer track an open-window count
    // (that state was removed). These remain as no-op lifecycle hooks; assert
    // only that the lifecycle is callable in any order without crashing.
    @Test func lifecycleHooksAreCallable() {
        let activation = AppActivation()
        activation.windowDidAppear()
        activation.windowDidAppear()
        activation.windowDidDisappear()
        activation.windowDidDisappear()
    }

    @Test func disappearWithoutAppearIsSafe() {
        let activation = AppActivation()
        activation.windowDidDisappear()
        activation.windowDidDisappear()
    }
}
