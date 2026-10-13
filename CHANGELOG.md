# Changelog

All notable changes to WKContentKit are documented here. The project follows [Semantic Versioning](https://semver.org/).

## [0.1.1] - 2026-10-13

### Fixed

- Readiness and capture timeouts now include JavaScript evaluation. Before, a page whose `evaluateJavaScript` never returned could keep `waitUntilContentIsReady` or `captureFullPage` waiting past the timeout. Both now throw `timedOut` on time.

### Internal

- Readiness polling is separated from `WKWebView`, so it can be unit-tested with a fake JavaScript source. Added tests for policy, stability, timeout, and error paths.

### Documentation

- README: added Why, How it works, Design notes, Errors, and Testing sections. The Korean README now matches the English one.

## [0.1.0]

- Initial release: `WKWebViewReadiness` and `WKWebViewCapture`.

[0.1.1]: https://github.com/Dabin22/WKContentKit/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Dabin22/WKContentKit/releases/tag/v0.1.0
