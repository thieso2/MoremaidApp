import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationWillFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationWillFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let windowCount = NSApp.windows.count
        let visibleWindows = NSApp.windows.filter { $0.isVisible }
        print("[AppDelegate] applicationDidFinishLaunching — windows: \(windowCount), visible: \(visibleWindows.count)")
        for (i, w) in NSApp.windows.enumerated() {
            print("[AppDelegate]   window[\(i)]: visible=\(w.isVisible) alpha=\(w.alphaValue) title='\(w.title)' frame=\(w.frame)")
        }
    }

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
            PreferencesView()
                .environment(appState)
        }
    }
}

/// Each window instance claims a session or pending target.
struct WindowRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var sessionID = UUID()
    @State private var target: OpenTarget?
    @State private var initialFilePath: String?
    @State private var initialFrame: NSRect?
    @State private var didSetup = false
    @State private var windowReady = false

    private var isKeyWindow: Bool { controlActiveState == .key }

    var body: some View {
        Group {
            switch target {
            case .file(let path):
                SingleFileView(filePath: path, sessionID: sessionID)
            case .directory(let path):
                DirectoryWindowView(
                    directoryPath: path,
                    sessionID: sessionID,
                    initialFilePath: initialFilePath
                )
            case nil:
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WindowFrameTracker(
            sessionID: sessionID,
            initialFrame: initialFrame,
            appState: appState,
            isReady: windowReady
        ))
        .onAppear {
            print("[WindowRootView] onAppear sessionID=\(sessionID)")
        }
        .task {
            guard !didSetup else { return }
            didSetup = true
            print("[WindowRootView] .task running sessionID=\(sessionID)")
            print("[WindowRootView]   pendingSessions=\(appState.pendingSessionCount) pendingTargets=\(appState.pendingTargets.count)")

            if let session = appState.claimPendingSession() {
                print("[WindowRootView]   claimed session: \(session.target.path)")
                target = session.target
                initialFilePath = session.selectedFile
                if let x = session.frameX, let y = session.frameY,
                   let w = session.frameWidth, let h = session.frameHeight {
                    initialFrame = NSRect(x: x, y: y, width: w, height: h)
                }
                windowReady = true
                // Open windows for remaining pending sessions
                let remaining = appState.pendingSessionCount
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
                // No session or target to claim — close this empty window
                // Window was never made visible (alphaValue=0), so no flicker
                dismiss()
            }
        }
        .onChange(of: controlActiveState) {
            if isKeyWindow {
                appState.activeTarget = target
            }
        }
        .onDisappear {
            appState.unregisterSession(id: sessionID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPendingTargets)) { _ in
            // Use atomic counter to ensure only one window handles each request
            guard appState.windowsToOpen > 0 else { return }
            let count = appState.windowsToOpen
            appState.windowsToOpen = 0
            for _ in 0..<count {
                openWindow(id: "main")
            }
        }
    }
}

/// NSViewRepresentable that accesses the hosting NSWindow to restore frame and periodically save it.
struct WindowFrameTracker: NSViewRepresentable {
    let sessionID: UUID
    let initialFrame: NSRect?
    let appState: AppState
    var isReady: Bool

    func makeNSView(context: Context) -> WindowTrackerView {
        print("[WindowFrameTracker] makeNSView sessionID=\(sessionID)")
        let view = WindowTrackerView()
        view.coordinator = context.coordinator
        context.coordinator.sessionID = sessionID
        context.coordinator.initialFrame = initialFrame
        context.coordinator.appState = appState
        return view
    }

    func updateNSView(_ nsView: WindowTrackerView, context: Context) {
        print("[WindowFrameTracker] updateNSView isReady=\(isReady) didRestore=\(context.coordinator.didRestore)")

        // Reveal window once content is ready
        if isReady, let window = nsView.window, window.alphaValue == 0 {
            print("[WindowFrameTracker]   revealing window (alpha=1)")
            window.alphaValue = 1
        }
    }

    /// Custom NSView that hides its window immediately when attached, before it renders.
    class WindowTrackerView: NSView {
        var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let coordinator, !coordinator.didRestore else { return }
            coordinator.didRestore = true
            print("[WindowTrackerView] viewDidMoveToWindow — hiding window (alpha=0), visible=\(window.isVisible) alpha=\(window.alphaValue)")
            window.alphaValue = 0
            if let frame = coordinator.initialFrame {
                window.setFrame(frame, display: true)
            }
            coordinator.window = window
            coordinator.startTracking()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    class Coordinator {
        var sessionID = UUID()
        var initialFrame: NSRect?
        var appState: AppState?
        var window: NSWindow?
        var didRestore = false
        private var timer: Timer?

        func startTracking() {
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.saveFrame()
                }
            }
        }

        private func saveFrame() {
            guard let window, let appState else { return }
            let frame = window.frame
            if var session = appState.openSessions[sessionID] {
                session.frameX = frame.origin.x
                session.frameY = frame.origin.y
                session.frameWidth = frame.size.width
                session.frameHeight = frame.size.height
                appState.openSessions[sessionID] = session
                appState.saveSessions()
            }
        }

        nonisolated deinit {
            // Timer cleanup handled when view is removed
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
