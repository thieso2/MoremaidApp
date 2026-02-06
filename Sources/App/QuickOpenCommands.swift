import SwiftUI
import Combine

/// Global notification for quick open toggle.
extension Notification.Name {
    static let toggleQuickOpen = Notification.Name("toggleQuickOpen")
}

/// Installs a local key event monitor for CMD-K that works regardless of focus.
@MainActor
enum QuickOpenShortcut {
    private nonisolated(unsafe) static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, let chars = event.charactersIgnoringModifiers {
                if chars == "k" || chars == "p" {
                    NotificationCenter.default.post(name: .toggleQuickOpen, object: nil)
                    return nil // consume the event
                }
            }
            return event
        }
    }
}
