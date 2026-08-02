import Foundation
import WKWebViewReadiness

public struct CaptureOptions: Sendable {
    public var readiness: ReadinessPolicy?
    public var loadLazyContent: Bool

    /// Caps output width without changing the web view's layout width.
    /// Set to `nil` to capture at the display's native pixel width.
    public var maximumPixelWidth: Int?

    /// Prevents allocating an unsafe full-page bitmap.
    public var maximumPixelCount: Int
    public var timeout: TimeInterval

    public init(
        readiness: ReadinessPolicy? = .balanced,
        loadLazyContent: Bool = true,
        maximumPixelWidth: Int? = 750,
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

public enum CaptureError: LocalizedError, Equatable, Sendable {
    case alreadyInProgress
    case contentChangedDuringCapture
    case documentChangedDuringCapture
    case imageTooLarge
    case invalidOptions(String)
    case snapshotFailed
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            "A capture is already in progress for this web view."
        case .contentChangedDuringCapture:
            "The page size changed during capture."
        case .documentChangedDuringCapture:
            "The web view navigated to another document during capture."
        case .imageTooLarge:
            "The page exceeds the configured capture pixel limit."
        case let .invalidOptions(message):
            "Invalid capture options: \(message)."
        case .snapshotFailed:
            "WebKit could not create a snapshot of the page."
        case .timedOut:
            "The full-page capture timed out."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .imageTooLarge:
            "Reduce maximumPixelWidth, disable loadLazyContent, or increase maximumPixelCount if memory allows."
        case .contentChangedDuringCapture:
            "Retry after the page stops changing."
        case .documentChangedDuringCapture:
            "Retry after navigation finishes."
        case .timedOut:
            "Increase the timeout or capture a less dynamic page."
        default:
            nil
        }
    }
}
