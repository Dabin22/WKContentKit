import Foundation
import WebKit

@MainActor
public extension WKWebView {
    /// Waits until the page satisfies `policy`.
    ///
    /// The timeout covers the whole wait, including JavaScript evaluation that never
    /// returns. When the timeout passes, this throws ``ReadinessError/timedOut``.
    func waitUntilContentIsReady(
        policy: ReadinessPolicy = .balanced
    ) async throws {
        try await ReadinessWaiter(evaluator: self).wait(policy: policy)
    }
}

/// Polls a JavaScript probe until a ``ReadinessPolicy`` is satisfied.
///
/// Separated from `WKWebView` so the waiting logic can be unit-tested with a fake
/// ``JavaScriptEvaluating`` source.
@MainActor
package struct ReadinessWaiter {
    package let evaluator: any JavaScriptEvaluating
    package let pollInterval: TimeInterval

    package init(
        evaluator: any JavaScriptEvaluating,
        pollInterval: TimeInterval = 0.1
    ) {
        self.evaluator = evaluator
        self.pollInterval = pollInterval
    }

    package func wait(policy: ReadinessPolicy) async throws {
        try policy.validate()

        let script = ReadinessScript.make(customJavaScript: policy.customJavaScript)
        let startedAt = ProcessInfo.processInfo.systemUptime
        var lastSignature: StabilitySignature?
        var stableSince: TimeInterval?

        while true {
            try Task.checkCancellation()

            let remaining = policy.timeout - (ProcessInfo.processInfo.systemUptime - startedAt)
            guard remaining > 0 else {
                throw ReadinessError.timedOut
            }

            let evaluator = self.evaluator
            let json = try await withTimeout(
                seconds: remaining,
                onTimeout: ReadinessError.timedOut
            ) {
                try await evaluateString(script, using: evaluator)
            }
            let snapshot = try ReadinessSnapshot.decode(json)
            let signature = StabilitySignature(
                mutationCount: snapshot.mutationCount,
                height: snapshot.height
            )

            if snapshot.satisfies(policy) {
                if policy.stabilityDuration == .zero {
                    return
                }

                let now = ProcessInfo.processInfo.systemUptime
                if signature != lastSignature {
                    stableSince = now
                } else if let stableSince,
                          now - stableSince >= policy.stabilityDuration {
                    return
                }
            } else {
                stableSince = nil
            }

            lastSignature = signature
            try await Task<Never, Never>.sleep(
                nanoseconds: UInt64(pollInterval * 1_000_000_000)
            )
        }
    }
}

struct ReadinessSnapshot: Decodable {
    let readyState: String
    let fontsReady: Bool
    let pendingRequestedImages: Int
    let pendingAllImages: Int
    let mutationCount: Int
    let height: Int
    let customReady: Bool

    static func decode(_ json: String) throws -> ReadinessSnapshot {
        guard let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(ReadinessSnapshot.self, from: data) else {
            throw ReadinessError.invalidJavaScriptResult
        }
        return snapshot
    }

    func satisfies(_ policy: ReadinessPolicy) -> Bool {
        let documentReady: Bool
        switch policy.readyState {
        case .interactive:
            documentReady = readyState == "interactive" || readyState == "complete"
        case .complete:
            documentReady = readyState == "complete"
        }

        let imagesReady: Bool
        switch policy.images {
        case .none:
            imagesReady = true
        case .requested:
            imagesReady = pendingRequestedImages == 0
        case .all:
            imagesReady = pendingAllImages == 0
        }

        return documentReady
            && (!policy.waitForFonts || fontsReady)
            && imagesReady
            && customReady
    }
}

struct StabilitySignature: Equatable {
    let mutationCount: Int
    let height: Int
}

extension ReadinessPolicy {
    func validate() throws {
        guard timeout > 0, timeout.isFinite else {
            throw ReadinessError.invalidPolicy("timeout must be greater than zero")
        }
        guard stabilityDuration >= 0, stabilityDuration.isFinite else {
            throw ReadinessError.invalidPolicy("stabilityDuration cannot be negative")
        }
        if let customJavaScript,
           customJavaScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ReadinessError.invalidPolicy("customJavaScript cannot be empty")
        }
    }
}

enum ReadinessScript {
    static func make(customJavaScript: String?) -> String {
        let customExpression = customJavaScript
            .map { "Boolean((\($0)))" }
            ?? "true"

        return """
        (() => {
            const key = "__wkContentKitReadinessV1";
            let state = window[key];

            if (!state) {
                state = { mutationCount: 0, observer: null };
                Object.defineProperty(window, key, {
                    value: state,
                    configurable: true
                });
            }

            if (!state.observer && document.documentElement) {
                state.observer = new MutationObserver(() => {
                    state.mutationCount += 1;
                });
                state.observer.observe(document.documentElement, {
                    subtree: true,
                    childList: true,
                    attributes: true,
                    characterData: true
                });
            }

            const images = Array.from(document.images);
            const hasSource = image => Boolean(
                image.currentSrc || image.getAttribute("src")
            );
            const isVisible = image => {
                const rect = image.getBoundingClientRect();
                return rect.bottom >= 0 && rect.top <= window.innerHeight;
            };
            const pendingAllImages = images.filter(image =>
                hasSource(image) && !image.complete
            ).length;
            const pendingRequestedImages = images.filter(image =>
                hasSource(image)
                && !image.complete
                && (image.loading !== "lazy" || isVisible(image))
            ).length;
            const rootHeight = document.documentElement?.scrollHeight ?? 0;
            const bodyHeight = document.body?.scrollHeight ?? 0;

            return JSON.stringify({
                readyState: document.readyState,
                fontsReady: !document.fonts || document.fonts.status === "loaded",
                pendingRequestedImages,
                pendingAllImages,
                mutationCount: state.mutationCount,
                height: Math.max(rootHeight, bodyHeight),
                customReady: \(customExpression)
            });
        })()
        """
    }
}
