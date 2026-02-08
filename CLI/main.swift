import Foundation

let version = "1.0.0"

func printUsage() {
    let usage = """
    mm - Open files and folders in Moremaid

    Usage:
      mm                       Launch Moremaid
      mm <path> [<path> ...]   Open files/folders in Moremaid
      mm --help                Show this help
      mm --version             Show version
    """
    print(usage)
}

func resolvePath(_ raw: String) -> String {
    let expanded = NSString(string: raw).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return expanded
    }
    let cwd = FileManager.default.currentDirectoryPath
    return (cwd as NSString).appendingPathComponent(expanded)
}

let args = CommandLine.arguments.dropFirst()

if args.contains("--help") || args.contains("-h") {
    printUsage()
    exit(0)
}

if args.contains("--version") || args.contains("-v") {
    print("mm \(version) (Moremaid CLI)")
    exit(0)
}

// Resolve paths
var urls: [String] = []
for arg in args {
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

// Build `open` command
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
