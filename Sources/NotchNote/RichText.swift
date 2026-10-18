import AppKit
import SwiftUI

enum RichText {
    static var defaults: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1)]
    }

    static func decode(_ data: Data?, text: String) -> NSAttributedString {
        if let data, let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
           value.string == text { return value }
        return NSAttributedString(string: text, attributes: defaults)
    }

    static func encode(_ value: NSAttributedString) throws -> Data {
        try value.data(from: NSRange(location: 0, length: value.length),
                       documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    struct Line: Identifiable {
        let line: NoteLine
        let text: AttributedString
        var id: Int { line.id }
    }

    static func lines(_ value: NSAttributedString) -> [Line] {
        var offset = 0
        return NoteLine.parse(value.string).map { line in
            let length = (line.raw as NSString).length
            let prefix = line.displayPrefixLength
            let range = NSRange(location: offset + prefix, length: length - prefix)
            offset += length + 1
            let content = value.attributedSubstring(from: range)
            return Line(line: line, text: (try? AttributedString(content, including: \.appKit)) ?? AttributedString(line.displayText))
        }
    }

    static func color(_ hex: String) -> NSColor {
        let rgb = UInt32(hex, radix: 16) ?? 0x292929
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

enum EditorCommand: Equatable {
    case bold, italic, underline, meeting
    case font(String), size(Double), color(String)
}

struct EditorStyle: Equatable {
    var fontFamily = ""
    var size: Double = 15
    var bold = false
    var italic = false
    var underline = false
    var meeting = false
    var lineIndex = 0
}
