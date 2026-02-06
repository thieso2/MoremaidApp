import Foundation

/// All 10 theme CSS variable blocks, ported from ../lib/styles.js
enum ThemeCSS {
    static let all = """
    :root, [data-theme="light"] {
        --bg-color: white;
        --bg-color-rgb: 255, 255, 255;
        --text-color: #333;
        --heading-color: #2c3e50;
        --heading2-color: #34495e;
        --border-color: #ecf0f1;
        --code-bg: #f4f4f4;
        --code-color: #d14;
        --link-color: #3498db;
        --blockquote-color: #555;
        --table-header-bg: #f0f0f0;
        --table-border: #ddd;
        --file-info-bg: #f5f5f5;
        --file-info-color: #666;
        --mermaid-btn-bg: rgba(52, 73, 94, 0.8);
        --mermaid-btn-hover: rgba(52, 73, 94, 1);
    }

    [data-theme="dark"] {
        --bg-color: #1a1a1a;
        --bg-color-rgb: 26, 26, 26;
        --text-color: #e0e0e0;
        --heading-color: #61afef;
        --heading2-color: #56b6c2;
        --border-color: #3a3a3a;
        --code-bg: #2d2d2d;
        --code-color: #e06c75;
        --link-color: #61afef;
        --blockquote-color: #abb2bf;
        --table-header-bg: #2d2d2d;
        --table-border: #4a4a4a;
        --file-info-bg: #2d2d2d;
        --file-info-color: #abb2bf;
        --mermaid-btn-bg: rgba(97, 175, 239, 0.8);
        --mermaid-btn-hover: rgba(97, 175, 239, 1);
    }

    [data-theme="github"] {
        --bg-color: #ffffff;
        --bg-color-rgb: 255, 255, 255;
        --text-color: #24292e;
        --heading-color: #24292e;
        --heading2-color: #24292e;
        --border-color: #e1e4e8;
        --code-bg: #f6f8fa;
        --code-color: #e36209;
        --link-color: #0366d6;
        --blockquote-color: #6a737d;
        --table-header-bg: #f6f8fa;
        --table-border: #e1e4e8;
        --file-info-bg: #f6f8fa;
        --file-info-color: #586069;
        --mermaid-btn-bg: rgba(3, 102, 214, 0.8);
        --mermaid-btn-hover: rgba(3, 102, 214, 1);
    }

    [data-theme="github-dark"] {
        --bg-color: #0d1117;
        --bg-color-rgb: 13, 17, 23;
        --text-color: #c9d1d9;
        --heading-color: #58a6ff;
        --heading2-color: #58a6ff;
        --border-color: #30363d;
        --code-bg: #161b22;
        --code-color: #ff7b72;
        --link-color: #58a6ff;
        --blockquote-color: #8b949e;
        --table-header-bg: #161b22;
        --table-border: #30363d;
        --file-info-bg: #161b22;
        --file-info-color: #8b949e;
        --mermaid-btn-bg: rgba(88, 166, 255, 0.8);
        --mermaid-btn-hover: rgba(88, 166, 255, 1);
    }

    [data-theme="dracula"] {
        --bg-color: #282a36;
        --bg-color-rgb: 40, 42, 54;
        --text-color: #f8f8f2;
        --heading-color: #bd93f9;
        --heading2-color: #ff79c6;
        --border-color: #44475a;
        --code-bg: #44475a;
        --code-color: #ff79c6;
        --link-color: #8be9fd;
        --blockquote-color: #6272a4;
        --table-header-bg: #44475a;
        --table-border: #6272a4;
        --file-info-bg: #44475a;
        --file-info-color: #6272a4;
        --mermaid-btn-bg: rgba(189, 147, 249, 0.8);
        --mermaid-btn-hover: rgba(189, 147, 249, 1);
    }

    [data-theme="nord"] {
        --bg-color: #2e3440;
        --bg-color-rgb: 46, 52, 64;
        --text-color: #eceff4;
        --heading-color: #88c0d0;
        --heading2-color: #81a1c1;
        --border-color: #3b4252;
        --code-bg: #3b4252;
        --code-color: #d08770;
        --link-color: #88c0d0;
        --blockquote-color: #d8dee9;
        --table-header-bg: #3b4252;
        --table-border: #4c566a;
        --file-info-bg: #3b4252;
        --file-info-color: #d8dee9;
        --mermaid-btn-bg: rgba(136, 192, 208, 0.8);
        --mermaid-btn-hover: rgba(136, 192, 208, 1);
    }

    [data-theme="solarized-light"] {
        --bg-color: #fdf6e3;
        --bg-color-rgb: 253, 246, 227;
        --text-color: #657b83;
        --heading-color: #073642;
        --heading2-color: #586e75;
        --border-color: #eee8d5;
        --code-bg: #eee8d5;
        --code-color: #dc322f;
        --link-color: #268bd2;
        --blockquote-color: #839496;
        --table-header-bg: #eee8d5;
        --table-border: #93a1a1;
        --file-info-bg: #eee8d5;
        --file-info-color: #839496;
        --mermaid-btn-bg: rgba(38, 139, 210, 0.8);
        --mermaid-btn-hover: rgba(38, 139, 210, 1);
    }

    [data-theme="solarized-dark"] {
        --bg-color: #002b36;
        --bg-color-rgb: 0, 43, 54;
        --text-color: #839496;
        --heading-color: #93a1a1;
        --heading2-color: #839496;
        --border-color: #073642;
        --code-bg: #073642;
        --code-color: #dc322f;
        --link-color: #268bd2;
        --blockquote-color: #657b83;
        --table-header-bg: #073642;
        --table-border: #586e75;
        --file-info-bg: #073642;
        --file-info-color: #657b83;
        --mermaid-btn-bg: rgba(38, 139, 210, 0.8);
        --mermaid-btn-hover: rgba(38, 139, 210, 1);
    }

    [data-theme="monokai"] {
        --bg-color: #272822;
        --bg-color-rgb: 39, 40, 34;
        --text-color: #f8f8f2;
        --heading-color: #66d9ef;
        --heading2-color: #a6e22e;
        --border-color: #3e3d32;
        --code-bg: #3e3d32;
        --code-color: #f92672;
        --link-color: #66d9ef;
        --blockquote-color: #75715e;
        --table-header-bg: #3e3d32;
        --table-border: #75715e;
        --file-info-bg: #3e3d32;
        --file-info-color: #75715e;
        --mermaid-btn-bg: rgba(102, 217, 239, 0.8);
        --mermaid-btn-hover: rgba(102, 217, 239, 1);
    }

    [data-theme="one-dark"] {
        --bg-color: #282c34;
        --bg-color-rgb: 40, 44, 52;
        --text-color: #abb2bf;
        --heading-color: #61afef;
        --heading2-color: #e06c75;
        --border-color: #3e4451;
        --code-bg: #3e4451;
        --code-color: #e06c75;
        --link-color: #61afef;
        --blockquote-color: #5c6370;
        --table-header-bg: #3e4451;
        --table-border: #4b5263;
        --file-info-bg: #3e4451;
        --file-info-color: #5c6370;
        --mermaid-btn-bg: rgba(97, 175, 239, 0.8);
        --mermaid-btn-hover: rgba(97, 175, 239, 1);
    }
    """
}
