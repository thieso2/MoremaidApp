import SwiftUI

struct DirectoryWindowView: View {
    let directoryPath: String
    let sessionID: UUID
    let initialFilePath: String?
    @Environment(AppState.self) private var appState
    @State private var selectedFile: FileEntry?
    @State private var webViewStore = WebViewStore()
    @State private var copyFeedback = false
    @State private var showQuickOpen = false
    @State private var projectFiles: [FileEntry] = []
    @State private var isScanning = false
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var findCurrent = 0
    @State private var findTotal = 0
    @FocusState private var findFieldFocused: Bool
    @Environment(\.controlActiveState) private var controlActiveState

    // MARK: - History

    private struct HistoryEntry {
        let file: FileEntry
        var scrollY: Double = 0
    }

    @State private var fileHistory: [HistoryEntry] = []
    @State private var historyIndex = -1
    @State private var isNavigatingHistory = false

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < fileHistory.count - 1 }

    private var isKeyWindow: Bool { controlActiveState == .key }

    private var directoryName: String {
        (directoryPath as NSString).lastPathComponent
    }

    var body: some View {
        contentView
            .navigationTitle(windowTitle)
            .navigationSubtitle(windowSubtitle)
            .navigationDocument(fileURL)
            .toolbar { toolbarContent }
            .task {
                webViewStore.onNavigateToFile = { path in
                    navigateToFileAtPath(path)
                }
                webViewStore.onAnchorClicked = { anchor in
                    handleAnchorClick(anchor)
                }
                scanFiles()
            }
    }

    private var fileURL: URL {
        if let file = selectedFile {
            return URL(fileURLWithPath: file.absolutePath)
        }
        return URL(fileURLWithPath: directoryPath)
    }

    private var windowTitle: String {
        selectedFile?.relativePath ?? directoryName
    }

    private var windowSubtitle: String {
        let dirLabel = abbreviatePath(directoryPath)
        guard let file = selectedFile else { return dirLabel }
        let size = formatSize(file.size)
        let age = formatTimeAgo(file.modifiedDate)
        return "\(dirLabel) \u{2022} \(size) \u{2022} \(age)"
    }

    private var contentView: some View {
        webViewLayer
            .overlay { placeholderOverlay }
            .overlay { quickOpenOverlay }
            .overlay(alignment: .top) { findBarOverlay }
            .onChange(of: selectedFile) { handleFileChange() }
    }

    private var webViewLayer: some View {
        WebView(store: webViewStore)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(for: .toggleQuickOpen)) { _ in
                guard isKeyWindow else { return }
                showQuickOpen.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
                guard isKeyWindow, selectedFile != nil else { return }
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
                guard isKeyWindow, selectedFile != nil else { return }
                webViewStore.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goBack)) { _ in
                guard isKeyWindow else { return }
                goBack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goForward)) { _ in
                guard isKeyWindow else { return }
                goForward()
            }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var placeholderOverlay: some View {
        if selectedFile == nil {
            Text("Press \u{2318}K to open a file")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
    }

    @ViewBuilder
    private var quickOpenOverlay: some View {
        if showQuickOpen {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { showQuickOpen = false }

            VStack {
                QuickOpenView(
                    files: projectFiles,
                    isScanning: isScanning,
                    onSelect: { file in
                        selectedFile = file
                        showQuickOpen = false
                    },
                    onDismiss: { showQuickOpen = false }
                )
                .padding(.top, 60)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var findBarOverlay: some View {
        if showFindBar {
            findBar
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Find Bar (Liquid Glass)

    private var findBar: some View {
        HStack(spacing: 8) {
            findTextField
            findStatusText
            findNavigationButtons
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

    private var findTextField: some View {
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
    }

    @ViewBuilder
    private var findStatusText: some View {
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
    }

    private var findNavigationButtons: some View {
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
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: goBack) {
                Label("Back", systemImage: "chevron.backward")
            }
            .disabled(!canGoBack)

            Button(action: goForward) {
                Label("Forward", systemImage: "chevron.forward")
            }
            .disabled(!canGoForward)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if selectedFile != nil {
                Button {
                    webViewStore.copyMarkdown()
                    copyFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copyFeedback = false }
                } label: {
                    Label(copyFeedback ? "Copied!" : "Copy Markdown", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)
                .help("Copy raw markdown to clipboard (\u{2318}C)")
            }
        }
    }

    // MARK: - History Navigation

    private func pushToHistory(_ file: FileEntry) {
        // Trim forward history
        if historyIndex < fileHistory.count - 1 {
            fileHistory = Array(fileHistory[0...historyIndex])
        }
        fileHistory.append(HistoryEntry(file: file))
        historyIndex = fileHistory.count - 1
    }

    private func goBack() {
        guard canGoBack else { return }
        Task {
            fileHistory[historyIndex].scrollY = await webViewStore.getScrollPosition()
            historyIndex -= 1
            let target = fileHistory[historyIndex]
            if target.file == selectedFile {
                // Same file — just scroll, no reload
                webViewStore.scrollTo(target.scrollY)
            } else {
                isNavigatingHistory = true
                webViewStore.pendingScrollY = target.scrollY
                selectedFile = target.file
            }
        }
    }

    private func goForward() {
        guard canGoForward else { return }
        Task {
            fileHistory[historyIndex].scrollY = await webViewStore.getScrollPosition()
            historyIndex += 1
            let target = fileHistory[historyIndex]
            if target.file == selectedFile {
                webViewStore.scrollTo(target.scrollY)
            } else {
                isNavigatingHistory = true
                webViewStore.pendingScrollY = target.scrollY
                selectedFile = target.file
            }
        }
    }

    /// Navigate to a file or directory by absolute path (from relative link clicks).
    private func navigateToFileAtPath(_ path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            print("[moremaid] navigateToFileAtPath: path does not exist: \(path)")
            return
        }

        if isDir.boolValue {
            print("[moremaid] navigateToFileAtPath: directory → auto-index: \(path)")
            selectedFile = makeAutoIndexEntry(for: path)
            return
        }

        print("[moremaid] navigateToFileAtPath: file: \(path)")
        if let existing = projectFiles.first(where: { $0.absolutePath == path }) {
            selectedFile = existing
            return
        }
        selectedFile = makeFileEntry(absolutePath: path)
    }

    // MARK: - Handlers

    private func handleFileChange() {
        guard let file = selectedFile else { return }
        let savedPath = isAutoIndex(file) ? nil : file.absolutePath

        if isNavigatingHistory {
            isNavigatingHistory = false
            loadFileOrAutoIndex(file)
            appState.registerSession(id: sessionID, target: .directory(path: directoryPath), selectedFile: savedPath)
        } else {
            Task {
                if historyIndex >= 0 {
                    fileHistory[historyIndex].scrollY = await webViewStore.getScrollPosition()
                }
                pushToHistory(file)
                webViewStore.pendingScrollY = 0
                loadFileOrAutoIndex(file)
                appState.registerSession(id: sessionID, target: .directory(path: directoryPath), selectedFile: savedPath)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            webViewStore.becomeFirstResponder()
        }
    }

    private func handleAnchorClick(_ anchor: String) {
        Task {
            // Save current scroll position
            if historyIndex >= 0 {
                fileHistory[historyIndex].scrollY = await webViewStore.getScrollPosition()
            }
            // Scroll to the anchor and get new position
            let newScrollY = await webViewStore.scrollToAnchor(anchor)
            // Push history entry at the new scroll position
            if let file = selectedFile {
                if historyIndex < fileHistory.count - 1 {
                    fileHistory = Array(fileHistory[0...historyIndex])
                }
                fileHistory.append(HistoryEntry(file: file, scrollY: newScrollY))
                historyIndex = fileHistory.count - 1
            }
        }
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

    // MARK: - File Loading

    private func scanFiles() {
        isScanning = true

        // Load saved/default file immediately — no waiting for full scan
        tryLoadInitialFile()

        // Full background scan for Quick Open
        FileScanner.scanBatched(directory: directoryPath, filter: .allFiles, batchSize: 50) { batch, done in
            DispatchQueue.main.async {
                projectFiles.append(contentsOf: batch)
                if done {
                    isScanning = false
                    if selectedFile == nil {
                        appState.registerSession(id: sessionID, target: .directory(path: directoryPath), selectedFile: nil)
                    }
                }
            }
        }
    }

    /// Try to load the saved file or a default file immediately (before scan completes).
    private func tryLoadInitialFile() {
        // 1. Try the saved file from last session
        if let path = initialFilePath, FileManager.default.fileExists(atPath: path) {
            selectedFile = makeFileEntry(absolutePath: path)
            appState.registerSession(id: sessionID, target: .directory(path: directoryPath), selectedFile: path)
            return
        }

        // 2. Try default files in top-level directory
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) {
            for name in Self.defaultFileNames {
                if let match = contents.first(where: { $0.lowercased() == name }) {
                    let fullPath = (directoryPath as NSString).appendingPathComponent(match)
                    guard FileManager.default.fileExists(atPath: fullPath) else { continue }
                    selectedFile = makeFileEntry(absolutePath: fullPath)
                    appState.registerSession(id: sessionID, target: .directory(path: directoryPath), selectedFile: fullPath)
                    return
                }
            }
        }

        // 3. Auto-index — show directory contents
        selectedFile = makeAutoIndexEntry(for: directoryPath)
    }

    private func makeFileEntry(absolutePath path: String) -> FileEntry {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? Int) ?? 0
        let date = (attrs?[.modificationDate] as? Date) ?? Date()
        let basePath = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        let relativePath = path.hasPrefix(basePath) ? String(path.dropFirst(basePath.count)) : name
        return FileEntry(
            id: relativePath,
            name: name,
            relativePath: relativePath,
            absolutePath: path,
            size: size,
            modifiedDate: date,
            isMarkdown: Constants.markdownExtensions.contains(ext)
        )
    }

    private static let defaultFileNames = [
        "readme.md", "readme.markdown",
        "index.md", "index.markdown",
        "claude.md",
    ]

    // MARK: - Auto-Index

    private static let autoIndexPrefix = "__autoindex__:"

    private func isAutoIndex(_ file: FileEntry) -> Bool {
        file.id.hasPrefix(Self.autoIndexPrefix)
    }

    private func makeAutoIndexEntry(for dirPath: String) -> FileEntry {
        let name = (dirPath as NSString).lastPathComponent
        let basePath = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        let relativePath: String
        if dirPath == directoryPath {
            relativePath = name
        } else if dirPath.hasPrefix(basePath) {
            relativePath = String(dirPath.dropFirst(basePath.count))
        } else {
            relativePath = name
        }
        return FileEntry(
            id: "\(Self.autoIndexPrefix)\(dirPath)",
            name: name,
            relativePath: relativePath,
            absolutePath: dirPath,
            size: 0,
            modifiedDate: Date(),
            isMarkdown: true
        )
    }

    private func loadFileOrAutoIndex(_ file: FileEntry) {
        if isAutoIndex(file) {
            let content = generateAutoIndex(for: file.absolutePath)
            webViewStore.loadMarkdown(content: content, title: file.name, contentDirectory: file.absolutePath, baseDirectory: directoryPath)
        } else {
            webViewStore.load(file: file, baseDirectory: directoryPath)
        }
    }

    private func generateAutoIndex(for dirPath: String) -> String {
        let dirName = (dirPath as NSString).lastPathComponent
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dirPath)) ?? []

        var dirs: [(name: String, date: Date)] = []
        var files: [(name: String, size: Int, date: Date)] = []

        for item in items.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            guard !item.hasPrefix(".") else { continue }
            let fullPath = (dirPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
            let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath)
            let date = (attrs?[.modificationDate] as? Date) ?? Date()

            if isDir.boolValue {
                dirs.append((name: item, date: date))
            } else {
                let size = (attrs?[.size] as? Int) ?? 0
                files.append((name: item, size: size, date: date))
            }
        }

        var md = "# \(dirName)\n\n"

        if dirs.isEmpty && files.isEmpty {
            md += "*Empty directory*\n"
            return md
        }

        md += "| Name | Size | Modified |\n"
        md += "|------|------|----------|\n"

        for d in dirs {
            let escaped = d.name.replacingOccurrences(of: "|", with: "\\|")
            let encoded = d.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? d.name
            md += "| 📁 [\(escaped)/](\(encoded)/) | — | \(formatTimeAgo(d.date)) |\n"
        }

        for f in files {
            let escaped = f.name.replacingOccurrences(of: "|", with: "\\|")
            let encoded = f.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? f.name
            md += "| [\(escaped)](\(encoded)) | \(formatSize(f.size)) | \(formatTimeAgo(f.date)) |\n"
        }

        return md
    }
}

// MARK: - View Modifiers

struct ZoomHandlers: ViewModifier {
    let isKeyWindow: Bool
    let webViewStore: WebViewStore

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
                guard isKeyWindow else { return }
                adjustZoom(10)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
                guard isKeyWindow else { return }
                adjustZoom(-10)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomReset)) { _ in
                guard isKeyWindow else { return }
                UserDefaults.standard.set(Constants.zoomDefault, forKey: "defaultZoom")
                webViewStore.applyZoom(Constants.zoomDefault)
            }
    }

    private func adjustZoom(_ delta: Int) {
        let current = UserDefaults.standard.object(forKey: "defaultZoom") as? Int ?? Constants.zoomDefault
        let newZoom = max(Constants.zoomMin, min(Constants.zoomMax, current + delta))
        UserDefaults.standard.set(newZoom, forKey: "defaultZoom")
        webViewStore.applyZoom(newZoom)
    }
}

struct FindHandlers: ViewModifier {
    let isKeyWindow: Bool
    let onFind: () -> Void
    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onUseSelection: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .findInPage)) { _ in
                guard isKeyWindow else { return }
                onFind()
            }
            .onReceive(NotificationCenter.default.publisher(for: .findNext)) { _ in
                guard isKeyWindow else { return }
                onFindNext()
            }
            .onReceive(NotificationCenter.default.publisher(for: .findPrevious)) { _ in
                guard isKeyWindow else { return }
                onFindPrevious()
            }
            .onReceive(NotificationCenter.default.publisher(for: .useSelectionForFind)) { _ in
                guard isKeyWindow else { return }
                onUseSelection()
            }
    }
}
