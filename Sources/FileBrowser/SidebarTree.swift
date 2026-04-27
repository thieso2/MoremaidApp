import Foundation

/// A node in the sidebar outline tree.
/// Folders contain children; files are leaves at the file level (their headings live
/// in a separate cache and are attached at render time, not in the model).
enum SidebarNode: Identifiable, Hashable {
    case folder(path: String, name: String, children: [SidebarNode])
    case file(FileEntry)

    var id: String {
        switch self {
        case .folder(let path, _, _): return "dir:\(path)"
        case .file(let entry): return "file:\(entry.relativePath)"
        }
    }

    var name: String {
        switch self {
        case .folder(_, let name, _): return name
        case .file(let entry): return entry.name
        }
    }

    /// Path used for expanded-state persistence — folders use their relative path,
    /// files use their relative path so we can remember per-file expansion.
    var persistencePath: String {
        switch self {
        case .folder(let path, _, _): return path
        case .file(let entry): return entry.relativePath
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}

/// Builds a hierarchical SidebarNode tree from a flat list of FileEntry.
/// Empty folders (after filtering) are pruned automatically because we only
/// add folder nodes that contain at least one descendant file.
enum SidebarTreeBuilder {
    static func build(files: [FileEntry], sort: SidebarSort) -> [SidebarNode] {
        // Mutable intermediate node — we build the tree imperatively, then convert
        // to immutable enum cases.
        final class MutableFolder {
            let path: String
            let name: String
            var subfolders: [String: MutableFolder] = [:]
            var files: [FileEntry] = []
            init(path: String, name: String) {
                self.path = path
                self.name = name
            }
        }

        let root = MutableFolder(path: "", name: "")

        for file in files {
            let components = file.relativePath.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            // Walk/build folders for everything but the last component (the file).
            var current = root
            if components.count > 1 {
                for i in 0..<(components.count - 1) {
                    let segment = components[i]
                    let segPath = components[0...i].joined(separator: "/")
                    if let existing = current.subfolders[segment] {
                        current = existing
                    } else {
                        let folder = MutableFolder(path: segPath, name: segment)
                        current.subfolders[segment] = folder
                        current = folder
                    }
                }
            }
            current.files.append(file)
        }

        func convert(_ folder: MutableFolder) -> [SidebarNode] {
            let folderNodes: [SidebarNode] = folder.subfolders.values.map { sub in
                SidebarNode.folder(path: sub.path, name: sub.name, children: convert(sub))
            }
            let fileNodes: [SidebarNode] = folder.files.map { SidebarNode.file($0) }

            switch sort {
            case .foldersFirst:
                let sortedFolders = folderNodes.sorted { lhs, rhs in
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                let sortedFiles = fileNodes.sorted { lhs, rhs in
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return sortedFolders + sortedFiles
            case .interleaved:
                return (folderNodes + fileNodes).sorted { lhs, rhs in
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
        }

        return convert(root)
    }

    /// Walk the tree and return the persistence paths of every ancestor folder
    /// containing the given file (so we can auto-expand them on selection).
    static func ancestorFolderPaths(for file: FileEntry) -> [String] {
        let components = file.relativePath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return [] }
        var paths: [String] = []
        for i in 0..<(components.count - 1) {
            paths.append(components[0...i].joined(separator: "/"))
        }
        return paths
    }
}
