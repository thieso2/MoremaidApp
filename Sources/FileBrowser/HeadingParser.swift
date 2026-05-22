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
        if isHTMLFile(path) {
            return extractHeadings(fromHTML: content)
        }
        return extractHeadings(from: content)
    }

    static func extractHeadings(from content: String, fileName: String) -> [WebViewStore.HeadingEntry] {
        if isHTMLFile(fileName) {
            return extractHeadings(fromHTML: content)
        }
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

    static func extractHeadings(fromHTML html: String) -> [WebViewStore.HeadingEntry] {
        let structuralHTML = firstTagBody("main", in: html)
            ?? removeBlocks(["aside", "nav", "header", "footer"], from: html)
        let cleanedHTML = removeBlocks(["script", "style", "pre"], from: structuralHTML)
        guard let regex = try? NSRegularExpression(
            pattern: #"<h([1-6])\b([^>]*)>(.*?)</h\1\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let nsHTML = cleanedHTML as NSString
        let matches = regex.matches(
            in: cleanedHTML,
            range: NSRange(location: 0, length: nsHTML.length)
        )
        var idCounts: [String: Int] = [:]
        var results: [WebViewStore.HeadingEntry] = []

        for match in matches {
            guard match.numberOfRanges >= 4,
                  let levelRange = Range(match.range(at: 1), in: cleanedHTML),
                  let attrsRange = Range(match.range(at: 2), in: cleanedHTML),
                  let bodyRange = Range(match.range(at: 3), in: cleanedHTML),
                  let level = Int(cleanedHTML[levelRange]) else { continue }

            let attrs = String(cleanedHTML[attrsRange])
            let body = String(cleanedHTML[bodyRange])
            let text = normalizeHTMLText(stripHTMLTags(body))
            guard !text.isEmpty else { continue }

            let existingID = extractHTMLAttribute("id", from: attrs)
            let id: String
            if let existingID, !existingID.isEmpty {
                id = existingID
                idCounts[id, default: 0] += 1
            } else {
                let slug = slugify(text)
                let base = slug.isEmpty ? "heading" : slug
                id = uniqueID(base: base, counts: &idCounts)
            }
            results.append(.init(level: level, text: text, id: id))
        }

        return results
    }

    // MARK: - Internals

    private static func firstTagBody(_ tag: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(tag)\b[^>]*>(.*?)</\#(tag)\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let nsHTML = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private static func removeBlocks(_ tags: [String], from html: String) -> String {
        var result = html
        for tag in tags {
            result = result.replacingOccurrences(
                of: #"(?is)<\#(tag)\b[^>]*>.*?</\#(tag)\s*>"#,
                with: "",
                options: .regularExpression
            )
        }
        return result
    }

    private static func stripHTMLTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func normalizeHTMLText(_ text: String) -> String {
        decodeHTMLEntities(text)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractHTMLAttribute(_ name: String, from attrs: String) -> String? {
        let pattern = #"\b\#(name)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsAttrs = attrs as NSString
        guard let match = regex.firstMatch(in: attrs, range: NSRange(location: 0, length: nsAttrs.length)) else {
            return nil
        }
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location != NSNotFound {
                return decodeHTMLEntities(nsAttrs.substring(with: range))
            }
        }
        return nil
    }

    private static func uniqueID(base: String, counts: inout [String: Int]) -> String {
        if let existing = counts[base] {
            counts[base] = existing + 1
            return "\(base)-\(existing)"
        }
        counts[base] = 1
        return base
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&", let semi = text[index...].firstIndex(of: ";") {
                let entityStart = text.index(after: index)
                let entity = String(text[entityStart..<semi])
                if let decoded = decodeHTMLEntity(entity) {
                    result.append(decoded)
                    index = text.index(after: semi)
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func decodeHTMLEntity(_ entity: String) -> String? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#39": return "'"
        case "nbsp": return " "
        default:
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                let hex = entity.dropFirst(2)
                if let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) {
                    return String(scalar)
                }
            } else if entity.hasPrefix("#") {
                let decimal = entity.dropFirst()
                if let value = UInt32(decimal), let scalar = UnicodeScalar(value) {
                    return String(scalar)
                }
            }
            return nil
        }
    }

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
