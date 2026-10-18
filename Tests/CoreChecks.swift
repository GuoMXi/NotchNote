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

        let legacyURL = folder.appending(path: "legacy.json")
        let legacyText = "【近期会议】\n- [ ] 讨论进展\n\n【项目甲】\n- [x] 已处理\n- [ ] 整理材料\n\n【项目乙】\n参考资料\nhttps://example.com\n"
        let legacyData = try JSONEncoder().encode(NoteDocument(text: legacyText))
        try legacyData.write(to: legacyURL)
        let migrated = NoteStore(url: legacyURL)
        precondition(migrated.sections.map(\.title) == ["近期会议", "项目甲", "项目乙"])
        precondition(migrated.totalPendingCount == 2 && migrated.pendingCount == 1)
        let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("legacy.v1-") }
        precondition(backups.count == 1)
        let backupData = try Data(contentsOf: backups[0])
        precondition(backupData == legacyData)
        precondition(migrated.sections[2].text.contains("https://example.com"))
        print("PASS: 旧便笺按栏目迁移，保留勾选、链接和完整原文件备份")

        let first = migrated.selectedID
        let second = migrated.sections[1].id
        migrated.select(second)
        migrated.toggle(1)
        precondition(migrated.pendingCount == 0 && migrated.text(in: first) == "- [ ] 讨论进展")
        migrated.updateText("会议补充", in: first)
        precondition(migrated.selectedID == second && migrated.text.hasPrefix("- [x] 已处理"))
        let restored = NoteStore(url: legacyURL)
        precondition(restored.selectedID == second && restored.sections == migrated.sections)
        precondition(restored.exportText.contains("【项目乙】") && restored.exportText.contains("会议补充"))
        precondition(restored.addSection(title: "   ") == nil)
        precondition(restored.addSection(title: " 新项目 ") != nil)
        precondition(restored.selectedSection.title == "新项目" && restored.text.isEmpty && restored.hasContent)
        print("PASS: 栏目独立编辑、选择记忆、完整导出和新建栏目")

        let duplicateURL = folder.appending(path: "duplicate.json")
        let duplicate = migrated.sections[0]
        let invalidData = try JSONEncoder().encode(NotebookDocument(sections: [duplicate, duplicate], selectedID: duplicate.id))
        try invalidData.write(to: duplicateURL)
        let invalidStore = NoteStore(url: duplicateURL)
        invalidStore.save()
        let invalidPreserved = try Data(contentsOf: duplicateURL)
        precondition(invalidStore.saveError != nil && invalidPreserved == invalidData)
        precondition(NotebookMigration.sections(from: "普通文本\n\n仍是同一张纸").count == 1)
        print("PASS: 非分组旧便笺保留为随手记，异常栏目数据禁止覆盖")

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
        precondition(expanded.midX == -756 && compact.width == 196 && expanded.width == 500)
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

        let richURL = folder.appending(path: "rich.json")
        let richStore = NoteStore(url: richURL)
        let formatted = NSMutableAttributedString(string: "- [ ] 记录🙂\n第二行", attributes: RichText.defaults)
        let wordRange = (formatted.string as NSString).range(of: "记录🙂")
        formatted.addAttributes([.font: NSFont.boldSystemFont(ofSize: 20), .underlineStyle: 1,
                                 .foregroundColor: RichText.color("C43D35")], range: wordRange)
        richStore.updateRichText(formatted, in: richStore.selectedID)
        richStore.toggle(0)
        let richReopened = NoteStore(url: richURL)
        let content = richReopened.attributedText(in: richReopened.selectedID)
        let attributes = content.attributes(at: wordRange.location, effectiveRange: nil)
        precondition(content.string == "- [x] 记录🙂\n第二行")
        precondition((attributes[.font] as? NSFont)?.pointSize == 20)
        precondition(NSFontManager.shared.traits(of: attributes[.font] as! NSFont).contains(.boldFontMask))
        precondition(attributes[.underlineStyle] as? Int == 1)
        let color = (attributes[.foregroundColor] as! NSColor).usingColorSpace(.sRGB)!
        precondition(abs(color.redComponent - CGFloat(0xC4) / 255) < 0.01)
        let rendered = RichText.lines(content)
        precondition(String(rendered[0].text.characters) == "记录🙂")
        let exported = try RichText.encode(richReopened.exportRichText)
        let exportedContent = RichText.decode(exported, text: richReopened.exportRichText.string)
        let exportWord = (exportedContent.string as NSString).range(of: "记录🙂")
        precondition(exportedContent.attribute(.underlineStyle, at: exportWord.location, effectiveRange: nil) as? Int == 1)
        print("PASS: 字号、加粗、下划线与颜色重启保留，勾选和导出不丢格式")

        editor.isRichText = true
        editor.textStorage?.setAttributedString(formatted)
        editor.setSelectedRange(wordRange)
        editor.apply(.font("Menlo"))
        editor.apply(.size(18))
        precondition((editor.textStorage?.attribute(.font, at: wordRange.location, effectiveRange: nil) as? NSFont)?.pointSize == 18)
        // Menlo uses a Chinese fallback font. Verify the family on glyphs Menlo actually supports.
        let latinEditor = EditorTextView()
        latinEditor.isRichText = true
        latinEditor.textStorage?.setAttributedString(NSAttributedString(string: "Latin note", attributes: RichText.defaults))
        latinEditor.setSelectedRange(NSRange(location: 0, length: 10))
        latinEditor.apply(.font("Menlo"))
        latinEditor.apply(.size(18))
        precondition((latinEditor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName == "Menlo")
        editor.toggleTask()
        let movedWord = (editor.string as NSString).range(of: "记录🙂")
        precondition(editor.textStorage?.attribute(.underlineStyle, at: movedWord.location, effectiveRange: nil) as? Int == 1)
        editor.setSelectedRange(movedWord)
        editor.editHistory.removeAllActions()
        editor.apply(.underline)
        precondition(editor.currentStyle.underline == false)
        editor.editHistory.undo()
        precondition(editor.currentStyle.underline)
        print("PASS: 原生字体与字号调整、行转待办保留格式，以及格式撤销")
    }
}
