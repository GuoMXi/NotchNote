import AppKit
import UserNotifications

@main struct MeetingChecks {
    @MainActor static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        let leapMonth = calendar.date(from: DateComponents(year: 2028, month: 2, day: 15, hour: 19, minute: 30))!
        let days = MeetingCalendarMath.days(in: leapMonth, calendar: calendar)
        precondition(days.count % 7 == 0 && days.count <= 42)
        precondition(calendar.component(.weekday, from: days[0]) == 1)
        precondition(days.filter { calendar.component(.month, from: $0) == 2 }.count == 29)
        let march = calendar.date(from: DateComponents(year: 2027, month: 3, day: 14))!
        let chosen = MeetingCalendarMath.selecting(march, keepingTimeOf: leapMonth, calendar: calendar)
        let chosenParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: chosen)
        precondition(chosenParts.year == 2027 && chosenParts.month == 3 && chosenParts.day == 14)
        precondition(chosenParts.hour == 19 && chosenParts.minute == 30)
        print("PASS: 无边框日历覆盖闰月、整周网格及夏令时切日保留会议时间")

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

        let deadlineProject = store.addSection(title: "截止测试")!
        let styledDeadline = NSMutableAttributedString(string: "交稿🙂\n无时间的小事", attributes: RichText.defaults)
        styledDeadline.addAttribute(.underlineStyle, value: 1, range: NSRange(location: 0, length: 4))
        store.updateRichText(styledDeadline, in: deadlineProject)
        let dueDay = calendar.date(from: DateComponents(year: 2027, month: 3, day: 14, hour: 12))!
        precondition(store.setSchedule(store.reference(forLine: 0, in: deadlineProject)!, date: dueDay,
                                       kind: .deadline, dateOnly: true, reminderMinutes: nil))
        precondition(store.text == "- [ ] 交稿🙂\n无时间的小事")
        let deadlineID = store.plan(in: deadlineProject, line: 0)!.id
        precondition(store.projectMeetings.filter { $0.reference.sectionID == deadlineProject }.count == 1)
        precondition(store.attributedText(in: deadlineProject).attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int == 1)
        let roundTrip = NoteStore(url: url)
        precondition(roundTrip.plan(in: deadlineProject, line: 0)?.scheduleKind == .deadline)
        precondition(roundTrip.plan(in: deadlineProject, line: 0)?.isDateOnly == true)
        print("PASS: 普通行设截止自动成为任务，保留富文本，未定日期小事不进入近期，重启保留类型")

        let samplePlan = MeetingPlan(sectionID: deadlineProject, lineIndex: 0, raw: "- [ ] 交稿", date: dueDay,
                                     reminderMinutes: 0, kind: .deadline, dateOnly: true, reminderRule: .onDay)
        let dueParts = calendar.dateComponents([.day, .hour], from: samplePlan.dueDate(calendar: calendar))
        precondition(dueParts.day == 15 && dueParts.hour == 0)
        let fireParts = calendar.dateComponents([.day, .hour], from: samplePlan.reminderDate(calendar: calendar)!)
        precondition(fireParts.day == 14 && fireParts.hour == 9)
        var previousDay = samplePlan
        previousDay.reminderRule = .dayBefore
        let previousParts = calendar.dateComponents([.day, .hour], from: previousDay.reminderDate(calendar: calendar)!)
        precondition(previousParts.day == 13 && previousParts.hour == 9)
        let legacyPlan = try JSONDecoder().decode(MeetingPlan.self, from: Data("{\"id\":\"\(UUID())\",\"sectionID\":\"\(deadlineProject)\",\"lineIndex\":0,\"raw\":\"旧会议\",\"date\":0}".utf8))
        precondition(legacyPlan.scheduleKind == .meeting && !legacyPlan.isDateOnly)
        print("PASS: 仅日期截止持续到次日零点，夏令时当天及前一天九点提醒正确，旧计划兼容")

        let sampleRef = MeetingReference(sectionID: deadlineProject, lineIndex: 0, expectedRaw: "- [ ] 交稿")
        let sampleItem = ProjectMeeting(reference: sampleRef, projectTitle: "测试",
                                       rendered: RichText.lines(NSAttributedString(string: "- [ ] 交稿"))[0], plan: samplePlan)
        precondition(sampleItem.group(now: dueDay, calendar: calendar) == .today)
        precondition(sampleItem.group(now: samplePlan.dueDate(calendar: calendar), calendar: calendar) == .overdue)
        var oldMeeting = sampleItem
        oldMeeting.plan?.kind = .meeting
        oldMeeting.plan?.dateOnly = false
        precondition(oldMeeting.group(now: calendar.date(byAdding: .day, value: 2, to: dueDay)!, calendar: calendar) == .past)
        print("PASS: 日期截止当天不误判逾期，会议过时归档而非标成逾期")

        precondition(store.setSchedule(store.reference(forLine: 0, in: deadlineProject)!, date: dueDay,
                                       kind: .meeting, dateOnly: false, reminderMinutes: nil))
        precondition(store.text.hasPrefix("- [ ] #会议 交稿🙂"))
        precondition(store.plan(in: deadlineProject, line: 0)?.id == deadlineID)
        precondition(store.setSchedule(store.reference(forLine: 0, in: deadlineProject)!, date: dueDay,
                                       kind: .deadline, dateOnly: true, reminderMinutes: 0, reminderRule: .dayBefore))
        precondition(store.text.hasPrefix("- [ ] 交稿🙂"))
        precondition(store.plan(in: deadlineProject, line: 0)?.id == deadlineID)
        store.updateText("新增说明\n" + store.text, in: deadlineProject)
        precondition(store.plan(in: deadlineProject, line: 1)?.id == deadlineID)
        store.toggleMeeting(store.reference(forLine: 1, in: deadlineProject)!)
        precondition(store.overviewMeetings.first { $0.plan?.id == deadlineID }?.group(now: dueDay) == .completed)
        precondition(store.deleteSection(deadlineProject))
        precondition(store.restoreSection(deadlineProject) == deadlineProject)
        precondition(store.plan(in: deadlineProject, line: 1)?.scheduleKind == .deadline)
        precondition(store.plan(in: deadlineProject, line: 1)?.reminderMinutes == nil)
        store.clearMeetingPlan(store.reference(forLine: 1, in: deadlineProject)!)
        precondition(!store.projectMeetings.contains { $0.reference.sectionID == deadlineProject })
        print("PASS: 会议与截止互转保留身份，行位移和完成同步，删除恢复保留截止且关闭提醒，清除后退出近期")

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
        precondition(store.setMeetingPlan(store.reference(forLine: 0, in: direct)!, date: future, reminderMinutes: 5))
        await reminders.synchronizeNow()
        precondition(delivery.requests.count == 1)
        precondition(store.deleteSection(direct))
        await reminders.synchronizeNow()
        precondition(delivery.requests.isEmpty)
        precondition(store.restoreSection(direct) == direct)
        await reminders.synchronizeNow()
        precondition(delivery.requests.isEmpty && store.plan(in: direct, line: 0)?.date == future)
        print("PASS: 删除整个项目取消系统提醒，恢复保留会议时间且不会重新弹出提醒")
        let deadlineFuture = Calendar.current.date(byAdding: .day, value: 2, to: .now)!
        precondition(store.setSchedule(store.reference(forLine: 0, in: direct)!, date: deadlineFuture,
                                       kind: .deadline, dateOnly: true, reminderMinutes: 0, reminderRule: .onDay))
        await reminders.synchronizeNow()
        let deadlineRequest = delivery.requests.values.first!
        precondition(delivery.requests.count == 1 && deadlineRequest.title.hasPrefix("截止提醒"))
        precondition(Calendar.current.component(.hour, from: deadlineRequest.fireDate) == 9)
        store.toggleMeeting(store.reference(forLine: 0, in: direct)!)
        await reminders.synchronizeNow()
        precondition(delivery.requests.isEmpty)
        store.toggleMeeting(store.reference(forLine: 0, in: direct)!)
        store.toggleMeetingMark(0, in: direct)
        precondition(store.plan(in: direct, line: 0)?.scheduleKind == .meeting)
        precondition(store.plan(in: direct, line: 0)?.reminderMinutes == nil)
        store.toggleMeetingMark(0, in: direct)
        precondition(store.plan(in: direct, line: 0) == nil)
        precondition(store.setSchedule(store.reference(forLine: 0, in: direct)!, date: deadlineFuture,
                                       kind: .deadline, dateOnly: true, reminderMinutes: nil))
        store.text = "恢复普通说明"
        precondition(store.plan(in: direct, line: 0) == nil)
        print("PASS: 日期截止发送九点提醒，完成后撤销，手动会议标记同步类型并关闭旧提醒，取消待办移除截止")



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
