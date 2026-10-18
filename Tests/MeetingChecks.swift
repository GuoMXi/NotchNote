import AppKit
import UserNotifications

@main struct MeetingChecks {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "note.json")
        let store = NoteStore(url: url)
        let project = store.selectedID, hub = store.meetingsSectionID
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.text = "- [ ] #会议 晚会\n- [ ] #会议 早会\n- [x] #会议 已完成\n- [ ] #会议 未定"
        store.updateText("- [ ] 直接写的会", in: hub)
        let late = store.reference(forLine: 0, in: project)!
        precondition(store.setMeetingPlan(late, date: now.addingTimeInterval(7200), reminderMinutes: 15))
        precondition(store.setMeetingPlan(store.reference(forLine: 1, in: project)!, date: now.addingTimeInterval(3600), reminderMinutes: nil))
        precondition(store.setMeetingPlan(store.reference(forLine: 2, in: project)!, date: now, reminderMinutes: 5))
        precondition(store.setMeetingPlan(store.reference(forLine: 0, in: hub)!, date: now.addingTimeInterval(5400), reminderMinutes: 0))
        precondition(store.overviewMeetings.map { $0.rendered.line.displayText } == ["早会", "直接写的会", "晚会", "未定", "已完成"])
        let reopened = NoteStore(url: url)
        precondition(reopened.meetingPlans == store.meetingPlans && reopened.overviewMeetings.map(\.id) == store.overviewMeetings.map(\.id))
        print("PASS: 项目与直接记录统一按时间排序，未定与已完成后置，时间提醒重启保留")

        let identity = store.plan(in: project, line: 0)!.id
        store.updateText("新增说明\n- [ ] #会议 晚会\n- [ ] #会议 早会\n- [x] #会议 已完成\n- [ ] #会议 未定", in: project)
        precondition(store.plan(in: project, line: 1)?.id == identity)
        store.updateText(store.text(in: project).replacingOccurrences(of: "晚会", with: "晚会更新🙂"), in: project)
        precondition(store.plan(in: project, line: 1)?.id == identity)
        precondition(store.plan(in: project, line: 1)?.date == now.addingTimeInterval(7200))
        store.toggleMeeting(store.reference(forLine: 1, in: project)!)
        precondition(store.plan(in: project, line: 1)?.id == identity)
        store.toggleMeeting(store.reference(forLine: 1, in: project)!)
        precondition(store.setMeetingPlan(store.reference(forLine: 1, in: project)!, date: now.addingTimeInterval(10_800), reminderMinutes: 30))
        precondition(store.plan(in: project, line: 1)?.id == identity)
        print("PASS: 插入行、修改中文标题、完成切换与改期保留同一会议身份和时间")

        let expected = MeetingReminderRequest.pending(plans: store.meetingPlans, sections: store.sections, now: now)
        precondition(expected.count == 2)
        precondition(expected[0].body == "直接写的会" && expected[0].fireDate == now.addingTimeInterval(5400))
        precondition(expected[1].body == "晚会更新🙂" && expected[1].fireDate == now.addingTimeInterval(9000))
        precondition(MeetingReminderRequest.pending(plans: store.meetingPlans, sections: store.sections, now: now.addingTimeInterval(20_000)).isEmpty)
        store.toggleMeetingMark(1, in: project)
        precondition(!store.meetingPlans.contains { $0.id == identity })
        store.updateText("", in: hub)
        precondition(!store.meetingPlans.contains { $0.sectionID == hub })
        print("PASS: 提前量按实际时间计算，过去与完成会议不提醒，删除和取消标记清除计划")

        let direct = store.addSection(title: "新项目")!
        store.text = "写一条新会议🙂"
        precondition(store.setMeetingPlan(store.reference(forLine: 0, in: direct)!, date: now, reminderMinutes: nil))
        precondition(store.text == "- [ ] #会议 写一条新会议🙂" && store.plan(in: direct, line: 0) != nil)
        store.clearMeetingPlan(store.reference(forLine: 0, in: direct)!)
        precondition(store.plan(in: direct, line: 0) == nil && store.text.contains("#会议"))
        store.updateText("直接写的新会议", in: hub)
        precondition(store.setMeetingPlan(store.reference(forLine: 0, in: hub)!, date: now, reminderMinutes: nil))
        precondition(store.overviewMeetings.contains { $0.reference.sectionID == hub && $0.plan != nil })
        store.toggleMeetingMark(0, in: hub)
        precondition(store.plan(in: hub, line: 0) == nil)
        precondition(!store.setMeetingPlan(late, date: now, reminderMinutes: 15))
        print("PASS: 自由文本选择日期自动标记会议，直接写会议可排期，清除时间保留正文，过期操作拒绝")

        let attrs = NSMutableAttributedString(string: "- [ ] #会议 重点🙂", attributes: RichText.defaults)
        attrs.addAttribute(.underlineStyle, value: 1, range: NSRange(location: 10, length: 4))
        store.updateRichText(attrs, in: direct)
        precondition(store.setMeetingPlan(store.reference(forLine: 0, in: direct)!, date: now, reminderMinutes: nil))
        let canonical = RichText.decode(try RichText.encode(attrs), text: attrs.string)
        precondition(store.attributedText(in: direct).isEqual(to: canonical))
        print("PASS: 会议日期独立保存，不改变正文和富文本格式")

        // No system notifications or permission dialogs: exercise scheduling through a fake delivery.
        let delivery = FakeNotifications()
        let reminders = MeetingReminders(store: store, delivery: delivery)
        let future = Date().addingTimeInterval(3600)
        precondition(store.setMeetingPlan(store.reference(forLine: 0, in: direct)!, date: future, reminderMinutes: 15))
        await reminders.synchronizeNow()
        precondition(delivery.authorizationRequests == 0 && delivery.requests.isEmpty)
        await reminders.enableAndSync()
        precondition(delivery.authorizationRequests == 1 && delivery.requests.count == 1)
        let id = store.plan(in: direct, line: 0)!.id
        precondition(delivery.requests[id]?.fireDate == future.addingTimeInterval(-900))
        precondition(store.setMeetingPlan(store.reference(forLine: 0, in: direct)!, date: future.addingTimeInterval(3600), reminderMinutes: 5))
        await reminders.synchronizeNow()
        precondition(delivery.requests.count == 1 && delivery.requests[id]?.fireDate == future.addingTimeInterval(3300))
        delivery.delivered = ["notchnote.meeting." + id.uuidString]
        store.toggleMeeting(store.reference(forLine: 0, in: direct)!)
        await reminders.synchronizeNow()
        precondition(delivery.requests.isEmpty && delivery.delivered.isEmpty)
        print("PASS: 仅主动启用时请求权限，改期替换原通知，完成后撤销待发和已显示通知")

        store.toggleMeeting(store.reference(forLine: 0, in: direct)!)
        delivery.permission = .denied
        await reminders.enableAndSync()
        precondition(delivery.authorizationRequests == 1 && delivery.requests.isEmpty && reminders.statusText.contains("通知未允许"))
        delivery.permission = .authorized
        delivery.failAdds = true
        await reminders.synchronizeNow()
        precondition(reminders.statusText.contains("未能安排"))
        delivery.failAdds = false
        store.clearMeetingPlan(store.reference(forLine: 0, in: direct)!)
        await reminders.synchronizeNow()
        precondition(delivery.requests.isEmpty)
        print("PASS: 权限拒绝和通知安排失败提供真实状态，清除时间不残留提醒")
        let notification = SystemMeetingNotifications.notification(for: expected[1])
        let trigger = notification.trigger as! UNCalendarNotificationTrigger
        precondition(!trigger.repeats)
        precondition(Int(trigger.nextTriggerDate()!.timeIntervalSince1970) == Int(expected[1].fireDate.timeIntervalSince1970))
        precondition(notification.content.userInfo["meetingPlanID"] as? String == expected[1].id.uuidString)
        print("PASS: 原生通知触发器使用完整日期与时区，点击通知可定位稳定会议身份")

        precondition(store.setMeetingPlan(store.reference(forLine: 0, in: direct)!, date: future, reminderMinutes: 5))
        delivery.pauseNextAdd = true
        let oldSync = Task { await reminders.synchronizeNow() }
        var attempts = 0
        while delivery.heldAdd == nil && attempts < 1000 { attempts += 1; await Task.yield() }
        precondition(delivery.heldAdd != nil)
        store.clearMeetingPlan(store.reference(forLine: 0, in: direct)!)
        let finalSync = Task { await reminders.synchronizeNow() }
        await Task.yield()
        delivery.heldAdd?.resume()
        delivery.heldAdd = nil
        await oldSync.value
        await finalSync.value
        precondition(delivery.requests.isEmpty)
        print("PASS: 通知异步安排途中删除会议，最终同步等待完成且不残留过期通知")

    }
}

