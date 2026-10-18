// Standalone regression checks also run with Command Line Tools without XCTest/Testing.
import AppKit
import Foundation

@main struct CoreChecks {
    @MainActor static func main() throws {
        let text = "一个想法\n\n- [ ] 发邮件 📮\n- [x] 买咖啡\n"
        let toggled = NoteLine.toggling(2, in: text)
        precondition(toggled == "一个想法\n\n- [x] 发邮件 📮\n- [x] 买咖啡\n")
        precondition(NoteLine.toggling(2, in: toggled) == text)
        precondition(NoteLine.toggling(0, in: text) == text)
        precondition(NoteLine.toggling(99, in: text) == text)
        print("PASS: 待办切换保留中文、空行和其他文本")

        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "note.json")
        let store = NoteStore(url: url)
        store.text = "记得休息\n- [ ] 完成原型\n"
        store.toggle(1)
        let reopened = NoteStore(url: url)
        precondition(reopened.text == "记得休息\n- [x] 完成原型\n")
        precondition(reopened.pendingCount == 0 && reopened.saveError == nil)
        print("PASS: 自动保存并重新读取内容")

        let original = Data("corrupted document".utf8)
        try original.write(to: url)
        let unreadable = NoteStore(url: url)
        precondition(unreadable.saveError != nil)
        unreadable.text = "新输入的内容"
        unreadable.save()
        let preserved = try Data(contentsOf: url)
        precondition(preserved == original)
        print("PASS: 损坏的数据文件不会被覆盖")

        // An existing file as the parent directory deterministically simulates a write failure.
        let unwritable = NoteStore(url: url.appending(path: "child.json"))
        unwritable.text = "需要备份的内容"
        precondition(unwritable.saveError != nil && unwritable.text == "需要备份的内容")
        print("PASS: 写入失败保留内存内容并显示错误")

        let geometry = PanelGeometry(screen: CGRect(x: -1512, y: 200, width: 1512, height: 982),
                                     safeTop: 32, notchWidth: 184)
        let compact = geometry.frame(expanded: false)
        let expanded = geometry.frame(expanded: true)
        precondition(compact.maxY == 1150 && expanded.maxY == compact.maxY)
        precondition(expanded.midX == -756 && compact.width == 196 && expanded.width == 420)
        let external = PanelGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeTop: 24, notchWidth: 0)
        precondition(external.frame(expanded: true).maxY == 1056)
        print("PASS: 刘海与无刘海屏幕定位、负坐标显示器居中")

        // Exercise the real NSTextView edit/undo path rather than a second implementation.
        _ = NSApplication.shared
        let editor = EditorTextView()
        editor.allowsUndo = true
        editor.string = "先做这个\n第二行"
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.toggleTask()
        precondition(editor.string == "- [ ] 先做这个\n第二行")
        editor.toggleTask()
        precondition(editor.string == "先做这个\n第二行")
        print("PASS: 原生编辑器当前行转换为待办并还原")
    }
}
