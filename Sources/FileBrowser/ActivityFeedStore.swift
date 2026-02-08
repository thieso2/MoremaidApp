import Foundation
import Observation

@Observable
@MainActor
final class ActivityFeedStore {
    var events: [ActivityEvent] = []
    var markdownOnly = false
    private var knownPaths: Set<String> = []

    var filteredEvents: [ActivityEvent] {
        if markdownOnly {
            return events.filter { $0.fileEntry.isMarkdown }
        }
        return events
    }

    var unseenCount: Int {
        filteredEvents.filter { !$0.isSeen }.count
    }

    var newCount: Int {
        filteredEvents.filter { $0.changeType == .created }.count
    }

    var updatedCount: Int {
        filteredEvents.filter { $0.changeType == .modified }.count
    }

    func seedKnownPaths(_ files: [FileEntry]) {
        knownPaths = Set(files.map(\.absolutePath))
    }

    func processFileChangeEvent(_ event: FileChangeEvent, makeEntry: (String) -> FileEntry?) {
        for path in event.paths {
            // Skip non-existent files (deletions)
            guard FileManager.default.fileExists(atPath: path) else { continue }

            // Skip directories
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            guard !isDir.boolValue else { continue }

            guard let fileEntry = makeEntry(path) else { continue }

            let changeType: ActivityEvent.ChangeType = knownPaths.contains(path) ? .modified : .created

            // Coalesce: if an unseen event for same path exists within the coalesce window, update it
            if let existingIndex = events.firstIndex(where: { $0.fileEntry.absolutePath == path && !$0.isSeen }) {
                let existing = events[existingIndex]
                if Date().timeIntervalSince(existing.detectedAt) < Constants.activityCoalesceWindow {
                    events[existingIndex] = ActivityEvent(
                        id: existing.id,
                        fileEntry: fileEntry,
                        changeType: existing.changeType == .created ? .created : changeType,
                        detectedAt: Date(),
                        isSeen: false
                    )
                    // Move to front
                    let updated = events.remove(at: existingIndex)
                    events.insert(updated, at: 0)
                    knownPaths.insert(path)
                    continue
                }
            }

            // New event
            let activityEvent = ActivityEvent(
                id: UUID(),
                fileEntry: fileEntry,
                changeType: changeType,
                detectedAt: Date(),
                isSeen: false
            )
            events.insert(activityEvent, at: 0)

            // Cap at max
            if events.count > Constants.activityFeedMaxEvents {
                events.removeLast(events.count - Constants.activityFeedMaxEvents)
            }

            knownPaths.insert(path)
        }
    }

    func markSeen(id: UUID) {
        if let index = events.firstIndex(where: { $0.id == id }) {
            events[index] = ActivityEvent(
                id: events[index].id,
                fileEntry: events[index].fileEntry,
                changeType: events[index].changeType,
                detectedAt: events[index].detectedAt,
                isSeen: true
            )
        }
    }

    func markSeenByPath(_ path: String) {
        for (index, event) in events.enumerated() where event.fileEntry.absolutePath == path && !event.isSeen {
            events[index] = ActivityEvent(
                id: event.id,
                fileEntry: event.fileEntry,
                changeType: event.changeType,
                detectedAt: event.detectedAt,
                isSeen: true
            )
        }
    }

    func markAllSeen() {
        for (index, event) in events.enumerated() where !event.isSeen {
            events[index] = ActivityEvent(
                id: event.id,
                fileEntry: event.fileEntry,
                changeType: event.changeType,
                detectedAt: event.detectedAt,
                isSeen: true
            )
        }
    }

    func dismiss(id: UUID) {
        events.removeAll { $0.id == id }
    }

    func clear() {
        events.removeAll()
    }
}
