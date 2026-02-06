import Foundation

/// All embedded JavaScript for rendered HTML pages.
/// Ported from ../lib/html-generator.js lines 882-1681.
enum PageScripts {
    /// Full script block for markdown pages.
    static func allScripts(
        rawMarkdownJSON: String,
        titleJSON: String,
        forceThemeJS: String,
        searchQueryJS: String,
        isServer: Bool
    ) -> String {
        return """
        // Store raw markdown for copy functionality
        var rawMarkdown = \(rawMarkdownJSON);
        var documentTitle = \(titleJSON);

        \(themeScript(forceThemeJS: forceThemeJS))
        \(typographyScript)
        \(zoomScript)
        \(controlsToggleScript)
        \(copyButtonScript)
        \(pdfButtonScript)
        \(zoomControlsScript)
        \(zoomKeyboardScript)
        \(mermaidInitScript)
        \(mermaidFullscreenScript)
        \(codeCopyButtonsScript)
        \(markedRenderScript)
        \(isServer ? webSocketScript : "")
        \(searchQueryJS != "null" ? searchHighlightScript(searchQueryJS: searchQueryJS) : "")
        """
    }

    /// Simplified script block for code pages.
    static func codePageScripts(forceThemeJS: String) -> String {
        return """
        \(themeScript(forceThemeJS: forceThemeJS))
        \(typographyScript)
        \(zoomScript)
        \(controlsToggleScript)
        \(copyButtonScript)
        \(zoomControlsScript)
        \(zoomKeyboardScript)
        \(codeCopyButtonsScript)
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(function() {
                try { Prism.highlightAll(); } catch(e) { console.error('Prism error:', e); }
            }, 10);
        });
        """
    }

    // MARK: - Theme

    private static func themeScript(forceThemeJS: String) -> String {
        return """
        var themes = {
            light: { name: 'Light', mermaid: 'default' },
            dark: { name: 'Dark', mermaid: 'dark' },
            github: { name: 'GitHub', mermaid: 'default' },
            'github-dark': { name: 'GitHub Dark', mermaid: 'dark' },
            dracula: { name: 'Dracula', mermaid: 'dark' },
            nord: { name: 'Nord', mermaid: 'dark' },
            'solarized-light': { name: 'Solarized Light', mermaid: 'default' },
            'solarized-dark': { name: 'Solarized Dark', mermaid: 'dark' },
            monokai: { name: 'Monokai', mermaid: 'dark' },
            'one-dark': { name: 'One Dark', mermaid: 'dark' }
        };

        function initTheme() {
            var forcedTheme = \(forceThemeJS);
            var savedTheme = localStorage.getItem('theme');
            var systemPrefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
            var defaultTheme = forcedTheme || savedTheme || (systemPrefersDark ? 'dark' : 'light');
            var theme = themes[defaultTheme] ? defaultTheme : 'light';
            document.documentElement.setAttribute('data-theme', theme);
            updateThemeSelector(theme);
            return theme;
        }

        function updateThemeSelector(theme) {
            var selector = document.getElementById('themeSelector');
            if (selector) selector.value = theme;
        }

        function switchTheme(newTheme) {
            if (!themes[newTheme]) return;
            document.documentElement.setAttribute('data-theme', newTheme);
            localStorage.setItem('theme', newTheme);
            updateThemeSelector(newTheme);
            if (typeof initializeMermaid === 'function') initializeMermaid(newTheme);
        }

        var currentTheme = initTheme();

        document.getElementById('themeSelector').addEventListener('change', function(e) {
            switchTheme(e.target.value);
        });
        """
    }

    // MARK: - Typography

    private static let typographyScript = """
    function switchTypography(typography) {
        document.body.setAttribute('data-typography', typography);
        localStorage.setItem('preferredTypography', typography);
    }

    function loadPreferredTypography() {
        var saved = localStorage.getItem('preferredTypography') || 'default';
        switchTypography(saved);
        var selector = document.getElementById('typographySelector');
        if (selector) selector.value = saved;
    }

    document.getElementById('typographySelector').addEventListener('change', function(e) {
        switchTypography(e.target.value);
    });

    loadPreferredTypography();
    """

    // MARK: - Zoom

