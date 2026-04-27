import Foundation
import SwiftUI

@Observable
@MainActor
final class AppState {
    /// The target of the key (front) window. Set by WindowRootView.
    var activeTarget: OpenTarget?

    /// Recently opened items (most recent first), persisted via UserDefaults.
    private(set) var recentTargets: [RecentTarget] = []
    private static let maxRecent = 10
    private static let recentTargetsKey = "recentTargets"

    /// Bridge from AppDelegate's `application(_:open:)` (and other non-View
    /// contexts) to SwiftUI's `openWindow(value:)`. The first window's
    /// `WindowRootView` registers a handler; URLs received before that drain
    /// once the handler is set.
    var openTargetHandler: (@MainActor (OpenTarget) -> Void)? {
        didSet {
            guard openTargetHandler != nil, !pendingOpens.isEmpty else { return }
            let queued = pendingOpens
            pendingOpens.removeAll()
            for target in queued { openTargetHandler?(target) }
        }
    }
    private var pendingOpens: [OpenTarget] = []

    init() {
        print("[AppState] init")
        loadRecentTargets()
    }

    // MARK: - Open URL Bridge

    /// Called by AppDelegate. If a handler is registered, opens immediately;
    /// otherwise queues until a window's task registers one.
    func openTarget(_ target: OpenTarget) {
        if let handler = openTargetHandler {
            handler(target)
        } else {
            pendingOpens.append(target)
        }
    }

    // MARK: - Recent Targets

    func trackRecentTarget(_ target: OpenTarget) {
        guard let recent = target.recent else { return }
        recentTargets.removeAll { $0 == recent }
        recentTargets.insert(recent, at: 0)
        if recentTargets.count > Self.maxRecent {
            recentTargets = Array(recentTargets.prefix(Self.maxRecent))
        }
        saveRecentTargets()
    }

    func clearRecentTargets() {
        recentTargets = []
        saveRecentTargets()
    }

    private func loadRecentTargets() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentTargetsKey) else { return }
        // Try the current format first.
        if let decoded = try? JSONDecoder().decode([RecentTarget].self, from: data) {
            recentTargets = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
            return
        }
        // Old format: array of legacy `OpenTarget` (no initialFile, no .empty).
        if let legacy = try? JSONDecoder().decode([LegacyOpenTarget].self, from: data) {
            recentTargets = legacy
                .compactMap { $0.recent }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            saveRecentTargets()
        }
    }

    private func saveRecentTargets() {
        if let data = try? JSONEncoder().encode(recentTargets) {
            UserDefaults.standard.set(data, forKey: Self.recentTargetsKey)
        }
    }
}

/// Decoder shim for old `recentTargets` UserDefaults data, which serialized
/// `OpenTarget` before it gained `initialFile` and `.empty`.
private enum LegacyOpenTarget: Codable {
    case file(path: String)
    case directory(path: String)

    var recent: RecentTarget {
        switch self {
        case .file(let p): .file(path: p)
        case .directory(let p): .directory(path: p)
        }
    }
}
