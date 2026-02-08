import SwiftUI

struct SingleFileView: View {
    let filePath: String
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var webViewStore = WebViewStore()
    @State private var copyFeedback = false
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var findCurrent = 0
    @State private var findTotal = 0
    @FocusState private var findFieldFocused: Bool
    @AppStorage("showStatusBar") private var showStatusBar = true
    @Environment(\.controlActiveState) private var controlActiveState

    private var isKeyWindow: Bool { controlActiveState == .key }

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    private var baseDirectory: String {
        (filePath as NSString).deletingLastPathComponent
    }

    var body: some View {
        webViewLayer
            .overlay(alignment: .top) { findBarOverlay }
            .safeAreaInset(edge: .bottom, spacing: 0) { singleFileStatusBar }
            .navigationTitle(abbreviatePath(filePath))
            .navigationSubtitle(windowSubtitle)
            .navigationDocument(URL(fileURLWithPath: filePath))
            .toolbar { toolbarContent }
            .toolbarRole(.editor)
            .task {
                webViewStore.onAnchorClicked = { anchor in
                    Task { _ = await webViewStore.scrollToAnchor(anchor) }
                }
                webViewStore.onNavigateToFile = { path, _ in
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
                webViewStore.onOpenInNewTab = { path, _ in
                    appState.queueNewTab(target: .file(path: path), selectedFile: path)
                    openAsTab()
                }
                webViewStore.onOpenInNewWindow = { path, _ in
                    appState.queueNewTab(target: .file(path: path), selectedFile: path)
                    openWindow(id: "main")
                }
                loadFile()
            }
    }

    private var webViewLayer: some View {
        WebView(store: webViewStore)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
                guard isKeyWindow else { return }
                webViewStore.exportPDF()
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsChanged)) { _ in
                handleSettingsChanged()
            }
            .modifier(ZoomHandlers(isKeyWindow: isKeyWindow, webViewStore: webViewStore))
            .modifier(FindHandlers(
                isKeyWindow: isKeyWindow,
                onFind: handleFindInPage,
                onFindNext: handleFindNext,
                onFindPrevious: handleFindPrevious,
                onUseSelection: handleUseSelectionForFind
            ))
            .onReceive(NotificationCenter.default.publisher(for: .reloadFile)) { _ in
                guard isKeyWindow else { return }
                webViewStore.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleStatusBar)) { _ in
                guard isKeyWindow else { return }
                withAnimation(.easeInOut(duration: 0.2)) { showStatusBar.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                guard isKeyWindow else { return }
                appState.queueNewTab(target: .file(path: filePath), selectedFile: filePath)
                openAsTab()
            }
    }

    private var windowSubtitle: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath) else { return "" }
        let size = (attrs[.size] as? Int) ?? 0
        let date = (attrs[.modificationDate] as? Date) ?? Date()
        return "\(formatSize(size)) \u{2022} \(formatTimeAgo(date))"
    }

    // MARK: - Status Bar

    @ViewBuilder
    private var singleFileStatusBar: some View {
        if showStatusBar {
            HStack {
                Text(webViewStore.hoveredLink.isEmpty ? " " : webViewStore.hoveredLink)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(.bar)
        }
    }

    // MARK: - Find Bar (Liquid Glass)

    @ViewBuilder
    private var findBarOverlay: some View {
        if showFindBar {
            findBar
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            TextField("Find in document...", text: $findQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($findFieldFocused)
                .onSubmit { performFind() }
                .onChange(of: findQuery) {
                    if findQuery.isEmpty {
                        webViewStore.findClear()
                        findCurrent = 0
                        findTotal = 0
                    } else {
                        performFind()
                    }
                }

            if findTotal > 0 {
                Text("\(findCurrent) of \(findTotal)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 60)
            } else if !findQuery.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60)
            }

            HStack(spacing: 4) {
                Button(action: {
                    Task {
                        let r = await webViewStore.findPrevious()
                        findCurrent = r.current
                        findTotal = r.total
                    }
                }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(findTotal == 0)

                Button(action: {
                    Task {
                        let r = await webViewStore.findNext()
                        findCurrent = r.current
                        findTotal = r.total
                    }
                }) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(findTotal == 0)
            }

            Button("Done") { dismissFind() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                webViewStore.copyMarkdown()
                copyFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copyFeedback = false }
            } label: {
                Label(copyFeedback ? "Copied!" : "Copy Markdown", systemImage: "doc.on.doc")
            }
            .help("Copy raw markdown to clipboard")
        }
    }

    // MARK: - New Tab

    private func openAsTab() {
        let before = Set(NSApp.windows.map(\.windowNumber))
        let sourceWindow = webViewStore.webView?.window
        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let sourceWindow else { return }
            if let newWindow = NSApp.windows.first(where: { !before.contains($0.windowNumber) && $0.canBecomeMain }) {
                sourceWindow.addTabbedWindow(newWindow, ordered: .above)
                newWindow.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Handlers

    private func loadFile() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
        let size = (attrs?[.size] as? Int) ?? 0
        let date = (attrs?[.modificationDate] as? Date) ?? Date()
        let ext = (fileName as NSString).pathExtension.lowercased()
        let isMarkdown = Constants.markdownExtensions.contains(ext)

        let entry = FileEntry(
            id: fileName,
            name: fileName,
            relativePath: fileName,
            absolutePath: filePath,
            size: size,
            modifiedDate: date,
            isMarkdown: isMarkdown
        )

        webViewStore.load(file: entry, baseDirectory: baseDirectory)
        appState.trackRecentTarget(.file(path: filePath))
    }

    private func handleSettingsChanged() {
        webViewStore.startAutoReload()
        let theme = UserDefaults.standard.string(forKey: "defaultTheme") ?? Constants.defaultTheme
        let typography = UserDefaults.standard.string(forKey: "defaultTypography") ?? Constants.defaultTypography
        let zoom = UserDefaults.standard.object(forKey: "defaultZoom") as? Int ?? Constants.zoomDefault
        webViewStore.applyTheme(theme)
        webViewStore.applyTypography(typography)
        webViewStore.applyZoom(zoom)
    }

    private func handleFindInPage() {
        withAnimation(.easeInOut(duration: 0.2)) { showFindBar = true }
        findFieldFocused = true
    }

    private func handleFindNext() {
        guard showFindBar else { return }
        Task {
            let r = await webViewStore.findNext()
            findCurrent = r.current
            findTotal = r.total
        }
    }

    private func handleFindPrevious() {
        guard showFindBar else { return }
        Task {
            let r = await webViewStore.findPrevious()
            findCurrent = r.current
            findTotal = r.total
        }
    }

    private func handleUseSelectionForFind() {
        Task {
            let selection = await webViewStore.getSelection()
            guard !selection.isEmpty else { return }
            findQuery = selection
            withAnimation(.easeInOut(duration: 0.2)) { showFindBar = true }
            findFieldFocused = true
            performFind()
        }
    }

    private func performFind() {
        Task {
            let r = await webViewStore.findInPage(findQuery)
            findCurrent = r.current
            findTotal = r.total
        }
    }

    private func dismissFind() {
        withAnimation(.easeInOut(duration: 0.2)) { showFindBar = false }
        findQuery = ""
        webViewStore.findClear()
        findCurrent = 0
        findTotal = 0
        webViewStore.becomeFirstResponder()
    }

}
