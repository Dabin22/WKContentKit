import Foundation
import WKWebViewReadiness

public struct CaptureOptions: Sendable {
    public var readiness: ReadinessPolicy?
    public var loadLazyContent: Bool

    /// Caps output width without changing the web view's layout width.
    public var maximumPixelWidth: Int?

    /// Prevents allocating an unsafe full-page bitmap.
    public var maximumPixelCount: Int
    public var timeout: TimeInterval

    public init(
        readiness: ReadinessPolicy? = .balanced,
        loadLazyContent: Bool = true,
        maximumPixelWidth: Int? = nil,
        maximumPixelCount: Int = 20_000_000,
        timeout: TimeInterval = 30
    ) {
        self.readiness = readiness
        self.loadLazyContent = loadLazyContent
        self.maximumPixelWidth = maximumPixelWidth
        self.maximumPixelCount = maximumPixelCount
        self.timeout = timeout
    }

    public static let `default` = Self()
}

public enum CaptureError: Error, Equatable, Sendable {
    case alreadyInProgress
    case contentChangedDuringCapture
    case documentChangedDuringCapture
    case imageTooLarge
    case invalidOptions(String)
    case snapshotFailed
    case timedOut
}
