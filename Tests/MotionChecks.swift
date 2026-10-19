import AppKit
import SwiftUI

@main struct MotionChecks {
    @MainActor static func main() throws {
        setbuf(__stdoutp, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = NotchController(store: NoteStore(url: folder.appending(path: "note.json")))
        // Drive hover explicitly so pointer movement cannot override the test actions.
        (controller.panel.contentView as? NotchContainer)?.onHover = nil
        defer { controller.panel.orderOut(nil) }
        pump(0.05)
        let canvas = CGRect(origin: .zero, size: controller.state.surfaceSize)
        let closed = NotchReveal(progress: 0, compactWidth: controller.state.compactWidth).path(in: canvas).boundingRect
        let open = NotchReveal(progress: 1, compactWidth: controller.state.compactWidth).path(in: canvas).boundingRect
        precondition(closed.height == 10 && closed.width == controller.state.compactWidth)
        precondition(closed.midX == canvas.midX && closed.minY == open.minY && open == canvas)
        print("PASS: 揭示遮罩始终锚定刘海下缘，开合端点正确")

        controller.edit(animated: false)
        pump(0.05)
        let expandedFrame = controller.panel.frame
        let host = controller.panel.contentView!.subviews[0]
        let contentSize = host.frame.size
        controller.collapse()
        precondition(controller.state.contentMode == .editing)
        precondition(controller.panel.frame == expandedFrame)
        pump(0.4)
        precondition(controller.panel.frame.height == 10, "动画结束后必须缩回原生点击区域")
        precondition(host.frame.size == contentSize && controller.panel.contentView!.subviews[0] === host)
        precondition(controller.panel.frame.maxY == expandedFrame.maxY)
        print("PASS: 收起完成后才缩小窗口，编辑器始终保留尺寸和身份")

        controller.hover(true)
        pump(0.06)
        controller.collapse()
        pump(0.05)
        controller.hover(true)
        pump(0.4)
        precondition(controller.state.mode == .preview && controller.state.revealed)
        precondition(controller.panel.frame == expandedFrame, "被打断的收起动画不能关闭重新展开的窗口")
        print("PASS: 收起中重新展开，过期完成回调不会缩小窗口")

        controller.hover(false)
        pump(0.1)
        controller.hover(true)
        pump(0.4)
        precondition(controller.state.mode == .preview)
        print("PASS: 快速移出再移入可取消延迟收起")

        controller.collapse()
        pump(0.04)
        controller.toggle()
        precondition(controller.state.mode == .editing && controller.panel.frame == expandedFrame)
        pump(0.4)
        precondition(controller.panel.frame == expandedFrame)
        controller.toggle()
        precondition(controller.state.mode == .collapsed && controller.panel.frame.height == 10)
        print("PASS: 键盘开合即时完成，可覆盖未结束的鼠标过渡")

        controller.edit(animated: false)
        pump(0.08)
        let firstID = controller.store.selectedID
        let firstEditor = findEditor(in: host)!
        firstEditor.insertText("第一栏内容", replacementRange: firstEditor.selectedRange())
        let inputDeadline = Date(timeIntervalSinceNow: 1)
        while controller.store.text(in: firstID) != "第一栏内容", Date() < inputDeadline { pump(0.01) }
        precondition(controller.store.text(in: firstID) == "第一栏内容", "编辑器=\(firstEditor.string.debugDescription)，模型=\(controller.store.text(in: firstID).debugDescription)，存储=\(firstEditor.textStorage != nil)")
        firstEditor.setSelectedRange(NSRange(location: 0, length: firstEditor.string.utf16.count))
        firstEditor.apply(.bold)
        pump(0.08)
        precondition(firstEditor.selectedRange().length == firstEditor.string.utf16.count)
        firstEditor.apply(.underline)
        pump(0.08)
        precondition(firstEditor.selectedRange().length == firstEditor.string.utf16.count)
        precondition(firstEditor.currentStyle.bold && firstEditor.currentStyle.underline)
        let styled = controller.store.attributedText(in: firstID)
        precondition(styled.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == 1)
        print("PASS: 连续设置文字格式保留选区，RTF 保存不会打断编辑")
        controller.addSection("第二栏")
        pump(0.08)
        let secondEditor = findEditor(in: host)!
        precondition(firstEditor !== secondEditor && secondEditor.string.isEmpty)
        secondEditor.insertText("第二栏内容", replacementRange: secondEditor.selectedRange())
        pump(0.08)
        precondition(secondEditor.undoManager?.canUndo == true, "当前栏目必须支持撤销输入")
        secondEditor.undoManager?.undo()
        let undoDeadline = Date(timeIntervalSinceNow: 1)
        while !(secondEditor.string.isEmpty && controller.store.text.isEmpty), Date() < undoDeadline {
            pump(0.01)
        }
        precondition(secondEditor.string.isEmpty && controller.store.text.isEmpty)
        precondition(controller.store.text(in: firstID) == "第一栏内容")
        print("PASS: 切换栏目创建独立编辑器，撤销不会影响其他栏目的文字")
        controller.selectSection(firstID)
        pump(0.05)
        precondition(controller.state.showingEditor == false && controller.state.mode == .editing)
        precondition(controller.store.text == "第一栏内容")
        print("PASS: 点击索引签只显示对应栏目")

        controller.hover(true)
        controller.hover(false)
        pump(0.8)
        precondition(controller.state.mode == .collapsed && controller.panel.frame.height == 10)
        print("PASS: 切换项目后移开鼠标也能自动收起")

        controller.hover(true)
        controller.edit(animated: false)
        controller.hover(false)
        pump(0.8)
        precondition(controller.state.mode == .collapsed)
        print("PASS: 编辑状态移开鼠标自动收起，并保存输入")

        controller.hover(true)
        controller.togglePin()
        controller.hover(false)
        pump(0.5)
        precondition(controller.state.mode != .collapsed)
        controller.togglePin()
        pump(0.8)
        precondition(controller.state.mode == .collapsed)
        print("PASS: 固定阻止自动收起，取消固定恢复自动收起")

        controller.hover(true)
        controller.interaction("format", active: true)
        controller.hover(false)
        pump(0.5)
        precondition(controller.state.mode != .collapsed)
        controller.interaction("format", active: false)
        pump(0.8)
        precondition(controller.state.mode == .collapsed)
        controller.edit(animated: false)
        pump(0.5)
        precondition(controller.state.mode == .editing)
        print("PASS: 格式弹窗保护操作，键盘唤出无需先将鼠标移入")

        let sourceEditor = findEditor(in: host)!
        sourceEditor.insertText("前言🙂\n- [ ] #会议 讨论议程",
                                replacementRange: NSRange(location: 0, length: sourceEditor.string.utf16.count))
        pump(0.08)
        controller.selectSection(controller.store.meetingsSectionID)
        pump(0.08)
        precondition(controller.store.isMeetingOverview && !controller.state.showingEditor)
        let meeting = controller.store.projectMeetings[0]
        controller.openMeeting(meeting.reference)
        pump(0.15)
        precondition(controller.store.selectedID == firstID && controller.state.showingEditor)
        let meetingEditor = findEditor(in: host)!
        precondition((meetingEditor.string as NSString).substring(with: meetingEditor.selectedRange()) == "- [ ] #会议 讨论议程", "key=\(controller.panel.isKeyWindow), active=\(app.isActive), responder=\(String(describing: controller.panel.firstResponder)), selection=\(meetingEditor.selectedRange())")
        meetingEditor.apply(.meeting)
        pump(0.1)
        precondition(controller.store.projectMeetings.isEmpty)
        precondition(controller.store.text == "前言🙂\n- [ ] 讨论议程")
        print("PASS: 会议汇总跳回来源精确选中原行，编辑器取消标记自动保存并移出汇总")

        controller.toggleEditor()
        pump(0.08)
        precondition(!controller.state.showingEditor)
        controller.panel.orderOut(nil)
        controller.panel.orderFrontRegardless()
        controller.toggleEditor()
        pump(0.15)
        let resumedEditor = findEditor(in: host)!
        precondition(controller.panel.firstResponder === resumedEditor, "key=\(controller.panel.isKeyWindow), active=\(app.isActive), responder=\(String(describing: controller.panel.firstResponder))")
        resumedEditor.setSelectedRange(NSRange(location: resumedEditor.string.utf16.count, length: 0))
        resumedEditor.insertText("，补充", replacementRange: resumedEditor.selectedRange())
        pump(0.08)
        precondition(controller.store.text.hasSuffix("讨论议程，补充"))
        controller.toggleEditor()
        pump(0.08)
        precondition(NoteStore(url: folder.appending(path: "note.json")).text.hasSuffix("讨论议程，补充"))
        controller.panel.orderOut(nil)
        controller.panel.orderFrontRegardless()
        controller.edit(animated: false)
        pump(0.15)
        precondition(controller.panel.firstResponder === findEditor(in: host))
        print("PASS: 失去焦点后继续写与重新打开均恢复键盘响应，修改成功保存并可重读")

        let longEditor = findEditor(in: host)!
        let longText = (1...60).map { "第\($0)行：需要能够顺畅滚动并编辑到最后一行。" }.joined(separator: "\n")
        longEditor.insertText(longText, replacementRange: NSRange(location: 0, length: longEditor.string.utf16.count))
        pump(0.1)
        let scroll = longEditor.enclosingScrollView!
        longEditor.layoutManager?.ensureLayout(for: longEditor.textContainer!)
        longEditor.scrollRangeToVisible(NSRange(location: longEditor.string.utf16.count, length: 0))
        pump(0.1)
        precondition(longEditor.visibleRect.minY > 0, "长内容应能向下滚动")
        let lastGlyph = longEditor.layoutManager!.glyphRange(forCharacterRange: NSRange(location: longEditor.string.utf16.count - 1, length: 1), actualCharacterRange: nil)
        let lastRect = longEditor.layoutManager!.boundingRect(forGlyphRange: lastGlyph, in: longEditor.textContainer!)
            .offsetBy(dx: longEditor.textContainerOrigin.x, dy: longEditor.textContainerOrigin.y)
        precondition(longEditor.visibleRect.contains(lastRect), "最后一行必须能完整滚入可视区域：visible=\(longEditor.visibleRect), last=\(lastRect), document=\(longEditor.frame), clip=\(scroll.contentView.bounds)")
        print("PASS: 长便笺可以下滑至末行，末行完整显示")
        controller.selectSection(controller.store.meetingsSectionID)
        pump(0.05)
        controller.selectSection(firstID)
        controller.edit(animated: false)
        pump(0.1)
        let restoredEditor = findEditor(in: host)!
        precondition(restoredEditor !== longEditor && restoredEditor.string == longText)
        restoredEditor.scrollRangeToVisible(NSRange(location: restoredEditor.string.utf16.count, length: 0))
        pump(0.1)
        precondition(restoredEditor.visibleRect.minY > 0, "重开时 frame=\(restoredEditor.frame), max=\(restoredEditor.maxSize), used=\(restoredEditor.layoutManager!.usedRect(for: restoredEditor.textContainer!)), viewport=\(restoredEditor.enclosingScrollView!.contentView.bounds)")
        restoredEditor.insertText("短便笺", replacementRange: NSRange(location: 0, length: restoredEditor.string.utf16.count))
        pump(0.1)
        precondition(restoredEditor.frame.height <= restoredEditor.enclosingScrollView!.contentSize.height + 1,
                     "删去长内容后文档应收缩，不能留下大段空白滚动区")
        print("PASS: 切换后已有长便笺仍可滚动，删短内容后滚动区域随之收缩")
        controller.addSection("删除交互检查")
        pump(0.08)
        let deletableID = controller.store.selectedID
        let deletionEditor = findEditor(in: host)!
        deletionEditor.insertText("尚未离开编辑器的内容", replacementRange: deletionEditor.selectedRange())
        controller.deleteSection(deletableID)
        pump(0.08)
        precondition(controller.store.isScratch && !controller.state.showingEditor)
        precondition(controller.store.deletedSections.first?.section.text == "尚未离开编辑器的内容")
        controller.restoreSection(deletableID)
        pump(0.08)
        precondition(controller.store.selectedID == deletableID && controller.store.text == "尚未离开编辑器的内容")
        controller.openScratch()
        pump(0.08)
        precondition(controller.store.isScratch && controller.state.showingEditor)
        precondition(controller.panel.firstResponder === findEditor(in: host))
        print("PASS: 删除先保存实时编辑内容，恢复正确项目，随手记直接进入可输入状态")

    }

    @MainActor private static func pump(_ duration: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }

    @MainActor private static func findEditor(in view: NSView) -> EditorTextView? {
        if let editor = view as? EditorTextView { return editor }
        for child in view.subviews {
            if let editor = findEditor(in: child) { return editor }
        }
        return nil
    }
}
