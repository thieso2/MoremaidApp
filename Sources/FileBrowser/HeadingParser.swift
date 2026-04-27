import Foundation

/// Extracts a markdown file's headings (level + text + slug) without rendering
/// it in a WebView. The slug logic mirrors `PageScripts.slugify` so the IDs
/// produced here match the ones generated client-side, which means clicks
/// from the sidebar resolve to anchors that actually exist on the rendered
/// page.
///
/// JS reference (Sources/Rendering/PageScripts.swift):
///   s.toLowerCase()
///    .replace(/[^\w\s-]/g, '')
///    .replace(/\s+/g, '-')
///    .replace(/-+/g, '-')
///    .replace(/^-|-$/g, '')
/// where JS `\w` is `[A-Za-z0-9_]` (ASCII).
enum HeadingParser {
    static func extractHeadings(fromFileAtPath path: String) -> [WebViewStore.HeadingEntry] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return extractHeadings(from: content)
    }

    static func extractHeadings(from markdown: String) -> [WebViewStore.HeadingEntry] {
        var inFence = false
        var fenceMarker: Character = "`"
        var fenceCount = 0
        var idCounts: [String: Int] = [:]
        var results: [WebViewStore.HeadingEntry] = []

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let fence = matchFence(line) {
                if !inFence {
                    inFence = true
                    fenceMarker = fence.marker
                    fenceCount = fence.count
                } else if fence.marker == fenceMarker && fence.count >= fenceCount {
                    inFence = false
                }
                continue
            }
            if inFence { continue }

            guard let (level, text) = parseHeading(line) else { continue }

            let base = slugify(text)
            let id: String
            if let existing = idCounts[base] {
                id = "\(base)-\(existing)"
                idCounts[base] = existing + 1
            } else {
                id = base
                idCounts[base] = 1
            }
            results.append(.init(level: level, text: text, id: id))
        }
        return results
    }

    static func slugify(_ s: String) -> String {
        let lower = s.lowercased()
        var stripped = ""
        stripped.reserveCapacity(lower.count)
        for ch in lower {
            // Match JS `[^\w\s-]` removal: keep ASCII a-z 0-9 _, whitespace, and -.
            if let scalar = ch.unicodeScalars.first {
                let v = scalar.value
                let isASCIILetter = v >= 0x61 && v <= 0x7A
                let isDigit = v >= 0x30 && v <= 0x39
                let isUnderscore = v == 0x5F
                let isHyphen = v == 0x2D
                let isWhitespace = v == 0x20 || v == 0x09 || v == 0x0A || v == 0x0D
                if isASCIILetter || isDigit || isUnderscore || isHyphen || isWhitespace {
                    stripped.append(ch)
                }
            }
        }
        let dashed = stripped.replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        let collapsed = dashed.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: - Internals

    private static func parseHeading(_ line: String) -> (Int, String)? {
        // Allow up to 3 leading spaces (CommonMark). 4+ is a code block.
        var prefix = 0
        for ch in line {
            if ch == " " && prefix < 3 { prefix += 1 } else { break }
        }
        let trimmed = line.dropFirst(prefix)
        var level = 0
        for ch in trimmed {
            if ch == "#" && level < 6 { level += 1 } else { break }
        }
        guard level >= 1 else { return nil }
        let after = trimmed.dropFirst(level)
        // Must be followed by a space/tab or end of line; "###foo" is not a heading.
        if let first = after.first, first != " " && first != "\t" { return nil }
        var text = after.trimmingCharacters(in: .whitespaces)
        // Strip optional CommonMark trailing #s.
        while text.hasSuffix("#") { text = String(text.dropLast()) }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func matchFence(_ line: String) -> (marker: Character, count: Int)? {
        let trimmed = line.drop(while: { $0 == " " })
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        var count = 0
        for ch in trimmed {
            if ch == first { count += 1 } else { break }
        }
        return count >= 3 ? (first, count) : nil
    }
}