    private static let zoomScript = """
    var currentZoom = 100;

    function setZoom(scale) {
        var zoomContainer = document.getElementById('zoomContainer');
        if (zoomContainer) {
            zoomContainer.style.transform = 'scale(' + scale + ')';
            zoomContainer.style.transformOrigin = '0 0';
            zoomContainer.style.width = (100 / scale) + '%';
            zoomContainer.style.height = (100 / scale) + '%';
        }
    }

    function updateZoom(zoomLevel) {
        currentZoom = Math.max(50, Math.min(200, zoomLevel));
        setZoom(currentZoom / 100);
        document.getElementById('zoomValue').textContent = currentZoom + '%';
        localStorage.setItem('zoom', currentZoom);
    }

    var savedZoom = localStorage.getItem('zoom');
    if (savedZoom) {
        currentZoom = parseInt(savedZoom);
        updateZoom(currentZoom);
    }
    """

    // MARK: - Controls Toggle

    private static let controlsToggleScript = """
    var controlsTrigger = document.querySelector('.controls-trigger');
    var controls = document.querySelector('.controls');
    var controlsVisible = false;

    if (controlsTrigger && controls) {
        controlsTrigger.addEventListener('click', function() {
            controlsVisible = !controlsVisible;
            if (controlsVisible) {
                controls.classList.add('visible');
            } else {
                controls.classList.remove('visible');
            }
        });

        document.addEventListener('click', function(e) {
            if (!controlsTrigger.contains(e.target) && !controls.contains(e.target)) {
                controlsVisible = false;
                controls.classList.remove('visible');
            }
        });
    }
    """

    // MARK: - Copy Button

    private static let copyButtonScript = """
    var copyButton = document.getElementById('copyButton');
    if (copyButton) {
        copyButton.addEventListener('click', async function() {
            try {
                await navigator.clipboard.writeText(rawMarkdown);
                copyButton.textContent = 'Copied!';
                setTimeout(function() { copyButton.textContent = 'Copy'; }, 2000);
            } catch (err) {
                console.error('Failed to copy:', err);
                copyButton.textContent = 'Failed';
                setTimeout(function() { copyButton.textContent = 'Copy'; }, 2000);
            }
        });
    }
    """

    // MARK: - PDF Button

    private static let pdfButtonScript = """
    var downloadPdfButton = document.getElementById('downloadPdfButton');
    if (downloadPdfButton) {
        downloadPdfButton.addEventListener('click', async function() {
            try {
                downloadPdfButton.textContent = 'Generating...';
                downloadPdfButton.disabled = true;
                var params = new URLSearchParams(window.location.search);
                params.set('path', documentTitle);
                var response = await fetch('/api/pdf?' + params.toString());
                if (!response.ok) throw new Error('PDF generation failed: ' + response.statusText);
                var blob = await response.blob();
                var url = window.URL.createObjectURL(blob);
                var a = document.createElement('a');
                a.href = url;
                a.download = documentTitle.replace(/\\.md$/, '') + '.pdf';
                document.body.appendChild(a);
                a.click();
                window.URL.revokeObjectURL(url);
                document.body.removeChild(a);
                downloadPdfButton.textContent = 'Downloaded!';
                setTimeout(function() { downloadPdfButton.textContent = 'PDF'; downloadPdfButton.disabled = false; }, 2000);
            } catch (err) {
                console.error('Failed to download PDF:', err);
                downloadPdfButton.textContent = 'Failed';
                setTimeout(function() { downloadPdfButton.textContent = 'PDF'; downloadPdfButton.disabled = false; }, 2000);
            }
        });
    }
    """

    // MARK: - Zoom Controls

    private static let zoomControlsScript = """
    document.getElementById('zoomIn').addEventListener('click', function() { updateZoom(currentZoom + 10); });
    document.getElementById('zoomOut').addEventListener('click', function() { updateZoom(currentZoom - 10); });
    document.getElementById('zoomReset').addEventListener('click', function() { updateZoom(100); });
    """

    // MARK: - Zoom Keyboard

    private static let zoomKeyboardScript = """
    document.addEventListener('keydown', function(e) {
        if (e.ctrlKey || e.metaKey) {
            if (e.key === '=' || e.key === '+') { e.preventDefault(); updateZoom(currentZoom + 10); }
            else if (e.key === '-') { e.preventDefault(); updateZoom(currentZoom - 10); }
            else if (e.key === '0') { e.preventDefault(); updateZoom(100); }
        }
    });
    """

    // MARK: - Mermaid Init

