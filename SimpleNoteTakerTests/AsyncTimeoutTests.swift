import Foundation
import Testing
@testable import SimpleNoteTaker

struct AsyncTimeoutTests {
    @Test func returnsValueWhenOperationCompletesInTime() async throws {
        let value = try await withTimeout(seconds: 1.0) {
            try await Task.sleep(nanoseconds: 10_000_000)
            return 42
        }
        #expect(value == 42)
    }

    @Test func throwsTimeoutErrorWhenOperationExceedsDeadline() async {
        do {
            _ = try await withTimeout(seconds: 0.05) {
                try await Task.sleep(nanoseconds: 500_000_000)
                return "unreachable"
            }
            Issue.record("expected timeout")
        } catch is AsyncTimeoutError {
            // expected
        } catch {
            Issue.record("expected AsyncTimeoutError, got \(error)")
        }
    }

    @Test func propagatesOperationError() async {
        struct OpError: Error {}
        do {
            _ = try await withTimeout(seconds: 1.0) {
                throw OpError()
            }
            Issue.record("expected throw")
        } catch is OpError {
            // expected
        } catch {
            Issue.record("expected OpError, got \(error)")
        }
    }
}
