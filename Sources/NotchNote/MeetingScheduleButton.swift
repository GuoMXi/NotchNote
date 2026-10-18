import SwiftUI

struct MeetingScheduleButton: View {
    @Bindable var store: NoteStore
    let reference: MeetingReference
    let reminders: MeetingReminders?
    let onInteraction: (String, Bool) -> Void
    var compact = true
    @State private var presented = false
    @State private var date = Date()
    @State private var reminder = -1
    @State private var saving = false
    @State private var error: String?

    private var plan: MeetingPlan? { store.plan(in: reference.sectionID, line: reference.lineIndex) }
    private var label: String {
        guard let plan else { return compact ? "设时间" : "时间" }
        return plan.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "zh_CN")))
    }

    var body: some View {
        Button { presented = true } label: {
            HStack(spacing: 3) {
                Image(systemName: plan?.reminderMinutes == nil ? "calendar" : "bell")
                Text(label).lineLimit(1)
            }.font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(plan == nil ? .secondary : .primary)
                .frame(minHeight: compact ? 23 : 26)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help("选择会议日期、时间和提醒")
            .accessibilityLabel("会议时间与提醒：\(label)")
            .popover(isPresented: $presented, arrowEdge: .bottom) { controls }
            .onChange(of: presented) { _, visible in onInteraction("meeting-date", visible) }
            .onDisappear { if presented { onInteraction("meeting-date", false) } }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("会议时间").font(.system(size: 13, weight: .semibold))
                Text(NoteLine(id: 0, raw: reference.expectedRaw).displayText)
                    .font(.system(size: 11)).lineLimit(2).foregroundStyle(.secondary)
            }
            MeetingCalendar(selection: $date)
                .frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                HStack {
                    Text("时间").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute)
                        .labelsHidden().fixedSize()
                }
                HStack {
                    Text("提醒").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Picker("提醒", selection: $reminder) {
                        Text("不提醒").tag(-1)
                        Text("会议开始时").tag(0)
                        ForEach([5, 10, 15, 30, 60, 1440], id: \.self) { minutes in
                            Text(minutes == 1440 ? "提前 1 天" : "提前 \(minutes) 分钟").tag(minutes)
                        }
                    }.labelsHidden().frame(width: 136)
                }
            }.controlSize(.small)
            if reminder >= 0 {
                Text(reminders?.statusText ?? "提醒通过 macOS 通知发送。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if date.addingTimeInterval(-Double(reminder) * 60) <= .now {
                    Text("所选提醒时间已过去，请调整时间或提前量。")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
            }
            if let error { Text(error).font(.system(size: 10)).foregroundStyle(.red) }
            Divider().padding(.top, 2)
            HStack(spacing: 8) {
                if plan != nil {
                    Button("清除时间") { store.clearMeetingPlan(reference); presented = false }
                }
                Spacer()
                Button("取消") { presented = false }
                Button(saving ? "保存中…" : "保存") {
                    guard store.setMeetingPlan(reference, date: date, reminderMinutes: reminder < 0 ? nil : reminder) else {
                        error = "原行已改变或保存失败，请关闭后重新选择。"; return
                    }
                    saving = true
                    Task {
                        if reminder >= 0 { await reminders?.enableAndSync() }
                        saving = false
                        presented = false
                    }
                }.keyboardShortcut(.defaultAction).disabled(saving || (reminder >= 0 && date.addingTimeInterval(-Double(reminder) * 60) <= .now))
            }.controlSize(.small)
        }.padding(14).frame(width: 236)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .onAppear {
                error = nil
                if let plan { date = plan.date; reminder = plan.reminderMinutes ?? -1 }
                else {
                    date = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
                    reminder = -1
                }
            }
    }
}
