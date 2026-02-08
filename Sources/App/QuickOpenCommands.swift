import SwiftUI
import Combine

/// Global notifications for quick open and its controls.
extension Notification.Name {
    static let toggleQuickOpen = Notification.Name("toggleQuickOpen")
    static let toggleBrowseMode = Notification.Name("toggleBrowseMode")
    static let exportPDF = Notification.Name("exportPDF")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")
    static let findInPage = Notification.Name("findInPage")
    static let findNext = Notification.Name("findNext")
    static let findPrevious = Notification.Name("findPrevious")
    static let useSelectionForFind = Notification.Name("useSelectionForFind")
    static let reloadFile = Notification.Name("reloadFile")
    static let goBack = Notification.Name("goBack")
    static let goForward = Notification.Name("goForward")
    static let toggleTOC = Notification.Name("toggleTOC")
    static let newTab = Notification.Name("newTab")
    static let toggleBreadcrumb = Notification.Name("toggleBreadcrumb")
    static let toggleStatusBar = Notification.Name("toggleStatusBar")
    static let searchInFiles = Notification.Name("searchInFiles")
    static let toggleActivityFeed = Notification.Name("toggleActivityFeed")
}

/// Installs a local key event monitor for shortcuts that work regardless of focus.
@MainActor
enum QuickOpenShortcut {
    private nonisolated(unsafe) static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, let chars = event.charactersIgnoringModifiers {
                if chars == "k" {
                    NotificationCenter.default.post(name: .toggleQuickOpen, object: nil)
                    return nil
                }
                if chars == "q" {
                    NSApplication.shared.terminate(nil)
                    return nil
                }
            }
            // Shift+Tab to toggle browse mode (TextField eats this before onKeyPress)
            if event.keyCode == 48 /* Tab */ && flags == .shift {
                NotificationCenter.default.post(name: .toggleBrowseMode, object: nil)
                return nil
            }
            return event
        }
    }
}
