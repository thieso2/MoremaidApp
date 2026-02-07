import Foundation
import SwiftUI

struct WindowSession: Codable {
    let target: OpenTarget
    let selectedFile: String?
    var frameX: Double?
    var frameY: Double?
    var frameWidth: Double?
    var frameHeight: Double?
}

@Observable
@MainActor
final class AppState {
    private(set) var pendingSessions: [WindowSession] = []
    /// Queue for targets from Cmd+O or drag-drop that need new windows
    var pendingTargets: [OpenTarget] = []
    /// Tracks currently open window sessions for saving on quit
    var openSessions: [UUID: WindowSession] = [:]
    /// The target of the key (front) window
    var activeTarget: OpenTarget?
    /// Atomic counter for windows that need opening (used by notification handler)
    var windowsToOpen = 0
    /// Recently opened targets (most recent first), persisted via UserDefaults
    private(set) var recentTargets: [OpenTarget] = []
    private static let maxRecent = 10
    private var isTerminating = false

    private var restoreWindows: Bool {
        UserDefaults.standard.object(forKey: "restoreWindows") as? Bool ?? true
    }

    init() {
        loadSavedSessions()
        loadRecentTargets()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                self.isTerminating = true
            }
        }
    }

    // MARK: - Session Management

    func claimPendingSession() -> WindowSession? {
        guard !pendingSessions.isEmpty else { return nil }
        return pendingSessions.removeFirst()
    }

    func claimPendingTarget() -> OpenTarget? {
        guard !pendingTargets.isEmpty else { return nil }
        return pendingTargets.removeFirst()
    }

    var pendingSessionCount: Int { pendingSessions.count }

    func queueNewTab(target: OpenTarget, selectedFile: String?) {
        pendingSessions.append(WindowSession(target: target, selectedFile: selectedFile))
    }

    func registerSession(id: UUID, target: OpenTarget, selectedFile: String?, frame: NSRect? = nil) {
        var session = WindowSession(target: target, selectedFile: selectedFile)
        if let frame {
            session.frameX = frame.origin.x
            session.frameY = frame.origin.y
            session.frameWidth = frame.size.width
            session.frameHeight = frame.size.height
        } else if let existing = openSessions[id] {
            session.frameX = existing.frameX
            session.frameY = existing.frameY
            session.frameWidth = existing.frameWidth
            session.frameHeight = existing.frameHeight
        }
        openSessions[id] = session
        saveSessions()
        addRecentTarget(target)
    }

    func unregisterSession(id: UUID) {
        guard !isTerminating else { return }
        openSessions.removeValue(forKey: id)
        saveSessions()
    }

    // MARK: - Persistence

    private func loadSavedSessions() {
        guard restoreWindows,
              let data = UserDefaults.standard.data(forKey: "savedWindowSessions"),
              let sessions = try? JSONDecoder().decode([WindowSession].self, from: data) else {
            return
        }
        // Filter out sessions whose paths no longer exist on disk
        pendingSessions = sessions.filter { session in
            FileManager.default.fileExists(atPath: session.target.path)
        }
    }

    func saveSessions() {
        let sessions = Array(openSessions.values)
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: "savedWindowSessions")
        }
    }

    // MARK: - Recent Targets

    private func addRecentTarget(_ target: OpenTarget) {
        recentTargets.removeAll { $0 == target }
        recentTargets.insert(target, at: 0)
        if recentTargets.count > Self.maxRecent {
            recentTargets = Array(recentTargets.prefix(Self.maxRecent))
        }
        saveRecentTargets()
    }

    private func loadRecentTargets() {
        guard let data = UserDefaults.standard.data(forKey: "recentTargets"),
              let targets = try? JSONDecoder().decode([OpenTarget].self, from: data) else { return }
        recentTargets = targets.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func saveRecentTargets() {
        if let data = try? JSONEncoder().encode(recentTargets) {
            UserDefaults.standard.set(data, forKey: "recentTargets")
        }
    }

    func clearRecentTargets() {
        recentTargets = []
        saveRecentTargets()
    }

    func startup() async {
        // Future: start file watcher, etc.
    }
}
