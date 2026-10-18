import Foundation

nonisolated struct MeetingPlan: Codable, Equatable, Identifiable {
    var id = UUID()
    var sectionID: UUID
    var lineIndex: Int
    var raw: String
    var date: Date
    var reminderMinutes: Int?
}

nonisolated enum MeetingAnchors {
    /// Map unchanged lines first, then a replacement within the same unchanged boundaries.
    /// Ambiguous splits/deletions drop the plan instead of moving a reminder to another meeting.
    static func reconcile(_ plans: [MeetingPlan], sectionID: UUID, old: String, new: String, hub: Bool) -> [MeetingPlan] {
        let before = old.components(separatedBy: "\n")
        let after = new.components(separatedBy: "\n")
        let difference = after.difference(from: before)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        let unchanged = Array(zip(before.indices.filter { !removed.contains($0) }, after.indices.filter { !inserted.contains($0) }))
        let matches = Dictionary(uniqueKeysWithValues: unchanged)
        return plans.compactMap { original in
            guard original.sectionID == sectionID else { return original }
            guard before.indices.contains(original.lineIndex), before[original.lineIndex] == original.raw else { return nil }
            var target = matches[original.lineIndex]
            if target == nil {
                let exact = inserted.filter { after[$0] == original.raw }
                if exact.count == 1 { target = exact.first }
            }
            if target == nil {
                let left = unchanged.last { $0.0 < original.lineIndex } ?? (-1, -1)
                let right = unchanged.first { $0.0 > original.lineIndex } ?? (before.count, after.count)
                let oldCount = right.0 - left.0 - 1
                let newCount = right.1 - left.1 - 1
                if oldCount == newCount { target = left.1 + original.lineIndex - left.0 }
            }
            guard let target, after.indices.contains(target) else { return nil }
            let line = NoteLine(id: target, raw: after[target])
            if NoteLine(id: original.lineIndex, raw: original.raw).isMeeting && !line.isMeeting { return nil }
            guard (hub || line.isMeeting), !line.displayText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            var result = original
            result.lineIndex = target
            result.raw = line.raw
            return result
        }
    }
}

nonisolated struct MeetingReminderRequest: Equatable {
    let id: UUID
    let title: String
    let body: String
    let fireDate: Date

    static func pending(plans: [MeetingPlan], sections: [NoteSection], now: Date) -> [MeetingReminderRequest] {
        plans.compactMap { plan in
            guard let minutes = plan.reminderMinutes, minutes >= 0,
                  let section = sections.first(where: { $0.id == plan.sectionID }) else { return nil }
            let lines = NoteLine.parse(section.text)
            guard lines.indices.contains(plan.lineIndex), lines[plan.lineIndex].raw == plan.raw,
                  !lines[plan.lineIndex].isDone else { return nil }
            let fire = plan.date.addingTimeInterval(-Double(minutes) * 60)
            guard fire > now else { return nil }
            return MeetingReminderRequest(id: plan.id, title: "会议提醒 · \(section.title)",
                                          body: lines[plan.lineIndex].displayText, fireDate: fire)
        }.sorted { $0.fireDate < $1.fireDate }
    }
}
