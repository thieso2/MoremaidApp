import Foundation

struct FileChangeEvent: Sendable {
    let paths: [String]
    let timestamp: Date
}

/// Watches directories for file changes using FSEvents.
actor FileWatcher {
    private var streams: [String: FSEventStreamRef] = [:]
    private var continuations: [String: AsyncStream<FileChangeEvent>.Continuation] = [:]

    func watch(directory: String) -> AsyncStream<FileChangeEvent> {
        // Stop existing watcher for this directory
        stopWatching(directory: directory)

        let (stream, continuation) = AsyncStream<FileChangeEvent>.makeStream()
        continuations[directory] = continuation

        startFSEventStream(for: directory)

        return stream
    }

    func stopWatching(directory: String) {
        if let stream = streams.removeValue(forKey: directory) {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        continuations[directory]?.finish()
        continuations.removeValue(forKey: directory)
    }

    func stopAll() {
        for directory in Array(streams.keys) {
            stopWatching(directory: directory)
        }
    }

    nonisolated func handleEvents(paths: [String], directory: String) {
        Task {
            await _handleEvents(paths: paths, directory: directory)
        }
    }

    private func _handleEvents(paths: [String], directory: String) {
        guard let continuation = continuations[directory] else { return }

        // Filter out hidden files, .git, node_modules, build artifacts
        let filtered = paths.filter { path in
            let components = path.split(separator: "/")
            return !components.contains(where: { component in
                let c = String(component)
                return c.hasPrefix(".") || c == "node_modules" || c == "Derived" || c == "build"
            })
        }

        guard !filtered.isEmpty else { return }

        let event = FileChangeEvent(paths: filtered, timestamp: Date())
        continuation.yield(event)
    }

    private func startFSEventStream(for directory: String) {
        let pathsToWatch = [directory] as CFArray

        // Store reference to self for the callback context
        let context = Unmanaged.passRetained(WatcherContext(watcher: self, directory: directory))

        var fsContext = FSEventStreamContext(
            version: 0,
            info: context.toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<WatcherContext>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &fsContext,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2, // 200ms latency (debounce)
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            context.release()
            return
        }

        streams[directory] = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }
}

/// Context object passed to FSEvents callback.
private final class WatcherContext: @unchecked Sendable {
    let watcher: FileWatcher
    let directory: String

    init(watcher: FileWatcher, directory: String) {
        self.watcher = watcher
        self.directory = directory
    }
}

/// FSEvents C callback.
private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let context = Unmanaged<WatcherContext>.fromOpaque(info).takeUnretainedValue()

    guard let cfPaths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

    context.watcher.handleEvents(paths: cfPaths, directory: context.directory)
}
