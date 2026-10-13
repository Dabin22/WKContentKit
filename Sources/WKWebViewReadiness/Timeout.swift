import Foundation

/// Runs `operation` and throws `timeoutError` if it does not finish within `seconds`.
///
/// The operation and a timer race in a task group. Whichever finishes first decides the
/// result, and the other child is cancelled. Because a task group waits for all of its
/// children before returning, `operation` must respond to cancellation; JavaScript
/// evaluation does so through ``evaluateString(_:using:)``.
package func withTimeout<Value: Sendable>(
    seconds: TimeInterval,
    onTimeout timeoutError: any Error,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    guard seconds > 0, seconds.isFinite else {
        throw timeoutError
    }

    return try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw timeoutError
        }
        defer { group.cancelAll() }

        guard let value = try await group.next() else {
            throw timeoutError
        }
        return value
    }
}
