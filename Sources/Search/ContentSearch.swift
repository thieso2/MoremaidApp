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
