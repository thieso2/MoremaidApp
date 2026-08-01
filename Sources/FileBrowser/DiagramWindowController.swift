import AppKit
import WebKit

/// Standalone window showing a single mermaid diagram with zoom and pan.
/// Opened from the ⛶ button on rendered diagrams. Zoom via the in-page
/// dropdown, ⌘+/⌘−/⌘0 (routed through the app's View menu notifications),
/// pinch/⌘-scroll, and drag or scroll to pan.
@MainActor
final class DiagramWindowController: NSWindowController, NSWindowDelegate {
    /// Keeps controllers alive while their window is open.
    private static var active: [DiagramWindowController] = []
    private let diagramWebView: WKWebView

    static func present(definition: String, theme: String) {
        let controller = DiagramWindowController(definition: definition, theme: theme)
        active.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(definition: String, theme: String) {
        let webView = WKWebView(frame: .zero)
        diagramWebView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mermaid Diagram"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()

        super.init(window: window)
        window.delegate = self

        webView.loadHTMLString(
            HTMLGenerator.diagramPage(definition: definition, theme: theme),
            baseURL: nil
        )

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleZoomIn), name: .zoomIn, object: nil)
        center.addObserver(self, selector: #selector(handleZoomOut), name: .zoomOut, object: nil)
        center.addObserver(self, selector: #selector(handleZoomReset), name: .zoomReset, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func handleZoomIn() { evaluateIfKey("moremaidDiagramZoomIn();") }
    @objc private func handleZoomOut() { evaluateIfKey("moremaidDiagramZoomOut();") }
    @objc private func handleZoomReset() { evaluateIfKey("moremaidDiagramZoomReset();") }

    private func evaluateIfKey(_ js: String) {
        guard window?.isKeyWindow == true else { return }
        diagramWebView.evaluateJavaScript(js, completionHandler: nil)
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        Self.active.removeAll { $0 === self }
    }
}
