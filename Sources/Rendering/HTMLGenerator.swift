import Foundation

/// Main entry point for generating HTML pages.
enum HTMLGenerator {
    /// Returns raw HTML so `.html` and `.htm` files render as documents.
    static func htmlPage(content: String) -> String {
        content
    }

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
            <script src="https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/prism.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/plugins/autoloader/prism-autoloader.min.js"></script>
            <script>Prism.plugins.autoloader.languages_path = 'https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/components/';</script>
            <script src="https://cdn.jsdelivr.net/npm/markdown-it/dist/markdown-it.min.js"></script>
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

    /// Generates the standalone diagram viewer page (zoom dropdown, ⌘+/⌘− zoom, pan).
    static func diagramPage(definition: String, theme: String) -> String {
        let background = MermaidConfig.fullscreenBackgrounds[theme] ?? "white"
        let (mermaidTheme, _) = MermaidConfig.variablesForTheme(theme)
        let variablesJSON = MermaidConfig.variablesJSON(for: theme)
        let isDark = Constants.darkThemes.contains(theme)
        let toolbarBg = isDark ? "rgba(60,60,60,0.92)" : "rgba(255,255,255,0.92)"
        let toolbarFg = isDark ? "#e6e6e6" : "#333"
        let toolbarBorder = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.15)"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>Mermaid Diagram</title>
            <script src="https://cdn.jsdelivr.net/npm/mermaid@\(Constants.mermaidVersion)/dist/mermaid.min.js"></script>
            <style>
            html, body {
                margin: 0; height: 100%; overflow: hidden;
                background: \(background);
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            }
            #viewport { position: absolute; inset: 0; overflow: hidden; cursor: grab; }
            #viewport.panning { cursor: grabbing; }
            #stage { position: absolute; top: 0; left: 0; transform-origin: 0 0; }
            #stage svg { display: block; }
            #toolbar {
                position: fixed; top: 12px; right: 12px; z-index: 10;
                display: flex; align-items: center; gap: 4px;
                background: \(toolbarBg); color: \(toolbarFg);
                border: 1px solid \(toolbarBorder); border-radius: 8px;
                padding: 4px 6px; box-shadow: 0 2px 8px rgba(0,0,0,0.25);
                -webkit-user-select: none; user-select: none;
            }
            #toolbar button {
                background: transparent; color: inherit; border: none; border-radius: 5px;
                width: 24px; height: 24px; font-size: 15px; line-height: 1; cursor: pointer;
            }
            #toolbar button:hover { background: \(toolbarBorder); }
            #zoomSelect {
                background: transparent; color: inherit;
                border: 1px solid \(toolbarBorder); border-radius: 5px;
                font-size: 12px; padding: 2px 4px; cursor: pointer;
            }
            #error {
                color: #e74c3c; padding: 20px; margin: 40px auto; max-width: 600px;
                background: #ffecec; border-radius: 5px; font-size: 14px;
                white-space: pre-wrap;
            }
            </style>
        </head>
        <body>
            <div id="viewport"><div id="stage"></div></div>
            <div id="toolbar">
                <button id="zoomOutBtn" title="Zoom Out (⌘−)">−</button>
                <select id="zoomSelect" title="Zoom">
                    <option value="fit">Fit</option>
                    <option id="zoomCustom" hidden></option>
                    <option value="50">50%</option>
                    <option value="75">75%</option>
                    <option value="100">100%</option>
                    <option value="125">125%</option>
                    <option value="150">150%</option>
                    <option value="200">200%</option>
                    <option value="300">300%</option>
                    <option value="400">400%</option>
                </select>
                <button id="zoomInBtn" title="Zoom In (⌘+)">+</button>
            </div>
            <script>
            var graphDefinition = \(definition.jsonStringLiteral);
            mermaid.initialize({ startOnLoad: false, theme: '\(mermaidTheme)', themeVariables: \(variablesJSON) });

            var viewport = document.getElementById('viewport');
            var stage = document.getElementById('stage');
            var zoomSelect = document.getElementById('zoomSelect');
            var zoomCustom = document.getElementById('zoomCustom');
            var MIN_SCALE = 0.1, MAX_SCALE = 8, STEP = 1.25;
            var scale = 1, tx = 0, ty = 0;
            var contentW = 0, contentH = 0;
            var fitMode = true;

            function applyTransform() {
                stage.style.transform = 'translate(' + tx + 'px,' + ty + 'px) scale(' + scale + ')';
                updateZoomSelect();
            }

            function updateZoomSelect() {
                if (fitMode) { zoomCustom.hidden = true; zoomSelect.value = 'fit'; return; }
                var pct = String(Math.round(scale * 100));
                var presets = ['50','75','100','125','150','200','300','400'];
                if (presets.indexOf(pct) >= 0) {
                    zoomCustom.hidden = true;
                } else {
                    zoomCustom.hidden = false;
                    zoomCustom.value = pct;
                    zoomCustom.textContent = pct + '%';
                }
                zoomSelect.value = pct;
            }

            function setScale(newScale, cx, cy) {
                newScale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, newScale));
                if (cx === undefined) { cx = viewport.clientWidth / 2; cy = viewport.clientHeight / 2; }
                var k = newScale / scale;
                tx = cx - (cx - tx) * k;
                ty = cy - (cy - ty) * k;
                scale = newScale;
                fitMode = false;
                applyTransform();
            }

            function fitToWindow() {
                if (!contentW || !contentH) return;
                var pad = 40;
                var vw = Math.max(50, viewport.clientWidth - pad);
                var vh = Math.max(50, viewport.clientHeight - pad);
                scale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, Math.min(vw / contentW, vh / contentH)));
                tx = (viewport.clientWidth - contentW * scale) / 2;
                ty = (viewport.clientHeight - contentH * scale) / 2;
                fitMode = true;
                applyTransform();
            }

            window.moremaidDiagramZoomIn = function() { setScale(scale * STEP); };
            window.moremaidDiagramZoomOut = function() { setScale(scale / STEP); };
            window.moremaidDiagramZoomReset = function() { setScale(1); };

            document.getElementById('zoomInBtn').onclick = function() { moremaidDiagramZoomIn(); };
            document.getElementById('zoomOutBtn').onclick = function() { moremaidDiagramZoomOut(); };
            zoomSelect.addEventListener('change', function() {
                if (zoomSelect.value === 'fit') fitToWindow();
                else setScale(parseFloat(zoomSelect.value) / 100);
                zoomSelect.blur();
            });

            var panning = false, lastX = 0, lastY = 0;
            viewport.addEventListener('mousedown', function(e) {
                if (e.button !== 0) return;
                panning = true; lastX = e.clientX; lastY = e.clientY;
                viewport.classList.add('panning');
                e.preventDefault();
            });
            window.addEventListener('mousemove', function(e) {
                if (!panning) return;
                tx += e.clientX - lastX; ty += e.clientY - lastY;
                lastX = e.clientX; lastY = e.clientY;
                fitMode = false;
                applyTransform();
            });
            window.addEventListener('mouseup', function() {
                panning = false;
                viewport.classList.remove('panning');
            });

            viewport.addEventListener('wheel', function(e) {
                e.preventDefault();
                if (e.ctrlKey || e.metaKey) {
                    setScale(scale * Math.pow(1.01, -e.deltaY), e.clientX, e.clientY);
                } else {
                    tx -= e.deltaX; ty -= e.deltaY;
                    fitMode = false;
                    applyTransform();
                }
            }, { passive: false });

            document.addEventListener('keydown', function(e) {
                if (e.target === zoomSelect) return;
                if (e.key === '+' || e.key === '=') { moremaidDiagramZoomIn(); e.preventDefault(); }
                else if (e.key === '-') { moremaidDiagramZoomOut(); e.preventDefault(); }
                else if (e.key === '0') { fitToWindow(); e.preventDefault(); }
                else if (e.key === '1') { moremaidDiagramZoomReset(); e.preventDefault(); }
                else if (e.key === 'ArrowLeft') { tx += 40; fitMode = false; applyTransform(); e.preventDefault(); }
                else if (e.key === 'ArrowRight') { tx -= 40; fitMode = false; applyTransform(); e.preventDefault(); }
                else if (e.key === 'ArrowUp') { ty += 40; fitMode = false; applyTransform(); e.preventDefault(); }
                else if (e.key === 'ArrowDown') { ty -= 40; fitMode = false; applyTransform(); e.preventDefault(); }
            });

            window.addEventListener('resize', function() { if (fitMode) fitToWindow(); });

            (async function() {
                try {
                    var result = await mermaid.render('diagram', graphDefinition);
                    stage.innerHTML = result.svg;
                    var svg = stage.querySelector('svg');
                    svg.style.maxWidth = 'none';
                    var vb = svg.viewBox && svg.viewBox.baseVal;
                    if (vb && vb.width && vb.height) {
                        contentW = vb.width; contentH = vb.height;
                        svg.setAttribute('width', vb.width);
                        svg.setAttribute('height', vb.height);
                    } else {
                        var r = svg.getBoundingClientRect();
                        contentW = r.width; contentH = r.height;
                    }
                    fitToWindow();
                } catch (error) {
                    document.getElementById('toolbar').style.display = 'none';
                    var div = document.createElement('div');
                    div.id = 'error';
                    div.textContent = 'Error rendering diagram: ' + error.message;
                    document.body.appendChild(div);
                }
            })();
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
        let language = LanguageMaps.language(forFile: fileName)
        let escapedContent = content.htmlEscaped
        let escapedTitle = fileName.htmlEscaped
        let themeJS = "'\(theme)'"

        let isDark = Constants.darkThemes.contains(theme)
        let prismTheme = isDark ? "prism-tomorrow" : "prism"
        let langScripts = LanguageMaps.prismScriptTags(for: language, version: Constants.prismVersion)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapedTitle)</title>
            <link href="https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/themes/\(prismTheme).min.css" rel="stylesheet" />
            <script src="https://cdn.jsdelivr.net/npm/prismjs@\(Constants.prismVersion)/prism.min.js"></script>
            \(langScripts)
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
