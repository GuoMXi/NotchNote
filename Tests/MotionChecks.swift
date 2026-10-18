import AppKit
import SwiftUI

@main struct MotionChecks {
    @MainActor static func main() throws {
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
    }

    @MainActor private static func pump(_ duration: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }
}
