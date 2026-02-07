import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func application(_ application: NSApplication, open urls: [URL]) {
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
        return true
    }
}

@main
struct MoremaidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        QuickOpenShortcut.install()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            WindowRootView()
                .environment(appState)
                .onAppear { appDelegate.appState = appState }
        }
        .defaultSize(width: 800, height: 600)
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
            appState: appState
        ))
        .task {
            guard !didSetup else { return }
            didSetup = true

            if let session = appState.claimPendingSession() {
                target = session.target
                initialFilePath = session.selectedFile
                if let x = session.frameX, let y = session.frameY,
                   let w = session.frameWidth, let h = session.frameHeight {
                    initialFrame = NSRect(x: x, y: y, width: w, height: h)
                }
                // Open windows for remaining pending sessions
                let remaining = appState.pendingSessionCount
                for _ in 0..<remaining {
                    openWindow(id: "main")
                }
            } else if let pendingTarget = appState.claimPendingTarget() {
                target = pendingTarget
                // Open windows for remaining pending targets
                let remainingTargets = appState.pendingTargets.count
                for _ in 0..<remainingTargets {
                    openWindow(id: "main")
                }
            } else {
                // No session or target to claim — close this empty window
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

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.sessionID = sessionID
        context.coordinator.initialFrame = initialFrame
        context.coordinator.appState = appState
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window, !context.coordinator.didRestore {
            context.coordinator.didRestore = true
            if let frame = initialFrame {
                window.setFrame(frame, display: true)
            }
            context.coordinator.window = window
            context.coordinator.startTracking()
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

        CommandMenu("View") {
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
        }
    }
}
