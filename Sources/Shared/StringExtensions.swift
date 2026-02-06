import Foundation

extension String {
    /// Escapes the string for safe embedding in HTML content.
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Escapes the string as a JSON string literal (with surrounding quotes).
    /// Safe for embedding in `<script>` blocks.
    var jsonStringLiteral: String {
        let data = try? JSONEncoder().encode(self)
        if let data, let json = String(data: data, encoding: .utf8) {
            return json
        }
        // Fallback: manual escape
        let escaped = self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "</", with: "<\\/") // prevent script tag injection
        return "\"\(escaped)\""
    }
}
