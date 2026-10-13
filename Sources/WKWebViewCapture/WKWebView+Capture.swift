import UIKit
import WebKit
import WKWebViewReadiness

@MainActor
private enum CaptureRegistry {
    static var activeWebViews = Set<ObjectIdentifier>()
}

@MainActor
public extension WKWebView {
    func captureFullPage(
        options: CaptureOptions = .default
    ) async throws -> UIImage {
        try options.validate()
        guard bounds.width > 0, bounds.height > 0 else {
            throw CaptureError.invalidOptions("web view bounds must be non-empty")
        }

        let identifier = ObjectIdentifier(self)
        guard CaptureRegistry.activeWebViews.insert(identifier).inserted else {
            throw CaptureError.alreadyInProgress
        }

        let originalState = CaptureState(webView: self)
        scrollView.isScrollEnabled = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        isUserInteractionEnabled = false

        defer {
            originalState.restore(to: self)
            CaptureRegistry.activeWebViews.remove(identifier)
        }

        let deadline = ProcessInfo.processInfo.systemUptime + options.timeout
        let documentIdentifier = try await captureDocumentIdentifier(deadline: deadline)

        if options.loadLazyContent {
            try await prepareLazyContent(
                options: options,
                deadline: deadline,
                documentIdentifier: documentIdentifier
            )
        }

        try await waitForCaptureReadiness(options: options, deadline: deadline)
        try await ensureDocument(documentIdentifier, deadline: deadline)
        try checkDeadline(deadline)

        scrollView.setContentOffset(.zero, animated: false)
        try await Task<Never, Never>.sleep(nanoseconds: 50_000_000)

        let contentHeight = max(scrollView.contentSize.height, bounds.height)
        let metrics = try outputMetrics(
            contentHeight: contentHeight,
            options: options
        )
        guard let context = makeBitmapContext(metrics: metrics) else {
            throw CaptureError.imageTooLarge
        }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(
            CGRect(
                x: 0,
                y: 0,
                width: metrics.pixelWidth,
                height: metrics.pixelHeight
            )
        )

        for offsetY in captureOffsets(
            contentHeight: contentHeight,
            viewportHeight: bounds.height
        ) {
            try Task.checkCancellation()
            try checkDeadline(deadline)
            try await ensureDocument(documentIdentifier, deadline: deadline)

            let currentHeight = max(scrollView.contentSize.height, bounds.height)
            guard abs(currentHeight - contentHeight) <= 1 else {
                throw CaptureError.contentChangedDuringCapture
            }

            scrollView.setContentOffset(
                CGPoint(x: 0, y: offsetY),
                animated: false
            )
            try await Task<Never, Never>.sleep(nanoseconds: 50_000_000)

            let image = try await captureViewportSnapshot()
            guard let cgImage = image.cgImage else {
                throw CaptureError.snapshotFailed
            }

            context.draw(
                cgImage,
                in: CGRect(
                    x: 0,
                    y: captureDestinationY(
                        pixelHeight: metrics.pixelHeight,
                        offsetY: offsetY,
                        viewportHeight: bounds.height,
                        scale: metrics.scale
                    ),
                    width: CGFloat(metrics.pixelWidth),
                    height: bounds.height * metrics.scale
                )
            )
        }

        guard let image = context.makeImage() else {
            throw CaptureError.snapshotFailed
        }
        return UIImage(cgImage: image, scale: metrics.scale, orientation: .up)
    }
}

private struct CaptureState {
    let contentOffset: CGPoint
    let isScrollEnabled: Bool
    let showsHorizontalScrollIndicator: Bool
    let showsVerticalScrollIndicator: Bool
    let isUserInteractionEnabled: Bool

    @MainActor
    init(webView: WKWebView) {
        contentOffset = webView.scrollView.contentOffset
        isScrollEnabled = webView.scrollView.isScrollEnabled
        showsHorizontalScrollIndicator = webView.scrollView.showsHorizontalScrollIndicator
        showsVerticalScrollIndicator = webView.scrollView.showsVerticalScrollIndicator
        isUserInteractionEnabled = webView.isUserInteractionEnabled
    }

    @MainActor
    func restore(to webView: WKWebView) {
        webView.scrollView.setContentOffset(contentOffset, animated: false)
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.showsHorizontalScrollIndicator = showsHorizontalScrollIndicator
        webView.scrollView.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        webView.isUserInteractionEnabled = isUserInteractionEnabled
    }
}

private struct OutputMetrics {
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: CGFloat
}

private extension CaptureOptions {
    func validate() throws {
        guard maximumPixelCount > 0 else {
            throw CaptureError.invalidOptions("maximumPixelCount must be greater than zero")
        }
        if let maximumPixelWidth, maximumPixelWidth <= 0 {
            throw CaptureError.invalidOptions("maximumPixelWidth must be greater than zero")
        }
        guard timeout > 0, timeout.isFinite else {
            throw CaptureError.invalidOptions("timeout must be greater than zero")
        }
    }
}

