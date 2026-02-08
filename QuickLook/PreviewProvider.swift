import QuickLookUI
import UniformTypeIdentifiers

/// QuickLook preview provider for Markdown files.
/// Renders markdown with Mermaid diagram and syntax highlighting support.
class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping (QLPreviewReply?, (any Error)?) -> Void
    ) {
        do {
            let data = try Data(contentsOf: request.fileURL)
            guard let content = String(data: data, encoding: .utf8) else {
                handler(nil, CocoaError(.fileReadUnknownStringEncoding))
                return
            }

            let html = Self.generateHTML(
                content: content,
                title: request.fileURL.lastPathComponent
            )

            let reply = QLPreviewReply(
                dataOfContentType: .html,
                contentSize: CGSize(width: 800, height: 800)
            ) { _ in
                Data(html.utf8)
            }
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }

    // MARK: - HTML Generation

    private static func generateHTML(content: String, title: String) -> String {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let bundle = Bundle(for: PreviewProvider.self)
        let markedJS = Self.loadResource("marked.min", ext: "js", bundle: bundle)
        let markedGfmJS = Self.loadResource("marked-gfm-heading-id.umd", ext: "js", bundle: bundle)
        let mermaidJS = Self.loadResource("mermaid.min", ext: "js", bundle: bundle)
        let prismCoreJS = Self.loadResource("prism-core.min", ext: "js", bundle: bundle)
        let prismAutoloaderJS = Self.loadResource("prism-autoloader.min", ext: "js", bundle: bundle)
        let prismCSS = Self.loadResource("prism-tomorrow.min", ext: "css", bundle: bundle)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapedTitle)</title>
            <style>\(prismCSS)</style>
            <script>\(prismCoreJS)</script>
            <script>\(prismAutoloaderJS)</script>
            <script>\(markedJS)</script>
            <script>\(markedGfmJS)</script>
            <script>\(mermaidJS)</script>
            <style>\(quickLookCSS)</style>
        </head>
        <body>
            <div id="content"></div>
            <script>
            var rawMarkdown = `\(escaped)`;

            mermaid.initialize({ startOnLoad: false, theme: 'default' });
            marked.use(markedGfmHeadingId.gfmHeadingId());
            marked.setOptions({ breaks: true, gfm: true, langPrefix: 'language-' });

            document.addEventListener('DOMContentLoaded', async function() {
                var contentDiv = document.getElementById('content');
                if (!contentDiv || !rawMarkdown) return;

                markedGfmHeadingId.resetHeadings();
                var htmlContent = marked.parse(rawMarkdown);

                var aliases = [
                    ['class="language-js"', 'class="language-javascript"'],
                    ['class="language-ts"', 'class="language-typescript"'],
                    ['class="language-py"', 'class="language-python"'],
                    ['class="language-rb"', 'class="language-ruby"'],
                    ['class="language-yml"', 'class="language-yaml"'],
                    ['class="language-sh"', 'class="language-bash"'],
                    ['class="language-shell"', 'class="language-bash"'],
                    ['class="language-cs"', 'class="language-csharp"']
                ];
                aliases.forEach(function(pair) {
                    htmlContent = htmlContent.split(pair[0]).join(pair[1]);
                });

                htmlContent = htmlContent.replace(/<pre><code class="language-mermaid">([\\s\\S]*?)<\\/code><\\/pre>/g,
                    function(match, code) {
                        return '<div class="mermaid">' + code.replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'") + '</div>';
                    });

                contentDiv.innerHTML = htmlContent;

                setTimeout(function() {
                    try { Prism.highlightAll(); } catch(e) {}
                }, 10);

                var diagrams = contentDiv.querySelectorAll('.mermaid');
                for (var i = 0; i < diagrams.length; i++) {
                    var diagram = diagrams[i];
                    var graphDefinition = diagram.textContent;
                    var id = 'mermaid-' + Date.now() + '-' + i;
                    try {
                        var result = await mermaid.render(id, graphDefinition);
                        diagram.innerHTML = result.svg;
                    } catch (error) {
                        diagram.innerHTML = '<div style="color:#e74c3c;padding:10px;background:#ffecec;border-radius:4px;font-size:13px;">Diagram error: ' + error.message + '</div>';
                    }
                }
            });
            </script>
        </body>
        </html>
        """
    }

    private static func loadResource(_ name: String, ext: String, bundle: Bundle) -> String {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    private static let quickLookCSS = """
    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
        background: #ffffff;
        color: #24292e;
        padding: 24px 32px;
        line-height: 1.6;
        font-size: 15px;
    }

    h1, h2, h3, h4, h5, h6 {
        margin-top: 24px;
        margin-bottom: 12px;
        font-weight: 600;
        line-height: 1.25;
    }
    h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid #eaecef; }
    h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid #eaecef; }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1em; }

    p { margin: 0 0 16px 0; }

    a { color: #0366d6; text-decoration: none; }
    a:hover { text-decoration: underline; }

    code {
        background: #f6f8fa;
        padding: 0.2em 0.4em;
        border-radius: 3px;
        font-family: "SF Mono", SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace;
        font-size: 0.85em;
    }

    pre {
        background: #282c34;
        padding: 16px;
        border-radius: 6px;
        overflow-x: auto;
        margin: 0 0 16px 0;
    }
    pre code {
        background: none;
        padding: 0;
        font-size: 0.9em;
        color: #abb2bf;
    }

    blockquote {
        padding: 0 16px;
        margin: 0 0 16px 0;
        border-left: 4px solid #dfe2e5;
        color: #6a737d;
    }

    ul, ol { padding-left: 2em; margin: 0 0 16px 0; }
    li { margin: 4px 0; }
    li > ul, li > ol { margin: 0; }

    table {
        border-collapse: collapse;
        width: 100%;
        margin: 0 0 16px 0;
    }
    th, td {
        border: 1px solid #dfe2e5;
        padding: 8px 12px;
        text-align: left;
    }
    th { background: #f6f8fa; font-weight: 600; }
    tr:nth-child(even) { background: #f6f8fa; }

    hr {
        border: none;
        border-top: 1px solid #eaecef;
        margin: 24px 0;
    }

    img {
        max-width: 100%;
        height: auto;
    }

    .mermaid {
        text-align: center;
        margin: 16px 0;
    }
    .mermaid svg {
        max-width: 100%;
        height: auto;
    }

    @media (prefers-color-scheme: dark) {
        body { background: #0d1117; color: #c9d1d9; }
        h1, h2 { border-bottom-color: #30363d; }
        a { color: #58a6ff; }
        code { background: #161b22; }
        pre { background: #161b22; }
        pre code { color: #c9d1d9; }
        blockquote { border-left-color: #30363d; color: #8b949e; }
        th, td { border-color: #30363d; }
        th { background: #161b22; }
        tr:nth-child(even) { background: #161b22; }
        hr { border-top-color: #30363d; }
    }
    """
}
