import SwiftUI

struct NoteLineRow: View {
    let rendered: RichText.Line
    let onToggle: () -> Void
    let onEdit: () -> Void
    var meetingCheckbox = false
    var showMeetingBadge = true
    var schedule: MeetingScheduleButton? = nil
    var projectTitle: String? = nil

    var body: some View {
        let line = rendered.line
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if line.isTask || line.isMeeting || meetingCheckbox {
                    Button(action: onToggle) {
                        Image(systemName: line.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16)).foregroundStyle(.black.opacity(line.isDone ? 0.3 : 0.5))
                            .frame(width: 20, height: 24)
                    }.buttonStyle(.plain)
                        .accessibilityLabel(line.isDone ? "标记未完成：\(line.displayText)" : "完成：\(line.displayText)")
                } else { Color.clear.frame(width: 20, height: 24).accessibilityHidden(true) }
            }.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
            Text(line.displayText.isEmpty ? AttributedString(" ") : rendered.text)
                .font(.system(size: 15)).lineSpacing(3)
                .strikethrough(line.isDone).opacity(line.isDone ? 0.4 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture(perform: onEdit)
                .layoutPriority(1)
            if let schedule { schedule }
            else if line.isMeeting && showMeetingBadge {
                Image(systemName: "calendar").font(.system(size: 10)).foregroundStyle(.secondary)
                    .help("已标记为会议，自动显示到近期").accessibilityLabel("会议标记")
            }
            if let projectTitle {
                Button(action: onEdit) {
                    Text(projectTitle).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).frame(width: 58, alignment: .trailing)
                }.buttonStyle(.plain).help("来自\(projectTitle)，点击编辑原文")
                    .accessibilityLabel("在项目“\(projectTitle)”中编辑事项")
            }
        }.padding(.vertical, 3)
    }
}

struct MeetingOverview: View {
    @Bindable var store: NoteStore
    let reminders: MeetingReminders?
    let onWrite: () -> Void
    let onOpenMeeting: (MeetingReference) -> Void
    let onInteraction: (String, Bool) -> Void
    @State private var showingCompleted = false
    @State private var showingPast = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let meetings = store.overviewMeetings
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(RecentGroup.allCases) { group in
                        let items = meetings.filter { $0.group(now: context.date) == group }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                if group == .completed || group == .past {
                                    Button {
                                        if group == .completed { showingCompleted.toggle() } else { showingPast.toggle() }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: (group == .completed ? showingCompleted : showingPast) ? "chevron.down" : "chevron.right")
                                                .font(.system(size: 8))
                                            Text("\(group.title) · \(items.count)")
                                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                                    }.buttonStyle(.plain)
                                } else {
                                    Text(group.title).font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(group == .overdue ? Color(red: 0.65, green: 0.29, blue: 0.23) : .secondary)
                                }
                                if group != .completed && group != .past || (group == .completed ? showingCompleted : showingPast) {
                                    ForEach(items) { meeting in
                                        NoteLineRow(rendered: meeting.rendered,
                                                    onToggle: { store.toggleMeeting(meeting.reference) },
                                                    onEdit: { onOpenMeeting(meeting.reference) },
                                                    meetingCheckbox: true, showMeetingBadge: false,
                                                    schedule: MeetingScheduleButton(store: store, reference: meeting.reference,
                                                                                    reminders: reminders, onInteraction: onInteraction),
                                                    projectTitle: meeting.projectTitle)
                                    }
                                }
                            }
                        }
                    }
                    ForEach(RichText.lines(store.attributedText(in: store.meetingsSectionID)).filter {
                        !$0.line.isTask && !$0.line.isMeeting
                    }) { rendered in
                        NoteLineRow(rendered: rendered, onToggle: {}, onEdit: onWrite)
                    }
                    if meetings.isEmpty {
                        Text("在任意项目或随手记中设置时间，\n截止任务和会议会自动汇总到这里。")
                            .font(.system(size: 12)).lineSpacing(5).foregroundStyle(.secondary)
                        Button("记一件事", action: onWrite).buttonStyle(.plain).font(.system(size: 12))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
        }
    }
}
