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

## 왜 만들었나

`WKWebView.takeSnapshot`은 보이는 영역만 찍고, lazy 이미지나 늦게 그려지는 DOM은 빠지기 쉽습니다. 아이트래킹 웹 분석 앱에서 "언제 페이지가 준비됐는지"와 "긴 페이지를 메모리 안에서 어떻게 한 장으로 만들지"를 반복해서 풀다가 패키지로 분리했습니다.

## 주요 기능

- document 상태, DOM mutation, font, image 및 custom JavaScript 조건을 이용한 `WKWebView` readiness 감지
- viewport tile과 네이티브 `UIImage`를 이용한 전체 페이지 및 긴 웹페이지 캡처
- lazy-loaded content 탐색, timeout 및 pixel count 기반 메모리 제한
- 외부 dependency 없음

## 설치

Xcode의 Package Dependencies에서 `https://github.com/Dabin22/WKContentKit.git`을 추가하고 **Up to Next Minor Version** 규칙으로 `0.1.0`을 선택한 다음 필요한 product를 연결합니다.

`Package.swift`에서는 다음과 같이 추가합니다.

```swift
.package(
    url: "https://github.com/Dabin22/WKContentKit.git",
    .upToNextMinor(from: "0.1.0")
)
```

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

## 동작 방식

**Readiness** (`waitUntilContentIsReady`)는 100ms마다 작은 JavaScript probe를 실행합니다. probe는 `document.readyState`, 폰트 로딩, 대기 중인 이미지, `MutationObserver` 변경 횟수, 문서 높이를 보고합니다. 정책 조건을 만족하고 변경 횟수와 높이가 `stabilityDuration` 동안 그대로이면 준비된 것으로 봅니다. 그 전에 timeout이 지나면 `ReadinessError.timedOut`을 던집니다. timeout은 각 JavaScript 호출에도 적용되므로 `evaluateJavaScript`가 응답하지 않는 페이지도 멈추지 않고 제시간에 실패합니다.

**Capture** (`captureFullPage`):

1. WebView의 스크롤·상호작용 상태를 기록하고 사용자 입력을 막습니다.
2. 페이지를 한 번 훑어 lazy content를 불러오고, 단계마다 readiness를 기다립니다.
3. 결과 크기를 계산하고 **bitmap을 할당하기 전에 pixel 한도를 검사**합니다.
4. viewport 단위로 스크롤하며 타일을 찍어 하나의 `CGContext`에 그립니다.
5. 성공·실패·취소와 관계없이 `defer`에서 원래 상태를 복원합니다.

## 설계 메모

- **Main actor 격리.** WebKit 접근은 모두 `@MainActor`입니다. 공개 옵션과 오류는 `Sendable` 값 타입입니다.
- **재진입 방지.** 캡처는 main actor에서 여러 번 suspend됩니다. 첫 `await` 전에 동기적으로 WebView를 등록하고, 동시 호출은 `CaptureError.alreadyInProgress`로 실패시킵니다.
- **`await` 이후 상태 재검증.** 타일마다 문서가 바뀌지 않았는지(`documentChangedDuringCapture`), 높이가 변하지 않았는지(`contentChangedDuringCapture`) 다시 확인합니다.
- **협력적 취소.** 루프에서 `Task.checkCancellation()`을 호출하므로 호출한 task를 취소하면 다음 단계에서 멈춥니다.
- **JavaScript까지 포함한 timeout.** `evaluateJavaScript`는 취소할 수 없고, task group은 모든 자식이 끝나야 반환합니다. 그래서 각 probe를 continuation을 정확히 한 번만 재개하는 취소 대응 브리지로 감싸고, 남은 시간 동안 타이머와 경주시킵니다.
- **보장 대신 예산.** readiness는 네트워크 완료 증명이 아니라 정책 만족입니다. 캡처는 한도 없는 이미지를 할당하지 않고 복구 방법과 함께 빨리 실패합니다.

## 오류

| 오류 | 발생 시점 | 해볼 것 |
| --- | --- | --- |
| `CaptureError.imageTooLarge` | 결과가 `maximumPixelCount` 초과 | `maximumPixelWidth`를 낮추거나 `loadLazyContent`를 끄거나 한도를 올림 |
| `CaptureError.timedOut` | 캡처가 `timeout` 초과 | timeout을 늘리거나 덜 동적인 페이지를 캡처 |
| `CaptureError.contentChangedDuringCapture` | 캡처 중 페이지 높이 변경 | 페이지 변화가 멈춘 뒤 재시도 |
| `CaptureError.documentChangedDuringCapture` | 캡처 중 navigation 발생 | navigation 완료 후 재시도 |
| `CaptureError.alreadyInProgress` | 같은 WebView에서 캡처 진행 중 | 첫 캡처가 끝날 때까지 대기 |
| `ReadinessError.timedOut` | `timeout` 전에 정책 미충족 | 느슨한 preset 사용 또는 `customJavaScript` 추가 |

## 테스트

readiness 루프는 `WKWebView`를 직접 쓰지 않고 내부 protocol(`JavaScriptEvaluating`)을 통해 페이지와 통신합니다. 단위 테스트는 이를 정해진 probe 결과를 돌려주거나, 실패하거나, 끝내 응답하지 않는 fake로 바꿔서 웹 페이지 없이 정책·안정화·timeout·오류 경로를 검증합니다.

```sh
xcodebuild test -scheme WKContentKit-Package -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## 메모리

내부 캡처는 viewport 타일 단위로 수행하지만 공개 결과는 하나의 `UIImage`입니다. 최종 bitmap을 만들기 전에 pixel count를 검사하며, `maximumPixelCount`를 넘으면 `CaptureError.imageTooLarge`를 반환합니다.

기본 캡처 폭은 750px로 제한됩니다. 2천만 pixel 메모리 한도를 유지하면서 일반적인 모바일 페이지를 전송하기 적합한 크기로 더 길게 캡처하기 위한 값입니다. 디스플레이의 네이티브 해상도가 필요하면 `maximumPixelWidth`를 `nil`로 지정합니다.

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

## 버전 정책

WKContentKit은 [Semantic Versioning](https://semver.org/)을 따릅니다. `1.0.0` 이전에는 minor release에 호환되지 않는 API 변경이 포함될 수 있으며 patch release는 하위 호환성을 유지합니다.
