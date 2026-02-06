import Foundation

/// Main entry point for generating HTML pages.
/// Full implementation in Phase 3.
enum HTMLGenerator {
    /// Generates a full HTML page for rendering markdown content.
    static func markdownPage(
        content: String,
        title: String,
        forceTheme: String? = nil,
        searchQuery: String? = nil,
        modifiedDate: Date? = nil,
        fileSize: Int? = nil,
        projectID: UUID? = nil,
        embedded: Bool = false
    ) -> String {
        let escapedTitle = title.htmlEscaped
        let rawMarkdownJSON = content.jsonStringLiteral
        let themeJS = forceTheme.map { "'\($0)'" } ?? "null"
        let searchJS = searchQuery.map { $0.jsonStringLiteral } ?? "null"

        let fileInfoHTML: String
        let buttonsHTML: String
        if embedded {
            fileInfoHTML = ""
            buttonsHTML = ""
        } else {
            let modifiedDisplay = modifiedDate.map { formatTimeAgo($0) } ?? ""
            let modifiedFull = modifiedDate.map { formatFullDate($0) } ?? ""
            if !modifiedDisplay.isEmpty {
                fileInfoHTML = """
                <div class="file-info" title="\(modifiedFull.htmlEscaped)"><strong>\(escapedTitle)</strong> • Last modified: \(modifiedDisplay.htmlEscaped)</div>
                """
            } else {
                fileInfoHTML = ""
            }
            buttonsHTML = """
            <div class="file-buttons-container">
                <button id="copyButton" class="copy-file-btn" title="Copy raw markdown">Copy</button>
                <button id="downloadPdfButton" class="download-pdf-btn" title="Download as PDF">PDF</button>
            </div>
            """
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapedTitle)</title>
            <script src="https://cdn.jsdelivr.net/npm/mermaid@\(Constants.mermaidVersion)/dist/mermaid.min.js"></script>
            <link href="https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/themes/prism-tomorrow.min.css" rel="stylesheet" />
            <script src="https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/components/prism-core.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/plugins/autoloader/prism-autoloader.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            <style>
        \(ThemeCSS.all)
        \(TypographyCSS.all)
        \(BaseCSS.all)
            </style>
        </head>
        <body data-typography="default">
            <button class="controls-trigger">⚙</button>
            <div class="controls">
                <div class="zoom-control">
                    <button id="zoomOut" title="Zoom out">−</button>
                    <span class="zoom-value" id="zoomValue">100%</span>
                    <button id="zoomIn" title="Zoom in">+</button>
                    <button id="zoomReset" title="Reset zoom">⟲</button>
                </div>
                <select id="themeSelector" title="Select color theme">
                    <option value="light">☀️ Light</option>
                    <option value="dark">🌙 Dark</option>
                    <option value="github">📘 GitHub</option>
                    <option value="github-dark">📕 GitHub Dark</option>
                    <option value="dracula">🧛 Dracula</option>
                    <option value="nord">❄️ Nord</option>
                    <option value="solarized-light">🌅 Solarized Light</option>
                    <option value="solarized-dark">🌃 Solarized Dark</option>
                    <option value="monokai">🎨 Monokai</option>
                    <option value="one-dark">🌑 One Dark</option>
                </select>
                <select id="typographySelector" title="Select typography theme">
                    <option value="default">Default</option>
                    <option value="github">GitHub</option>
                    <option value="latex">LaTeX</option>
                    <option value="tufte">Tufte</option>
                    <option value="medium">Medium</option>
                    <option value="compact">Compact</option>
                    <option value="wide">Wide</option>
                    <option value="newspaper">Newspaper</option>
                    <option value="terminal">Terminal</option>
                    <option value="book">Book</option>
                </select>
            </div>
            \(buttonsHTML)
            <div class="zoom-container" id="zoomContainer">
                <div class="container">
                    \(fileInfoHTML)
                    <div id="content"></div>
                </div>
            </div>
            <script>
        \(PageScripts.allScripts(
            rawMarkdownJSON: rawMarkdownJSON,
            titleJSON: title.jsonStringLiteral,
            forceThemeJS: themeJS,
            searchQueryJS: searchJS,
            isServer: true
        ))
            </script>
        </body>
        </html>
        """
    }

    /// Generates a syntax-highlighted code view for non-markdown files.
    static func codePage(
        content: String,
        fileName: String,
        forceTheme: String? = nil,
        modifiedDate: Date? = nil,
        fileSize: Int? = nil,
        embedded: Bool = false
    ) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let language = LanguageMaps.extensionToLanguage[ext] ?? "plaintext"
        let escapedContent = content.htmlEscaped
        let escapedTitle = fileName.htmlEscaped
        let themeJS = forceTheme.map { "'\($0)'" } ?? "null"

        let isDark = forceTheme.map { Constants.darkThemes.contains($0) } ?? false
        let prismTheme = isDark ? "prism-tomorrow" : "prism"

        let fileInfoHTML: String
        let buttonsHTML: String
        if embedded {
            fileInfoHTML = ""
            buttonsHTML = ""
        } else {
            let modifiedDisplay = modifiedDate.map { formatTimeAgo($0) } ?? ""
            let modifiedFull = modifiedDate.map { formatFullDate($0) } ?? ""
            if !modifiedDisplay.isEmpty {
                fileInfoHTML = """
                <div class="file-info" title="\(modifiedFull.htmlEscaped)"><strong>\(escapedTitle)</strong> • Last modified: \(modifiedDisplay.htmlEscaped)</div>
                """
            } else {
                fileInfoHTML = ""
            }
            buttonsHTML = """
            <div class="file-buttons-container">
                <button id="copyButton" class="copy-file-btn" title="Copy file content">Copy</button>
            </div>
            """
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapedTitle)</title>
            <link href="https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/themes/\(prismTheme).min.css" rel="stylesheet" />
            <script src="https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/components/prism-core.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/plugins/autoloader/prism-autoloader.min.js"></script>
            <style>
        \(ThemeCSS.all)
        \(TypographyCSS.all)
        \(BaseCSS.all)
            </style>
        </head>
        <body data-typography="default">
            <button class="controls-trigger">⚙</button>
            <div class="controls">
                <div class="zoom-control">
                    <button id="zoomOut" title="Zoom out">−</button>
                    <span class="zoom-value" id="zoomValue">100%</span>
                    <button id="zoomIn" title="Zoom in">+</button>
                    <button id="zoomReset" title="Reset zoom">⟲</button>
                </div>
                <select id="themeSelector" title="Select color theme">
                    <option value="light">☀️ Light</option>
                    <option value="dark">🌙 Dark</option>
                    <option value="github">📘 GitHub</option>
                    <option value="github-dark">📕 GitHub Dark</option>
                    <option value="dracula">🧛 Dracula</option>
                    <option value="nord">❄️ Nord</option>
                    <option value="solarized-light">🌅 Solarized Light</option>
                    <option value="solarized-dark">🌃 Solarized Dark</option>
                    <option value="monokai">🎨 Monokai</option>
                    <option value="one-dark">🌑 One Dark</option>
                </select>
                <select id="typographySelector" title="Select typography theme">
                    <option value="default">Default</option>
                    <option value="github">GitHub</option>
                    <option value="latex">LaTeX</option>
                    <option value="tufte">Tufte</option>
                    <option value="medium">Medium</option>
                    <option value="compact">Compact</option>
                    <option value="wide">Wide</option>
                    <option value="newspaper">Newspaper</option>
                    <option value="terminal">Terminal</option>
                    <option value="book">Book</option>
                </select>
            </div>
            \(buttonsHTML)
            <div class="zoom-container" id="zoomContainer">
                <div class="container">
                    \(fileInfoHTML)
                    <pre><code class="language-\(language)">\(escapedContent)</code></pre>
                </div>
            </div>
            <script>
                var rawMarkdown = \(content.jsonStringLiteral);
                var documentTitle = \(fileName.jsonStringLiteral);
        \(PageScripts.codePageScripts(forceThemeJS: themeJS))
            </script>
        </body>
        </html>
        """
    }
}
