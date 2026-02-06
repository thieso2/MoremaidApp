import Foundation

/// Base CSS styles ported from ../lib/styles.js getBaseStyles() and html-generator.js
enum BaseCSS {
    static let all = """
    * {
        margin: 0;
        padding: 0;
        box-sizing: border-box;
    }

    body {
        font-family: var(--font-body);
        background: var(--bg-color);
        color: var(--text-color);
        margin: 0;
        padding: 0;
        line-height: var(--line-height);
        font-size: var(--font-size-base);
        transition: background-color 0.3s, color 0.3s;
        min-height: 100vh;
    }

    .zoom-container {
        padding: 80px 30px 30px 30px;
        transform-origin: 0 0;
        min-height: 100vh;
    }

    .container {
        max-width: var(--max-width);
        margin: 0 auto;
    }

    h1, h2, h3, h4, h5, h6 {
        font-family: var(--font-heading);
        color: var(--heading-color);
        margin-top: 1.5em;
        margin-bottom: 0.5em;
    }

    h1 { font-size: 2em; border-bottom: 2px solid var(--border-color); padding-bottom: 10px; margin-bottom: 20px; }
    h2 { font-size: 1.5em; color: var(--heading2-color); margin-top: 30px; margin-bottom: 15px; border-bottom: 1px solid var(--border-color); padding-bottom: 5px; }
    h3 { font-size: 1.25em; color: var(--heading2-color); margin-top: 20px; margin-bottom: 10px; }
    h4 { font-size: 1.1em; }
    h5 { font-size: 1em; }
    h6 { font-size: 0.9em; }

    p {
        margin-bottom: var(--paragraph-spacing);
        text-align: var(--text-align);
    }

    code, pre {
        font-family: var(--font-code) !important;
    }

    code:not([class*="language-"]) {
        background: var(--code-bg);
        padding: 2px 5px;
        border-radius: 3px;
        color: var(--code-color);
    }

    pre {
        margin: 15px 0;
        border-radius: 5px;
        overflow: hidden;
    }

    pre[class*="language-"] {
        margin: 15px 0;
        padding: 1em;
        border-radius: 5px;
        font-size: 14px;
        line-height: 1.5;
    }

    pre code:not([class*="language-"]) {
        padding: 0;
        background: transparent;
    }

    code[class*="language-"],
    pre[class*="language-"] {
        font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', 'Courier New', monospace;
    }

    /* Book style - indent paragraphs */
    [data-typography="book"] p + p {
        text-indent: 2em;
    }

    /* Newspaper multi-column */
    @media (min-width: 1200px) {
        [data-typography="newspaper"] .container {
            column-count: 3;
            column-gap: 2em;
            column-rule: 1px solid var(--border-color);
        }
    }

    blockquote {
        padding-left: 20px;
        margin: 20px 0;
        color: var(--blockquote-color);
        font-style: italic;
        border-left: 4px solid var(--border-color);
    }

    a { color: var(--link-color); text-decoration: none; }
    a:hover { text-decoration: underline; }

    ul, ol {
        margin-left: 30px;
        margin-bottom: 15px;
    }

    li { margin: 5px 0; }

    table {
        border-collapse: collapse;
        margin: 20px 0;
        width: 100%;
    }

    table th, table td {
        border: 1px solid var(--table-border);
        padding: 10px;
        text-align: left;
    }

    table th {
        background: var(--table-header-bg);
        font-weight: bold;
    }

    hr {
        border: none;
        border-top: 1px solid var(--border-color);
        margin: 2em 0;
    }

    img { max-width: 100%; height: auto; }

    /* Mermaid diagram styling */
    .mermaid {
        text-align: center;
        margin: 20px 0;
        position: relative;
        display: block;
        width: 100%;
    }

    .mermaid-container {
        position: relative;
        display: block;
        width: 100%;
    }

    .mermaid-container svg {
        max-width: 100%;
        height: auto;
    }

    .mermaid-fullscreen-btn {
        position: absolute;
        top: 10px;
        right: 10px;
        background: var(--mermaid-btn-bg);
        color: white;
        border: none;
        border-radius: 4px;
        padding: 8px 10px;
        cursor: pointer;
        font-size: 18px;
        z-index: 10;
        transition: background 0.2s;
    }

    .mermaid-fullscreen-btn:hover {
        background: var(--mermaid-btn-hover);
    }

    /* Controls styling */
    .controls-trigger {
        position: fixed;
        bottom: 10px;
        left: 10px;
        width: 30px;
        height: 30px;
        z-index: 2001;
        cursor: pointer;
        background: none;
        border: none;
        padding: 0;
        font-size: 24px;
        color: var(--text-color);
        opacity: 0.3;
        transition: opacity 0.2s;
    }

    .controls-trigger:hover { opacity: 0.6; }

    .controls {
        position: fixed;
        bottom: 20px;
        left: 20px;
        z-index: 2002;
        display: flex;
        gap: 10px;
        align-items: center;
        opacity: 0;
        visibility: hidden;
        transition: opacity 0.3s ease, visibility 0.3s ease;
    }

    .controls.visible {
        opacity: 1;
        visibility: visible;
    }

    .controls select {
        background: var(--heading-color);
        color: var(--bg-color);
        border: none;
        border-radius: 8px;
        padding: 10px 15px;
        font-size: 14px;
        cursor: pointer;
        box-shadow: 0 2px 10px rgba(0,0,0,0.2);
        transition: transform 0.2s, opacity 0.3s;
        appearance: none;
        padding-right: 35px;
        background-image: url("data:image/svg+xml;charset=UTF-8,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3e%3cpolyline points='6 9 12 15 18 9'%3e%3c/polyline%3e%3c/svg%3e");
        background-repeat: no-repeat;
        background-position: right 10px center;
        background-size: 20px;
    }

    .controls select:focus {
        outline: 2px solid var(--link-color);
        outline-offset: 2px;
    }

    .controls option {
        background: var(--bg-color);
        color: var(--text-color);
        padding: 10px;
    }

    .zoom-control {
        display: flex;
        align-items: center;
        gap: 8px;
        background: var(--heading-color);
        color: var(--bg-color);
        border-radius: 8px;
        padding: 8px 12px;
        box-shadow: 0 2px 10px rgba(0,0,0,0.2);
    }

    .zoom-control button {
        background: transparent;
        color: var(--bg-color);
        border: none;
        cursor: pointer;
        font-size: 18px;
        padding: 0 4px;
        opacity: 0.8;
        transition: opacity 0.2s;
    }

    .zoom-value {
        min-width: 45px;
        text-align: center;
        font-size: 13px;
        font-weight: 500;
    }

    /* File buttons */
    .file-buttons-container {
        position: fixed;
        top: 20px;
        right: 20px;
        display: flex;
        gap: 8px;
        z-index: 2000;
    }

    .copy-file-btn, .download-pdf-btn {
        position: relative;
        background: var(--mermaid-btn-bg);
        color: white;
        border: none;
        border-radius: 8px;
        padding: 10px 15px;
        font-size: 14px;
        cursor: pointer;
        box-shadow: 0 2px 10px rgba(0,0,0,0.2);
        transition: background 0.3s, transform 0.1s;
        white-space: nowrap;
    }

    .copy-file-btn:hover, .download-pdf-btn:hover {
        background: var(--mermaid-btn-hover);
    }

    .copy-file-btn:active, .download-pdf-btn:active {
        transform: scale(0.95);
    }

    /* Code block copy button */
    .code-block-wrapper {
        position: relative;
        margin: 15px 0;
    }

    .code-block-wrapper pre { margin: 0; }

    .copy-btn {
        position: absolute;
        top: 8px;
        right: 8px;
        background: var(--mermaid-btn-bg);
        color: white;
        border: none;
        border-radius: 4px;
        padding: 6px 12px;
        cursor: pointer;
        font-size: 12px;
        font-family: var(--font-body);
        opacity: 0;
        transition: opacity 0.3s, background 0.3s;
        z-index: 10;
    }

    .code-block-wrapper:hover .copy-btn { opacity: 1; }
    .copy-btn:hover { background: var(--mermaid-btn-hover); }
    .copy-btn:active { transform: scale(0.95); }

    /* File info bar */
    .file-info {
        background: var(--file-info-bg);
        padding: 10px 15px;
        border-radius: 5px;
        margin-bottom: 20px;
        font-size: 14px;
        color: var(--file-info-color);
    }

    .nav-bar {
        margin-bottom: 20px;
    }

    .nav-bar a {
        text-decoration: none;
        color: var(--link-color);
        font-size: 14px;
    }
    """
}
