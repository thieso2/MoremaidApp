import SwiftUI

@main
struct MoremaidApp: App {
    @State private var appState = AppState()

    init() {
        let state = _appState.wrappedValue
        Task { @MainActor in
            await state.startup()
        }
        QuickOpenShortcut.install()
    }

    var body: some Scene {
        MenuBarExtra("Moremaid", systemImage: "doc.richtext") {
            MenuBarView()
                .environment(appState)
        }

        Settings {
            PreferencesView()
                .environment(appState)
        }

        WindowGroup(id: "project", for: UUID.self) { $projectID in
            if let projectID, let project = appState.projectManager.project(for: projectID) {
                ProjectWindowView(project: project)
                    .environment(appState)
            } else {
                Text("Project not found")
                    .frame(width: 400, height: 300)
            }
        }
        .defaultSize(width: 800, height: 600)
    }
}
