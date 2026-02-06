import Foundation

struct ValidationError: Sendable {
    enum ErrorType: String, Sendable {
        case mermaid
        case markdown
        case file
    }

    let type: ErrorType
    let line: Int?
    let message: String
}

struct ValidationStats: Sendable {
    var markdownErrors: Int = 0
    var mermaidErrors: Int = 0
    var mermaidBlocksChecked: Int = 0
}

struct FileValidationResult: Sendable {
    let path: String
    let errors: [ValidationError]
    let stats: ValidationStats
}

struct ValidationResult: Sendable {
    var files: [FileValidationResult] = []
    var totalStats = TotalStats()

    struct TotalStats: Sendable {
        var filesChecked: Int = 0
        var filesWithErrors: Int = 0
        var markdownErrors: Int = 0
        var mermaidErrors: Int = 0
        var mermaidBlocksChecked: Int = 0
    }
}

/// Port of validator.js — validates Mermaid syntax in markdown files.
enum MermaidValidator {

    struct MermaidBlock {
        let content: String
        let lineNumber: Int
    }

    /// Extract mermaid code blocks from markdown content.
    static func extractMermaidBlocks(from markdown: String) -> [MermaidBlock] {
        var blocks: [MermaidBlock] = []
        let pattern = "```mermaid\\n([\\s\\S]*?)```"

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsMarkdown = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let contentRange = match.range(at: 1)
            let content = nsMarkdown.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = nsMarkdown.substring(to: match.range.location)
            let lineNumber = prefix.components(separatedBy: "\n").count

            blocks.append(MermaidBlock(content: content, lineNumber: lineNumber))
        }

        return blocks
    }

    /// Validate a single mermaid code block.
    static func validate(mermaidCode: String, lineNumber: Int) -> [ValidationError] {
        var errors: [ValidationError] = []
        let lines = mermaidCode.components(separatedBy: "\n")

        // Check empty
        if mermaidCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(ValidationError(type: .mermaid, line: lineNumber, message: "Empty Mermaid block"))
            return errors
        }

        // Check diagram type
        let firstLine = lines[0].trimmingCharacters(in: .whitespaces)
        let validTypes = [
            "graph", "flowchart", "sequenceDiagram", "classDiagram",
            "stateDiagram", "stateDiagram-v2", "erDiagram", "journey",
            "gantt", "pie", "quadrantChart", "requirementDiagram",
            "gitGraph", "mindmap", "timeline", "zenuml", "sankey-beta"
        ]

        let hasValidType = validTypes.contains { firstLine.hasPrefix($0) }
        if !hasValidType {
            errors.append(ValidationError(
                type: .mermaid,
                line: lineNumber,
                message: "Unknown or missing diagram type. First line: \"\(firstLine)\""
            ))
        }

        // Check bracket matching
        let openBrackets: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
        let closeBrackets: Set<Character> = [")", "]", "}"]
        var stack: [(expected: Character, position: Int)] = []

        for (i, char) in mermaidCode.enumerated() {
            if let closing = openBrackets[char] {
                stack.append((closing, i))
            } else if closeBrackets.contains(char) {
                if stack.isEmpty || stack.last?.expected != char {
                    let lineNum = mermaidCode.prefix(i).components(separatedBy: "\n").count
                    errors.append(ValidationError(
                        type: .mermaid,
                        line: lineNumber + lineNum - 1,
                        message: "Unmatched closing bracket '\(char)'"
                    ))
                } else {
                    stack.removeLast()
                }
            }
        }

        if !stack.isEmpty {
            errors.append(ValidationError(
                type: .mermaid,
                line: lineNumber,
                message: "\(stack.count) unclosed bracket(s)"
            ))
        }

        // Flowchart-specific checks
        if firstLine.hasPrefix("flowchart") || firstLine.hasPrefix("graph") {
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("%%") { continue }

                // Check for node labels starting with /
                checkNodeLabels(line: trimmed, lineNumber: lineNumber + i, errors: &errors)
            }
        }

        return errors
    }

    private static func checkNodeLabels(line: String, lineNumber: Int, errors: inout [ValidationError]) {
        let pattern = "(\\w+)\\[([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let label = nsLine.substring(with: match.range(at: 2))

            if label.trimmingCharacters(in: .whitespaces).hasPrefix("/") {
                let preview = String(label.prefix(30))
                errors.append(ValidationError(
                    type: .mermaid,
                    line: lineNumber,
                    message: "Node label starts with '/': \"\(preview)...\" - this may cause lexical errors"
                ))
            }

            let slashCount = label.filter { $0 == "/" }.count
            if slashCount >= 2 && !label.contains("\\/") {
                let preview = String(label.prefix(30))
                errors.append(ValidationError(
                    type: .mermaid,
                    line: lineNumber,
                    message: "Multiple unescaped slashes in label may cause parsing issues: \"\(preview)...\""
                ))
            }
        }
    }

    /// Validate a markdown file at the given path.
    static func validateFile(at path: String) -> FileValidationResult {
        var errors: [ValidationError] = []
        var stats = ValidationStats()

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            errors.append(ValidationError(type: .file, line: nil, message: "Cannot read file"))
            return FileValidationResult(path: path, errors: errors, stats: stats)
        }

        // Extract and validate mermaid blocks
        let blocks = extractMermaidBlocks(from: content)
        stats.mermaidBlocksChecked = blocks.count

        for block in blocks {
            let blockErrors = validate(mermaidCode: block.content, lineNumber: block.lineNumber)
            for error in blockErrors {
                errors.append(error)
                stats.mermaidErrors += 1
            }
        }

        return FileValidationResult(path: path, errors: errors, stats: stats)
    }

    /// Validate all markdown files in a directory.
    static func validateDirectory(at path: String) -> ValidationResult {
        var result = ValidationResult()
        let files = FileScanner.scan(directory: path, filter: .markdownOnly)

        for file in files {
            result.totalStats.filesChecked += 1
            let fileResult = validateFile(at: file.absolutePath)
            result.files.append(fileResult)

            if !fileResult.errors.isEmpty {
                result.totalStats.filesWithErrors += 1
            }
            result.totalStats.markdownErrors += fileResult.stats.markdownErrors
            result.totalStats.mermaidErrors += fileResult.stats.mermaidErrors
            result.totalStats.mermaidBlocksChecked += fileResult.stats.mermaidBlocksChecked
        }

        return result
    }
}
