import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
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
            appState.pendingTargets.append(target)
        }
        appState.windowsToOpen += urls.count
        NotificationCenter.default.post(name: .openPendingTargets, object: nil)
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
    @Environment(\.openWindow) private var openWindow

    init() {
        setbuf(stdout, nil)
        print("[MoremaidApp] init")
        QuickOpenShortcut.install()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            WindowRootView()
                .environment(appState)
                .onAppear { appDelegate.appState = appState }
        }
        .defaultSize(width: 800, height: 600)
        .restorationBehavior(.disabled)
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            PreferencesView(updater: appDelegate.updaterController.updater)
                .environment(appState)
        }
    }
}

/// Each window instance claims a pending tab or target.
struct WindowRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var target: OpenTarget?
    @State private var initialFilePath: String?
    @State private var didSetup = false
    @State private var windowReady = false

    private var isKeyWindow: Bool { controlActiveState == .key }

    var body: some View {
        Group {
            switch target {
            case .file(let path):
                SingleFileView(filePath: path)
            case .directory(let path):
                DirectoryWindowView(
                    directoryPath: path,
                    initialFilePath: initialFilePath
                )
            case nil:
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WindowFlickerGuard(isReady: windowReady))
        .task {
            guard !didSetup else { return }
            didSetup = true
            print("[WindowRootView] .task pendingTabs=\(appState.pendingTabCount) pendingTargets=\(appState.pendingTargets.count)")

            if let tab = appState.claimPendingTab() {
                print("[WindowRootView]   claimed tab: \(tab.target.path)")
                target = tab.target
                initialFilePath = tab.selectedFile
                windowReady = true
                // Open windows for remaining pending tabs
                let remaining = appState.pendingTabCount
                for _ in 0..<remaining {
                    openWindow(id: "main")
                }
            } else if let pendingTarget = appState.claimPendingTarget() {
                print("[WindowRootView]   claimed target: \(pendingTarget.path)")
                target = pendingTarget
                windowReady = true
                // Open windows for remaining pending targets
                let remainingTargets = appState.pendingTargets.count
                for _ in 0..<remainingTargets {
                    openWindow(id: "main")
                }
            } else {
                print("[WindowRootView]   nothing to claim — dismissing")
                dismiss()
            }
        }
        .onChange(of: controlActiveState) {
            if isKeyWindow {
                appState.activeTarget = target
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPendingTargets)) { _ in
            guard appState.windowsToOpen > 0 else { return }
            let count = appState.windowsToOpen
            appState.windowsToOpen = 0
            for _ in 0..<count {
                openWindow(id: "main")
            }
        }
    }
}

/// Hides the window (alpha=0) until content is ready, preventing flicker.
struct WindowFlickerGuard: NSViewRepresentable {
    var isReady: Bool

    func makeNSView(context: Context) -> FlickerGuardView {
        FlickerGuardView()
    }

    func updateNSView(_ nsView: FlickerGuardView, context: Context) {
        if isReady, let window = nsView.window, window.alphaValue == 0 {
            window.alphaValue = 1
        }
    }

    class FlickerGuardView: NSView {
        private var didHide = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !didHide else { return }
            didHide = true
            window.alphaValue = 0
        }
    }
}

extension Notification.Name {
    static let openPendingTargets = Notification.Name("openPendingTargets")
}

struct AppCommands: Commands {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    private func recentIcon(_ target: OpenTarget) -> String {
        switch target {
        case .file: "doc"
        case .directory: "folder"
        }
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button {
                Task { @MainActor in
                    let paths = await FilePicker.chooseFilesOrDirectories()
                    for path in paths {
                        var isDir: ObjCBool = false
                        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                        let target: OpenTarget = isDir.boolValue ? .directory(path: path) : .file(path: path)
                        appState.pendingTargets.append(target)
                        openWindow(id: "main")
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
                    ForEach(recents, id: \.self) { target in
                        Button {
                            appState.pendingTargets.append(target)
                            openWindow(id: "main")
                        } label: {
                            Label(abbreviatePath(target.path), systemImage: recentIcon(target))
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
                NotificationCenter.default.post(name: .newTab, object: nil)
            } label: {
                Label("New Tab", systemImage: "plus.square.on.square")
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(replacing: .printItem) {
            Button {
                NotificationCenter.default.post(name: .exportPDF, object: nil)
            } label: {
                Label("Export PDF...", systemImage: "arrow.down.doc")
            }
            .keyboardShortcut("p", modifiers: .command)
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
