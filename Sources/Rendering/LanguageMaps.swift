import Foundation

/// Language alias and extension maps from SPEC Appendix D.
enum LanguageMaps {
    /// Alias map: markdown code block language → Prism language name.
    /// Used during markdown→HTML conversion to fix class names.
    static let aliasMap: [String: String] = [
        "js": "javascript",
        "ts": "typescript",
        "py": "python",
        "rb": "ruby",
        "yml": "yaml",
        "sh": "bash",
        "shell": "bash",
        "cs": "csharp",
    ]

    /// File extension → Prism language name.
    /// Used when rendering non-markdown files.
    static let extensionToLanguage: [String: String] = [
        "js": "javascript",
        "ts": "typescript",
        "jsx": "jsx",
        "tsx": "tsx",
        "py": "python",
        "rb": "ruby",
        "yml": "yaml",
        "yaml": "yaml",
        "json": "json",
        "xml": "xml",
        "html": "html",
        "css": "css",
        "scss": "scss",
        "sass": "sass",
        "sh": "bash",
        "bash": "bash",
        "sql": "sql",
        "java": "java",
        "swift": "swift",
        "kt": "kotlin",
        "r": "r",
        "pl": "perl",
        "lua": "lua",
        "vim": "vim",
        "dockerfile": "docker",
        "makefile": "makefile",
        "txt": "plaintext",
        "c": "c",
        "cpp": "cpp",
        "h": "c",
        "hpp": "cpp",
        "cs": "csharp",
        "go": "go",
        "rs": "rust",
        "php": "php",
    ]
}
