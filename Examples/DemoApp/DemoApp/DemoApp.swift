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

    @Published var address = "https://example.com"
    @Published var status = "Load a page to begin."
    @Published var image: UIImage?
    @Published var isWorking = false
    @Published var isError = false

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    func load() {
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
        if status == "Loading…" {
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
}

struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
