import Foundation
import SwiftUI

@Observable
@MainActor
final class AppState {
    var projectManager: ProjectManager
    var serverManager: ServerManager

    init() {
        self.projectManager = ProjectManager()
        self.serverManager = ServerManager()
    }

    func startup() async {
        // Server is not started by default — only needed for external browser access.
        // The in-app WebView loads HTML directly via loadHTMLString.
    }

    func shutdown() async {
        await serverManager.stop()
    }
}
