import AppKit

enum FilePicker {
    @MainActor
    static func chooseFilesOrDirectories() async -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files or directories to open"
        panel.prompt = "Open"

        let response = await panel.begin()
        guard response == .OK else { return [] }
        return panel.urls.map(\.path)
    }
}