    private static let mermaidInitScript = """
    var themeVariables = {
        light: { primaryColor: '#3498db', primaryTextColor: '#fff', primaryBorderColor: '#2980b9', lineColor: '#5a6c7d', secondaryColor: '#ecf0f1', tertiaryColor: '#fff' },
        dark: { primaryColor: '#61afef', primaryTextColor: '#1a1a1a', primaryBorderColor: '#4b5263', lineColor: '#abb2bf', secondaryColor: '#2d2d2d', tertiaryColor: '#3a3a3a', background: '#1a1a1a', mainBkg: '#61afef', secondBkg: '#56b6c2', tertiaryBkg: '#98c379' },
        github: { primaryColor: '#0366d6', primaryTextColor: '#fff', primaryBorderColor: '#0366d6', lineColor: '#586069', secondaryColor: '#f6f8fa' },
        dracula: { primaryColor: '#bd93f9', primaryTextColor: '#f8f8f2', primaryBorderColor: '#6272a4', lineColor: '#6272a4', secondaryColor: '#44475a', background: '#282a36' },
        nord: { primaryColor: '#88c0d0', primaryTextColor: '#2e3440', primaryBorderColor: '#5e81ac', lineColor: '#4c566a', secondaryColor: '#3b4252', background: '#2e3440' },
        solarized: { primaryColor: '#268bd2', primaryTextColor: '#fdf6e3', primaryBorderColor: '#93a1a1', lineColor: '#657b83', secondaryColor: '#eee8d5' },
        monokai: { primaryColor: '#66d9ef', primaryTextColor: '#272822', primaryBorderColor: '#75715e', lineColor: '#75715e', secondaryColor: '#3e3d32', background: '#272822' }
    };

    function initializeMermaid(theme) {
        var themeConfig = themes[theme] || themes.light;
        var mermaidTheme = themeConfig.mermaid;
        var variables = themeVariables.light;
        if (theme === 'dark' || theme === 'one-dark') variables = themeVariables.dark;
        else if (theme === 'github') variables = themeVariables.github;
        else if (theme === 'github-dark') variables = Object.assign({}, themeVariables.github, { background: '#0d1117' });
        else if (theme === 'dracula') variables = themeVariables.dracula;
        else if (theme === 'nord') variables = themeVariables.nord;
        else if (theme === 'solarized-light') variables = themeVariables.solarized;
        else if (theme === 'solarized-dark') variables = Object.assign({}, themeVariables.solarized, { background: '#002b36' });
        else if (theme === 'monokai') variables = themeVariables.monokai;

        mermaid.initialize({ startOnLoad: false, theme: mermaidTheme, themeVariables: variables });
    }

    initializeMermaid(currentTheme);
    """

    // MARK: - Mermaid Fullscreen

    private static let mermaidFullscreenScript = """
    window.childWindows = window.childWindows || [];

    function openMermaidInNewWindow(graphDefinition) {
        var newWindow = window.open('', '_blank', 'width=800,height=600,scrollbars=yes,resizable=yes');
        if (newWindow) {
            window.childWindows.push(newWindow);
            newWindow.addEventListener('beforeunload', function() {
                var index = window.childWindows.indexOf(newWindow);
                if (index > -1) window.childWindows.splice(index, 1);
            });
        }
        var ct = document.documentElement.getAttribute('data-theme') || 'light';
        var bgColors = { light: 'white', dark: '#1a1a1a', github: '#ffffff', 'github-dark': '#0d1117', dracula: '#282a36', nord: '#2e3440', 'solarized-light': '#fdf6e3', 'solarized-dark': '#002b36', monokai: '#272822', 'one-dark': '#282c34' };
        var bgColor = bgColors[ct] || 'white';

        var html = '<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Mermaid Diagram</title>' +
            '<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></' + 'script>' +
            '<style>body{margin:0;padding:20px;display:flex;justify-content:center;align-items:center;min-height:100vh;background:' + bgColor + ';font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}#diagram{max-width:100%;overflow:auto}</style></head>' +
            '<body><div id="diagram" class="mermaid">' + graphDefinition + '</div>' +
            '<script>var theme="' + ct + '";var themes=' + JSON.stringify(themes) + ';' +
            'var themeConfig=themes[theme]||themes.light;var mermaidTheme=themeConfig.mermaid;' +
            'var themeVariables=' + JSON.stringify(themeVariables) + ';' +
            'var variables=themeVariables.light;' +
            'if(theme==="dark"||theme==="one-dark")variables=themeVariables.dark;' +
            'else if(theme==="github")variables=themeVariables.github;' +
            'else if(theme==="github-dark")variables=Object.assign({},themeVariables.github,{background:"#0d1117"});' +
            'else if(theme==="dracula")variables=themeVariables.dracula;' +
            'else if(theme==="nord")variables=themeVariables.nord;' +
            'else if(theme==="solarized-light")variables=themeVariables.solarized;' +
            'else if(theme==="solarized-dark")variables=Object.assign({},themeVariables.solarized,{background:"#002b36"});' +
            'else if(theme==="monokai")variables=themeVariables.monokai;' +
            'mermaid.initialize({startOnLoad:true,theme:mermaidTheme,themeVariables:variables});' +
            'setInterval(function(){try{if(!window.opener||window.opener.closed){window.close()}}catch(e){window.close()}},500);' +
            '</' + 'script></body></html>';

        newWindow.document.write(html);
        newWindow.document.close();
    }
    """

