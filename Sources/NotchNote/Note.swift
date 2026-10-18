import Foundation
import Observation
import AppKit

/// Plain text remains the source of truth, including blank lines and unfinished thoughts.
nonisolated struct NoteLine: Identifiable, Equatable {
    let id: Int
    let raw: String

    var isTask: Bool { raw.hasPrefix("- [ ] ") || raw.hasPrefix("- [x] ") }
    var isDone: Bool { raw.hasPrefix("- [x] ") }
    var text: String { isTask ? String(raw.dropFirst(6)) : raw }
    var isMeeting: Bool { text == "#会议" || text.hasPrefix("#会议 ") }
    var meetingPrefixLength: Int { isMeeting ? (text.hasPrefix("#会议 ") ? 4 : 3) : 0 }
    var displayText: String { isMeeting ? String(text.dropFirst(meetingPrefixLength)) : text }
    var displayPrefixLength: Int { (isTask ? 6 : 0) + meetingPrefixLength }

    static func parse(_ text: String) -> [NoteLine] {
        text.components(separatedBy: "\n").enumerated().map { NoteLine(id: $0.offset, raw: $0.element) }
    }

    static func toggling(_ index: Int, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(index) else { return text }
        let line = NoteLine(id: index, raw: lines[index])
        guard line.isTask else { return text }
        lines[index] = (line.isDone ? "- [ ] " : "- [x] ") + line.text
        return lines.joined(separator: "\n")
    }
}

nonisolated struct NoteDocument: Codable {
    var version = 1
    var text: String
}

nonisolated struct NoteSection: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var tint: Int
    var richText: Data? = nil
}

nonisolated struct NotebookDocument: Codable {
    var version = 2
    var sections: [NoteSection]
    var selectedID: UUID
    var meetingsSectionID: UUID? = nil
}

/// Converts standalone 【section titles】, preserving ungrouped text and completion marks.
nonisolated enum NotebookMigration {
    static func sections(from text: String) -> [NoteSection] {
        var result: [NoteSection] = []
        var title = "随手记"
        var buffer: [String] = []
        var hasHeading = false
        func flush() {
            let body = buffer.joined(separator: "\n")
            if hasHeading || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(NoteSection(title: title, text: body.trimmingCharacters(in: .newlines), tint: result.count % 7))
            }
        }
        for line in text.components(separatedBy: "\n") {
            let candidate = line.trimmingCharacters(in: .whitespaces)
            if candidate.hasPrefix("【"), candidate.hasSuffix("】"), candidate.count > 2 {
                flush()
                title = String(candidate.dropFirst().dropLast())
                buffer = []
                hasHeading = true
            } else {
                buffer.append(line)
            }
        }
        flush()
        return result.isEmpty ? [NoteSection(title: "随手记", text: text, tint: 0)] : result
    }
}

@Observable final class NoteStore {
    private(set) var sections: [NoteSection]
    private(set) var selectedID: UUID
    private(set) var meetingsSectionID: UUID
    private(set) var saveError: String?
    private(set) var savedAt: Date?
    private let url: URL
    private var canSave = true
    private var legacyData: Data?
    private let backupID = UUID()

    var selectedSection: NoteSection { sections.first(where: { $0.id == selectedID }) ?? sections[0] }
    var text: String {
        get { selectedSection.text }
        set { updateText(newValue, in: selectedID) }
    }
    var lines: [NoteLine] { NoteLine.parse(text) }
    var pendingCount: Int { pendingCount(in: selectedSection) }
    var totalPendingCount: Int { sections.reduce(0) { $0 + localPendingCount(in: $1) } }
    var isMeetingOverview: Bool { selectedID == meetingsSectionID }
    var hasContent: Bool { sections.contains { !$0.text.isEmpty } }
    var exportText: String { sections.map { "【\($0.title)】\n\($0.text)" }.joined(separator: "\n\n") }

    func pendingCount(in section: NoteSection) -> Int {
        localPendingCount(in: section) + (section.id == meetingsSectionID ? projectMeetings.filter { !$0.rendered.line.isDone }.count : 0)
    }

    private func localPendingCount(in section: NoteSection) -> Int {
        NoteLine.parse(section.text).filter {
            ($0.isTask || $0.isMeeting) && !$0.isDone &&
                (!$0.isMeeting || !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.count
    }

    var projectMeetings: [ProjectMeeting] {
        var result: [ProjectMeeting] = []
        for section in sections where section.id != meetingsSectionID {
            for rendered in RichText.lines(attributedText(in: section.id)) where rendered.line.isMeeting &&
                !rendered.line.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(ProjectMeeting(reference: MeetingReference(sectionID: section.id, lineIndex: rendered.id,
                                                                        expectedRaw: rendered.line.raw),
                                             projectTitle: section.title, rendered: rendered))
            }
        }
        return result.filter { !$0.rendered.line.isDone } + result.filter { $0.rendered.line.isDone }
    }

    func resolve(_ reference: MeetingReference) -> NoteLine? {
        guard let section = sections.first(where: { $0.id == reference.sectionID }), section.id != meetingsSectionID else { return nil }
        let lines = NoteLine.parse(section.text)
        if lines.indices.contains(reference.lineIndex), lines[reference.lineIndex].raw == reference.expectedRaw {
            return lines[reference.lineIndex].isMeeting ? lines[reference.lineIndex] : nil
        }
        let matches = lines.filter { $0.raw == reference.expectedRaw && $0.isMeeting }
        return matches.count == 1 ? matches[0] : nil
    }

    func toggleMeeting(_ reference: MeetingReference) {
        guard let line = resolve(reference) else { return }
        toggleTask(line.id, in: reference.sectionID, allowPlainMeeting: true)
    }

    func toggleMeetingMark(_ lineIndex: Int, in id: UUID) {
        let lines = NoteLine.parse(text(in: id))
        guard lines.indices.contains(lineIndex) else { return }
        let location = lines.prefix(lineIndex).reduce(0) { $0 + ($1.raw as NSString).length + 1 }
        let edit = MeetingMarkerEdit.toggle(line: lines[lineIndex], location: location)
        let value = NSMutableAttributedString(attributedString: attributedText(in: id))
        value.replaceCharacters(in: edit.range, with: edit.replacement)
        updateRichText(value, in: id)
    }

    func text(in id: UUID) -> String { sections.first(where: { $0.id == id })?.text ?? "" }

    func attributedText(in id: UUID) -> NSAttributedString {
        let section = sections.first(where: { $0.id == id }) ?? selectedSection
        return RichText.decode(section.richText, text: section.text)
    }

    func updateRichText(_ value: NSAttributedString, in id: UUID) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        do {
            let data = try RichText.encode(value)
            guard sections[index].text != value.string || sections[index].richText != data else { return }
            sections[index].text = value.string
            sections[index].richText = data
            save()
        } catch {
            saveError = "文字格式未能保存，请保留当前窗口并导出备份。"
        }
    }

