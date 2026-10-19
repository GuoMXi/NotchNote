import Foundation

nonisolated struct MeetingReference: Hashable {
    let sectionID: UUID
    let lineIndex: Int
    let expectedRaw: String
}

struct ProjectMeeting: Identifiable {
    let reference: MeetingReference
    let projectTitle: String
    let rendered: RichText.Line
    var plan: MeetingPlan? = nil
    var id: String { "\(reference.sectionID):\(reference.lineIndex)" }
}

nonisolated struct MeetingMarkerEdit {
    let range: NSRange
    let replacement: String

    static func toggle(line: NoteLine, location: Int) -> MeetingMarkerEdit {
        if line.isMeeting {
            return MeetingMarkerEdit(range: NSRange(location: location + (line.isTask ? 6 : 0),
                                                   length: line.meetingPrefixLength), replacement: "")
        }
        return MeetingMarkerEdit(range: NSRange(location: location + (line.isTask ? 6 : 0), length: 0),
                                 replacement: line.isTask ? "#会议 " : "- [ ] #会议 ")
    }
}

nonisolated enum RecentGroup: Int, CaseIterable, Identifiable {
    case overdue, today, upcoming, undated, past, completed
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .overdue: "已逾期"
        case .today: "今天"
        case .upcoming: "接下来"
        case .undated: "未定时间"
        case .past: "已过时间"
        case .completed: "已完成"
        }
    }
}

extension ProjectMeeting {
    func group(now: Date, calendar: Calendar = .current) -> RecentGroup {
        if rendered.line.isDone { return .completed }
        guard let plan else { return .undated }
        if plan.scheduleKind == .deadline && plan.dueDate(calendar: calendar) <= now { return .overdue }
        if calendar.isDate(plan.date, inSameDayAs: now) { return .today }
        return plan.date < calendar.startOfDay(for: now) ? .past : .upcoming
    }
}
