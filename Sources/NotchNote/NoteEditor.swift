import AppKit
import SwiftUI

struct NoteEditor: NSViewRepresentable {
    let content: NSAttributedString
    let focusID: Int
    let focusLine: Int?
    let taskID: Int
    let formatID: Int
    let command: EditorCommand
    let onChange: (NSAttributedString) -> NSAttributedString
    let onStyleChange: (EditorStyle) -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        let editor = EditorTextView()
        editor.isRichText = true
        editor.importsGraphics = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.allowsUndo = true
        editor.typingAttributes = RichText.defaults
        editor.insertionPointColor = .black
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 6, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.onEscape = onEscape
        editor.textStorage?.setAttributedString(content)
        editor.onStyleChanged = { [weak coordinator = context.coordinator] style in
            DispatchQueue.main.async { coordinator?.parent.onStyleChange(style) }
        }
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? EditorTextView else { return }
        context.coordinator.parent = self
        if !context.coordinator.lastContent.isEqual(to: content) && !editor.hasMarkedText() {
            let selection = editor.selectedRange()
            editor.textStorage?.setAttributedString(content)
            context.coordinator.lastContent = content
            editor.setSelectedRange(NSRange(location: min(selection.location, content.length), length: 0))
        }
        if context.coordinator.taskID != taskID {
            context.coordinator.taskID = taskID
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.window?.isKeyWindow == true else { return }
                editor.window?.makeFirstResponder(editor)
                editor.toggleTask()
            }
        }
        if context.coordinator.formatID != formatID {
            context.coordinator.formatID = formatID
            let command = command
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.window != nil else { return }
                if editor.window?.isKeyWindow == true { editor.window?.makeFirstResponder(editor) }
                editor.apply(command)
            }
        }
        if context.coordinator.focusID != focusID {
            context.coordinator.focusID = focusID
            let focusLine = focusLine
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.window?.isKeyWindow == true else { return }
                editor.window?.makeFirstResponder(editor)
                if let focusLine { editor.selectLine(focusLine) }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        var lastContent: NSAttributedString
        var focusID = -1
        var taskID: Int
        var formatID: Int
        init(_ parent: NoteEditor) {
            self.parent = parent
            lastContent = parent.content
            taskID = parent.taskID
            formatID = parent.formatID
        }
        func undoManager(for view: NSTextView) -> UndoManager? { (view as? EditorTextView)?.editHistory }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? EditorTextView else { return }
            let value = editor.attributedString()
            // Cache the saved RTF's canonical attributes, not the text system's transient attributes.
            // This prevents round-trip differences from resetting the live selection and undo stack.
            lastContent = parent.onChange(value)
            editor.reportStyle()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? EditorTextView)?.reportStyle()
        }
    }
}

final class EditorTextView: NSTextView {
    let editHistory = UndoManager()
    override var undoManager: UndoManager? { editHistory }
    var onEscape: (() -> Void)?
    var onStyleChanged: ((EditorStyle) -> Void)?
    private var ownedTextStorage: NSTextStorage?

