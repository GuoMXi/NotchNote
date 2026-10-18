import SwiftUI

struct NoteLineRow: View {
    let rendered: RichText.Line
    let onToggle: () -> Void
    let onEdit: () -> Void
    var meetingCheckbox = false
    var showMeetingBadge = true

    var body: some View {
        let line = rendered.line
        HStack(alignment: .top, spacing: 10) {
            if line.isTask || line.isMeeting || meetingCheckbox {
                Button(action: onToggle) {
                    Image(systemName: line.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17)).foregroundStyle(.black.opacity(line.isDone ? 0.35 : 0.65))
                        .frame(width: 24, height: 23)
                }.buttonStyle(.plain)
                    .accessibilityLabel(line.isDone ? "标记未完成：\(line.displayText)" : "完成：\(line.displayText)")
            }
            Text(line.displayText.isEmpty ? AttributedString(" ") : rendered.text)
                .font(.system(size: 15)).lineSpacing(4)
                .strikethrough(line.isDone).opacity(line.isDone ? 0.4 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture(perform: onEdit)
            if line.isMeeting && showMeetingBadge {
                Image(systemName: "calendar").font(.system(size: 11))
                    .foregroundStyle(.orange).padding(.top, 4)
                    .help("已标记为会议，会自动显示到近期会议")
                    .accessibilityLabel("会议标记")
            }
        }
    }
}

struct MeetingOverview: View {
    @Bindable var store: NoteStore
    let onWrite: () -> Void
    let onOpenMeeting: (MeetingReference) -> Void

    var body: some View {
        let meetings = store.projectMeetings
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !meetings.isEmpty { caption("直接记录") }
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(RichText.lines(store.attributedText(in: store.selectedID))) { rendered in
                            NoteLineRow(rendered: rendered, onToggle: { store.toggle(rendered.id) }, onEdit: onWrite)
                        }
                    }
                }

                if !meetings.isEmpty {
                    caption("来自项目 · 自动汇总")
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(meetings) { meeting in
                            HStack(alignment: .top, spacing: 6) {
                                NoteLineRow(rendered: meeting.rendered,
                                            onToggle: { store.toggleMeeting(meeting.reference) },
                                            onEdit: { onOpenMeeting(meeting.reference) },
                                            meetingCheckbox: true, showMeetingBadge: false)
                                Button { onOpenMeeting(meeting.reference) } label: {
                                    Text(meeting.projectTitle)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .frame(height: 23)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .help("来自\(meeting.projectTitle)，点击回到原项目")
                                    .accessibilityLabel("在项目“\(meeting.projectTitle)”中编辑会议")
                            }
                        }
                    }
                }

                if meetings.isEmpty {
                    Text("在项目里点“会议”，或写 #会议 标记一行，即可在这里汇总。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.text.isEmpty {
                        Button("直接记一条会议", action: onWrite).buttonStyle(.bordered)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
    }
}