    // MARK: - Code Block Copy Buttons

    private static let codeCopyButtonsScript = """
    function addCopyButtons(container) {
        container = container || document;
        var codeBlocks = container.querySelectorAll('pre');
        codeBlocks.forEach(function(pre) {
            if (pre.querySelector('.copy-btn')) return;
            var wrapper = document.createElement('div');
            wrapper.className = 'code-block-wrapper';
            pre.parentNode.insertBefore(wrapper, pre);
            wrapper.appendChild(pre);
            var button = document.createElement('button');
            button.className = 'copy-btn';
            button.textContent = 'Copy';
            button.onclick = function() {
                var code = pre.querySelector('code') ? pre.querySelector('code').textContent : pre.textContent;
                navigator.clipboard.writeText(code).then(function() {
                    button.textContent = 'Copied!';
                    setTimeout(function() { button.textContent = 'Copy'; }, 2000);
                }).catch(function(err) {
                    console.error('Failed to copy:', err);
                    button.textContent = 'Failed';
                    setTimeout(function() { button.textContent = 'Copy'; }, 2000);
                });
            };
            wrapper.appendChild(button);
        });
    }
    """

    // MARK: - marked.js Rendering

    private static let markedRenderScript = """
    document.addEventListener('DOMContentLoaded', async function() {
        // Configure marked
        marked.setOptions({ breaks: true, gfm: true, langPrefix: 'language-' });

        // Render markdown
        var contentDiv = document.getElementById('content');
        if (contentDiv && rawMarkdown) {
            var htmlContent = marked.parse(rawMarkdown);

            // Fix language aliases
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

            // Process mermaid blocks
            htmlContent = htmlContent.replace(/<pre><code class="language-mermaid">([\\s\\S]*?)<\\/code><\\/pre>/g,
                function(match, code) {
                    return '<div class="mermaid">' + code.replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'") + '</div>';
                });

            contentDiv.innerHTML = htmlContent;

            // Syntax highlighting
            setTimeout(function() {
                try { Prism.highlightAll(); addCopyButtons(); } catch(e) { console.error('Prism error:', e); }
            }, 10);

            // Render mermaid diagrams
            var diagrams = contentDiv.querySelectorAll('.mermaid');
            for (var i = 0; i < diagrams.length; i++) {
                var diagram = diagrams[i];
                var graphDefinition = diagram.textContent;
                var id = 'mermaid-' + Date.now() + '-' + i;
                try {
                    var result = await mermaid.render(id, graphDefinition);
                    var container = document.createElement('div');
                    container.className = 'mermaid-container';
                    var svgContainer = document.createElement('div');
                    svgContainer.innerHTML = result.svg;
                    container.appendChild(svgContainer);
                    var fullscreenBtn = document.createElement('button');
                    fullscreenBtn.className = 'mermaid-fullscreen-btn';
                    fullscreenBtn.innerHTML = '\\u26F6';
                    fullscreenBtn.title = 'Open in new window';
                    (function(def) {
                        fullscreenBtn.onclick = function(e) { e.stopPropagation(); openMermaidInNewWindow(def); };
                    })(graphDefinition);
                    container.appendChild(fullscreenBtn);
                    diagram.innerHTML = '';
                    diagram.appendChild(container);
                } catch (error) {
                    console.error('Error rendering mermaid diagram:', error);
                    diagram.innerHTML = '<div style="color:#e74c3c;padding:20px;background:#ffecec;border-radius:5px;">Error rendering diagram: ' + error.message + '</div>';
                }
            }
        }
    });
    """

