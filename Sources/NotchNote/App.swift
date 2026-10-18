import AppKit

@main struct NotchNoteApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var shortcut: GlobalShortcut?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent two copies from editing the same local document.
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.guomxi.NotchNote").count > 1 {
            NSApp.terminate(nil)
            return
        }
        installEditMenu()
        let controller = NotchController()
        self.controller = controller
        let shortcut = GlobalShortcut { [weak controller] in controller?.toggle() }
        controller.state.shortcutAvailable = shortcut.register()
        self.shortcut = shortcut

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NotchNote")
        let menu = NSMenu()
        menu.addItem(withTitle: "打开便笺    ⌃⌥空格", action: #selector(openNote), keyEquivalent: "")
        menu.addItem(withTitle: "导出便笺…", action: #selector(exportNote), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 NotchNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action == #selector(openNote) || menuItem.action == #selector(exportNote) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
        // First launch opens the empty page, subsequent launches stay quiet.
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            controller.edit(animated: false)
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.store.save()
        shortcut?.unregister()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.store.save()
        guard let store = controller?.store, store.saveError != nil, !store.text.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "便笺尚未成功保存"
        alert.informativeText = "请先返回便笺，使用导出按钮备份内容。"
        alert.addButton(withTitle: "返回便笺")
        alert.addButton(withTitle: "仍然退出")
        if alert.runModal() == .alertFirstButtonReturn {
            controller?.edit()
            return .terminateCancel
        }
        return .terminateNow
    }

    @objc private func openNote() { controller?.edit() }
    @objc private func exportNote() { controller?.export() }

    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 NotchNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [
            ("撤销", Selector(("undo:")), "z"),
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("复制", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.insertItem(redo, at: 1)
        editItem.submenu = editMenu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