@MainActor final class FakeNotifications: MeetingNotificationDelivery {
    weak var delegate: (any UNUserNotificationCenterDelegate)?
    var permission = UNAuthorizationStatus.notDetermined
    var authorizationRequests = 0
    var requests: [UUID: MeetingReminderRequest] = [:]
    var delivered: [String] = []
    var failAdds = false
    var pauseNextAdd = false
    var heldAdd: CheckedContinuation<Void, Never>?
    func status() async -> UNAuthorizationStatus { permission }
    func authorize() async throws -> Bool { authorizationRequests += 1; permission = .authorized; return true }
    func pendingIDs() async -> [String] { requests.keys.map { "notchnote.meeting." + $0.uuidString } }
    func deliveredIDs() async -> [String] { delivered }
    func removePending(_ ids: [String]) { requests = requests.filter { !ids.contains("notchnote.meeting." + $0.key.uuidString) } }
    func removeDelivered(_ ids: [String]) { delivered.removeAll { ids.contains($0) } }
    func add(_ request: MeetingReminderRequest) async throws {
        if failAdds { throw CocoaError(.fileWriteUnknown) }
        if pauseNextAdd {
            pauseNextAdd = false
            await withCheckedContinuation { heldAdd = $0 }
        }
        requests[request.id] = request
    }
}
