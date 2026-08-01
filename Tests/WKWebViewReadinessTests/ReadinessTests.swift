import XCTest
@testable import WKWebViewReadiness

final class ReadinessTests: XCTestCase {
    func testSnapshotUsesSelectedPolicyRequirements() {
        let snapshot = ReadinessSnapshot(
            readyState: "complete",
            fontsReady: false,
            pendingRequestedImages: 0,
            pendingAllImages: 1,
            mutationCount: 0,
            height: 100,
            customReady: true
        )

        var policy = ReadinessPolicy.balanced
        XCTAssertFalse(snapshot.satisfies(policy))

        policy.waitForFonts = false
        XCTAssertTrue(snapshot.satisfies(policy))

        policy.images = .all
        XCTAssertFalse(snapshot.satisfies(policy))
    }
}
