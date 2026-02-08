import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Holds a reference to the WKWebView and the raw file content for native actions.
@Observable
@MainActor
class WebViewStore {
    var webView: WKWebView?
    var onNavigateToFile: ((String, String?) -> Void)?
    var onOpenInNewTab: ((String, String?) -> Void)?
    var onOpenInNewWindow: ((String, String?) -> Void)?
    var onAnchorClicked: ((String) -> Void)?
    var pendingScrollY: Double = 0
    var pendingAnchor: String?
    var hoveredLink: String = ""
    var onPageLoaded: (() -> Void)?
    private(set) var rawContent: String?
    private(set) var currentFile: FileEntry?
    private(set) var currentBaseDirectory: String?
    private var pollTimer: Timer?
    private var lastContentHash: Int?

    private var theme: String { UserDefaults.standard.string(forKey: "defaultTheme") ?? Constants.defaultTheme }
    private var typography: String { UserDefaults.standard.string(forKey: "defaultTypography") ?? Constants.defaultTypography }
    private var zoom: Int { UserDefaults.standard.object(forKey: "defaultZoom") as? Int ?? Constants.zoomDefault }

    func load(file: FileEntry, baseDirectory: String) {
        print("[moremaid] load file=\(file.absolutePath) baseDir=\(baseDirectory)")
        currentFile = file
        currentBaseDirectory = baseDirectory
        lastContentHash = nil
        loadContent()
        startAutoReload()
    }

    func reload() {
        reloadInPlace()
    }

    /// Load raw markdown content (not from a file on disk). Used for auto-index pages.
    func loadMarkdown(content: String, title: String, contentDirectory: String, baseDirectory: String) {
        currentFile = nil
        currentBaseDirectory = baseDirectory
        rawContent = content
        lastContentHash = nil
        stopWatching()

        print("[moremaid] loadMarkdown title=\(title) contentDir=\(contentDirectory) baseDir=\(baseDirectory)")

        let html = HTMLGenerator.markdownPage(
            content: content,
            title: title,
            modifiedDate: nil,
            fileSize: nil,
            theme: theme,
            typography: typography
        )

        let baseURL = URL(fileURLWithPath: contentDirectory, isDirectory: true)
        webView?.loadHTMLString(html, baseURL: baseURL)
        applyZoom(zoom)
    }

    private func loadContent() {
        guard let file = currentFile, let baseDirectory = currentBaseDirectory else { return }

        guard let data = FileManager.default.contents(atPath: file.absolutePath),
              let content = String(data: data, encoding: .utf8) else {
            rawContent = nil
            return
        }

        lastContentHash = content.hashValue
        rawContent = content

        let attrs = try? FileManager.default.attributesOfItem(atPath: file.absolutePath)
        let modDate = attrs?[.modificationDate] as? Date
        let fileSize = attrs?[.size] as? Int

        let html: String
        if file.isMarkdown {
            html = HTMLGenerator.markdownPage(
                content: content,
                title: file.name,
                modifiedDate: modDate,
                fileSize: fileSize,
                theme: theme,
                typography: typography
            )
        } else {
            html = HTMLGenerator.codePage(
                content: content,
                fileName: file.name,
                modifiedDate: modDate,
                fileSize: fileSize,
                theme: theme,
                typography: typography
            )
        }

        let fileDir = (file.absolutePath as NSString).deletingLastPathComponent
        let baseURL = URL(fileURLWithPath: fileDir, isDirectory: true)
        webView?.loadHTMLString(html, baseURL: baseURL)
        applyZoom(zoom)
    }

    /// Re-render content in-place via JavaScript — no flicker, preserves scroll.
    private func reloadInPlace() {
        guard let file = currentFile else { return }

        guard let data = FileManager.default.contents(atPath: file.absolutePath),
              let content = String(data: data, encoding: .utf8) else { return }

        let hash = content.hashValue
        if let lastHash = lastContentHash, lastHash == hash { return }
        lastContentHash = hash
        rawContent = content

        let escaped = content.jsonStringLiteral
        if file.isMarkdown {
            webView?.evaluateJavaScript("reRenderMarkdown(\(escaped));", completionHandler: nil)
        } else {
            let ext = (file.name as NSString).pathExtension.lowercased()
            let language = LanguageMaps.extensionToLanguage[ext] ?? "plaintext"
            webView?.evaluateJavaScript("reRenderCode(\(escaped), '\(language)');", completionHandler: nil)
        }
    }

