import Foundation

enum AsyncTimeoutError: Error {
    case timedOut
}

/// Runs `operation`, returning its value if it completes within `seconds`.
/// If the deadline elapses first, throws `AsyncTimeoutError.timedOut` and
/// cancels the operation task.
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AsyncTimeoutError.timedOut
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw AsyncTimeoutError.timedOut
        }
        return result
    }
}
