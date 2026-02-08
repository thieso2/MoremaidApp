import Foundation

enum Constants {
    // MARK: - Server
    static let serverPort: UInt16 = 13277
    static let maxPortAttempts = 10

    // MARK: - Timeouts & Intervals
    static let inactivityTimeout: TimeInterval = 10.0
    static let wsReconnectDelay: TimeInterval = 0.5
    static let wsPingInterval: TimeInterval = 30.0
    static let fseventsDebounce: TimeInterval = 0.2
    static let copyFeedbackDuration: TimeInterval = 2.0
    static let parentPollInterval: TimeInterval = 0.5
    static let childCloseDelay: TimeInterval = 0.5

    // MARK: - Zoom
    static let zoomMin = 50
    static let zoomMax = 200
    static let zoomStep = 10
    static let zoomDefault = 100

    // MARK: - Search
    static let searchMaxMatches = 5
    static let searchLineTrim = 200
    static let searchFuzzy = 0.2
    static let searchMinTerm = 2

    // MARK: - Search in Files
    static let searchInFilesMaxMatches = 20
    static let searchInFilesDebounce: TimeInterval = 0.3
    static let searchPanelMinWidth: CGFloat = 250
    static let searchPanelMaxWidth: CGFloat = 500
    static let searchPanelDefaultWidth: CGFloat = 320

    // MARK: - Archive
    static let lruCacheSize = 100 * 1024 * 1024 // 100 MB
    static let archiveExtension = ".moremaid"
    static let markdownExtensions: Set<String> = ["md", "markdown"]

    // MARK: - CDN Versions
    static let mermaidVersion = "10"
    static let prismVersion = "1.29.0"

    // MARK: - PDF
    static let pdfPaper = "A4"
    static let pdfMarginTop = "20mm"
    static let pdfMarginRight = "20mm"
    static let pdfMarginBottom = "25mm"
    static let pdfMarginLeft = "20mm"

    // MARK: - Mermaid Fullscreen
    static let fullscreenWindowWidth = 800
    static let fullscreenWindowHeight = 600

    // MARK: - Persistence
    static let appSupportDirectory = "Moremaid"

    // MARK: - Themes
    static let availableThemes = [
        "light", "dark", "github", "github-dark", "dracula",
        "nord", "solarized-light", "solarized-dark", "monokai", "one-dark",
    ]
    static let defaultTheme = "light"

    static let darkThemes: Set<String> = [
        "dark", "github-dark", "dracula", "nord",
        "solarized-dark", "monokai", "one-dark",
    ]

    // MARK: - Typography
    static let availableTypography = [
        "default", "github", "latex", "tufte", "medium",
        "compact", "wide", "newspaper", "terminal", "book",
    ]
    static let defaultTypography = "default"
}
