# WKContentKit

Policy-based `WKWebView` content stabilization and bounded full-page screenshot capture for iOS.

Use WKContentKit to detect when `WKWebView` content is ready, wait for DOM, fonts, and images to stabilize, or capture a memory-bounded full-page screenshot in Swift.

[한국어](README.ko.md)

## Requirements

- iOS 15+
- Swift 6
- Swift Package Manager

## Products

- `WKWebViewReadiness`: Wait until a page satisfies an explicit readiness policy.
- `WKWebViewCapture`: Trigger lazy content, capture viewport tiles, and merge them into a bounded `UIImage`.

`WKWebViewCapture` depends on `WKWebViewReadiness`.

## Features

- `WKWebView` readiness detection using document state, DOM mutations, fonts, images, and an optional custom JavaScript condition.
- Full-page and long-page `WKWebView` screenshot capture using viewport tiles and native `UIImage` output.
- Lazy-loaded content discovery, async/await APIs, capture timeout, and configurable pixel limits.
- No third-party dependencies.

## Installation

Add `https://github.com/Dabin22/WKContentKit.git` in Xcode's Package Dependencies UI, then select either product.

## Readiness

```swift
import WKWebViewReadiness

try await webView.waitUntilContentIsReady(policy: .balanced)
```

Presets are ordinary values and can be adjusted:

```swift
var policy = ReadinessPolicy.balanced
policy.timeout = 20
policy.images = .all
policy.customJavaScript = "window.appContentReady === true"

try await webView.waitUntilContentIsReady(policy: policy)
```

## Full-page capture

```swift
import WKWebViewCapture

let image = try await webView.captureFullPage()
```

For an upload-sized error report, reduce output width before capture and use UIKit's native encoder:

```swift
var options = CaptureOptions.default
options.maximumPixelWidth = 1_440

let image = try await webView.captureFullPage(options: options)
let data = image.jpegData(compressionQuality: 0.8)
```

## Memory behavior

Capture is tile-based internally, but the public result is one `UIImage`. The package checks the final pixel count before allocating the bitmap and throws `CaptureError.imageTooLarge` when it exceeds `maximumPixelCount`.

## Demo app

Open `Examples/DemoApp/DemoApp.xcodeproj`, select an iOS Simulator, and run the `DemoApp` scheme. The app uses the package from the repository root.

## Limitations

- Readiness is policy satisfaction, not proof that every network request has finished.
- Cross-origin iframe contents cannot be inspected for readiness.
- Infinite scroll is bounded by capture timeout and pixel limits.
- Fixed and sticky elements may repeat between captured viewports.
- Capture temporarily scrolls the supplied web view and restores its native state afterward. JavaScript side effects caused by scrolling cannot be undone.
- Capturing a new top-level document during an active capture fails.

## License

WKContentKit is available under the MIT License.
