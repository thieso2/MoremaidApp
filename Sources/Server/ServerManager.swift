import Foundation
import FlyingFox

@Observable
@MainActor
final class ServerManager {
    private(set) var isRunning = false
    private var serverTask: Task<Void, Never>?
    private var server: MoremaidServer?
    private let fileWatcher = FileWatcher()
    private var watchTasks: [String: Task<Void, Never>] = [:]

    func start(projectManager: ProjectManager) async {
        guard !isRunning else { return }

        let moremaidServer = MoremaidServer(port: Constants.serverPort)
        self.server = moremaidServer

        serverTask = Task { [weak self] in
            do {
                try await moremaidServer.start(projectManager: projectManager)
            } catch {
                if !Task.isCancelled {
                    print("Server error: \(error)")
                }
            }
            self?.isRunning = false
        }

        isRunning = true
        print("Moremaid server starting on port \(Constants.serverPort)")
    }

    func watchProject(path: String) {
        guard watchTasks[path] == nil else { return }

        let watcher = fileWatcher
        watchTasks[path] = Task.detached {
            let events = await watcher.watch(directory: path)
            for await _ in events {
                await ClientRegistry.shared.broadcast(.text("reload"))
            }
        }
    }

    func unwatchProject(path: String) {
        watchTasks[path]?.cancel()
        watchTasks.removeValue(forKey: path)

        Task {
            await fileWatcher.stopWatching(directory: path)
        }
    }

    func stop() async {
        serverTask?.cancel()
        serverTask = nil

        for (_, task) in watchTasks {
            task.cancel()
        }
        watchTasks.removeAll()

        await fileWatcher.stopAll()
        await server?.stop()
        server = nil
        isRunning = false
        print("Moremaid server stopped")
    }
}
