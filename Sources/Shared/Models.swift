import Foundation

// MARK: - Open Target

/// Identity of a window's content. Used as the value type for
/// `WindowGroup(for: OpenTarget.self)`, so SwiftUI handles state restoration
/// and "focus existing window with same value" automatically.
enum OpenTarget: Codable, Hashable, Sendable {
    case file(path: String)
    case directory(path: String, initialFile: String?)
    /// Empty placeholder window/tab — UUID makes each instance unique so
    /// `openWindow(value:)` opens a fresh window every time ⌘T / ⌘N is pressed.
    case empty(id: UUID)

    var path: String? {
        switch self {
        case .file(let path): path
        case .directory(let path, _): path
        case .empty: nil
        }
    }

    var displayName: String {
        switch self {
        case .file(let path), .directory(let path, _):
            return (path as NSString).lastPathComponent
        case .empty:
            return "Untitled"
        }
    }

    static func directory(path: String) -> OpenTarget {
        .directory(path: path, initialFile: nil)
    }

    static func newEmpty() -> OpenTarget {
        .empty(id: UUID())
    }
}

// MARK: - Recent Target

/// Stable identity of a recently-opened item. Persisted to UserDefaults; we
/// keep it separate from `OpenTarget` so adding new associated values to
/// `OpenTarget` doesn't break existing user data.
enum RecentTarget: Codable, Hashable, Sendable {
    case file(path: String)
    case directory(path: String)

    var path: String {
        switch self {
        case .file(let path), .directory(let path): path
        }
    }

    var openTarget: OpenTarget {
        switch self {
        case .file(let path): .file(path: path)
        case .directory(let path): .directory(path: path, initialFile: nil)
        }
    }
}

extension OpenTarget {
    var recent: RecentTarget? {
        switch self {
        case .file(let path): .file(path: path)
        case .directory(let path, _): .directory(path: path)
        case .empty: nil
        }
    }
}

// MARK: - File Entry

struct FileEntry: Identifiable, Hashable, Sendable {
    let id: String // relative path from project root
    let name: String
    let relativePath: String
    let absolutePath: String
    let size: Int
    let modifiedDate: Date
    let isMarkdown: Bool

    var directory: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir == "." ? "" : dir
    }
}

// MARK: - Sort Method

enum SortMethod: String, CaseIterable, Sendable {
    case nameAsc = "name-asc"
    case nameDesc = "name-desc"
    case dateDesc = "date-desc"
    case dateAsc = "date-asc"
    case sizeDesc = "size-desc"
    case sizeAsc = "size-asc"

    var label: String {
        switch self {
        case .nameAsc: "Name (A→Z)"
        case .nameDesc: "Name (Z→A)"
        case .dateDesc: "Newest First"
        case .dateAsc: "Oldest First"
        case .sizeDesc: "Largest First"
        case .sizeAsc: "Smallest First"
        }
    }

    func sort(_ files: [FileEntry]) -> [FileEntry] {
        switch self {
        case .nameAsc: files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        case .nameDesc: files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedDescending }
        case .dateDesc: files.sorted { $0.modifiedDate > $1.modifiedDate }
        case .dateAsc: files.sorted { $0.modifiedDate < $1.modifiedDate }
        case .sizeDesc: files.sorted { $0.size > $1.size }
        case .sizeAsc: files.sorted { $0.size < $1.size }
        }
    }
}

// MARK: - Sidebar Sort

enum SidebarSort: String, Sendable {
    case foldersFirst = "folders-first"
    case interleaved = "interleaved"
}

// MARK: - Search Mode

enum SearchMode: String, Sendable {
    case filename
    case content
}

// MARK: - Activity Event

struct ActivityEvent: Identifiable, Sendable {
    let id: UUID
    let fileEntry: FileEntry
    let changeType: ChangeType
    var detectedAt: Date
    var isSeen: Bool
    var updateCount: Int = 1

    enum ChangeType: String, Sendable {
        case created
        case modified
    }
}

// MARK: - File Filter

enum FileFilter: String, Sendable {
    case markdownOnly = "*.md"
    case allFiles = "*"

    var label: String {
        switch self {
        case .markdownOnly: "Markdown Only"
        case .allFiles: "All Files"
        }
    }

    func matches(_ entry: FileEntry) -> Bool {
        switch self {
        case .markdownOnly: entry.isMarkdown
        case .allFiles: true
        }
    }
}