@MainActor
private extension WKWebView {
    func prepareLazyContent(
        options: CaptureOptions,
        deadline: TimeInterval,
        documentIdentifier: String
    ) async throws {
        var nextOffsetY: CGFloat = 0

        while true {
            try Task.checkCancellation()
            try checkDeadline(deadline)
            try await ensureDocument(documentIdentifier, deadline: deadline)

            let contentHeight = max(scrollView.contentSize.height, bounds.height)
            _ = try outputMetrics(contentHeight: contentHeight, options: options)

            let maximumOffsetY = max(0, contentHeight - bounds.height)
            let offsetY = min(nextOffsetY, maximumOffsetY)
            scrollView.setContentOffset(
                CGPoint(x: 0, y: offsetY),
                animated: false
            )
            try await Task<Never, Never>.sleep(nanoseconds: 100_000_000)

            if var policy = options.readiness {
                policy.images = .requested
                policy.timeout = min(
                    policy.timeout,
                    try remainingDuration(until: deadline)
                )
                try await waitUntilContentIsReady(policy: policy)
            }

            let updatedHeight = max(scrollView.contentSize.height, bounds.height)
            _ = try outputMetrics(contentHeight: updatedHeight, options: options)
            let updatedMaximumOffsetY = max(0, updatedHeight - bounds.height)

            if offsetY >= updatedMaximumOffsetY - 0.5 {
                return
            }
            nextOffsetY = offsetY + bounds.height
        }
    }

    func waitForCaptureReadiness(
        options: CaptureOptions,
        deadline: TimeInterval
    ) async throws {
        guard var policy = options.readiness else {
            return
        }

        policy.timeout = min(
            policy.timeout,
            try remainingDuration(until: deadline)
        )
        try await waitUntilContentIsReady(policy: policy)
    }

    func outputMetrics(
        contentHeight: CGFloat,
        options: CaptureOptions
    ) throws -> OutputMetrics {
        let nativeScale = max(traitCollection.displayScale, 1)
        let nativePixelWidth = Int(ceil(bounds.width * nativeScale))
        let pixelWidth = min(
            nativePixelWidth,
            options.maximumPixelWidth ?? nativePixelWidth
        )
        let scale = CGFloat(pixelWidth) / bounds.width
        let pixelHeight = Int(ceil(contentHeight * scale))

        guard pixelWidth > 0,
              pixelHeight > 0,
              Double(pixelWidth) * Double(pixelHeight)
                <= Double(options.maximumPixelCount) else {
            throw CaptureError.imageTooLarge
        }

        return OutputMetrics(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            scale: scale
        )
    }

    func makeBitmapContext(metrics: OutputMetrics) -> CGContext? {
        CGContext(
            data: nil,
            width: metrics.pixelWidth,
            height: metrics.pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    func captureViewportSnapshot() async throws -> UIImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = bounds
        configuration.afterScreenUpdates = true

        return try await withCheckedThrowingContinuation { continuation in
            takeSnapshot(with: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: CaptureError.snapshotFailed)
                }
            }
        }
    }

    func captureDocumentIdentifier(deadline: TimeInterval) async throws -> String {
        let script = """
        (() => {
            const key = "__wkContentKitDocumentIdentifierV1";
            if (!window[key]) {
                Object.defineProperty(window, key, {
                    value: `${performance.timeOrigin}-${Math.random()}`,
                    configurable: true
                });
            }
            return window[key];
        })()
        """

        // JavaScript evaluation counts against the capture deadline, so a page whose
        // script never returns fails with `timedOut` instead of hanging the capture.
        let remaining = try remainingDuration(until: deadline)
        let evaluator: any JavaScriptEvaluating = self
        do {
            return try await withTimeout(
                seconds: remaining,
                onTimeout: CaptureError.timedOut
            ) {
                try await evaluateString(script, using: evaluator)
            }
        } catch ReadinessError.invalidJavaScriptResult {
            throw CaptureError.snapshotFailed
        }
    }

    func ensureDocument(
        _ expectedIdentifier: String,
        deadline: TimeInterval
    ) async throws {
        guard try await captureDocumentIdentifier(deadline: deadline) == expectedIdentifier else {
            throw CaptureError.documentChangedDuringCapture
        }
    }

    func checkDeadline(
        _ deadline: TimeInterval
    ) throws {
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            throw CaptureError.timedOut
        }
    }

    func remainingDuration(
        until deadline: TimeInterval
    ) throws -> TimeInterval {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else {
            throw CaptureError.timedOut
        }
        return remaining
    }
}

func captureDestinationY(
    pixelHeight: Int,
    offsetY: CGFloat,
    viewportHeight: CGFloat,
    scale: CGFloat
) -> CGFloat {
    CGFloat(pixelHeight) - (offsetY + viewportHeight) * scale
}

func captureOffsets(
    contentHeight: CGFloat,
    viewportHeight: CGFloat
) -> [CGFloat] {
    let maximumOffsetY = max(0, contentHeight - viewportHeight)
    guard maximumOffsetY > 0 else {
        return [0]
    }

    var offsets: [CGFloat] = [0]
    var nextOffsetY = viewportHeight
    while nextOffsetY < maximumOffsetY {
        offsets.append(nextOffsetY)
        nextOffsetY += viewportHeight
    }
    if offsets.last != maximumOffsetY {
        offsets.append(maximumOffsetY)
    }
    return offsets
}
