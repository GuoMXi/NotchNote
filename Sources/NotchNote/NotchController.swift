import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class NotchController: NSObject {
    let store: NoteStore
    let state = PanelState()
    let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
    private var collapseTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?
    private var geometry: PanelGeometry?
    private var keyMonitor: Any?
    private var container: NotchContainer?
    private var presentationID = 0

    init(store: NoteStore = NoteStore()) {
        self.store = store
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: NotchView(store: store, state: state,
            onHover: { [weak self] in self?.hover($0) },
            onEdit: { [weak self] in self?.edit() },
            onClose: { [weak self] in self?.collapse() },
            onEscape: { [weak self] in self?.collapse(animated: false) },
            onSelectSection: { [weak self] in self?.selectSection($0) },
            onAddSection: { [weak self] in self?.addSection($0) },
            onExport: { [weak self] in self?.export() }))
        host.sizingOptions = []
        let container = NotchContainer(host: host)
        self.container = container
        panel.contentView = container
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, event.keyCode == 53,
                  (self.panel.firstResponder as? NSTextView)?.hasMarkedText() != true else { return event }
            self.collapse(animated: false)
            return nil
        }
        screenChanged()
        panel.orderFrontRegardless()
    }

    @objc private func screenChanged() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else {
            panel.orderOut(nil)
            return
        }
        geometry = PanelGeometry(screen: screen)
        if let geometry {
            state.surfaceSize = geometry.frame(expanded: true).size
            state.compactWidth = geometry.compactWidth
            container?.surfaceSize = state.surfaceSize
        }
        present(state.mode != .collapsed, animated: false)
        panel.orderFrontRegardless()
    }

    private func layout(expanded: Bool) {
        guard let geometry else { return }
        // Anchor the top edge below the physical camera so no controls are obscured.
        panel.setFrame(geometry.frame(expanded: expanded), display: true)
        container?.needsLayout = true
        container?.layoutSubtreeIfNeeded()
        panel.hasShadow = expanded
    }

    private func present(_ visible: Bool, animated: Bool) {
        presentationID += 1
        let ticket = presentationID
        if visible { layout(expanded: true) }

        guard animated else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { state.revealed = visible }
            layout(expanded: visible)
            return
        }

        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(NotchMotion.animation(reduceMotion: reduced), completionCriteria: .removed) {
            state.revealed = visible
        } completion: { [weak self] in
            guard let self, self.presentationID == ticket, !visible,
                  self.state.mode == .collapsed else { return }
            // Shrink the native hit area only after the outgoing paper has disappeared.
            self.layout(expanded: false)
        }
    }

    func hover(_ inside: Bool) {
        collapseTask?.cancel()
        if inside && state.mode == .collapsed {
            state.mode = .preview
            state.contentMode = .preview
            present(true, animated: true)
        } else if !inside && state.mode == .preview {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self, self.state.mode == .preview else { return }
                self.collapse()
            }
        }
    }

    func edit(animated: Bool = true) {
        collapseTask?.cancel()
        if state.mode != .editing { previousApp = NSWorkspace.shared.frontmostApplication }
        state.mode = .editing
        state.contentMode = .editing
        state.showingEditor = true
        present(true, animated: animated)
        panel.orderFrontRegardless()
        panel.makeKey()
        state.focusID += 1
    }

    func toggle() { state.mode == .editing ? collapse(animated: false) : edit(animated: false) }

    private func finishEditing() {
        if let editor = panel.firstResponder as? EditorTextView {
            editor.unmarkText()
            store.text = editor.string
        }
        panel.makeFirstResponder(nil)
    }

    func selectSection(_ id: UUID) {
        finishEditing()
        store.select(id)
        collapseTask?.cancel()
        if state.mode != .editing { previousApp = NSWorkspace.shared.frontmostApplication }
        state.mode = .editing
        state.contentMode = .editing
        state.showingEditor = false
        present(true, animated: false)
        panel.makeKey()
    }

    func addSection(_ title: String) {
        finishEditing()
        guard let id = store.addSection(title: title) else { return }
        selectSection(id)
        edit(animated: false)
    }

    func collapse(animated: Bool = true) {
        collapseTask?.cancel()
        finishEditing()
        store.save()
        let wasEditing = state.mode == .editing
        panel.makeFirstResponder(nil)
        panel.resignKey()
        state.mode = .collapsed
        present(false, animated: animated)
        if wasEditing, let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }

    func export() {
        edit()
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "NotchNote.txt"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else { return }
            do { try self.store.exportText.write(to: url, atomically: true, encoding: .utf8) }
            catch { NSAlert(error: error).runModal() }
        }
    }
}
