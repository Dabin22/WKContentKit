import SwiftUI
import WebKit
import WKWebViewCapture
import WKWebViewReadiness

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var model = DemoModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("https://example.com", text: $model.address)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)

                Button("Load") {
                    model.load()
                }
            }

            WebView(webView: model.webView)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                }

            HStack {
                Button("Wait until ready") {
                    Task { await model.waitUntilReady() }
                }

                Button("Capture full page") {
                    Task { await model.capture() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isWorking)

            Text(model.status)
                .font(.footnote)
                .foregroundStyle(model.isError ? .red : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let image = model.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .accessibilityLabel("Full-page capture preview")
            }
        }
        .padding()
        .onAppear { model.load() }
    }
}

@MainActor
final class DemoModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView = WKWebView()

    @Published var address = "demo://long-page"
    @Published var status = "Load a page to begin."
    @Published var image: UIImage?
    @Published var isWorking = false
    @Published var isError = false

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    func load() {
        if address == "demo://long-page" {
            image = nil
            isError = false
            status = "Loading demo page…"
            webView.loadHTMLString(Self.demoHTML, baseURL: nil)
            return
        }

        guard let url = URL(string: address),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            show(error: "Enter a valid HTTP or HTTPS URL.")
            return
        }

        image = nil
        isError = false
        status = "Loading…"
        webView.load(URLRequest(url: url))
    }

    func waitUntilReady() async {
        await perform(status: "Waiting for readiness…") {
            try await webView.waitUntilContentIsReady(policy: .balanced)
            status = "Content is ready."
        }
    }

    func capture() async {
        await perform(status: "Capturing…") {
            image = try await webView.captureFullPage()
            if let image {
                status = "Captured \(Int(image.size.width)) × \(Int(image.size.height)) points."
            }
        }
    }

    private func perform(
        status workingStatus: String,
        operation: () async throws -> Void
    ) async {
        guard !isWorking else { return }
        isWorking = true
        isError = false
        status = workingStatus
        defer { isWorking = false }

        do {
            try await operation()
        } catch {
            let suggestion = (error as? LocalizedError)?.recoverySuggestion
            show(error: [error.localizedDescription, suggestion]
                .compactMap { $0 }
                .joined(separator: " "))
        }
    }

    private func show(error message: String) {
        isError = true
        status = message
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        if status == "Loading…" || status == "Loading demo page…" {
            status = "Page loaded. Use readiness to verify dynamic content."
        }


    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        show(error: error.localizedDescription)
    }

    private static let demoHTML = #"""
    <!doctype html>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      * { box-sizing: border-box } body { margin: 0; font: 16px -apple-system; color: #172033; background: #f5f7fb }
      header { padding: 54px 24px; color: white; background: linear-gradient(135deg, #5754e8, #18a7c8) }
      h1 { margin: 0 0 10px; font-size: 36px } header p { margin: 0; opacity: .85 }
      main { padding: 20px } article { margin: 0 0 16px; padding: 24px; border-radius: 18px; background: white; box-shadow: 0 5px 18px #18213a12 }
      .number { color: #5754e8; font-size: 13px; font-weight: 700 } h2 { margin: 8px 0 } p { line-height: 1.55 }
      footer { padding: 42px 24px; text-align: center; color: white; background: #172033 }
    </style>
    <header><h1>WKContentKit</h1><p>A deterministic long page for full-page capture.</p></header>
    <main id="content"></main>
    <footer>Ready. Stable. Captured.</footer>
    <script>
      const root = document.querySelector('#content')
      for (let i = 1; i <= 8; i++) root.insertAdjacentHTML('beforeend',
        `<article><div class="number">SECTION ${String(i).padStart(2, '0')}</div><h2>Content that keeps going</h2><p>WKContentKit waits for dynamic content, captures viewport-sized tiles, and merges them into one bounded image.</p></article>`)
    </script>
    """#
}

struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
