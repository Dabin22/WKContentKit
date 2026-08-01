import XCTest
@testable import WKWebViewCapture

final class CaptureTests: XCTestCase {
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
}
