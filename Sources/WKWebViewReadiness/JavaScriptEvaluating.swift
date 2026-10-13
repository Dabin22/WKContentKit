import Foundation
import WebKit

/// A source that can evaluate a JavaScript expression and report a string result.
///
/// `WKWebView` is the production implementation. Tests provide fakes so readiness
/// logic can be verified without loading a real page.
package protocol JavaScriptEvaluating: AnyObject, Sendable {
    @MainActor
    func evaluate(
        _ script: String,
        completion: @escaping @Sendable (Result<String, any Error>) -> Void
    )
}

extension WKWebView: JavaScriptEvaluating {
    package func evaluate(
        _ script: String,
        completion: @escaping @Sendable (Result<String, any Error>) -> Void
    ) {
        evaluateJavaScript(script) { value, error in
            if let error {
                completion(.failure(error))
            } else if let value = value as? String {
                completion(.success(value))
            } else {
                completion(.failure(ReadinessError.invalidJavaScriptResult))
            }
        }
    }
}

/// Evaluates `script` and returns its string result.
///
/// WebKit's completion handler cannot be cancelled. If this function only waited for
/// that callback, a page whose JavaScript never finishes would keep the caller (and any
/// task group racing it against a timeout) suspended forever. The bridge therefore
/// resumes with `CancellationError` as soon as the calling task is cancelled and ignores
/// whichever result arrives second.
@MainActor
package func evaluateString(
    _ script: String,
    using evaluator: any JavaScriptEvaluating
) async throws -> String {
    let gate = ContinuationGate<String>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            evaluator.evaluate(script) { result in
                gate.resume(with: result)
            }
        }
    } onCancel: {
        gate.resume(with: .failure(CancellationError()))
    }
}

/// Resumes a continuation exactly once, whichever of the callback or cancellation
/// arrives first. A result that arrives before the continuation is installed is kept
/// and delivered on install.
final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var pending: Result<Value, any Error>?
    private var isFinished = false

    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        lock.lock()
        if let pending {
            self.pending = nil
            isFinished = true
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        guard !isFinished else {
            lock.unlock()
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with result: Result<Value, any Error>) {
        lock.lock()
        guard !isFinished, pending == nil else {
            lock.unlock()
            return
        }
        guard let continuation else {
            pending = result
            lock.unlock()
            return
        }
        self.continuation = nil
        isFinished = true
        lock.unlock()
        continuation.resume(with: result)
    }
}
