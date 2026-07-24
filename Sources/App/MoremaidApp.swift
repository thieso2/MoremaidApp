import Sparkle
import SwiftUI

@MainActor class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    var appState: AppState?

    // MARK: - PDF batch mode

    /// True when launched by `mm --pdf` to convert files headlessly.
    private var isPDFBatchMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--pdf")
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationWillFinishLaunching")
        if isPDFBatchMode {
            // Run silently — no Dock icon, no app-switcher entry.
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isPDFBatchMode {
            Task { @MainActor in await runPDFBatch() }
            return
        }

        let windowCount = NSApp.windows.count
        let visibleWindows = NSApp.windows.filter { $0.isVisible }
        print("[AppDelegate] applicationDidFinishLaunching — windows: \(windowCount), visible: \(visibleWindows.count)")
        for (i, w) in NSApp.windows.enumerated() {
            print("[AppDelegate]   window[\(i)]: visible=\(w.isVisible) alpha=\(w.alphaValue) title='\(w.title)' frame=\(w.frame)")
        }

        #if DEBUG
        applyDevIcon()
        #endif
    }

    /// Parse arguments and export each markdown file to PDF, then exit.
    @MainActor
    private func runPDFBatch() async {
        let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
        var inputFiles: [String] = []
        var outputDir = FileManager.default.currentDirectoryPath
        var idx = args.startIndex
        while idx < args.endIndex {
            let arg = args[idx]
            idx = args.index(after: idx)
            if arg == "--pdf" { continue }
            if arg == "--output" {
                if idx < args.endIndex { outputDir = args[idx]; idx = args.index(after: idx) }
                continue
            }
            if !arg.hasPrefix("-") { inputFiles.append(arg) }
        }

        let exporter = PDFBatchExporter()
        var exitCode: Int32 = 0

        for inputPath in inputFiles {
            let stem = ((inputPath as NSString).lastPathComponent as NSString).deletingPathExtension
            let outputPath = (outputDir as NSString).appendingPathComponent("\(stem).pdf")
            do {
                try await exporter.export(inputPath: inputPath, outputPath: outputPath)
                print("✓ \(outputPath)")
            } catch {
                fputs("✗ \(inputPath): \(error.localizedDescription)\n", stderr)
                exitCode = 1
            }
        }

        exit(exitCode)
    }

    #if DEBUG
    /// Set dock icon at runtime to bypass macOS icon cache.
    private func applyDevIcon() {
        let icnsPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? ""
        if let icon = NSImage(contentsOfFile: icnsPath), icon.isValid {
            NSApp.applicationIconImage = icon
        }
    }
    #endif

    func application(_ application: NSApplication, open urls: [URL]) {
        print("[AppDelegate] open urls: \(urls)")
        guard let appState else { return }
        for url in urls {
            let path = url.path
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            let target: OpenTarget = isDir.boolValue ? .directory(path: path) : .file(path: path)
            appState.openTarget(target)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        print("[AppDelegate] applicationShouldHandleReopen hasVisibleWindows=\(flag)")
        return flag
    }
}

@main
struct MoremaidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    init() {
        setbuf(stdout, nil)
        print("[MoremaidApp] init")
        QuickOpenShortcut.install()
    }

    var body: some Scene {
        WindowGroup(for: OpenTarget.self) { $target in
            WindowRootView(target: $target)
                .environment(appState)
                .onAppear { appDelegate.appState = appState }
        }
        .defaultSize(width: 800, height: 600)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            PreferencesView(updater: appDelegate.updaterController.updater)
                .environment(appState)
        }
    }
}

/// Renders the content for the bound `OpenTarget`. With `WindowGroup(for:)`
/// SwiftUI manages window lifecycle, state restoration, and "focus existing
/// window with this value" — no manual claim-queue / dismiss logic needed.
struct WindowRootView: View {
    @Binding var target: OpenTarget?
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.controlActiveState) private var controlActiveState

    private var isKeyWindow: Bool { controlActiveState == .key }

    var body: some View {
        Group {
            switch target {
            case .file(let path):
                SingleFileView(filePath: path)
            case .directory(let path, let initialFile):
                DirectoryWindowView(
                    directoryPath: path,
                    initialFilePath: initialFile
                )
            case .empty:
                EmptyWindowPlaceholder()
            case nil:
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ImplicitDefaultWindowSuppressor(isSuppressed: target == nil))
        .task { await windowTask() }
        .onChange(of: controlActiveState) {
            if isKeyWindow {
                appState.activeTarget = target
            }
        }
    }

    private func windowTask() async {
        // Register a bridge so AppDelegate.application(_:open:) — and any
        // other non-View context — can call into SwiftUI's openWindow.
        appState.openTargetHandler = { [openWindow] target in
            openWindow(value: target)
        }

        await dismissImplicitDefaultWindowIfNeeded()
    }

    private func dismissImplicitDefaultWindowIfNeeded() async {
        guard target == nil else { return }
        await Task.yield()
        guard target == nil else { return }
        dismiss()
    }
}

/// Keeps SwiftUI's implicit `nil` scene from flashing before we dismiss it.
private struct ImplicitDefaultWindowSuppressor: NSViewRepresentable {
    let isSuppressed: Bool

    func makeNSView(context: Context) -> SuppressorView {
        SuppressorView()
    }

    func updateNSView(_ nsView: SuppressorView, context: Context) {
        nsView.isSuppressed = isSuppressed
        nsView.applySuppression()
    }

    final class SuppressorView: NSView {
        var isSuppressed = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applySuppression()
        }

