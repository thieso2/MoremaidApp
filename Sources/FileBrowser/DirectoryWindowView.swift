import SwiftUI

struct DirectoryWindowView: View {
    let directoryPath: String
    let sessionID: UUID
    let initialFilePath: String?
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var selectedFile: FileEntry?
    @State private var webViewStore = WebViewStore()
    @State private var copyFeedback = false
    @State private var showQuickOpen = false
    @State private var projectFiles: [FileEntry] = []
    @State private var isScanning = false
    @State private var scanGeneration = 0
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var findCurrent = 0
    @State private var findTotal = 0
    @FocusState private var findFieldFocused: Bool
    @State private var showTOC = false
    @State private var showSearchPanel = false
    @State private var searchInFilesQuery = ""
    @State private var searchInFilesResults: [SearchResult] = []
    @State private var sifFileIndex = -1
    @State private var sifMatchIndex = -1
    @State private var headings: [WebViewStore.HeadingEntry] = []
    @State private var currentHeadingID = ""
    @State private var tocScrollTimer: Timer?
    @State private var autoIndexTimer: Timer?
    @State private var lastAutoIndexHash: Int?
    @AppStorage("showBreadcrumb") private var showBreadcrumb = true
    @AppStorage("showStatusBar") private var showStatusBar = true
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
            .toolbarRole(.editor)
            .task {
                webViewStore.onNavigateToFile = { path, fragment in
                    navigateToFileAtPath(path, fragment: fragment)
                }
                webViewStore.onOpenInNewTab = { path, fragment in
                    openInNewTab(path: path, fragment: fragment)
                }
                webViewStore.onOpenInNewWindow = { path, fragment in
                    openInNewWindow(path: path, fragment: fragment)
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
        HStack(spacing: 0) {
            if showTOC {
                tocPanel
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            webViewLayer
                .overlay { placeholderOverlay }
                .overlay { quickOpenOverlay }
                .overlay(alignment: .top) { findBarOverlay }
                .safeAreaInset(edge: .top, spacing: 0) { breadcrumbBar }
                .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
            if showSearchPanel {
                Divider()
                SearchInFilesView(
                    files: projectFiles,
                    searchQuery: $searchInFilesQuery,
                    isPresented: $showSearchPanel,
                    searchResults: $searchInFilesResults,
                    activeFileIndex: $sifFileIndex,
                    activeMatchIndex: $sifMatchIndex,
                    onSelectResult: { file, query, lineNumber, matchIndex in
                        handleSearchInFilesSelect(file: file, query: query, matchIndex: matchIndex)
                    },
                    onNext: { handleSearchInFilesNext() },
                    onPrevious: { handleSearchInFilesPrevious() },
                    onFirst: {
                        guard !searchInFilesResults.isEmpty else { return }
                        sifFileIndex = 0
                        sifMatchIndex = 0
                        navigateToSifMatch()
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onChange(of: selectedFile) { handleFileChange() }
        .onChange(of: showSearchPanel) {
            if !showSearchPanel {
                webViewStore.findClear()
                sifFileIndex = -1
                sifMatchIndex = -1
            }
        }
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
            .onReceive(NotificationCenter.default.publisher(for: .toggleTOC)) { _ in
                guard isKeyWindow else { return }
                withAnimation(.easeInOut(duration: 0.2)) { showTOC.toggle() }
                if showTOC {
                    refreshHeadings()
                    startTOCScrollTracking()
                } else {
                    stopTOCScrollTracking()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                guard isKeyWindow else { return }
                let filePath = selectedFile.flatMap { isAutoIndex($0) ? nil : $0.absolutePath }
                appState.queueNewTab(target: .directory(path: directoryPath), selectedFile: filePath)
                openAsTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleBreadcrumb)) { _ in
                guard isKeyWindow else { return }
                withAnimation(.easeInOut(duration: 0.2)) { showBreadcrumb.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleStatusBar)) { _ in
                guard isKeyWindow else { return }
                withAnimation(.easeInOut(duration: 0.2)) { showStatusBar.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchInFiles)) { _ in
                guard isKeyWindow else { return }
                withAnimation(.easeInOut(duration: 0.2)) { showSearchPanel.toggle() }
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

    // MARK: - Breadcrumbs

    @ViewBuilder
    private var breadcrumbBar: some View {
        if showBreadcrumb, let file = selectedFile {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Button(directoryName) {
                        selectedFile = makeAutoIndexEntry(for: directoryPath)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    let components = file.relativePath.split(separator: "/").map(String.init)
                    ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if index < components.count - 1 {
                            // Directory segment — navigate to its auto-index
                            Button(component) {
                                let subPath = components[0...index].joined(separator: "/")
                                let fullPath = (directoryPath as NSString).appendingPathComponent(subPath)
                                selectedFile = makeAutoIndexEntry(for: fullPath)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        } else {
                            // Current file/directory — not clickable
                            Text(component)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .rect(cornerRadius: 8))
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }

    // MARK: - Status Bar

    @ViewBuilder
    private var statusBar: some View {
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

    // MARK: - Table of Contents

    private var tocPanel: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if headings.isEmpty {
                            Text("No headings")
                                .foregroundStyle(.tertiary)
                                .font(.subheadline)
                                .padding(16)
                        } else {
                            ForEach(headings) { heading in
                                let isActive = heading.id == currentHeadingID
                                Button {
                                    Task { _ = await webViewStore.scrollToAnchor(heading.id) }
                                } label: {
                                    HStack {
                                        Text(heading.text)
                                            .font(heading.level == 1 ? .body : .callout)
                                            .fontWeight(heading.level <= 2 ? .medium : .regular)
                                            .foregroundStyle(isActive ? .primary : (heading.level <= 2 ? .primary : .secondary))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.leading, CGFloat((heading.level - 1) * 14))
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 14)
                                    .background(
                                        isActive
                                            ? RoundedRectangle(cornerRadius: 6).fill(.selection.opacity(0.3))
                                            : nil
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(heading.id)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: currentHeadingID) {
                    if !currentHeadingID.isEmpty {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(currentHeadingID, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            .background(.windowBackground)

            Divider()
        }
    }


    private func refreshHeadings() {
        Task {
            headings = await webViewStore.getHeadings()
            currentHeadingID = await webViewStore.getCurrentHeadingID()
        }
    }

    private func startTOCScrollTracking() {
        stopTOCScrollTracking()
        tocScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                guard showTOC else { return }
                let id = await webViewStore.getCurrentHeadingID()
                if id != currentHeadingID {
                    currentHeadingID = id
                }
            }
        }
    }

    private func stopTOCScrollTracking() {
        tocScrollTimer?.invalidate()
        tocScrollTimer = nil
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

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showTOC.toggle() }
                if showTOC {
                    refreshHeadings()
                    startTOCScrollTracking()
                } else {
                    stopTOCScrollTracking()
                }
            } label: {
                Label("Table of Contents", systemImage: "sidebar.left")
            }
            .help("Toggle Table of Contents (\u{21E7}\u{2318}T)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSearchPanel.toggle() }
            } label: {
                Label("Find in Files", systemImage: "doc.text.magnifyingglass")
            }
            .help("Find in Files (\u{21E7}\u{2318}F)")
        }

    }

    // MARK: - History Navigation

    private static let maxHistorySize = 100

    private func pushToHistory(_ file: FileEntry) {
        // Trim forward history
        if historyIndex < fileHistory.count - 1 {
            fileHistory = Array(fileHistory[0...historyIndex])
        }
        fileHistory.append(HistoryEntry(file: file))
        // Cap history
        if fileHistory.count > Self.maxHistorySize {
            let excess = fileHistory.count - Self.maxHistorySize
            fileHistory.removeFirst(excess)
        }
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
    private func navigateToFileAtPath(_ path: String, fragment: String? = nil) {
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

        if let fragment {
            webViewStore.pendingAnchor = fragment
        }

        print("[moremaid] navigateToFileAtPath: file: \(path)\(fragment.map { "#\($0)" } ?? "")")
        if let existing = projectFiles.first(where: { $0.absolutePath == path }) {
            selectedFile = existing
            return
        }
        selectedFile = makeFileEntry(absolutePath: path)
    }

    // MARK: - New Tab / Window

    private func openInNewTab(path: String, fragment: String?) {
        appState.queueNewTab(target: .directory(path: directoryPath), selectedFile: path)
        openAsTab()
    }

    private func openInNewWindow(path: String, fragment: String?) {
        appState.queueNewTab(target: .directory(path: directoryPath), selectedFile: path)
        openWindow(id: "main")
    }

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
            if showTOC { refreshHeadings() }
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
        if showSearchPanel && !searchInFilesResults.isEmpty {
            handleSearchInFilesNext()
            return
        }
        guard showFindBar else { return }
        Task {
            let r = await webViewStore.findNext()
            findCurrent = r.current
            findTotal = r.total
        }
    }

    private func handleFindPrevious() {
        if showSearchPanel && !searchInFilesResults.isEmpty {
            handleSearchInFilesPrevious()
            return
        }
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

    // MARK: - Search in Files Navigation

    /// Called when user clicks a match in the search-in-files panel.
    private func handleSearchInFilesSelect(file: FileEntry, query: String, matchIndex: Int) {
        guard let fileIdx = searchInFilesResults.firstIndex(where: { $0.path == file.relativePath }) else { return }
        sifFileIndex = fileIdx
        sifMatchIndex = matchIndex
        navigateToSifMatch()
    }

    /// Cmd+G in search-in-files mode. Wraps around.
    private func handleSearchInFilesNext() {
        guard !searchInFilesResults.isEmpty else { return }
        let fileIdx = max(0, sifFileIndex)
        let fileResult = searchInFilesResults[fileIdx]
        let matchCount = fileResult.matches?.count ?? 0

        if sifMatchIndex + 1 < matchCount {
            sifMatchIndex += 1
        } else {
            sifFileIndex = (fileIdx + 1) % searchInFilesResults.count
            sifMatchIndex = 0
        }
        navigateToSifMatch()
    }

    /// Shift+Cmd+G in search-in-files mode. Wraps around.
    private func handleSearchInFilesPrevious() {
        guard !searchInFilesResults.isEmpty else { return }

        if sifMatchIndex > 0 {
            sifMatchIndex -= 1
        } else {
            sifFileIndex = (sifFileIndex - 1 + searchInFilesResults.count) % searchInFilesResults.count
            let prevResult = searchInFilesResults[sifFileIndex]
            sifMatchIndex = max(0, (prevResult.matches?.count ?? 1) - 1)
        }
        navigateToSifMatch()
    }

    /// Navigate the webview to the current sifFileIndex/sifMatchIndex and highlight.
    private func navigateToSifMatch() {
        guard sifFileIndex >= 0, sifFileIndex < searchInFilesResults.count else { return }
        let result = searchInFilesResults[sifFileIndex]
        guard let file = projectFiles.first(where: { $0.relativePath == result.path }) else { return }

        let needsNavigation = selectedFile != file
        if needsNavigation {
            selectedFile = file
        }

        let matchIndex = sifMatchIndex
        let query = searchInFilesQuery
        let delay: Double = needsNavigation ? 0.5 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task {
                _ = await webViewStore.findInPage(query)
                _ = await webViewStore.findJumpToIndex(matchIndex)
            }
        }
    }

    // MARK: - File Loading

    private func scanFiles() {
        isScanning = true
        scanGeneration += 1
        let generation = scanGeneration
        projectFiles = []

        // Load saved/default file immediately — no waiting for full scan
        tryLoadInitialFile()

        // Full background scan for Quick Open
        FileScanner.scanBatched(directory: directoryPath, filter: .allFiles, batchSize: 200) { batch, done in
            DispatchQueue.main.async {
                guard generation == scanGeneration else { return }
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
            lastAutoIndexHash = content.hashValue
            webViewStore.loadMarkdown(content: content, title: file.name, contentDirectory: file.absolutePath, baseDirectory: directoryPath)
            startAutoIndexWatcher(for: file.absolutePath)
        } else {
            stopAutoIndexWatcher()
            webViewStore.load(file: file, baseDirectory: directoryPath)
        }
    }

    // MARK: - Auto-Index File Watcher

    private func startAutoIndexWatcher(for dirPath: String) {
        stopAutoIndexWatcher()
        autoIndexTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [dirPath] _ in
            Task { @MainActor in
                let content = generateAutoIndex(for: dirPath)
                let hash = content.hashValue
                guard hash != lastAutoIndexHash else { return }
                lastAutoIndexHash = hash
                let escaped = content.jsonStringLiteral
                webViewStore.webView?.evaluateJavaScript("reRenderMarkdown(\(escaped));", completionHandler: nil)
            }
        }
    }

    private func stopAutoIndexWatcher() {
        autoIndexTimer?.invalidate()
        autoIndexTimer = nil
        lastAutoIndexHash = nil
    }

    private func generateAutoIndex(for dirPath: String) -> String {
        let dirName = (dirPath as NSString).lastPathComponent
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dirPath)) ?? []
        let gitignore = GitignoreParser(basePath: directoryPath)
        let basePath = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"

        var dirs: [(name: String, date: Date)] = []
        var files: [(name: String, size: Int, date: Date)] = []

        for item in items.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            guard !item.hasPrefix(".") else { continue }
            let fullPath = (dirPath as NSString).appendingPathComponent(item)
            let relativePath = fullPath.hasPrefix(basePath) ? String(fullPath.dropFirst(basePath.count)) : item
            if gitignore.isIgnored(relativePath) { continue }
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