    // MARK: - WebSocket

    private static let webSocketScript = """
    window.ws = null;

    function connectWebSocket() {
        var protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        window.ws = new WebSocket(protocol + '//' + window.location.host + '/ws');

        window.ws.onopen = function() { console.log('WebSocket connected'); };

        window.ws.onmessage = function(event) {
            if (event.data === 'reload') {
                window.location.reload();
            }
        };

        window.ws.onclose = function() {
            console.log('WebSocket disconnected');
            var childCount = window.childWindows ? window.childWindows.length : 0;
            if (childCount > 0) {
                var childrenToClose = window.childWindows.slice();
                childrenToClose.forEach(function(childWindow) {
                    try { if (childWindow && !childWindow.closed) childWindow.close(); } catch(e) {}
                });
                window.childWindows = [];
            }
        };

        window.ws.onerror = function(error) { console.error('WebSocket error:', error); };

        setInterval(function() {
            if (window.ws && window.ws.readyState === WebSocket.OPEN) {
                window.ws.send('ping');
            }
        }, 30000);
    }

    connectWebSocket();
    """

    // MARK: - Search Highlight

    private static func searchHighlightScript(searchQueryJS: String) -> String {
        return """
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(function() {
                var searchQuery = \(searchQueryJS);
                if (!searchQuery) return;
                var searchTerms = searchQuery.toLowerCase().split(/\\s+/).filter(function(t) { return t.length >= 2; });
                if (searchTerms.length === 0) return;

                var container = document.querySelector('.container');
                if (!container) return;

                var walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT, {
                    acceptNode: function(node) {
                        var parent = node.parentNode;
                        if (parent.tagName === 'SCRIPT' || parent.tagName === 'STYLE' || parent.tagName === 'MARK' || parent.closest('mark')) return NodeFilter.FILTER_REJECT;
                        return NodeFilter.FILTER_ACCEPT;
                    }
                }, false);

                var textNodes = [];
                var node;
                while (node = walker.nextNode()) textNodes.push(node);

                var allMarks = [];
                textNodes.forEach(function(textNode) {
                    var text = textNode.nodeValue;
                    var lowerText = text.toLowerCase();
                    var hasMatch = searchTerms.some(function(t) { return lowerText.includes(t); });
                    if (!hasMatch) return;

                    var matches = [];
                    searchTerms.forEach(function(term) {
                        var idx = lowerText.indexOf(term, 0);
                        while (idx !== -1) {
                            matches.push({ start: idx, end: idx + term.length });
                            idx = lowerText.indexOf(term, idx + 1);
                        }
                    });
                    matches.sort(function(a, b) { return a.start - b.start; });

                    var merged = [];
                    matches.forEach(function(m) {
                        if (merged.length === 0 || m.start > merged[merged.length - 1].end) merged.push(m);
                        else merged[merged.length - 1].end = Math.max(merged[merged.length - 1].end, m.end);
                    });

                    var fragment = document.createDocumentFragment();
                    var lastIndex = 0;
                    merged.forEach(function(m) {
                        if (m.start > lastIndex) fragment.appendChild(document.createTextNode(text.substring(lastIndex, m.start)));
                        var mark = document.createElement('mark');
                        mark.style.cssText = 'background:#ffeb3b;color:#333;padding:0 2px;border-radius:2px;';
                        mark.textContent = text.substring(m.start, m.end);
                        fragment.appendChild(mark);
                        allMarks.push(mark);
                        lastIndex = m.end;
                    });
                    if (lastIndex < text.length) fragment.appendChild(document.createTextNode(text.substring(lastIndex)));
                    textNode.parentNode.replaceChild(fragment, textNode);
                });

                if (allMarks.length > 0) {
                    setTimeout(function() {
                        allMarks[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
                        allMarks[0].style.transition = 'background-color 0.5s ease';
                        allMarks[0].style.backgroundColor = '#ffd54f';
                        setTimeout(function() { allMarks[0].style.backgroundColor = '#ffeb3b'; }, 500);
                    }, 100);
                }
            }, 100);
        });
        """
    }
}
