import XCTest
@testable import WKWebViewCapture

final class CaptureTests: XCTestCase {
    func testDefaultUsesMobileBalancedWidth() {
        XCTAssertEqual(CaptureOptions.default.maximumPixelWidth, 750)
        XCTAssertEqual(CaptureOptions.default.maximumPixelCount, 20_000_000)
    }

    func testCaptureOffsetsIncludeFinalViewport() {
        XCTAssertEqual(
            captureOffsets(contentHeight: 350, viewportHeight: 100),
            [0, 100, 200, 250]
        )
        XCTAssertEqual(
            captureOffsets(contentHeight: 80, viewportHeight: 100),
            [0]
        )
    }

    func testImageTooLargeExplainsRecovery() {
        let error = CaptureError.imageTooLarge

        XCTAssertEqual(
            error.errorDescription,
            "The page exceeds the configured capture pixel limit."
        )
        XCTAssertNotNil(error.recoverySuggestion)
    }
}
