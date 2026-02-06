import Foundation

// MARK: - Project

@Observable
final class Project: Identifiable, Codable, @unchecked Sendable {
    let id: UUID
    var name: String
    var path: String
    var addedDate: Date
    var isActive: Bool
    var themeOverride: String?
    var typographyOverride: String?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        addedDate: Date = Date(),
        isActive: Bool = true,
        themeOverride: String? = nil,
        typographyOverride: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.addedDate = addedDate
        self.isActive = isActive
        self.themeOverride = themeOverride
        self.typographyOverride = typographyOverride
    }

    enum CodingKeys: String, CodingKey {
        case id, name, path, addedDate, isActive, themeOverride, typographyOverride
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        addedDate = try container.decode(Date.self, forKey: .addedDate)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        themeOverride = try container.decodeIfPresent(String.self, forKey: .themeOverride)
        typographyOverride = try container.decodeIfPresent(String.self, forKey: .typographyOverride)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(addedDate, forKey: .addedDate)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(themeOverride, forKey: .themeOverride)
        try container.encodeIfPresent(typographyOverride, forKey: .typographyOverride)
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
