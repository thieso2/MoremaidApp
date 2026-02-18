import Foundation
import WebKit

// MARK: - PDF Batch Exporter

/// Headless WKWebView-based PDF exporter used when the app is launched in
/// batch mode from the CLI (`mm --pdf ...`).
@MainActor
final class PDFBatchExporter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        // A4 width: 794px at 96 DPI (595 points); height is a starting estimate —
        // WebKit paginates automatically when creating the PDF.
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    /// Export a single markdown file to PDF.
    func export(inputPath: String, outputPath: String) async throws {
        guard let content = try? String(contentsOfFile: inputPath, encoding: .utf8) else {
            throw PDFBatchError.cannotReadFile(inputPath)
        }

        let title = (inputPath as NSString).lastPathComponent
        let html = HTMLGenerator.markdownPage(content: content, title: title, theme: "light", typography: "default")

        // Load HTML and wait for the navigation to finish.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.loadContinuation = cont
            webView.loadHTMLString(html, baseURL: nil)
        }

        // Give JavaScript (markdown-it render + Mermaid diagrams) time to finish.
        // Wait longer when the file contains Mermaid blocks.
        let hasMermaid = content.contains("```mermaid")
        let waitNs: UInt64 = hasMermaid ? 5_000_000_000 : 2_000_000_000
        try await Task.sleep(nanoseconds: waitNs)

        // Generate and save the PDF.
        let pdfData = try await webView.pdf(configuration: WKPDFConfiguration())
        try pdfData.write(to: URL(fileURLWithPath: outputPath))
    }

    // MARK: WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.loadContinuation?.resume()
            self.loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.loadContinuation?.resume(throwing: error)
            self.loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.loadContinuation?.resume(throwing: error)
            self.loadContinuation = nil
        }
    }
}

// MARK: - Errors

enum PDFBatchError: LocalizedError {
    case cannotReadFile(String)

    var errorDescription: String? {
        switch self {
        case .cannotReadFile(let path): "Cannot read file: \(path)"
        }
    }
}
