import Foundation
import SwiftUI

struct PendingTab {
    let target: OpenTarget
    let selectedFile: String?
}

@Observable
@MainActor
final class AppState {
    /// Queue for new tabs (from queueNewTab)
    private(set) var pendingTabs: [PendingTab] = []
    /// Queue for targets from Cmd+O or drag-drop that need new windows
    var pendingTargets: [OpenTarget] = []
    /// The target of the key (front) window
    var activeTarget: OpenTarget?
    /// Atomic counter for windows that need opening (used by notification handler)
    var windowsToOpen = 0
    /// Recently opened targets (most recent first), persisted via UserDefaults
    private(set) var recentTargets: [OpenTarget] = []
    private static let maxRecent = 10

    init() {
        print("[AppState] init")
        loadRecentTargets()
    }

    // MARK: - Tab Queue

    func claimPendingTab() -> PendingTab? {
        guard !pendingTabs.isEmpty else { return nil }
        return pendingTabs.removeFirst()
    }

    func claimPendingTarget() -> OpenTarget? {
        guard !pendingTargets.isEmpty else { return nil }
        return pendingTargets.removeFirst()
    }

    var pendingTabCount: Int { pendingTabs.count }

    func queueNewTab(target: OpenTarget, selectedFile: String?) {
        pendingTabs.append(PendingTab(target: target, selectedFile: selectedFile))
    }

    func trackRecentTarget(_ target: OpenTarget) {
        addRecentTarget(target)
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
