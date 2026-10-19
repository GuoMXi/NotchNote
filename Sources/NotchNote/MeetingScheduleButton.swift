import SwiftUI

struct MeetingScheduleButton: View {
    @Bindable var store: NoteStore
    let reference: MeetingReference
    let reminders: MeetingReminders?
    let onInteraction: (String, Bool) -> Void
    var compact = true
    @State private var presented = false
    @State private var date = Date()
    @State private var kind = ScheduleKind.deadline
    @State private var dateOnly = true
    @State private var reminder = -1
    @State private var saving = false
    @State private var error: String?

    private var plan: MeetingPlan? { store.plan(in: reference.sectionID, line: reference.lineIndex) }
    private var label: String {
        guard let plan else { return compact ? "设时间" : "时间" }
        let day = plan.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "zh_CN")))
        if plan.isDateOnly { return "\(day)截止" }
        let time = plan.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "zh_CN")))
        return "\(day) \(time)"
    }

    private var isOverdue: Bool {
        guard let plan, plan.scheduleKind == .deadline,
              !NoteLine(id: 0, raw: reference.expectedRaw).isDone else { return false }
        return plan.dueDate() <= .now
    }

    private var draft: MeetingPlan {
        MeetingPlan(sectionID: reference.sectionID, lineIndex: reference.lineIndex, raw: reference.expectedRaw,
                    date: date, reminderMinutes: reminder < -1 ? 0 : (reminder < 0 ? nil : reminder),
                    kind: kind, dateOnly: dateOnly,
                    reminderRule: reminder == -2 ? .onDay : (reminder == -3 ? .dayBefore : .offset))
    }
    private var reminderPassed: Bool { draft.reminderDate().map { $0 <= .now } ?? false }

    var body: some View {
        Button { presented = true } label: {
            HStack(spacing: 3) {
                Image(systemName: plan?.scheduleKind.symbol ?? "calendar.badge.plus")
                Text(label).lineLimit(1)
            }.font(.system(size: compact ? 10 : 11))
                .foregroundStyle(isOverdue ? Color(red: 0.65, green: 0.29, blue: 0.23) : .secondary)
                .frame(width: compact ? 92 : nil, height: compact ? 24 : 26, alignment: .trailing)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help("设置截止时间、会议和提醒")
            .accessibilityLabel("事项时间与提醒：\(label)")
            .popover(isPresented: $presented, arrowEdge: .bottom) { controls }
            .onChange(of: presented) { _, visible in onInteraction("meeting-date", visible) }
            .onDisappear { if presented { onInteraction("meeting-date", false) } }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("设置时间").font(.system(size: 13, weight: .semibold))
                Spacer()
                if plan != nil {
                    Button("清除") { store.clearMeetingPlan(reference); presented = false }
                        .font(.system(size: 10)).foregroundStyle(.secondary).buttonStyle(.plain)
                        .accessibilityLabel("清除时间")
                }
            }
            Text(NoteLine(id: 0, raw: reference.expectedRaw).displayText)
                .font(.system(size: 11)).lineLimit(2).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(ScheduleKind.allCases, id: \.self) { option in
                    Button { kind = option; reminder = -1 } label: {
                        Text(option.title).font(.system(size: 12, weight: kind == option ? .medium : .regular))
                            .foregroundStyle(kind == option ? Color.accentColor : .secondary)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(kind == option ? Color.accentColor : Color.secondary.opacity(0.15)).frame(height: kind == option ? 2 : 1)
                            }
                    }.buttonStyle(.plain).accessibilityValue(kind == option ? "已选中" : "未选中")
                }
            }
            MeetingCalendar(selection: $date)
            if kind == .deadline {
                Toggle("只设日期", isOn: $dateOnly).font(.system(size: 11)).toggleStyle(.checkbox)
                    .onChange(of: dateOnly) { _, _ in reminder = -1 }
            }
            if kind == .meeting || !dateOnly {
                HStack {
                    Text(kind == .meeting ? "开始于" : "截止于").foregroundStyle(.secondary)
                    Spacer()
                    DatePicker(kind == .meeting ? "开始时间" : "截止时间", selection: $date, displayedComponents: .hourAndMinute)
                        .labelsHidden().fixedSize()
                }.font(.system(size: 11))
            }
            HStack {
                Text("提醒").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Picker("提醒", selection: $reminder) {
                    Text("不提醒").tag(-1)
                    if kind == .deadline {
                        Text("当天 09:00").tag(-2)
                        Text("前一天 09:00").tag(-3)
                        if !dateOnly { Text("提前 1 小时").tag(60) }
                    } else {
                        Text("开始时").tag(0)
                        ForEach([5, 10, 15, 30, 60, 1440], id: \.self) { minutes in
                            Text(minutes == 1440 ? "提前 1 天" : "提前 \(minutes) 分钟").tag(minutes)
                        }
                    }
                }.labelsHidden().frame(width: 128)
            }
            if reminder != -1 {
                Text(reminders?.statusText ?? "通过 macOS 通知提醒")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if reminderPassed {
                    Text("提醒时间已过，请调整。")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
            }
            if let error { Text(error).font(.system(size: 10)).foregroundStyle(.red) }
            HStack {
                Button("取消") { presented = false }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(saving ? "保存中…" : "保存") {
                    let value = draft
                    guard store.setSchedule(reference, date: value.date, kind: kind, dateOnly: dateOnly,
                                            reminderMinutes: value.reminderMinutes, reminderRule: value.reminderRule ?? .offset) else {
                        error = "原行已改变或保存失败，请关闭后重新选择。"; return
                    }
                    saving = true
                    Task {
                        if reminder != -1 { await reminders?.enableAndSync() }
                        saving = false
                        presented = false
                    }
                }.keyboardShortcut(.defaultAction).disabled(saving || (reminder != -1 && reminderPassed))
            }.padding(.top, 2)
        }.controlSize(.small).padding(16).frame(width: 248)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .onAppear {
                error = nil
                if let plan {
                    date = plan.date; kind = plan.scheduleKind; dateOnly = plan.isDateOnly
                    reminder = plan.reminderMinutes ?? -1
                    if plan.reminderMinutes != nil {
                        if plan.reminderRule == .onDay { reminder = -2 }
                        if plan.reminderRule == .dayBefore { reminder = -3 }
                    }
                } else {
                    date = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
                    kind = NoteLine(id: 0, raw: reference.expectedRaw).isMeeting ? .meeting : .deadline
                    dateOnly = kind == .deadline
                    reminder = -1
                }
            }
    }
}