    convenience init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        ownedTextStorage = storage
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        observeHistory()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeHistory()
    }

    private func observeHistory() {
        NotificationCenter.default.addObserver(self, selector: #selector(historyChanged), name: .NSUndoManagerDidUndoChange, object: editHistory)
        NotificationCenter.default.addObserver(self, selector: #selector(historyChanged), name: .NSUndoManagerDidRedoChange, object: editHistory)
    }

    @objc private func historyChanged(_ notification: Notification) {
        // AppKit rich-text undo can update storage without notifying the representable delegate.
        // Publish the final contents after undo/redo so autosave stays in sync with the editor.
        didChangeText()
        reportStyle()
    }

    var currentStyle: EditorStyle {
        let range = selectedRange()
        let attributes = range.length > 0 && range.location < (textStorage?.length ?? 0)
            ? (textStorage?.attributes(at: range.location, effectiveRange: nil) ?? typingAttributes) : typingAttributes
        let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 15)
        let family = font.familyName ?? ""
        let traits = NSFontManager.shared.traits(of: font)
        let source = string as NSString
        let lineRange = source.lineRange(for: NSRange(location: min(range.location, source.length), length: 0))
        let line = NoteLine(id: 0, raw: source.substring(with: lineRange).trimmingCharacters(in: .newlines))
        return EditorStyle(fontFamily: NSFontManager.shared.availableFontFamilies.contains(family) ? family : "",
                           size: font.pointSize, bold: traits.contains(.boldFontMask),
                           italic: traits.contains(.italicFontMask),
                           underline: (attributes[.underlineStyle] as? Int ?? 0) != 0, meeting: line.isMeeting)
    }

    func reportStyle() { onStyleChanged?(currentStyle) }

    func apply(_ command: EditorCommand) {
        guard !hasMarkedText() else { return }
        if command == .meeting { toggleMeetingMark(); return }
        breakUndoCoalescing()
        let selection = selectedRange()
        let style = currentStyle
        let transform: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] = { attributes in
            var attributes = attributes
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 15)
            let manager = NSFontManager.shared
            switch command {
            case .bold:
                attributes[.font] = style.bold ? manager.convert(font, toNotHaveTrait: .boldFontMask) : manager.convert(font, toHaveTrait: .boldFontMask)
            case .italic:
                attributes[.font] = style.italic ? manager.convert(font, toNotHaveTrait: .italicFontMask) : manager.convert(font, toHaveTrait: .italicFontMask)
            case .underline:
                attributes[.underlineStyle] = style.underline ? 0 : NSUnderlineStyle.single.rawValue
            case .font(let family):
                if family.isEmpty {
                    attributes[.font] = manager.convert(.systemFont(ofSize: font.pointSize), toHaveTrait: manager.traits(of: font))
                } else {
                    let traits = manager.traits(of: font).intersection([.boldFontMask, .italicFontMask])
                    attributes[.font] = manager.font(withFamily: family, traits: traits, weight: 5, size: font.pointSize)
                        ?? manager.font(withFamily: family, traits: [], weight: 5, size: font.pointSize)
                        ?? NSFont(name: family, size: font.pointSize) ?? font
                }
            case .size(let size): attributes[.font] = manager.convert(font, toSize: min(72, max(8, size)))
            case .color(let hex): attributes[.foregroundColor] = RichText.color(hex)
            case .meeting: break
            }
            return attributes
        }
        if selection.length == 0 {
            typingAttributes = transform(typingAttributes)
            reportStyle()
            return
        }
        let previous = NSAttributedString(attributedString: attributedString())
        editHistory.registerUndo(withTarget: self) { target in target.restore(previous, selection: selection) }
        editHistory.setActionName("文字格式")
        textStorage?.beginEditing()
        previous.enumerateAttributes(in: selection) { attributes, range, _ in
            textStorage?.setAttributes(transform(attributes), range: range)
        }
        textStorage?.endEditing()
        didChangeText()
        reportStyle()
    }

    private func restore(_ value: NSAttributedString, selection: NSRange) {
        let previous = NSAttributedString(attributedString: attributedString())
        let previousSelection = selectedRange()
        editHistory.registerUndo(withTarget: self) { target in target.restore(previous, selection: previousSelection) }
        textStorage?.setAttributedString(value)
        setSelectedRange(selection)
        didChangeText()
        reportStyle()
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { super.cancelOperation(sender) } else { onEscape?() }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains([.command, .shift]), event.charactersIgnoringModifiers?.lowercased() == "m" {
            toggleMeetingMark()
            return
        }
        if flags.contains(.command), !flags.contains(.option) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": apply(.bold); return
            case "i": apply(.italic); return
            case "u": apply(.underline); return
            default: break
            }
        }
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
        let changeRange = NSRange(location: range.location, length: isTask ? 6 : 0)
        let replacement = isTask ? "" : "- [ ] "
        guard shouldChangeText(in: changeRange, replacementString: replacement) else { return }
        let cursor = selectedRange().location
        textStorage?.replaceCharacters(in: changeRange, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: min(max(range.location, cursor + (isTask ? -6 : 6)), (string as NSString).length), length: 0))
    }

    func selectLine(_ index: Int) {
        let lines = NoteLine.parse(string)
        guard lines.indices.contains(index) else { return }
        let location = lines.prefix(index).reduce(0) { $0 + ($1.raw as NSString).length + 1 }
        let range = NSRange(location: location, length: (lines[index].raw as NSString).length)
        setSelectedRange(range)
        scrollRangeToVisible(range)
        reportStyle()
    }

    func toggleMeetingMark() {
        guard !hasMarkedText() else { return }
        let source = string as NSString
        let selection = selectedRange()
        let range = source.lineRange(for: NSRange(location: min(selection.location, source.length), length: 0))
        let line = NoteLine(id: 0, raw: source.substring(with: range).trimmingCharacters(in: .newlines))
        let edit = MeetingMarkerEdit.toggle(line: line, location: range.location)
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        let delta = (edit.replacement as NSString).length - edit.range.length
        setSelectedRange(NSRange(location: min((string as NSString).length, max(range.location, selection.location + delta)), length: 0))
        reportStyle()
    }
}
