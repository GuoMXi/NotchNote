import Foundation
import Observation

/// Plain text remains the source of truth, including blank lines and unfinished thoughts.
nonisolated struct NoteLine: Identifiable, Equatable {
    let id: Int
    let raw: String

    var isTask: Bool { raw.hasPrefix("- [ ] ") || raw.hasPrefix("- [x] ") }
    var isDone: Bool { raw.hasPrefix("- [x] ") }
    var text: String { isTask ? String(raw.dropFirst(6)) : raw }

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

@Observable final class NoteStore {
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            save()
        }
    }
    private(set) var saveError: String?
    private(set) var savedAt: Date?
    private let url: URL
    private var canSave = true

    var lines: [NoteLine] { NoteLine.parse(text) }
    var pendingCount: Int { lines.filter { $0.isTask && !$0.isDone }.count }

    init(url: URL = URL.applicationSupportDirectory
        .appending(path: "NotchNote", directoryHint: .isDirectory).appending(path: "note.json")) {
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let document = try JSONDecoder().decode(NoteDocument.self, from: Data(contentsOf: url))
                guard document.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                text = document.text
            }
        } catch {
            // Preserve an unreadable document instead of overwriting it with an empty note.
            canSave = false
            saveError = "未能读取原便笺，已保护原文件。请先导出当前内容，再检查 note.json。"
        }
    }

    func toggle(_ line: Int) { text = NoteLine.toggling(line, in: text) }

    func save() {
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(NoteDocument(text: text))
            try data.write(to: url, options: .atomic)
            savedAt = .now
            saveError = nil
        } catch {
            saveError = "保存失败，请导出内容备份，或检查磁盘空间与文件权限。"
        }
    }
}
