import SwiftUI
import AppKit

/// A plain-text source editor for editing the markdown of the currently-
/// viewed file. Wraps `NSTextView` so we get native macOS edit controls
/// (cmd-arrow word-jump, undo/redo, find, smart-quotes-disabled, etc.) plus
/// a monospaced font that doesn't fight markdown source.
struct SourceEditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var onCommandS: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.allowsUndo = true
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.string = text
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        // Avoid clobbering the user's selection on every keystroke; only push
        // updates when the binding genuinely diverges (e.g. external reload).
        if tv.string != text {
            let selection = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
        }
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        context.coordinator.onCommandS = onCommandS
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onCommandS: () -> Void = {}

        init(text: Binding<String>) { _text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
        }

        // Intercept ⌘S without depending on a SwiftUI keyboardShortcut, which
        // wouldn't fire while the NSTextView holds first responder.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                return false
            }
            return false
        }
    }
}
