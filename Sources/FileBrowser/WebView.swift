import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Holds a reference to the WKWebView and the raw file content for native actions.
@MainActor
class WebViewStore: ObservableObject {
    var webView: WKWebView?
    private(set) var rawContent: String?
    private var currentFile: FileEntry?
    private var currentProject: Project?

    func load(file: FileEntry, project: Project) {
        currentFile = file
        currentProject = project

        guard let content = try? String(contentsOfFile: file.absolutePath, encoding: .utf8) else {
            rawContent = nil
            return
        }
        rawContent = content

        let html: String
        if file.isMarkdown {
            let attrs = try? FileManager.default.attributesOfItem(atPath: file.absolutePath)
            let modDate = attrs?[.modificationDate] as? Date
            let fileSize = attrs?[.size] as? Int
            html = HTMLGenerator.markdownPage(
                content: content,
                title: file.name,
                forceTheme: project.themeOverride,
                modifiedDate: modDate,
                fileSize: fileSize,
                projectID: project.id,
                embedded: true
            )
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: file.absolutePath)
            let modDate = attrs?[.modificationDate] as? Date
            let fileSize = attrs?[.size] as? Int
            html = HTMLGenerator.codePage(
                content: content,
                fileName: file.name,
                forceTheme: project.themeOverride,
                modifiedDate: modDate,
                fileSize: fileSize,
                embedded: true
            )
        }

        let projectDir = URL(fileURLWithPath: project.path, isDirectory: true)
        webView?.loadHTMLString(html, baseURL: projectDir)
    }

    func copyMarkdown() {
        guard let text = rawContent else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func printDocument() {
        guard let webView else { return }
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        let op = webView.printOperation(with: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }
}

struct WebView: NSViewRepresentable {
    let store: WebViewStore

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        store.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        store.webView = webView
    }
}
