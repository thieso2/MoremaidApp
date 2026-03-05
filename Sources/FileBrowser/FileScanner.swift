import Foundation

private let scanQueue = DispatchQueue(label: "com.moremaid.scanner", qos: .userInitiated)
private let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
private let resourceKeysArray = Array(resourceKeys)
private let parallelQueue = DispatchQueue(label: "com.moremaid.scanner.parallel", qos: .userInitiated, attributes: .concurrent)

enum FileScanner {
    /// Recursively scans a directory for files, respecting .gitignore patterns.
    static func scan(directory: String, filter: FileFilter) -> [FileEntry] {
        let basePath = (directory as NSString).standardizingPath
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: basePath),
            includingPropertiesForKeys: resourceKeysArray,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [FileEntry] = []
        let gitignore = GitignoreParser(basePath: basePath)

        for case let url as URL in enumerator {
            let relativePath = String(url.path.dropFirst(basePath.count + 1))

            if shouldSkipComponent(relativePath) {
                if url.hasDirectoryPath { enumerator.skipDescendants() }
                continue
            }

            if gitignore.isIgnored(relativePath) {
                if url.hasDirectoryPath { enumerator.skipDescendants() }
                continue
            }

            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else { continue }

            let isMd = isMarkdownFile(url.lastPathComponent)
            if filter == .markdownOnly && !isMd { continue }

            entries.append(FileEntry(
                id: relativePath,
                name: url.lastPathComponent,
                relativePath: relativePath,
                absolutePath: url.path,
                size: values.fileSize ?? 0,
                modifiedDate: values.contentModificationDate ?? Date.distantPast,
                isMarkdown: isMd
            ))
        }

        return entries
    }

    /// Scans on background queues, parallelizing across top-level subdirectories.
    static func scanBatched(
        directory: String,
        filter: FileFilter,
        batchSize: Int,
        callback: @escaping @Sendable ([FileEntry], _ done: Bool) -> Void
    ) {
        scanQueue.async {
            let start = CFAbsoluteTimeGetCurrent()
            let basePath = (directory as NSString).standardizingPath
            let baseURL = URL(fileURLWithPath: basePath)
            let fm = FileManager.default
            print("[scan] starting: \(basePath)")

            let gitignore = GitignoreParser(basePath: basePath)

            // Collect top-level entries: scan root files + gather subdirectories
            var rootFiles: [FileEntry] = []
            var subdirs: [(url: URL, relativeName: String)] = []

            if let contents = try? fm.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: resourceKeysArray,
                options: [.skipsHiddenFiles]
            ) {
                for url in contents {
                    let name = url.lastPathComponent
                    if name == "node_modules" || name == ".git" { continue }
                    if gitignore.isIgnored(name) { continue }

                    if url.hasDirectoryPath {
                        subdirs.append((url: url, relativeName: name))
                    } else {
                        guard let values = try? url.resourceValues(forKeys: resourceKeys),
                              values.isRegularFile == true else { continue }
                        let isMd = isMarkdownFile(name)
                        if filter == .markdownOnly && !isMd { continue }
                        rootFiles.append(FileEntry(
                            id: name, name: name, relativePath: name, absolutePath: url.path,
                            size: values.fileSize ?? 0,
                            modifiedDate: values.contentModificationDate ?? Date.distantPast,
                            isMarkdown: isMd
                        ))
                    }
                }
            }

            if !rootFiles.isEmpty {
                callback(rootFiles, false)
            }

            if subdirs.isEmpty {
                callback([], true)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                print("[scan] done: \(rootFiles.count) files, 0 subdirs, \(String(format: "%.1f", elapsed))ms")
                return
            }

            // Scan subdirectories in parallel
            let group = DispatchGroup()
            let totalFiles = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            totalFiles.initialize(to: rootFiles.count)
            let lock = NSLock()

            for subdir in subdirs {
                group.enter()
                parallelQueue.async {
                    let prefix = subdir.relativeName + "/"
                    var batch: [FileEntry] = []

                    guard let enumerator = fm.enumerator(
                        at: subdir.url,
                        includingPropertiesForKeys: resourceKeysArray,
                        options: [.skipsHiddenFiles]
                    ) else {
                        group.leave()
                        return
                    }

                    for case let url as URL in enumerator {
                        let relativePath = prefix + String(url.path.dropFirst(subdir.url.path.count + 1))

                        if shouldSkipComponent(relativePath) {
                            if url.hasDirectoryPath { enumerator.skipDescendants() }
                            continue
                        }

                        if gitignore.isIgnored(relativePath) {
                            if url.hasDirectoryPath { enumerator.skipDescendants() }
                            continue
                        }

                        guard let values = try? url.resourceValues(forKeys: resourceKeys),
                              values.isRegularFile == true else { continue }

                        let isMd = isMarkdownFile(url.lastPathComponent)
                        if filter == .markdownOnly && !isMd { continue }

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
                            lock.lock()
                            totalFiles.pointee += chunk.count
                            lock.unlock()
                            callback(chunk, false)
                        }
                    }

                    if !batch.isEmpty {
                        lock.lock()
                        totalFiles.pointee += batch.count
                        lock.unlock()
                        callback(batch, false)
                    }
                    group.leave()
                }
            }

            group.wait()
            callback([], true)

            let count = totalFiles.pointee
            totalFiles.deallocate()
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[scan] done: \(count) files, \(subdirs.count) subdirs parallel, \(String(format: "%.1f", elapsed))ms")
        }
    }

    private static func shouldSkipComponent(_ relativePath: String) -> Bool {
        // Fast check: look for /node_modules or /node_modules/ and /.git or /.git/
        if relativePath.contains("node_modules") || relativePath.contains(".git") {
            let components = relativePath.split(separator: "/")
            return components.contains("node_modules") || components.contains(".git")
        }
        return false
    }
}
