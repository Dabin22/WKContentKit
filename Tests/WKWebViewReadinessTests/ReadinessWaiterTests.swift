import Foundation
import XCTest
@testable import WKWebViewReadiness

/// Plays back scripted JavaScript results so readiness logic can run without a web view.
@MainActor
final class FakeEvaluator: JavaScriptEvaluating {
    enum Step {
        case json(String)
        case failure(any Error)
        /// Never calls back, like a page whose JavaScript never finishes.
        case hang
    }

    private var steps: [Step]
    private(set) var callCount = 0

    /// The last step repeats once the earlier steps are used up.
    init(_ steps: [Step]) {
        precondition(!steps.isEmpty)
        self.steps = steps
    }

    func evaluate(
        _ script: String,
        completion: @escaping @Sendable (Result<String, any Error>) -> Void
    ) {
        callCount += 1
        let step = steps.count > 1 ? steps.removeFirst() : steps[0]
        switch step {
        case let .json(json):
            completion(.success(json))
        case let .failure(error):
            completion(.failure(error))
        case .hang:
            break
        }
    }
}

private struct TestError: Error, Equatable {}

private func snapshot(
    readyState: String = "complete",
    fontsReady: Bool = true,
    pendingImages: Int = 0,
    mutationCount: Int = 0,
    height: Int = 1_000,
    customReady: Bool = true
) -> FakeEvaluator.Step {
    .json("""
    {"readyState":"\(readyState)","fontsReady":\(fontsReady),\
    "pendingRequestedImages":\(pendingImages),"pendingAllImages":\(pendingImages),\
    "mutationCount":\(mutationCount),"height":\(height),"customReady":\(customReady)}
    """)
}

private func policy(
    timeout: TimeInterval = 1,
    stabilityDuration: TimeInterval = 0
) -> ReadinessPolicy {
    ReadinessPolicy(
        timeout: timeout,
        stabilityDuration: stabilityDuration,
        readyState: .complete,
        waitForFonts: true,
        images: .requested
    )
}

@MainActor
final class ReadinessWaiterTests: XCTestCase {
    func testReturnsAsSoonAsPolicyIsSatisfied() async throws {
        let evaluator = FakeEvaluator([snapshot()])
        let waiter = ReadinessWaiter(evaluator: evaluator, pollInterval: 0.01)

        try await waiter.wait(policy: policy())

        XCTAssertEqual(evaluator.callCount, 1)
    }

    func testWaitsUntilContentStopsChanging() async throws {
        let evaluator = FakeEvaluator([
            snapshot(readyState: "loading"),
            snapshot(mutationCount: 1),
            snapshot(mutationCount: 2),
            snapshot(mutationCount: 3)
        ])
        let waiter = ReadinessWaiter(evaluator: evaluator, pollInterval: 0.01)

        try await waiter.wait(policy: policy(stabilityDuration: 0.05))

        XCTAssertGreaterThan(evaluator.callCount, 4)
    }

    func testTimesOutWhenPolicyIsNeverSatisfied() async {
        let evaluator = FakeEvaluator([snapshot(pendingImages: 1)])
        let waiter = ReadinessWaiter(evaluator: evaluator, pollInterval: 0.01)

        await assertThrows(ReadinessError.timedOut) {
            try await waiter.wait(policy: policy(timeout: 0.2))
        }
    }

    /// Before the timeout covered JavaScript evaluation, this case waited forever.
    func testTimesOutWhenJavaScriptNeverReturns() async {
        let evaluator = FakeEvaluator([.hang])
        let waiter = ReadinessWaiter(evaluator: evaluator, pollInterval: 0.01)
        let startedAt = Date()

        await assertThrows(ReadinessError.timedOut) {
            try await waiter.wait(policy: policy(timeout: 0.2))
        }

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
    }

    func testPropagatesJavaScriptErrors() async {
        let evaluator = FakeEvaluator([.failure(TestError())])
        let waiter = ReadinessWaiter(evaluator: evaluator, pollInterval: 0.01)

        await assertThrows(TestError()) {
            try await waiter.wait(policy: policy())
        }
    }

    func testRejectsMalformedProbeResult() async {
        let evaluator = FakeEvaluator([.json("not json")])
        let waiter = ReadinessWaiter(evaluator: evaluator, pollInterval: 0.01)

        await assertThrows(ReadinessError.invalidJavaScriptResult) {
            try await waiter.wait(policy: policy())
        }
    }

    func testRejectsInvalidPolicyBeforeEvaluating() async {
        let evaluator = FakeEvaluator([snapshot()])
        let waiter = ReadinessWaiter(evaluator: evaluator, pollInterval: 0.01)

        await assertThrows(ReadinessError.invalidPolicy("timeout must be greater than zero")) {
            try await waiter.wait(policy: policy(timeout: 0))
        }
        XCTAssertEqual(evaluator.callCount, 0)
    }

    func testWithTimeoutReturnsFastResult() async throws {
        let value = try await withTimeout(seconds: 1, onTimeout: TestError()) {
            42
        }

        XCTAssertEqual(value, 42)
    }

    func testWithTimeoutThrowsForNonPositiveDuration() async {
        await assertThrows(TestError()) {
            _ = try await withTimeout(seconds: 0, onTimeout: TestError()) { 42 }
        }
    }
}

@MainActor
private func assertThrows<E: Error & Equatable>(
    _ expected: E,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        XCTFail("Expected \(expected) to be thrown", file: file, line: line)
    } catch let error as E {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected \(expected), got \(error)", file: file, line: line)
    }
}
