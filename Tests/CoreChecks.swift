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
        precondition(migrated.sections.map(\.title) == ["近期", "项目甲", "项目乙"])
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

        let meetingURL = folder.appending(path: "meetings.json")
        let meetings = NoteStore(url: meetingURL)
        let hubID = meetings.meetingsSectionID
        meetings.updateText("- [ ] 直接写的会议", in: hubID)
        let projectID = meetings.selectedID
        meetings.text = "普通会议不自动归类\n- [ ] #会议 讨论🙂\n#会议 评审\n- [x] #会议 已开完\n#会议 "
        precondition(meetings.projectMeetings.count == 3)
        precondition(meetings.totalPendingCount == 3)
        meetings.select(hubID)
        precondition(meetings.pendingCount == 3)
        let reference = meetings.projectMeetings[0].reference
        meetings.toggleMeeting(reference)
        precondition(meetings.selectedID == hubID && meetings.text == "- [ ] 直接写的会议")
        precondition(meetings.text(in: projectID).contains("- [x] #会议 讨论🙂"))
        precondition(meetings.pendingCount == 2 && meetings.totalPendingCount == 2)
        meetings.toggleMeeting(meetings.projectMeetings[0].reference)
        precondition(meetings.text(in: projectID).contains("- [x] #会议 评审"))
        precondition(meetings.pendingCount == 1)
        let meetingReopened = NoteStore(url: meetingURL)
        precondition(meetingReopened.meetingsSectionID == hubID && meetingReopened.projectMeetings.count == 3)
        print("PASS: 显式会议标记自动汇总、完成同步来源、直接记录保留、计数不重复及重启保存")

        meetings.updateText("前言\n- [ ] #会议 讨论🙂", in: projectID)
        precondition(meetings.resolve(reference)?.id == 1)
        meetings.updateText("新增一行\n前言\n- [ ] #会议 讨论🙂", in: projectID)
        precondition(meetings.resolve(reference)?.id == 2)
        meetings.toggleMeeting(reference)
        precondition(meetings.text(in: projectID).hasSuffix("- [x] #会议 讨论🙂"))
        let finished = meetings.projectMeetings[0].reference
        meetings.toggleMeetingMark(2, in: projectID)
        precondition(meetings.projectMeetings.isEmpty && meetings.resolve(finished) == nil)
        meetings.updateText("前言\n其他内容\n- [ ] #会议 讨论🙂\n- [ ] #会议 讨论🙂", in: projectID)
        let beforeStale = meetings.text(in: projectID)
        meetings.toggleMeeting(reference)
        precondition(meetings.text(in: projectID) == beforeStale)
        print("PASS: 项目增删与取消标记即时更新，过期引用不会误改其他行")

        let meetingRich = NSMutableAttributedString(string: "前言\n- [ ] #会议 讨论🙂", attributes: RichText.defaults)
        let meetingWord = (meetingRich.string as NSString).range(of: "讨论🙂")
        meetingRich.addAttribute(.underlineStyle, value: 1, range: meetingWord)
        meetings.updateRichText(meetingRich, in: projectID)
        meetings.toggleMeeting(meetings.projectMeetings[0].reference)
        precondition(meetings.attributedText(in: projectID).attribute(.underlineStyle, at: meetingWord.location, effectiveRange: nil) as? Int == 1)
        precondition(String(meetings.projectMeetings[0].rendered.text.characters) == "讨论🙂")
        meetings.toggleMeetingMark(1, in: projectID)
        meetings.toggleMeetingMark(1, in: projectID)
        let preservedWord = (meetings.text(in: projectID) as NSString).range(of: "讨论🙂")
        precondition(meetings.attributedText(in: projectID).attribute(.underlineStyle, at: preservedWord.location, effectiveRange: nil) as? Int == 1)
        print("PASS: 会议预览隐藏标记，标记与完成操作保留原行富文本格式")

        let meetingEditor = EditorTextView()
        meetingEditor.allowsUndo = true
        meetingEditor.isRichText = true
        meetingEditor.textStorage?.setAttributedString(meetingRich)
        meetingEditor.setSelectedRange(meetingWord)
        meetingEditor.toggleMeetingMark()
        precondition(meetingEditor.string == "前言\n- [ ] 讨论🙂" && !meetingEditor.currentStyle.meeting)
        meetingEditor.editHistory.undo()
        precondition(meetingEditor.string == meetingRich.string)
        meetingEditor.setSelectedRange(meetingWord)
        precondition(meetingEditor.currentStyle.meeting)
        precondition(meetingEditor.textStorage?.attribute(.underlineStyle, at: meetingWord.location, effectiveRange: nil) as? Int == 1)
        meetingEditor.selectLine(1)
        precondition((meetingEditor.string as NSString).substring(with: meetingEditor.selectedRange()) == "- [ ] #会议 讨论🙂")
        print("PASS: 原生会议按钮支持撤销、格式保留及精确定位中文会议行")

        let sectionURL = folder.appending(path: "sections.json")
        let sectionStore = NoteStore(url: sectionURL)
        let scratch = sectionStore.ensureScratchSection()
        precondition(sectionStore.ensureScratchSection() == scratch && sectionStore.sections.count == 2)
        precondition(!sectionStore.deleteSection(scratch) && !sectionStore.deleteSection(sectionStore.meetingsSectionID))
        let doomed = sectionStore.addSection(title: "可删除项目")!
        let preservedSection = NSMutableAttributedString(string: "- [ ] #会议 项目讨论🙂", attributes: RichText.defaults)
        preservedSection.addAttribute(.underlineStyle, value: 1, range: NSRange(location: 10, length: 6))
        sectionStore.updateRichText(preservedSection, in: doomed)
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        precondition(sectionStore.setMeetingPlan(sectionStore.reference(forLine: 0, in: doomed)!, date: date, reminderMinutes: 15))
        precondition(sectionStore.deleteSection(doomed))
        precondition(sectionStore.selectedID == scratch && !sectionStore.sections.contains { $0.id == doomed })
        precondition(sectionStore.projectMeetings.isEmpty && sectionStore.meetingPlans.isEmpty && sectionStore.totalPendingCount == 0)
        precondition(sectionStore.hasContent)
        precondition(sectionStore.deletedSections.count == 1 && sectionStore.deletedSections[0].section.richText != nil)
        let archivedStore = NoteStore(url: sectionURL)
        precondition(archivedStore.scratchSectionID == scratch && archivedStore.deletedSections[0].id == doomed)
        precondition(archivedStore.restoreSection(doomed) == doomed && archivedStore.selectedID == doomed)
        precondition(archivedStore.deletedSections.isEmpty && archivedStore.text == preservedSection.string)
        precondition(archivedStore.attributedText(in: doomed).attribute(.underlineStyle, at: 10, effectiveRange: nil) as? Int == 1)
        precondition(archivedStore.plan(in: doomed, line: 0)?.date == date && archivedStore.plan(in: doomed, line: 0)?.reminderMinutes == nil)
        precondition(archivedStore.restoreSection(doomed) == nil)
        print("PASS: 项目删除可跨重启恢复，完整保留正文格式和会议时间，内置栏目受保护")

        archivedStore.select(scratch)
        precondition(archivedStore.deleteSection(doomed) && archivedStore.selectedID == scratch)
        let withoutScratch = folder.appending(path: "no-scratch.json")
        let ordinary = NoteSection(title: "旧项目", text: "原内容", tint: 2)
        try JSONEncoder().encode(NotebookDocument(sections: [ordinary], selectedID: ordinary.id)).write(to: withoutScratch)
        let oldStore = NoteStore(url: withoutScratch)
        precondition(oldStore.scratchSectionID == nil && oldStore.text == "原内容")
        let newScratch = oldStore.ensureScratchSection()
        precondition(oldStore.sections.filter { $0.title == "随手记" }.count == 1 && oldStore.text(in: ordinary.id) == "原内容")
        precondition(oldStore.ensureScratchSection() == newScratch)
        oldStore.select(ordinary.id)
        precondition(oldStore.deleteSection(ordinary.id) && oldStore.selectedID == newScratch)
        let automaticURL = folder.appending(path: "auto-scratch.json")
        try JSONEncoder().encode(NotebookDocument(sections: [ordinary], selectedID: ordinary.id)).write(to: automaticURL)
        let automatic = NoteStore(url: automaticURL)
        precondition(automatic.deleteSection(ordinary.id) && automatic.isScratch)
        let automaticReopened = NoteStore(url: automaticURL)
        precondition(automaticReopened.isScratch && automaticReopened.deletedSections.first?.section.text == "原内容")
        print("PASS: 零散任务复用唯一随手记，旧项目不被改写，删除非当前项目保持选择")

    }
}
