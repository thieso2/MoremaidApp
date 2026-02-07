import Foundation

/// Main entry point for generating HTML pages.
enum HTMLGenerator {
    /// Generates a full HTML page for rendering markdown content.
    static func markdownPage(
        content: String,
        title: String,
        searchQuery: String? = nil,
        modifiedDate: Date? = nil,
        fileSize: Int? = nil,
        theme: String = Constants.defaultTheme,
        typography: String = Constants.defaultTypography
    ) -> String {
        let escapedTitle = title.htmlEscaped
        let rawMarkdownJSON = content.jsonStringLiteral
        let themeJS = "'\(theme)'"
        let searchJS = searchQuery.map { $0.jsonStringLiteral } ?? "null"

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
            <script src="https://cdn.jsdelivr.net/npm/marked-gfm-heading-id/lib/index.umd.js"></script>
            <style>
        \(ThemeCSS.all)
        \(TypographyCSS.all)
        \(BaseCSS.all)
            </style>
        </head>
        <body data-typography="\(typography)" style="padding: 30px;">
            <div id="content"></div>
            <script>
        \(PageScripts.markdownScripts(
            rawMarkdownJSON: rawMarkdownJSON,
            titleJSON: title.jsonStringLiteral,
            forceThemeJS: themeJS,
            searchQueryJS: searchJS
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
        modifiedDate: Date? = nil,
        fileSize: Int? = nil,
        theme: String = Constants.defaultTheme,
        typography: String = Constants.defaultTypography
    ) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let language = LanguageMaps.extensionToLanguage[ext] ?? "plaintext"
        let escapedContent = content.htmlEscaped
        let escapedTitle = fileName.htmlEscaped
        let themeJS = "'\(theme)'"

        let isDark = Constants.darkThemes.contains(theme)
        let prismTheme = isDark ? "prism-tomorrow" : "prism"

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
        <body data-typography="\(typography)" style="padding: 30px;">
            <pre><code class="language-\(language)">\(escapedContent)</code></pre>
            <script>
        \(PageScripts.codePageScripts(forceThemeJS: themeJS))
            </script>
        </body>
        </html>
        """
    }
}
