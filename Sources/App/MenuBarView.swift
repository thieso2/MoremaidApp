import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let projects = appState.projectManager.projects

        if projects.isEmpty {
            Text("No projects")
                .foregroundStyle(.secondary)
        } else {
            ForEach(projects) { project in
                Button {
                    openWindow(id: "project", value: project.id)
                    NSApplication.shared.activate()
                } label: {
                    HStack {
                        Text(project.name)
                        Spacer()
                    }
                }
            }
        }

        Divider()

        Button("Add Project...") {
            Task {
                await addProject()
            }
        }
        .keyboardShortcut("o", modifiers: .command)

        Divider()

        SettingsLink {
            Text("Preferences...")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Moremaid") {
            Task {
                await appState.shutdown()
                NSApplication.shared.terminate(nil)
            }
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @MainActor
    private func addProject() async {
        guard let path = await ProjectPicker.chooseDirectory() else { return }
        let name = (path as NSString).lastPathComponent
        appState.projectManager.addProject(path: path, name: name)
    }
}
