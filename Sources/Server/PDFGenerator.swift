import Foundation
import WebKit

/// Generates PDF from rendered HTML using an off-screen WKWebView in a hidden window.
@MainActor
final class PDFGenerator {

    // A4 at 72 DPI (PDF points)
    private static let a4Width: CGFloat = 595.28
    private static let a4Height: CGFloat = 841.89
    private static let marginH: CGFloat = 56.69   // 20mm
    private static let marginTop: CGFloat = 56.69  // 20mm
    private static let marginBottom: CGFloat = 70.87 // 25mm

    /// Generate PDF data from HTML content.
    static func generatePDF(from html: String) async throws -> Data {
        // Create a hidden off-screen window so WebKit actually renders
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: a4Width, height: a4Height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: a4Width, height: a4Height), configuration: config)
        window.contentView = webView
        window.orderBack(nil)

        print("[pdf] loading HTML (\(html.count) chars) into \(a4Width)x\(a4Height) webView")
        webView.loadHTMLString(html, baseURL: nil)

        // Wait for initial page load (HTML parsed, but CDN scripts may still be loading)
        try await waitForLoad(webView)
        print("[pdf] didFinish fired")

        // Wait for marked.js to render content — poll until #content has children
        try await waitForContent(webView, timeout: 10.0)

        // Inject CSS to hide UI controls and set print styling
        let printCSS = """
        var style = document.createElement('style');
        style.textContent = `
            .controls-trigger, .controls, .file-info,
            .file-buttons-container,
            #help-modal, .mermaid-fullscreen-btn, .copy-btn,
            .code-copy-btn { display: none !important; }
            .zoom-container { padding: 0 !important; }
            body { margin: 0; padding: 20px; -webkit-text-size-adjust: 100%; }
        `;
        document.head.appendChild(style);
        null;
        """
        _ = try await webView.evaluateJavaScript(printCSS)

        // Extra wait for mermaid diagrams to render
        try await Task.sleep(for: .milliseconds(500))

        let pdfConfig = WKPDFConfiguration()
        pdfConfig.rect = CGRect(
            x: marginH,
            y: marginTop,
            width: a4Width - marginH * 2,
            height: a4Height - marginTop - marginBottom
        )

        let data = try await webView.pdf(configuration: pdfConfig)
        print("[pdf] generated \(data.count) bytes")

        window.close()
        return data
    }

    /// Poll until #content has rendered children or timeout.
    private static func waitForContent(_ webView: WKWebView, timeout: TimeInterval) async throws {
        let start = CFAbsoluteTimeGetCurrent()
        while CFAbsoluteTimeGetCurrent() - start < timeout {
            let hasContent = try await webView.evaluateJavaScript(
                "(document.getElementById('content') && document.getElementById('content').innerHTML.length > 0) ? true : false;"
            ) as? Bool ?? false
            if hasContent {
                let length = try await webView.evaluateJavaScript(
                    "document.getElementById('content').innerHTML.length;"
                ) as? Int ?? 0
                print("[pdf] content rendered (\(length) chars) after \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("[pdf] WARNING: content not rendered after \(timeout)s, generating PDF anyway")
    }

    private static func waitForLoad(_ webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = LoadDelegate(continuation: continuation)
            webView.navigationDelegate = delegate
            objc_setAssociatedObject(webView, "loadDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

/// WKNavigationDelegate that bridges to async/await.
private final class LoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
