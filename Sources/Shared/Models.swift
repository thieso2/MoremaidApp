import Foundation

// MARK: - Open Target

enum OpenTarget: Codable, Hashable {
    case file(path: String)
    case directory(path: String)

    var path: String {
        switch self {
        case .file(let path): path
        case .directory(let path): path
        }
    }

    var displayName: String {
        (path as NSString).lastPathComponent
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

// MARK: - View Mode

enum ViewMode: String, Sendable {
    case flat
    case tree
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
