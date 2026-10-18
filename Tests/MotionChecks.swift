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
        // Keep the pointer out of this test panel so real hover doesn't override test actions.
        controller.panel.ignoresMouseEvents = true
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
        precondition((meetingEditor.string as NSString).substring(with: meetingEditor.selectedRange()) == "- [ ] #会议 讨论议程")
        meetingEditor.apply(.meeting)
        pump(0.1)
        precondition(controller.store.projectMeetings.isEmpty)
        precondition(controller.store.text == "前言🙂\n- [ ] 讨论议程")
        print("PASS: 会议汇总跳回来源精确选中原行，编辑器取消标记自动保存并移出汇总")

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
