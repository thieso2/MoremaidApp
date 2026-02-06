import Foundation
import ZIPFoundation

/// Handles creating and opening .moremaid archive files.
enum ArchiveHandler {

    /// Open a .moremaid or .zip file and return a ZipVirtualFS for browsing.
    static func open(url: URL) throws -> ZipVirtualFS {
        try ZipVirtualFS(url: url)
    }

    /// Pack markdown files from a directory into a .moremaid archive.
    static func pack(source: URL, destination: URL) throws {
        let sourcePath = source.path

        // Find markdown files
        let scanner = FileScanner.scan(
            directory: sourcePath,
            filter: .markdownOnly
        )

        guard !scanner.isEmpty else {
            throw ArchiveError.noMarkdownFiles
        }

        // Create archive
        let archive = try Archive(url: destination, accessMode: .create)

        for file in scanner {
            let fileURL = URL(fileURLWithPath: file.absolutePath)
            try archive.addEntry(
                with: file.relativePath,
                fileURL: fileURL,
                compressionMethod: .deflate
            )
        }

        // Add auto-generated README if none exists
        let hasReadme = scanner.contains { $0.name.lowercased() == "readme.md" }
        if !hasReadme {
            let baseName = source.lastPathComponent
            let readme = """
            # \(baseName)

            This archive contains \(scanner.count) markdown file(s).

            ## Files

            \(scanner.map { "- \($0.relativePath)" }.joined(separator: "\n"))

            ---
            *Created with Moremaid*
            """
            let readmeData = Data(readme.utf8)
            try archive.addEntry(
                with: "README.md",
                type: .file,
                uncompressedSize: Int64(readmeData.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    let start = Int(position)
                    let end = min(start + size, readmeData.count)
                    return readmeData.subdata(in: start..<end)
                }
            )
        }
    }

    enum ArchiveError: LocalizedError {
        case noMarkdownFiles

        var errorDescription: String? {
            switch self {
            case .noMarkdownFiles:
                return "No markdown files found in the specified directory"
            }
        }
    }
}
