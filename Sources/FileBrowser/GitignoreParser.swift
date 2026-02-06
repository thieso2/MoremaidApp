import Foundation

/// Simple .gitignore pattern matcher.
/// Supports basic patterns: wildcards, directory markers, negation.
struct GitignoreParser: Sendable {
    private let patterns: [Pattern]

    struct Pattern: @unchecked Sendable {
        let regex: Regex<AnyRegexOutput>
        let isNegation: Bool
        let isDirectoryOnly: Bool
    }

    init(basePath: String) {
        let gitignorePath = (basePath as NSString).appendingPathComponent(".gitignore")
        guard let content = try? String(contentsOfFile: gitignorePath, encoding: .utf8) else {
            self.patterns = []
            return
        }

        var parsed: [Pattern] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            var pattern = trimmed
            let isNegation = pattern.hasPrefix("!")
            if isNegation { pattern = String(pattern.dropFirst()) }

            let isDirectoryOnly = pattern.hasSuffix("/")
            if isDirectoryOnly { pattern = String(pattern.dropLast()) }

            // Convert glob to regex and compile once
            let regexStr = Self.globToRegex(pattern)
            guard let compiled = try? Regex(regexStr) else { continue }
            parsed.append(Pattern(regex: compiled, isNegation: isNegation, isDirectoryOnly: isDirectoryOnly))
        }

        self.patterns = parsed
    }

    func isIgnored(_ relativePath: String) -> Bool {
        var ignored = false
        for pattern in patterns {
            if relativePath.contains(pattern.regex) {
                ignored = !pattern.isNegation
            }
        }
        return ignored
    }

    private static func globToRegex(_ glob: String) -> String {
        var regex = ""
        var i = glob.startIndex

        // If pattern doesn't contain /, match against filename only
        let matchFullPath = glob.contains("/")

        if !matchFullPath {
            regex += "(^|/)"
        } else {
            regex += "^"
        }

        while i < glob.endIndex {
            let c = glob[i]
            switch c {
            case "*":
                let next = glob.index(after: i)
                if next < glob.endIndex && glob[next] == "*" {
                    // ** matches everything including /
                    regex += ".*"
                    i = glob.index(after: next)
                    if i < glob.endIndex && glob[i] == "/" {
                        i = glob.index(after: i) // skip trailing /
                    }
                    continue
                } else {
                    regex += "[^/]*"
                }
            case "?":
                regex += "[^/]"
            case ".":
                regex += "\\."
            case "/":
                regex += "/"
            default:
                regex += String(c)
            }
            i = glob.index(after: i)
        }

        regex += "(/|$)"
        return regex
    }
}
