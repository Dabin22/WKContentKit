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

    func testCaptureDestinationConvertsFromTopToBottomOrigin() {
        XCTAssertEqual(
            captureDestinationY(
                pixelHeight: 300,
                offsetY: 0,
                viewportHeight: 100,
                scale: 1
            ),
            200
        )
        XCTAssertEqual(
            captureDestinationY(
                pixelHeight: 300,
                offsetY: 200,
                viewportHeight: 100,
                scale: 1
            ),
            0
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
