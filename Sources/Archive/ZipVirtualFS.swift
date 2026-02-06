import Foundation
import ZIPFoundation

/// Virtual file system backed by a ZIP archive, serving files from memory with LRU cache.
actor ZipVirtualFS {
    private let archive: Archive
    private let cache: LRUCache
    private let entries: [String: Entry]

    init(url: URL, cacheSize: Int = 100 * 1024 * 1024) throws {
        self.archive = try Archive(url: url, accessMode: .read)
        self.cache = LRUCache(maxSize: cacheSize)

        // Index entries by path
        var indexed: [String: Entry] = [:]
        for entry in archive {
            guard entry.type == .file else { continue }
            let path = entry.path
            // Normalize: strip leading ./
            let normalized = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
            indexed[normalized] = entry
        }
        self.entries = indexed

        // Pre-caching done lazily via preCacheReadme() call after init
    }

    /// Pre-cache common README files. Call after init.
    func preCacheReadme() async {
        for name in ["README.md", "readme.md", "index.md"] {
            if entries[name] != nil {
                _ = await readFile(name)
            }
        }
    }

    func listFiles() -> [FileEntry] {
        entries.keys.sorted().map { path in
            let entry = entries[path]!
            let name = (path as NSString).lastPathComponent
            return FileEntry(
                id: path,
                name: name,
                relativePath: path,
                absolutePath: "",
                size: Int(entry.uncompressedSize),
                modifiedDate: entry.fileAttributes[.modificationDate] as? Date ?? Date.distantPast,
                isMarkdown: isMarkdownFile(name)
            )
        }
    }

    func listMarkdownFiles() -> [FileEntry] {
        listFiles().filter { isMarkdownFile($0.name) }
    }

    func readFile(_ path: String) async -> String? {
        // Check cache first
        if let cached = await cache.get(path) {
            return String(data: cached, encoding: .utf8)
        }

        guard let entry = entries[path] else { return nil }

        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
        } catch {
            return nil
        }

        await cache.set(path, data: data)
        return String(data: data, encoding: .utf8)
    }

    func exists(_ path: String) -> Bool {
        entries[path] != nil
    }

    func searchInFiles(query: String, filter: FileFilter) async -> [SearchResult] {
        let lowQuery = query.lowercased()
        var results: [SearchResult] = []

        let filesToSearch: [String]
        switch filter {
        case .markdownOnly:
            filesToSearch = entries.keys.filter { isMarkdownFile($0) }
        case .allFiles:
            filesToSearch = Array(entries.keys)
        }

        for path in filesToSearch.sorted() {
            guard let content = await readFile(path) else { continue }
            let lines = content.components(separatedBy: "\n")
            var matches: [SearchMatch] = []

            for (index, line) in lines.enumerated() {
                guard line.lowercased().contains(lowQuery) else { continue }

                var contextLines: [ContextLine] = []

                if index > 0 {
                    contextLines.append(ContextLine(
                        lineNumber: index,
                        text: String(lines[index - 1].prefix(Constants.searchLineTrim)),
                        isMatch: false
                    ))
                }

                contextLines.append(ContextLine(
                    lineNumber: index + 1,
                    text: String(line.trimmingCharacters(in: .whitespaces).prefix(Constants.searchLineTrim)),
                    isMatch: true
                ))

                if index < lines.count - 1 {
                    contextLines.append(ContextLine(
                        lineNumber: index + 2,
                        text: String(lines[index + 1].prefix(Constants.searchLineTrim)),
                        isMatch: false
                    ))
                }

                matches.append(SearchMatch(
                    lineNumber: index + 1,
                    text: String(line.trimmingCharacters(in: .whitespaces).prefix(Constants.searchLineTrim)),
                    contextLines: contextLines
                ))

                if matches.count >= Constants.searchMaxMatches { break }
            }

            if !matches.isEmpty {
                let name = (path as NSString).lastPathComponent
                let directory = (path as NSString).deletingLastPathComponent
                results.append(SearchResult(
                    path: path,
                    fileName: name,
                    directory: directory.isEmpty ? "/" : directory,
                    matches: matches
                ))
            }
        }

        return results
    }

    var fileCount: Int { entries.count }
    var markdownFileCount: Int { entries.keys.filter { isMarkdownFile($0) }.count }
}
