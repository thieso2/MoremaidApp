import AppKit

enum ProjectPicker {
    @MainActor
    static func chooseDirectory() async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory to add as a Moremaid project"
        panel.prompt = "Add Project"

        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