        func applySuppression() {
            guard let window else { return }
            window.alphaValue = isSuppressed ? 0 : 1
        }
    }
}

struct EmptyWindowPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Press \u{2318}O to open a file or folder")
                .foregroundStyle(.secondary)
            Text("\u{2318}K for Quick Open")
                .foregroundStyle(.tertiary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

struct AppCommands: Commands {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false

    private func recentIcon(_ recent: RecentTarget) -> String {
        switch recent {
        case .file: "doc"
        case .directory: "folder"
        }
    }

    private func closeKeyWindow() {
        if !NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil) {
            (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(nil)
        }
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button {
                openWindow(value: OpenTarget.newEmpty())
            } label: {
                Label("New Window", systemImage: "macwindow.badge.plus")
            }
            .keyboardShortcut("n", modifiers: .command)

            Button {
                Task { @MainActor in
                    let paths = await FilePicker.chooseFilesOrDirectories()
                    for path in paths {
                        var isDir: ObjCBool = false
                        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                        let target: OpenTarget = isDir.boolValue ? .directory(path: path) : .file(path: path)
                        openWindow(value: target)
                    }
                }
            } label: {
                Label("Open...", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent") {
                let recents = appState.recentTargets
                if recents.isEmpty {
                    Text("No Recent Items")
                } else {
                    ForEach(recents, id: \.self) { recent in
                        Button {
                            openWindow(value: recent.openTarget)
                        } label: {
                            Label(abbreviatePath(recent.path), systemImage: recentIcon(recent))
                        }
                    }
                    Divider()
                    Button {
                        appState.clearRecentTargets()
                    } label: {
                        Label("Clear Menu", systemImage: "trash")
                    }
                }
            }

            Divider()

            Button {
                NotificationCenter.default.post(name: .toggleQuickOpen, object: nil)
            } label: {
                Label("Quick Open...", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("k", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button {
                // New empty tab in the current window: prefer tab grouping on
                // the key window, then open a fresh empty target.
                if let win = NSApp.keyWindow {
                    win.tabbingMode = .preferred
                    DispatchQueue.main.async { win.tabbingMode = .automatic }
                }
                openWindow(value: OpenTarget.newEmpty())
            } label: {
                Label("New Tab", systemImage: "plus.square.on.square")
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button {
                closeKeyWindow()
            } label: {
                Label("Close Window", systemImage: "xmark.rectangle")
            }
            .keyboardShortcut("w", modifiers: .command)

            Divider()

            Button {
                NotificationCenter.default.post(name: .saveFile, object: nil)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        CommandGroup(replacing: .printItem) {
            Button {
                NotificationCenter.default.post(name: .exportPDF, object: nil)
            } label: {
                Label("Export PDF...", systemImage: "arrow.down.doc")
            }
            .keyboardShortcut("p", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .toggleSourceEdit, object: nil)
            } label: {
                Label("Edit Source", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button {
                NotificationCenter.default.post(name: .openInExternalEditor, object: nil)
            } label: {
                Label("Edit in External Editor", systemImage: "pencil")
            }
        }

        CommandGroup(replacing: .textEditing) {
            Button {
                NotificationCenter.default.post(name: .findInPage, object: nil)
            } label: {
                Label("Find...", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .searchInFiles, object: nil)
            } label: {
                Label("Find in Files...", systemImage: "doc.text.magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button {
                NotificationCenter.default.post(name: .findNext, object: nil)
            } label: {
                Label("Find Next", systemImage: "chevron.down")
            }
            .keyboardShortcut("g", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .findPrevious, object: nil)
            } label: {
                Label("Find Previous", systemImage: "chevron.up")
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button {
                NotificationCenter.default.post(name: .useSelectionForFind, object: nil)
            } label: {
                Label("Use Selection for Find", systemImage: "text.cursor")
            }
            .keyboardShortcut("e", modifiers: .command)
        }

        CommandGroup(before: .toolbar) {
            Button {
                NotificationCenter.default.post(name: .goBack, object: nil)
            } label: {
                Label("Back", systemImage: "chevron.backward")
            }
            .keyboardShortcut("[", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .goForward, object: nil)
            } label: {
                Label("Forward", systemImage: "chevron.forward")
            }
            .keyboardShortcut("]", modifiers: .command)

            Divider()

            Button {
                NotificationCenter.default.post(name: .toggleTOC, object: nil)
            } label: {
                Label("Table of Contents", systemImage: "list.bullet")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button {
                NotificationCenter.default.post(name: .toggleBreadcrumb, object: nil)
            } label: {
                Label("Breadcrumb Bar", systemImage: "chevron.right")
            }

            Button {
                NotificationCenter.default.post(name: .toggleStatusBar, object: nil)
            } label: {
                Label("Status Bar", systemImage: "rectangle.bottomhalf.filled")
            }

            Button {
                NotificationCenter.default.post(name: .toggleActivityFeed, object: nil)
            } label: {
                Label("Activity Feed", systemImage: "bell")
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            // App-wide "Show Hidden Files". Flipping the @AppStorage value updates
            // UserDefaults, which every open window observes and re-scans on (ticket 1).
            Toggle(isOn: $showHiddenFiles) {
                Label("Show Hidden Files", systemImage: "eye")
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Button {
                NotificationCenter.default.post(name: .reloadFile, object: nil)
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button {
                NotificationCenter.default.post(name: .zoomIn, object: nil)
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .keyboardShortcut("+", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .zoomOut, object: nil)
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .zoomReset, object: nil)
            } label: {
                Label("Actual Size", systemImage: "1.magnifyingglass")
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()
        }
    }
}
