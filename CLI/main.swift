import Foundation

let version = "1.0.0"

func printUsage() {
    print("""
    mm - Open files and folders in Moremaid

    Usage:
      mm                                   Launch Moremaid
      mm <path> [<path> ...]               Open files/folders in Moremaid
      mm --validate [<path> ...]           Validate Mermaid blocks in markdown files
                                           (defaults to current directory)
      mm --pdf <file.md> [<file.md> ...]   Convert markdown files to PDF
           [--output <dir>]                Output directory (default: current directory)
      mm --help                            Show this help
      mm --version                         Show version
    """)
}

func resolvePath(_ raw: String) -> String {
    let expanded = NSString(string: raw).expandingTildeInPath
    if expanded.hasPrefix("/") { return expanded }
    return (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(expanded)
}

/// Locates Moremaid.app binary relative to this CLI binary (which lives inside the bundle).
/// CLI path: Moremaid.app/Contents/SharedSupport/bin/mm
/// App path: Moremaid.app/Contents/MacOS/Moremaid
func findAppBinary() -> String? {
    let argv0URL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        .resolvingSymlinksInPath()

    let contentsURL = argv0URL
        .deletingLastPathComponent() // mm -> bin/
        .deletingLastPathComponent() // bin/ -> SharedSupport/
        .deletingLastPathComponent() // SharedSupport/ -> Contents/

    let bundleBinary = contentsURL.appendingPathComponent("MacOS/Moremaid")
    if FileManager.default.fileExists(atPath: bundleBinary.path) {
        return bundleBinary.path
    }

    // Fallback: common install locations
    for path in [
        "/Applications/Moremaid.app/Contents/MacOS/Moremaid",
        "\(NSHomeDirectory())/Applications/Moremaid.app/Contents/MacOS/Moremaid",
    ] {
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    return nil
}

let rawArgs = Array(CommandLine.arguments.dropFirst())

// --help
if rawArgs.contains("--help") || rawArgs.contains("-h") {
    printUsage()
    exit(0)
}

// --version
if rawArgs.contains("--version") || rawArgs.contains("-v") {
    print("mm \(version) (Moremaid CLI)")
    exit(0)
}

// --validate
if rawArgs.contains("--validate") {
    var paths: [String] = []
    for arg in rawArgs where arg != "--validate" {
        if arg.hasPrefix("-") {
            fputs("Unknown option: \(arg)\n", stderr)
            printUsage()
            exit(1)
        }
        paths.append(resolvePath(arg))
    }
    if paths.isEmpty {
        paths = [FileManager.default.currentDirectoryPath]
    }
    exit(CLIValidate.run(paths: paths))
}

// --pdf
if rawArgs.contains("--pdf") {
    var inputFiles: [String] = []
    var outputDir = FileManager.default.currentDirectoryPath
    var i = rawArgs.startIndex
    while i < rawArgs.endIndex {
        let arg = rawArgs[i]
        i = rawArgs.index(after: i)
        if arg == "--pdf" { continue }
        if arg == "--output" {
            guard i < rawArgs.endIndex else {
                fputs("Error: --output requires a directory argument\n", stderr)
                exit(1)
            }
            outputDir = resolvePath(rawArgs[i])
            i = rawArgs.index(after: i)
            continue
        }
        if arg.hasPrefix("-") {
            fputs("Unknown option: \(arg)\n", stderr)
            exit(1)
        }
        let resolved = resolvePath(arg)
        guard FileManager.default.fileExists(atPath: resolved) else {
            fputs("Error: No such file: \(resolved)\n", stderr)
            exit(1)
        }
        inputFiles.append(resolved)
    }

    if inputFiles.isEmpty {
        fputs("Error: --pdf requires at least one markdown file\n", stderr)
        printUsage()
        exit(1)
    }

    guard let appBinary = findAppBinary() else {
        fputs("Error: Cannot find Moremaid app binary. Is the CLI installed correctly?\n", stderr)
        exit(1)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: appBinary)
    process.arguments = ["--pdf"] + inputFiles + ["--output", outputDir]

    do {
        try process.run()
        process.waitUntilExit()
        exit(process.terminationStatus)
    } catch {
        fputs("Error: Failed to launch Moremaid for PDF export: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

// Default: open path(s) in Moremaid
var urls: [String] = []
for arg in rawArgs {
    if arg.hasPrefix("-") {
        fputs("Unknown option: \(arg)\n", stderr)
        printUsage()
        exit(1)
    }
    let resolved = resolvePath(arg)
    guard FileManager.default.fileExists(atPath: resolved) else {
        fputs("Error: No such file or directory: \(resolved)\n", stderr)
        exit(1)
    }
    urls.append(resolved)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
var arguments = ["-a", "Moremaid"]
arguments.append(contentsOf: urls)
process.arguments = arguments

do {
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    fputs("Error: Failed to launch Moremaid: \(error.localizedDescription)\n", stderr)
    exit(1)
}
