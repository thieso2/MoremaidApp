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

            // Deduplicate: if an event for the same path already exists, update and move to top
            if let existingIndex = events.firstIndex(where: { $0.fileEntry.absolutePath == path }) {
                let existing = events[existingIndex]
                let updated = ActivityEvent(
                    id: existing.id,
                    fileEntry: fileEntry,
                    changeType: existing.changeType == .created ? .created : changeType,
                    detectedAt: Date(),
                    isSeen: false,
                    updateCount: existing.updateCount + 1
                )
                events.remove(at: existingIndex)
                events.insert(updated, at: 0)
                knownPaths.insert(path)
                continue
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
            events[index].isSeen = true
        }
    }

    func markSeenByPath(_ path: String) {
        for (index, event) in events.enumerated() where event.fileEntry.absolutePath == path && !event.isSeen {
            events[index].isSeen = true
        }
    }

    func markAllSeen() {
        for index in events.indices where !events[index].isSeen {
            events[index].isSeen = true
        }
    }

    func dismiss(id: UUID) {
        events.removeAll { $0.id == id }
    }

    func clear() {
        events.removeAll()
    }
}
