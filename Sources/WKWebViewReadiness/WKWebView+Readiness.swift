import Foundation
import WebKit

@MainActor
public extension WKWebView {
    func waitUntilContentIsReady(
        policy: ReadinessPolicy = .balanced
    ) async throws {
        try policy.validate()

        let startedAt = ProcessInfo.processInfo.systemUptime
        var lastSignature: StabilitySignature?
        var stableSince: TimeInterval?

        while ProcessInfo.processInfo.systemUptime - startedAt < policy.timeout {
            try Task.checkCancellation()

            let snapshot = try await readinessSnapshot(policy: policy)
            let signature = StabilitySignature(
                mutationCount: snapshot.mutationCount,
                height: snapshot.height
            )

            if snapshot.satisfies(policy) {
                if policy.stabilityDuration == .zero {
                    return
                }

                if signature != lastSignature {
                    stableSince = ProcessInfo.processInfo.systemUptime
                } else if let stableSince,
                          ProcessInfo.processInfo.systemUptime - stableSince
                            >= policy.stabilityDuration {
                    return
                }
            } else {
                stableSince = nil
            }

            lastSignature = signature
            try await Task<Never, Never>.sleep(nanoseconds: 100_000_000)
        }

        throw ReadinessError.timedOut
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

private struct StabilitySignature: Equatable {
    let mutationCount: Int
    let height: Int
}

private extension ReadinessPolicy {
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

@MainActor
private extension WKWebView {
    func readinessSnapshot(
        policy: ReadinessPolicy
    ) async throws -> ReadinessSnapshot {
        let customExpression = policy.customJavaScript
            .map { "Boolean((\($0)))" }
            ?? "true"

        let script = """
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

        let json = try await evaluateJavaScriptString(script)
        guard let data = json.data(using: .utf8) else {
            throw ReadinessError.invalidJavaScriptResult
        }
        return try JSONDecoder().decode(ReadinessSnapshot.self, from: data)
    }

    func evaluateJavaScriptString(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let value = value as? String {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: ReadinessError.invalidJavaScriptResult)
                }
            }
        }
    }
}
