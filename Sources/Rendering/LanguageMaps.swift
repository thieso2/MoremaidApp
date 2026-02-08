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
        "dockerfile": "docker",
        "objc": "objectivec",
        "objective-c": "objectivec",
        "f#": "fsharp",
        "tex": "latex",
        "ps1": "powershell",
        "bat": "batch",
        "cmd": "batch",
        "proto": "protobuf",
        "tf": "hcl",
        "terraform": "hcl",
        "gql": "graphql",
        "patch": "diff",
        "zsh": "bash",
    ]

    /// File extension → Prism language name.
    /// Used when rendering non-markdown files.
    static let extensionToLanguage: [String: String] = [
        // Web
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "ts": "typescript",
        "jsx": "jsx",
        "tsx": "tsx",
        "html": "markup",
        "htm": "markup",
        "xml": "markup",
        "svg": "markup",
        "css": "css",
        "scss": "scss",
        "sass": "sass",
        "less": "less",
        "json": "json",
        "jsonc": "json",
        "graphql": "graphql",
        "gql": "graphql",
        "vue": "markup",
        "svelte": "markup",

        // Config
        "toml": "toml",
        "yaml": "yaml",
        "yml": "yaml",
        "ini": "ini",
        "cfg": "ini",
        "conf": "ini",
        "properties": "properties",
        "env": "bash",
        "hcl": "hcl",
        "tf": "hcl",
        "tfvars": "hcl",
        "nginx": "nginx",

        // Shell & scripting
        "sh": "bash",
        "bash": "bash",
        "zsh": "bash",
        "fish": "bash",
        "bat": "batch",
        "cmd": "batch",
        "ps1": "powershell",
        "psm1": "powershell",

        // Systems
        "c": "c",
        "h": "c",
        "cpp": "cpp",
        "cxx": "cpp",
        "cc": "cpp",
        "hpp": "cpp",
        "hxx": "cpp",
        "rs": "rust",
        "go": "go",
        "zig": "zig",

        // JVM
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "scala": "scala",
        "groovy": "groovy",
        "gradle": "groovy",

        // .NET
        "cs": "csharp",
        "fs": "fsharp",
        "fsx": "fsharp",
        "vb": "visual-basic",

        // Apple / mobile
        "swift": "swift",
        "m": "objectivec",
        "mm": "objectivec",
        "dart": "dart",

        // Scripting
        "py": "python",
        "pyw": "python",
        "rb": "ruby",
        "php": "php",
        "pl": "perl",
        "pm": "perl",
        "lua": "lua",
        "r": "r",
        "jl": "julia",

        // Functional
        "ex": "elixir",
        "exs": "elixir",
        "erl": "erlang",
        "clj": "clojure",
        "cljs": "clojure",
        "hs": "haskell",
        "ml": "ocaml",
        "mli": "ocaml",
        "elm": "elm",
        "lisp": "lisp",
        "scm": "scheme",
        "rkt": "scheme",

        // Data & query
        "sql": "sql",
        "proto": "protobuf",

        // Markup & docs
        "tex": "latex",
        "latex": "latex",
        "rst": "rest",
        "adoc": "asciidoc",
        "pug": "pug",
        "handlebars": "handlebars",
        "hbs": "handlebars",
        "ejs": "ejs",

        // DevOps & build
        "dockerfile": "docker",
        "makefile": "makefile",
        "cmake": "cmake",

        // Diff & patch
        "diff": "diff",
        "patch": "diff",

        // Misc
        "vim": "vim",
        "regex": "regex",
        "wasm": "wasm",
        "txt": "plaintext",
        "log": "plaintext",
    ]

    /// Basename (no extension) → Prism language name.
    /// Used for extensionless files like Dockerfile, Makefile, etc.
    static let filenameToLanguage: [String: String] = [
        "Dockerfile": "docker",
        "Makefile": "makefile",
        "Gemfile": "ruby",
        "Rakefile": "ruby",
        "CMakeLists.txt": "cmake",
        "Vagrantfile": "ruby",
        "Justfile": "makefile",
        ".gitignore": "git",
        ".gitattributes": "git",
        ".editorconfig": "editorconfig",
        ".dockerignore": "docker",
        ".bashrc": "bash",
        ".bash_profile": "bash",
        ".zshrc": "bash",
        ".profile": "bash",
    ]

    /// Prism language dependencies. Languages not listed here are standalone.
    /// prism.min.js includes: markup, css, clike, javascript.
    /// Only list dependencies NOT already in prism.min.js.
    private static let prismDependencies: [String: [String]] = [
        "typescript": ["javascript"],
        "jsx": ["markup", "javascript"],
        "tsx": ["jsx", "typescript"],
        "c": ["clike"],
        "cpp": ["c"],
        "csharp": ["clike"],
        "fsharp": ["clike"],
        "java": ["clike"],
        "kotlin": ["clike"],
        "scala": ["java"],
        "groovy": ["clike"],
        "go": ["clike"],
        "dart": ["clike"],
        "php": ["markup", "clike"],
        "objectivec": ["c"],
        "swift": ["clike"],
        "scss": ["css"],
        "less": ["css"],
        "pug": ["markup", "javascript"],
        "handlebars": ["markup"],
        "ejs": ["markup", "javascript"],
        "docker": ["clike"],
        "hcl": ["clike"],
        "protobuf": ["clike"],
    ]

    /// Languages already bundled in prism.min.js (no script tag needed).
    private static let builtinLanguages: Set<String> = [
        "markup", "html", "xml", "svg", "css", "clike", "javascript", "plaintext",
    ]

    /// Resolve the Prism language for a given filename.
    static func language(forFile fileName: String) -> String {
        // Try exact filename match first
        let basename = (fileName as NSString).lastPathComponent
        if let lang = filenameToLanguage[basename] {
            return lang
        }

        // Try extension
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext.isEmpty {
            // Try lowercased basename for extensionless files
            return filenameToLanguage[basename] ?? "plaintext"
        }
        return extensionToLanguage[ext] ?? "plaintext"
    }

    /// Returns an ordered list of Prism component names to load for a language.
    /// Resolves the full dependency chain, excludes builtins (already in prism.min.js).
    static func prismComponents(for language: String) -> [String] {
        if language == "plaintext" || builtinLanguages.contains(language) {
            return []
        }

        var result: [String] = []
        var visited: Set<String> = []

        func resolve(_ lang: String) {
            guard !visited.contains(lang), !builtinLanguages.contains(lang) else { return }
            visited.insert(lang)
            if let deps = prismDependencies[lang] {
                for dep in deps { resolve(dep) }
            }
            result.append(lang)
        }

        resolve(language)
        return result
    }

    /// Returns HTML `<script>` tags for loading Prism language components from CDN.
    static func prismScriptTags(for language: String, version: String) -> String {
        let components = prismComponents(for: language)
        return components.map { component in
            "<script src=\"https://cdn.jsdelivr.net/npm/prismjs@\(version)/components/prism-\(component).min.js\"></script>"
        }.joined(separator: "\n            ")
    }
}
