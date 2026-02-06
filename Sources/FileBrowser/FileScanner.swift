import Foundation

private let scanQueue = DispatchQueue(label: "com.moremaid.scanner", qos: .userInitiated)

enum FileScanner {
    /// Recursively scans a directory for files, respecting .gitignore patterns.
    static func scan(directory: String, filter: FileFilter) -> [FileEntry] {
        let basePath = (directory as NSString).standardizingPath
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: basePath),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [FileEntry] = []
        let gitignore = GitignoreParser(basePath: basePath)

        for case let url as URL in enumerator {
            let relativePath = String(url.path.dropFirst(basePath.count + 1))

            let components = relativePath.split(separator: "/").map(String.init)
            if components.contains("node_modules") || components.contains(".git") {
                if url.hasDirectoryPath { enumerator.skipDescendants() }
                continue
            }

            if gitignore.isIgnored(relativePath) {
                if url.hasDirectoryPath { enumerator.skipDescendants() }
                continue
            }

            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { continue }

            let isMd = isMarkdownFile(url.lastPathComponent)
            if filter == .markdownOnly && !isMd { continue }

            let entry = FileEntry(
                id: relativePath,
                name: url.lastPathComponent,
                relativePath: relativePath,
                absolutePath: url.path,
                size: values.fileSize ?? 0,
                modifiedDate: values.contentModificationDate ?? Date.distantPast,
                isMarkdown: isMd
            )
            entries.append(entry)
        }

        return entries
    }

    /// Scans on a background queue, dispatching batches to the caller via callback.
    static func scanBatched(
        directory: String,
        filter: FileFilter,
        batchSize: Int,
        callback: @escaping @Sendable ([FileEntry], _ done: Bool) -> Void
    ) {
        scanQueue.async {
            let start = CFAbsoluteTimeGetCurrent()
            let basePath = (directory as NSString).standardizingPath
            print("[scan] starting: \(basePath)")

            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: basePath),
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                print("[scan] failed to create enumerator")
                callback([], true)
                return
            }

            let gitignoreStart = CFAbsoluteTimeGetCurrent()
            let gitignore = GitignoreParser(basePath: basePath)
            print("[scan] gitignore parsed in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - gitignoreStart) * 1000))ms")

            var batch: [FileEntry] = []
            var count = 0
            var skippedDirs = 0
            var enumTime = 0.0
            var gitignoreTime = 0.0
            var statTime = 0.0

            for case let url as URL in enumerator {
                let t0 = CFAbsoluteTimeGetCurrent()
                let relativePath = String(url.path.dropFirst(basePath.count + 1))
                enumTime += CFAbsoluteTimeGetCurrent() - t0

                let components = relativePath.split(separator: "/").map(String.init)
                if components.contains("node_modules") || components.contains(".git") {
                    if url.hasDirectoryPath { enumerator.skipDescendants(); skippedDirs += 1 }
                    continue
                }

                let t1 = CFAbsoluteTimeGetCurrent()
                let ignored = gitignore.isIgnored(relativePath)
                gitignoreTime += CFAbsoluteTimeGetCurrent() - t1

                if ignored {
                    if url.hasDirectoryPath { enumerator.skipDescendants(); skippedDirs += 1 }
                    continue
                }

                let t2 = CFAbsoluteTimeGetCurrent()
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else {
                    statTime += CFAbsoluteTimeGetCurrent() - t2
                    continue
                }
                statTime += CFAbsoluteTimeGetCurrent() - t2

                let isMd = isMarkdownFile(url.lastPathComponent)
                if filter == .markdownOnly && !isMd { continue }

                count += 1
                if count == 1 {
                    print("[scan] first file found in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
                }

                batch.append(FileEntry(
                    id: relativePath,
                    name: url.lastPathComponent,
                    relativePath: relativePath,
                    absolutePath: url.path,
                    size: values.fileSize ?? 0,
                    modifiedDate: values.contentModificationDate ?? Date.distantPast,
                    isMarkdown: isMd
                ))

                if batch.count >= batchSize {
                    let chunk = batch
                    batch = []
                    callback(chunk, false)
                }
            }

            if !batch.isEmpty {
                callback(batch, false)
            }
            callback([], true)

            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[scan] done: \(count) files, \(skippedDirs) dirs skipped, \(String(format: "%.1f", elapsed))ms")
            print("[scan] breakdown — enum: \(String(format: "%.1f", enumTime * 1000))ms, gitignore: \(String(format: "%.1f", gitignoreTime * 1000))ms, stat: \(String(format: "%.1f", statTime * 1000))ms")
        }
    }
}