    // MARK: - File Monitoring

    private var autoReload: Bool {
        UserDefaults.standard.object(forKey: "autoReload") as? Bool ?? true
    }

    func startAutoReload() {
        stopWatching()
        guard autoReload else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkFileChanged()
            }
        }
    }

    func stopWatching() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkFileChanged() {
        guard autoReload else {
            stopWatching()
            return
        }
        guard currentFile != nil else { return }
        reloadInPlace()
    }

    nonisolated deinit {
        // Timer cleanup handled by stopWatching() when view disappears
    }

    func applyTheme(_ theme: String) {
        webView?.evaluateJavaScript("switchTheme('\(theme)');", completionHandler: nil)
    }

    func applyTypography(_ typography: String) {
        webView?.evaluateJavaScript("document.body.setAttribute('data-typography', '\(typography)');", completionHandler: nil)
    }

    func applyZoom(_ zoom: Int) {
        webView?.pageZoom = CGFloat(zoom) / 100.0
    }

    func becomeFirstResponder() {
        guard let webView else { return }
        webView.window?.makeFirstResponder(webView)
    }

    // MARK: - Scroll Position

    func getScrollPosition() async -> Double {
        guard let webView else { return 0 }
        do {
            let result = try await webView.evaluateJavaScript("window.scrollY")
            return (result as? Double) ?? 0
        } catch {
            return 0
        }
    }

    func restorePendingScroll() {
        if let anchor = pendingAnchor {
            pendingAnchor = nil
            pendingScrollY = 0
            // Brief delay to let content render before scrolling to anchor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                Task { @MainActor in
                    _ = await self?.scrollToAnchor(anchor)
                }
            }
            return
        }
        guard pendingScrollY > 0 else { return }
        let y = pendingScrollY
        pendingScrollY = 0
        // Brief delay to let content render before scrolling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.webView?.evaluateJavaScript("window.scrollTo(0, \(y));", completionHandler: nil)
        }
    }

    func scrollTo(_ y: Double) {
        webView?.evaluateJavaScript("window.scrollTo(0, \(y));", completionHandler: nil)
    }

    func scrollToAnchor(_ anchor: String) async -> Double {
        guard let webView else { return 0 }
        let escaped = anchor.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            var id = '\(escaped)';
            console.log('[anchor] looking for: ' + id);
            var el = document.getElementById(id);
            console.log('[anchor] getElementById: ' + (el ? el.tagName + '#' + el.id : 'null'));
            if (!el) {
                var anchors = document.querySelectorAll('a[name="' + id + '"]');
                console.log('[anchor] a[name] matches: ' + anchors.length);
                el = anchors.length > 0 ? anchors[0] : null;
            }
            if (!el) {
                var allIds = Array.from(document.querySelectorAll('[id]')).map(function(e) { return e.id; });
                console.log('[anchor] all IDs on page: ' + JSON.stringify(allIds.slice(0, 30)));
            }
            if (el) {
                console.log('[anchor] scrolling to: ' + el.tagName + '#' + el.id);
                el.scrollIntoView({behavior: 'instant'});
            } else {
                console.log('[anchor] NOT FOUND');
            }
            return window.scrollY;
        })();
        """
        do {
            let result = try await webView.evaluateJavaScript(js)
            let scrollY = (result as? Double) ?? 0
            print("[moremaid] scrollToAnchor(\(anchor)) → scrollY=\(scrollY)")
            return scrollY
        } catch {
            print("[moremaid] scrollToAnchor(\(anchor)) JS error: \(error)")
            return 0
        }
    }

    // MARK: - Headings (for TOC)

    struct HeadingEntry: Codable, Identifiable {
        let level: Int
        let text: String
        let id: String
    }

    func getHeadings() async -> [HeadingEntry] {
        guard let webView else { return [] }
        do {
            let result = try await webView.evaluateJavaScript("getHeadingList();")
            guard let json = result as? String,
                  let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([HeadingEntry].self, from: data)) ?? []
        } catch {
            return []
        }
    }

    func getCurrentHeadingID() async -> String {
        guard let webView else { return "" }
        do {
            let result = try await webView.evaluateJavaScript("getCurrentHeadingId();")
            return result as? String ?? ""
        } catch {
            return ""
        }
    }

    // MARK: - Find (async/await)

    func findInPage(_ query: String) async -> (current: Int, total: Int) {
        let escaped = query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return await evalFindResult("window.findInPage('\(escaped)');")
    }

    func findNext() async -> (current: Int, total: Int) {
        await evalFindResult("window.findNext();")
    }

    func findPrevious() async -> (current: Int, total: Int) {
        await evalFindResult("window.findPrevious();")
    }

    func findJumpToIndex(_ index: Int) async -> (current: Int, total: Int) {
        await evalFindResult("window.findJumpToIndex(\(index));")
    }

    private func evalFindResult(_ js: String) async -> (current: Int, total: Int) {
        guard let webView else { return (0, 0) }
        do {
            let result = try await webView.evaluateJavaScript(js)
            if let json = result as? String, let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                return (dict["current"] ?? 0, dict["total"] ?? 0)
            }
        } catch {}
        return (0, 0)
    }

    func findClear() {
        webView?.evaluateJavaScript("window.findClear();", completionHandler: nil)
    }

    func getSelection() async -> String {
        guard let webView else { return "" }
        do {
            let result = try await webView.evaluateJavaScript("window.getSelection2();")
            return result as? String ?? ""
        } catch {
            return ""
        }
    }

    func copyMarkdown() {
        guard let text = rawContent else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportPDF() {
        guard let webView else { return }
        Task {
            do {
                let pdfData = try await webView.pdf(configuration: WKPDFConfiguration())

                let baseName = currentFile?.name
                    .replacingOccurrences(of: ".md", with: "")
                    .replacingOccurrences(of: ".markdown", with: "") ?? "document"

                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.nameFieldStringValue = "\(baseName).pdf"
                panel.canCreateDirectories = true

                let response = panel.runModal()
                if response == .OK, let url = panel.url {
                    try pdfData.write(to: url)
                    NSWorkspace.shared.open(url)
                }
            } catch {
                print("[pdf] export failed: \(error)")
            }
        }
    }
}

// MARK: - Custom WKWebView with Link Context Menu

class MoremaidWebView: WKWebView {
    /// Updated by the coordinator on linkHover messages (main thread only).
    nonisolated(unsafe) var currentHoveredLink = ""
    nonisolated(unsafe) var onContextOpenInNewTab: ((String, String?) -> Void)?
    nonisolated(unsafe) var onContextOpenInNewWindow: ((String, String?) -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        let href = currentHoveredLink
        if !href.isEmpty, let url = URL(string: href), url.isFileURL {
            let path = url.path
            let fragment = url.fragment
            menu.removeAllItems()

            let newTabItem = NSMenuItem(title: "Open Link in New Tab", action: #selector(ctxOpenInNewTab(_:)), keyEquivalent: "")
            newTabItem.target = self
            newTabItem.representedObject = LinkContext(path: path, fragment: fragment)
            menu.addItem(newTabItem)

            let newWindowItem = NSMenuItem(title: "Open Link in New Window", action: #selector(ctxOpenInNewWindow(_:)), keyEquivalent: "")
            newWindowItem.target = self
            newWindowItem.representedObject = LinkContext(path: path, fragment: fragment)
            menu.addItem(newWindowItem)

            let splitItem = NSMenuItem(title: "Open Link in Split View", action: nil, keyEquivalent: "")
            menu.addItem(splitItem)
        }
        super.willOpenMenu(menu, with: event)
    }

    @objc private func ctxOpenInNewTab(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? LinkContext else { return }
        onContextOpenInNewTab?(ctx.path, ctx.fragment)
    }

    @objc private func ctxOpenInNewWindow(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? LinkContext else { return }
        onContextOpenInNewWindow?(ctx.path, ctx.fragment)
    }
}

private class LinkContext: NSObject {
    let path: String
    let fragment: String?
    init(path: String, fragment: String?) {
        self.path = path
        self.fragment = fragment
    }
}

struct WebView: NSViewRepresentable {
    let store: WebViewStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Bridge console.log → stdout and link hover → status bar
        let handler = context.coordinator
        config.userContentController.add(handler, name: "nativeLog")
        config.userContentController.add(handler, name: "linkHover")
        let consoleScript = WKUserScript(source: """
            (function() {
                var orig = console.log;
                console.log = function() {
                    var msg = Array.prototype.slice.call(arguments).map(function(a) {
                        return typeof a === 'object' ? JSON.stringify(a) : String(a);
                    }).join(' ');
                    window.webkit.messageHandlers.nativeLog.postMessage(msg);
                    orig.apply(console, arguments);
                };
                var origErr = console.error;
                console.error = function() {
                    var msg = Array.prototype.slice.call(arguments).map(function(a) {
                        return typeof a === 'object' ? JSON.stringify(a) : String(a);
                    }).join(' ');
                    window.webkit.messageHandlers.nativeLog.postMessage('[error] ' + msg);
                    origErr.apply(console, arguments);
                };
                var origWarn = console.warn;
                console.warn = function() {
                    var msg = Array.prototype.slice.call(arguments).map(function(a) {
                        return typeof a === 'object' ? JSON.stringify(a) : String(a);
                    }).join(' ');
                    window.webkit.messageHandlers.nativeLog.postMessage('[warn] ' + msg);
                    origWarn.apply(console, arguments);
                };
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(consoleScript)

        let linkHoverScript = WKUserScript(source: """
            (function() {
                document.addEventListener('mouseover', function(e) {
                    var a = e.target.closest('a');
                    if (a && a.href) {
                        window.webkit.messageHandlers.linkHover.postMessage(a.href);
                    }
                });
                document.addEventListener('mouseout', function(e) {
                    var a = e.target.closest('a');
                    if (a) {
                        window.webkit.messageHandlers.linkHover.postMessage('');
                    }
                });
            })();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(linkHoverScript)

        let webView = MoremaidWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.onContextOpenInNewTab = { [weak store] path, fragment in
            store?.onOpenInNewTab?(path, fragment)
        }
        webView.onContextOpenInNewWindow = { [weak store] path, fragment in
            store?.onOpenInNewWindow?(path, fragment)
        }
        store.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        store.webView = webView
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let store: WebViewStore

        init(store: WebViewStore) {
            self.store = store
        }

        nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "linkHover", let href = message.body as? String {
                (message.webView as? MoremaidWebView)?.currentHoveredLink = href
                Task { @MainActor in
                    self.store.hoveredLink = href
                }
                return
            }
            if let body = message.body as? String {
                print("[js] \(body)")
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.store.restorePendingScroll()
                if let callback = self.store.onPageLoaded {
                    self.store.onPageLoaded = nil
                    callback()
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url,
                  navigationAction.navigationType == .linkActivated else {
                return .allow
            }

            let isCmdClick = navigationAction.modifierFlags.contains(.command)
            print("[moremaid] link clicked: \(url.absoluteString)\(isCmdClick ? " (⌘-click)" : "")")

            // External links → open in browser
            if let scheme = url.scheme, ["http", "https"].contains(scheme) {
                print("[moremaid]   → opening in browser")
                NSWorkspace.shared.open(url)
                return .cancel
            }

            // Local file links → navigate within the app
            if url.isFileURL {
                let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path

                // In-page anchor links (#section) → scroll and push history (not for cmd-click)
                if !isCmdClick, let fragment = url.fragment {
                    let baseDir = (store.currentBaseDirectory ?? "")
                    let currentFile = store.currentFile?.absolutePath
                    if path == baseDir || path == currentFile {
                        print("[moremaid]   → in-page anchor: #\(fragment)")
                        store.onAnchorClicked?(fragment)
                        return .cancel
                    }
                }

                guard let baseDir = store.currentBaseDirectory else {
                    print("[moremaid]   → ERROR: no currentBaseDirectory set, cannot navigate to \(path)")
                    return .cancel
                }
                let basePath = baseDir.hasSuffix("/") ? baseDir : baseDir + "/"
                if path.hasPrefix(basePath) || path == baseDir {
                    if FileManager.default.fileExists(atPath: path) {
                        let fragment = url.fragment
                        if isCmdClick {
                            print("[moremaid]   → opening in new tab: \(path)\(fragment.map { "#\($0)" } ?? "")")
                            store.onOpenInNewTab?(path, fragment)
                        } else {
                            print("[moremaid]   → navigating to \(path)\(fragment.map { "#\($0)" } ?? "")")
                            store.onNavigateToFile?(path, fragment)
                        }
                        return .cancel
                    } else {
                        print("[moremaid]   → ERROR: file not found at \(path)")
                        return .cancel
                    }
                } else {
                    print("[moremaid]   → ERROR: path outside base directory: \(path) (base: \(basePath))")
                    return .cancel
                }
            }

            print("[moremaid]   → unhandled URL scheme, allowing")
            return .allow
        }
    }
}
