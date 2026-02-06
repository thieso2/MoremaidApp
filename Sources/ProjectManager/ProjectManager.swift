import Foundation

@Observable
@MainActor
final class ProjectManager {
    private(set) var projects: [Project] = []

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(Constants.appSupportDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Constants.projectsFilename)
    }

    init() {
        loadProjects()
    }

    // MARK: - CRUD

    func addProject(path: String, name: String) {
        let project = Project(name: name, path: path)
        projects.append(project)
        saveProjects()
    }

    func removeProject(id: UUID) {
        projects.removeAll { $0.id == id }
        saveProjects()
    }

    func renameProject(id: UUID, name: String) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        project.name = name
        saveProjects()
    }

    nonisolated func project(for id: UUID) -> Project? {
        // Note: This is a simplification for Phase 1.
        // In production, we'd use proper actor isolation.
        MainActor.assumeIsolated {
            projects.first { $0.id == id }
        }
    }

    func updateTheme(for id: UUID, theme: String?) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        project.themeOverride = theme
        saveProjects()
    }

    func updateTypography(for id: UUID, typography: String?) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        project.typographyOverride = typography
        saveProjects()
    }

    // MARK: - Persistence

    private func loadProjects() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            projects = try JSONDecoder().decode([Project].self, from: data)
        } catch {
            print("Failed to load projects: \(error)")
        }
    }

    private func saveProjects() {
        do {
            let data = try JSONEncoder().encode(projects)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save projects: \(error)")
        }
    }
}