    var exportRichText: NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for section in sections {
            if result.length > 0 { result.append(NSAttributedString(string: "\n\n")) }
            result.append(NSAttributedString(string: "【\(section.title)】\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]))
            result.append(attributedText(in: section.id))
        }
        return result
    }

    func updateText(_ value: String, in id: UUID) {
        guard let index = sections.firstIndex(where: { $0.id == id }), sections[index].text != value else { return }
        sections[index].text = value
        sections[index].richText = nil
        save()
    }

    init(url: URL = URL.applicationSupportDirectory
        .appending(path: "NotchNote", directoryHint: .isDirectory).appending(path: "note.json")) {
        self.url = url
        let initial = NoteSection(title: "随手记", text: "", tint: 0)
        let meetings = NoteSection(title: "近期会议", text: "", tint: 0)
        sections = [meetings, initial]
        selectedID = initial.id
        meetingsSectionID = meetings.id
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                struct Header: Decodable { let version: Int }
                let version = try JSONDecoder().decode(Header.self, from: data).version
                switch version {
                case 1:
                    let document = try JSONDecoder().decode(NoteDocument.self, from: data)
                    sections = NotebookMigration.sections(from: document.text)
                    selectedID = sections[0].id
                    legacyData = data
                case 2:
                    let document = try JSONDecoder().decode(NotebookDocument.self, from: data)
                    guard !document.sections.isEmpty,
                          Set(document.sections.map(\.id)).count == document.sections.count else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    sections = document.sections
                    selectedID = sections.contains { $0.id == document.selectedID } ? document.selectedID : sections[0].id
                    if let id = document.meetingsSectionID, sections.contains(where: { $0.id == id }) {
                        meetingsSectionID = id
                    }
                default:
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
        } catch {
            // Preserve an unreadable document instead of overwriting it with an empty note.
            canSave = false
            saveError = "未能读取原便笺，已保护原文件。请先导出当前内容，再检查 note.json。"
        }
        if canSave, !sections.contains(where: { $0.id == meetingsSectionID }) {
            if let existing = sections.first(where: { $0.title == "近期会议" }) {
                meetingsSectionID = existing.id
            } else {
                let meetings = NoteSection(title: "近期会议", text: "", tint: 0)
                sections.insert(meetings, at: 0)
                meetingsSectionID = meetings.id
            }
        }
        if legacyData != nil { save() }
    }

    func select(_ id: UUID) {
        guard sections.contains(where: { $0.id == id }), selectedID != id else { return }
        selectedID = id
        save()
    }

    @discardableResult func addSection(title: String) -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let section = NoteSection(title: title, text: "", tint: sections.count % 7)
        sections.append(section)
        selectedID = section.id
        save()
        return section.id
    }

    func toggle(_ line: Int) {
        toggleTask(line, in: selectedID, allowPlainMeeting: true)
    }

    private func toggleTask(_ line: Int, in id: UUID, allowPlainMeeting: Bool = false) {
        let sectionText = text(in: id)
        let parsed = NoteLine.parse(sectionText)
        guard parsed.indices.contains(line), parsed[line].isTask || (allowPlainMeeting && parsed[line].isMeeting) else { return }
        guard sections.first(where: { $0.id == id })?.richText != nil || !parsed[line].isTask else {
            updateText(NoteLine.toggling(line, in: sectionText), in: id)
            return
        }
        let value = NSMutableAttributedString(attributedString: attributedText(in: id))
        let start = parsed.prefix(line).reduce(0) { $0 + ($1.raw as NSString).length + 1 }
        if parsed[line].isTask {
            value.replaceCharacters(in: NSRange(location: start + 3, length: 1), with: parsed[line].isDone ? " " : "x")
        } else {
            value.replaceCharacters(in: NSRange(location: start, length: 0), with: "- [x] ")
        }
        updateRichText(value, in: id)
    }

    func save() {
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let legacyData {
                // Keep a byte-for-byte copy before the first schema upgrade; never overwrite another backup.
                let backup = url.deletingPathExtension().appendingPathExtension("v1-\(backupID.uuidString).json")
                try legacyData.write(to: backup, options: .atomic)
            }
            let data = try JSONEncoder().encode(NotebookDocument(sections: sections, selectedID: selectedID,
                                                               meetingsSectionID: meetingsSectionID))
            try data.write(to: url, options: .atomic)
            legacyData = nil
            savedAt = .now
            saveError = nil
        } catch {
            saveError = "保存失败，请导出内容备份，或检查磁盘空间与文件权限。"
        }
    }
}
