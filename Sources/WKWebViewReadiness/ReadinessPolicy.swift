import Foundation

public struct ReadinessPolicy: Sendable {
    public enum ReadyState: String, Sendable {
        case interactive
        case complete
    }

    public enum Images: Sendable {
        case none
        case requested
        case all
    }

    public var timeout: TimeInterval
    public var stabilityDuration: TimeInterval
    public var readyState: ReadyState
    public var waitForFonts: Bool
    public var images: Images

    /// A synchronous JavaScript expression that must evaluate to a truthy value.
    public var customJavaScript: String?

    public init(
        timeout: TimeInterval,
        stabilityDuration: TimeInterval,
        readyState: ReadyState,
        waitForFonts: Bool,
        images: Images,
        customJavaScript: String? = nil
    ) {
        self.timeout = timeout
        self.stabilityDuration = stabilityDuration
        self.readyState = readyState
        self.waitForFonts = waitForFonts
        self.images = images
        self.customJavaScript = customJavaScript
    }

    public static let documentLoaded = Self(
        timeout: 10,
        stabilityDuration: 0,
        readyState: .complete,
        waitForFonts: false,
        images: .none
    )

    public static let balanced = Self(
        timeout: 10,
        stabilityDuration: 0.5,
        readyState: .complete,
        waitForFonts: true,
        images: .requested
    )

    public static let strict = Self(
        timeout: 20,
        stabilityDuration: 1,
        readyState: .complete,
        waitForFonts: true,
        images: .all
    )
}

public enum ReadinessError: Error, Equatable, Sendable {
    case invalidPolicy(String)
    case invalidJavaScriptResult
    case timedOut
}
