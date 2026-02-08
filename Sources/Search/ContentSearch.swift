import Foundation

/// Content search results, matching the Node.js JSON format.
struct SearchResult: Codable, Sendable {
    let path: String
    let fileName: String
    let directory: String
    let matches: [SearchMatch]?
}

struct SearchMatch: Codable, Sendable {
    let lineNumber: Int
    let text: String
    let contextLines: [ContextLine]?
}

struct ContextLine: Codable, Sendable {
    let lineNumber: Int
    let text: String
    let isMatch: Bool
}

/// Search implementation. Full fuzzy search in Phase 7.
enum ContentSearch {
    static func search(
        query: String,
        inProject projectPath: String,
        mode: SearchMode,
        filter: FileFilter
    ) -> [SearchResult] {
        let basePath = (projectPath as NSString).standardizingPath
        let files = FileScanner.scan(directory: basePath, filter: filter)

        switch mode {
        case .filename:
            return filenameSearch(query: query, files: files)
        case .content:
            return contentSearch(query: query, files: files, basePath: basePath)
        }
    }

    private static func filenameSearch(query: String, files: [FileEntry]) -> [SearchResult] {
        return FuzzyMatcher.search(query: query, files: files).map { file in
            SearchResult(
                path: file.relativePath,
                fileName: file.name,
                directory: file.directory,
                matches: nil
            )
        }
    }

    /// Search content across pre-scanned files (for search-in-files panel).
    /// Uses parallel I/O and case-insensitive range search for speed.
    static func searchContent(
        query: String,
        in files: [FileEntry],
        maxMatchesPerFile: Int = Constants.searchInFilesMaxMatches,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async -> [SearchResult] {
        let queryBytes = query.lowercased().utf8
        guard !queryBytes.isEmpty else { return [] }

        // Parallel search across files
        return await withTaskGroup(of: SearchResult?.self, returning: [SearchResult].self) { group in
            for file in files {
                group.addTask {
                    try? Task.checkCancellation()
                    return Self.searchSingleFile(file, query: query, maxMatches: maxMatchesPerFile)
                }
            }
            var results: [SearchResult] = []
            var completed = 0
            for await result in group {
                completed += 1
                if let result { results.append(result) }
                if completed % 10 == 0 || completed == files.count {
                    onProgress?(completed)
                }
            }
            // Sort by file path for stable ordering
            return results.sorted { $0.path < $1.path }
        }
    }

    /// Search a single file. Runs off main thread via TaskGroup.
    private static func searchSingleFile(
        _ file: FileEntry,
        query: String,
        maxMatches: Int
    ) -> SearchResult? {
        // Fast reject: read raw data and do a quick case-insensitive byte scan
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file.absolutePath)),
              data.count < 2_000_000 else { return nil } // skip files > 2MB

        guard let content = String(data: data, encoding: .utf8) else { return nil }

        // Quick whole-file check before splitting lines
        guard content.localizedCaseInsensitiveContains(query) else { return nil }

        let lines = content.components(separatedBy: "\n")
        var matches: [SearchMatch] = []

        for (index, line) in lines.enumerated() {
            guard line.localizedCaseInsensitiveContains(query) else { continue }

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

            if matches.count >= maxMatches { break }
        }

        guard !matches.isEmpty else { return nil }
        return SearchResult(
            path: file.relativePath,
            fileName: file.name,
            directory: file.directory,
            matches: matches
        )
    }

    private static func contentSearch(query: String, files: [FileEntry], basePath: String) -> [SearchResult] {
        let lowercaseQuery = query.lowercased()
        var results: [SearchResult] = []

        for file in files {
            guard let content = try? String(contentsOfFile: file.absolutePath, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n")
            var matches: [SearchMatch] = []

            for (index, line) in lines.enumerated() {
                guard line.lowercased().contains(lowercaseQuery) else { continue }

                var contextLines: [ContextLine] = []

                // Previous line
                if index > 0 {
                    contextLines.append(ContextLine(
                        lineNumber: index,
                        text: String(lines[index - 1].prefix(Constants.searchLineTrim)),
                        isMatch: false
                    ))
                }

                // Matching line
                contextLines.append(ContextLine(
                    lineNumber: index + 1,
                    text: String(line.trimmingCharacters(in: .whitespaces).prefix(Constants.searchLineTrim)),
                    isMatch: true
                ))

                // Next line
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
                results.append(SearchResult(
                    path: file.relativePath,
                    fileName: file.name,
                    directory: file.directory,
                    matches: matches
                ))
            }
        }

        return results
    }
}
