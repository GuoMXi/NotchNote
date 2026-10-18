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
