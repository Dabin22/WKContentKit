// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WKContentKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "WKWebViewReadiness",
            targets: ["WKWebViewReadiness"]
        ),
        .library(
            name: "WKWebViewCapture",
            targets: ["WKWebViewCapture"]
        )
    ],
    targets: [
        .target(name: "WKWebViewReadiness"),
        .target(
            name: "WKWebViewCapture",
            dependencies: ["WKWebViewReadiness"]
        ),
        .testTarget(
            name: "WKWebViewReadinessTests",
            dependencies: ["WKWebViewReadiness"]
        ),
        .testTarget(
            name: "WKWebViewCaptureTests",
            dependencies: ["WKWebViewCapture"]
        )
    ]
)
