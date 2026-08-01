# WKContentKit

iOS `WKWebView`의 콘텐츠를 정책에 따라 안정화하고, 메모리 한도 안에서 전체 페이지 스크린샷을 만드는 Swift 패키지입니다.

WKContentKit은 `WKWebView` 로딩 완료 감지, DOM·폰트·이미지 안정화 대기, 전체 페이지 및 긴 웹페이지 스크린샷 캡처를 Swift async/await API로 제공합니다.

[English](README.md)

## 요구 사항

- iOS 15 이상
- Swift 6
- Swift Package Manager

## 제품

- `WKWebViewReadiness`: 명시적인 준비 정책을 만족할 때까지 기다립니다.
- `WKWebViewCapture`: lazy content를 유도하고 viewport별로 캡처한 뒤 제한된 크기의 `UIImage`로 병합합니다.

`WKWebViewCapture`는 `WKWebViewReadiness`에 의존합니다.

## 주요 기능

- document 상태, DOM mutation, font, image 및 custom JavaScript 조건을 이용한 `WKWebView` readiness 감지
- viewport tile과 네이티브 `UIImage`를 이용한 전체 페이지 및 긴 웹페이지 캡처
- lazy-loaded content 탐색, timeout 및 pixel count 기반 메모리 제한
- 외부 dependency 없음

## 준비 상태 기다리기

```swift
import WKWebViewReadiness

try await webView.waitUntilContentIsReady(policy: .balanced)
```

preset은 일반 값이므로 필요한 항목만 변경할 수 있습니다.

```swift
var policy = ReadinessPolicy.balanced
policy.timeout = 20
policy.images = .all
policy.customJavaScript = "window.appContentReady === true"

try await webView.waitUntilContentIsReady(policy: policy)
```

## 전체 페이지 캡처

```swift
import WKWebViewCapture

let image = try await webView.captureFullPage()
```

오류 보고용 이미지처럼 바로 전송할 경우 캡처 해상도를 먼저 제한하고 UIKit 인코더를 사용합니다.

```swift
var options = CaptureOptions.default
options.maximumPixelWidth = 1_440

let image = try await webView.captureFullPage(options: options)
let data = image.jpegData(compressionQuality: 0.8)
```

## 메모리

내부 캡처는 viewport 타일 단위로 수행하지만 공개 결과는 하나의 `UIImage`입니다. 최종 bitmap을 만들기 전에 pixel count를 검사하며, `maximumPixelCount`를 넘으면 `CaptureError.imageTooLarge`를 반환합니다.

## 데모 앱

`Examples/DemoApp/DemoApp.xcodeproj`를 열고 iOS Simulator를 선택한 다음 `DemoApp` scheme을 실행합니다. 저장소 루트의 패키지가 로컬로 연결되어 있습니다.

## 제한 사항

- readiness는 선택한 정책의 만족을 의미하며 모든 네트워크 요청 완료를 보장하지 않습니다.
- cross-origin iframe 내부의 준비 상태는 검사할 수 없습니다.
- 무한 스크롤은 timeout과 pixel 제한으로 중단됩니다.
- fixed/sticky 요소가 viewport마다 반복될 수 있습니다.
- 캡처 중 전달된 WebView를 일시적으로 스크롤하고 네이티브 상태를 복원합니다. 스크롤로 발생한 JavaScript 부작용은 되돌릴 수 없습니다.
- 캡처 도중 top-level document가 변경되면 실패합니다.

## 라이선스

WKContentKit은 MIT License로 제공됩니다.
