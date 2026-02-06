import Foundation

/// Mermaid theme variable sets from SPEC Appendix C.
enum MermaidConfig {
    struct ThemeVariables {
        let primaryColor: String
        let primaryTextColor: String
        let primaryBorderColor: String
        let lineColor: String
        let secondaryColor: String
        let tertiaryColor: String?
        let background: String?
        let mainBkg: String?
        let secondBkg: String?
        let tertiaryBkg: String?
    }

    static let light = ThemeVariables(
        primaryColor: "#3498db", primaryTextColor: "#fff", primaryBorderColor: "#2980b9",
        lineColor: "#5a6c7d", secondaryColor: "#ecf0f1", tertiaryColor: "#fff",
        background: nil, mainBkg: nil, secondBkg: nil, tertiaryBkg: nil
    )

    static let dark = ThemeVariables(
        primaryColor: "#61afef", primaryTextColor: "#1a1a1a", primaryBorderColor: "#4b5263",
        lineColor: "#abb2bf", secondaryColor: "#2d2d2d", tertiaryColor: "#3a3a3a",
        background: "#1a1a1a", mainBkg: "#61afef", secondBkg: "#56b6c2", tertiaryBkg: "#98c379"
    )

    static let github = ThemeVariables(
        primaryColor: "#0366d6", primaryTextColor: "#fff", primaryBorderColor: "#0366d6",
        lineColor: "#586069", secondaryColor: "#f6f8fa", tertiaryColor: nil,
        background: nil, mainBkg: nil, secondBkg: nil, tertiaryBkg: nil
    )

    static let dracula = ThemeVariables(
        primaryColor: "#bd93f9", primaryTextColor: "#f8f8f2", primaryBorderColor: "#6272a4",
        lineColor: "#6272a4", secondaryColor: "#44475a", tertiaryColor: nil,
        background: "#282a36", mainBkg: nil, secondBkg: nil, tertiaryBkg: nil
    )

    static let nord = ThemeVariables(
        primaryColor: "#88c0d0", primaryTextColor: "#2e3440", primaryBorderColor: "#5e81ac",
        lineColor: "#4c566a", secondaryColor: "#3b4252", tertiaryColor: nil,
        background: "#2e3440", mainBkg: nil, secondBkg: nil, tertiaryBkg: nil
    )

    static let solarized = ThemeVariables(
        primaryColor: "#268bd2", primaryTextColor: "#fdf6e3", primaryBorderColor: "#93a1a1",
        lineColor: "#657b83", secondaryColor: "#eee8d5", tertiaryColor: nil,
        background: nil, mainBkg: nil, secondBkg: nil, tertiaryBkg: nil
    )

    static let monokai = ThemeVariables(
        primaryColor: "#66d9ef", primaryTextColor: "#272822", primaryBorderColor: "#75715e",
        lineColor: "#75715e", secondaryColor: "#3e3d32", tertiaryColor: nil,
        background: "#272822", mainBkg: nil, secondBkg: nil, tertiaryBkg: nil
    )

    /// Maps app theme name to (mermaid base theme, variable set)
    static func variablesForTheme(_ theme: String) -> (base: String, variables: ThemeVariables) {
        switch theme {
        case "light", "solarized-light":
            return ("default", theme == "solarized-light" ? solarized : light)
        case "dark", "one-dark":
            return ("dark", dark)
        case "github":
            return ("default", github)
        case "github-dark":
            return ("dark", github)
        case "dracula":
            return ("dark", dracula)
        case "nord":
            return ("dark", nord)
        case "solarized-dark":
            return ("dark", solarized)
        case "monokai":
            return ("dark", monokai)
        default:
            return ("default", light)
        }
    }

    /// Background colors for mermaid fullscreen window per theme.
    static let fullscreenBackgrounds: [String: String] = [
        "light": "white",
        "dark": "#1a1a1a",
        "github": "#ffffff",
        "github-dark": "#0d1117",
        "dracula": "#282a36",
        "nord": "#2e3440",
        "solarized-light": "#fdf6e3",
        "solarized-dark": "#002b36",
        "monokai": "#272822",
        "one-dark": "#282c34",
    ]
}
