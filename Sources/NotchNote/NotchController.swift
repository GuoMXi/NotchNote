import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class NotchController: NSObject {
    let store: NoteStore
    let state = PanelState()
    // Hover only orders the panel front; editing uses normal app/window activation.
    let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless],
                                   backing: .buffered, defer: false)
    private var collapseTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?
    private var geometry: PanelGeometry?
    private var keyMonitor: Any?
    private var container: NotchContainer?
    private var presentationID = 0
    private var pointerInside = false
    private var pointerHasEntered = false
    private var activeInteractions: Set<String> = []

    init(store: NoteStore = NoteStore(), reminders: MeetingReminders? = nil) {
        self.store = store
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: NotchView(store: store, state: state, reminders: reminders,
            onEdit: { [weak self] in self?.edit() },
            onToggleEditor: { [weak self] in self?.toggleEditor() },
            onClose: { [weak self] in self?.collapse() },
            onEscape: { [weak self] in self?.collapse(animated: false) },
            onSelectSection: { [weak self] in self?.selectSection($0) },
            onOpenMeeting: { [weak self] in self?.openMeeting($0) },
            onAddSection: { [weak self] in self?.addSection($0) },
            onOpenScratch: { [weak self] in self?.openScratch() },
            onDeleteSection: { [weak self] in self?.deleteSection($0) },
            onRestoreSection: { [weak self] in self?.restoreSection($0) },
            onTogglePin: { [weak self] in self?.togglePin() },
            onInteraction: { [weak self] in self?.interaction($0, active: $1) },
            onExport: { [weak self] in self?.export() }))
        host.sizingOptions = []
        let container = NotchContainer(host: host)
        container.onHover = { [weak self] in self?.hover($0) }
        self.container = container
        panel.contentView = container
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationActivated),
            name: NSApplication.didBecomeActiveNotification, object: NSApp)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, event.keyCode == 53, self.activeInteractions.isEmpty,
                  (self.panel.firstResponder as? NSTextView)?.hasMarkedText() != true else { return event }
            self.collapse(animated: false)
            return nil
        }
        screenChanged()
        panel.orderFrontRegardless()
    }

    @objc private func applicationActivated() {
        guard state.mode == .editing, state.showingEditor else { return }
        panel.makeKeyAndOrderFront(nil)
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
        pointerInside = inside
        // A native exit also confirms entry: the area may have been rebuilt under a stationary pointer.
        if inside || state.mode != .collapsed { pointerHasEntered = true }
        collapseTask?.cancel()
        if inside && state.mode == .collapsed {
            state.mode = .preview
            state.contentMode = .preview
            present(true, animated: true)
        } else if !inside {
            scheduleAutoCollapse()
        }
    }

    private func scheduleAutoCollapse() {
        collapseTask?.cancel()
        guard pointerHasEntered, !pointerInside, !state.isPinned, activeInteractions.isEmpty,
              state.mode != .collapsed else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, !self.pointerInside, !self.state.isPinned,
                  self.activeInteractions.isEmpty, self.state.mode != .collapsed else { return }
            if self.panel.attachedSheet != nil || (self.panel.firstResponder as? NSTextView)?.hasMarkedText() == true || NSEvent.pressedMouseButtons != 0 {
                self.scheduleAutoCollapse()
                return
            }
            self.collapse()
        }
    }

    func interaction(_ id: String, active: Bool) {
        if active { activeInteractions.insert(id); collapseTask?.cancel() }
        else { activeInteractions.remove(id); scheduleAutoCollapse() }
    }

    func togglePin() {
        state.isPinned.toggle()
        if state.isPinned { collapseTask?.cancel() } else { scheduleAutoCollapse() }
    }

    func edit(animated: Bool = true) {
        collapseTask?.cancel()
        if state.mode != .editing { previousApp = NSWorkspace.shared.frontmostApplication }
        state.mode = .editing
        state.contentMode = .editing
        state.showingEditor = true
        state.focusLine = nil
        present(true, animated: animated)
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        state.focusID += 1
    }

    func toggle() { state.mode == .editing ? collapse(animated: false) : edit(animated: false) }

    func toggleEditor() {
        if state.showingEditor {
            finishEditing()
            state.showingEditor = false
        } else {
            edit(animated: false)
        }
    }

    private func finishEditing() {
        if let editor = panel.firstResponder as? EditorTextView {
            editor.unmarkText()
            store.updateRichText(editor.attributedString(), in: store.selectedID)
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
        panel.makeKeyAndOrderFront(nil)
    }

    func addSection(_ title: String) {
        finishEditing()
        guard let id = store.addSection(title: title) else { return }
        selectSection(id)
        edit(animated: false)
    }

    func openScratch() {
        finishEditing()
        store.select(store.ensureScratchSection())
        edit(animated: false)
    }

    func deleteSection(_ id: UUID) {
        finishEditing()
        let wasSelected = store.selectedID == id
        guard store.deleteSection(id) else { return }
        if wasSelected { selectSection(store.selectedID) }
        else if state.mode == .editing && state.showingEditor { edit(animated: false) }
    }

    func restoreSection(_ id: UUID) {
        finishEditing()
        guard let restored = store.restoreSection(id) else { return }
        selectSection(restored)
    }

    func openMeeting(_ reference: MeetingReference) {
        finishEditing()
        guard let line = store.resolve(reference) else { return }
        store.select(reference.sectionID)
        edit(animated: false)
        state.focusLine = line.id
    }

    func collapse(animated: Bool = true) {
        collapseTask?.cancel()
        finishEditing()
        store.save()
        let wasEditing = state.mode == .editing
        panel.makeFirstResponder(nil)
        // Ordering out clears AppKit's key-window ownership; resignKey() alone only sends
        // the resignation callback and can leave the next activation with stale ownership.
        panel.orderOut(nil)
        state.mode = .collapsed
        pointerHasEntered = false
        state.formattingPresented = false
        activeInteractions.removeAll()
        present(false, animated: animated)
        panel.orderFrontRegardless()
        if wasEditing, let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }

    func export() {
        edit()
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "NotchNote.rtf"
        savePanel.allowedContentTypes = [.rtf, .plainText]
        savePanel.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else { return }
            do {
                if url.pathExtension.lowercased() == "txt" {
                    try self.store.exportText.write(to: url, atomically: true, encoding: .utf8)
                } else {
                    try RichText.encode(self.store.exportRichText).write(to: url, options: .atomic)
                }
            }
            catch { NSAlert(error: error).runModal() }
        }
    }
}
