import AppKit
import SwiftUI

struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    let focusID: Int
    let taskID: Int
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        let editor = EditorTextView()
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.allowsUndo = true
        editor.font = .systemFont(ofSize: 15)
        editor.textColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        editor.insertionPointColor = .black
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 6, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.onEscape = onEscape
        editor.string = text
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? EditorTextView else { return }
        context.coordinator.parent = self
        if editor.string != text && !editor.hasMarkedText() {
            let selection = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        if context.coordinator.taskID != taskID {
            context.coordinator.taskID = taskID
            DispatchQueue.main.async { [weak editor] in
                guard let editor else { return }
                editor.window?.makeFirstResponder(editor)
                editor.toggleTask()
            }
        }
        if context.coordinator.focusID != focusID {
            context.coordinator.focusID = focusID
            // The hosting view needs to join the window before becoming first responder.
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.window?.isKeyWindow == true else { return }
                editor.window?.makeFirstResponder(editor)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        var focusID = -1
        var taskID: Int
        init(_ parent: NoteEditor) { self.parent = parent; taskID = parent.taskID }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

final class EditorTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { super.cancelOperation(sender) } else { onEscape?() }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains([.command, .shift]),
           event.charactersIgnoringModifiers?.lowercased() == "l" {
            toggleTask()
        } else {
            super.keyDown(with: event)
        }
    }

    func toggleTask() {
        guard !hasMarkedText() else { return }
        let source = string as NSString
        let range = source.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = source.substring(with: range)
        let isTask = line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ")
        let replacement = isTask ? String(line.dropFirst(6)) : "- [ ] " + line
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        let cursor = selectedRange().location
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: min(max(range.location, cursor + (isTask ? -6 : 6)), (string as NSString).length), length: 0))
    }
}
