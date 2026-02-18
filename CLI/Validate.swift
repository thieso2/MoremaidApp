import Foundation

enum CLIValidate {
    static func run(paths: [String]) -> Int32 {
        var hasErrors = false
        let fm = FileManager.default

        for path in paths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
                fputs("Warning: Path not found: \(path)\n", stderr)
                continue
            }

            if isDir.boolValue {
                let result = MermaidValidator.validateDirectory(at: path)
                printDirectoryResult(result, path: path)
                if result.totalStats.filesWithErrors > 0 { hasErrors = true }
            } else {
                guard isMarkdownFile(path) else {
                    fputs("Warning: Skipping non-markdown file: \(path)\n", stderr)
                    continue
                }
                let result = MermaidValidator.validateFile(at: path)
                printFileResult(result)
                if !result.errors.isEmpty { hasErrors = true }
            }
        }

        return hasErrors ? 1 : 0
    }

    private static func printFileResult(_ result: FileValidationResult) {
        if result.errors.isEmpty {
            print("✓ \(result.path)")
        } else {
            for error in result.errors {
                let loc = error.line.map { ":\($0)" } ?? ""
                print("✗ \(result.path)\(loc): \(error.message)")
            }
        }
    }

    private static func printDirectoryResult(_ result: ValidationResult, path: String) {
        for fileResult in result.files {
            printFileResult(fileResult)
        }

        let stats = result.totalStats
        if stats.filesChecked == 0 {
            print("No markdown files found in \(path)")
            return
        }

        print("")
        if stats.filesWithErrors == 0 {
            print("✓ \(stats.filesChecked) file(s) checked — no errors")
        } else {
            print("✗ \(stats.filesWithErrors)/\(stats.filesChecked) file(s) have errors (\(stats.mermaidErrors) mermaid error(s))")
        }
    }
}
