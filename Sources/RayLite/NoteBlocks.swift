import Foundation

public enum NoteBlockStyle: String, Codable, CaseIterable, Sendable {
    case display, headline, subheader, body, list, task

    public var prefixLength: Int { self == .list || self == .task ? 2 : 0 }
    public var fontSize: CGFloat {
        switch self {
        case .display: 56
        case .headline: 32
        case .subheader: 20
        case .body, .list, .task: 16
        }
    }
    public var lineHeight: CGFloat {
        switch self {
        case .display: 69.015625
        case .headline: 39.5
        case .subheader, .body, .list, .task: 28.265625
        }
    }
    public var title: String { rawValue.capitalized }
    public static func trigger(_ text: String) -> Self? {
        switch text {
        case "# ": .display
        case "## ": .headline
        case "### ": .subheader
        case "- ", "* ": .list
        case "[] ", "[ ] ": .task
        default: nil
        }
    }
}

public enum NoteMark: String, Codable, CaseIterable, Sendable {
    case bold, italic, underline, strikethrough, highlight
}

public struct NoteRun: Codable, Equatable, Sendable {
    public var text: String
    public var marks: Set<NoteMark>
    public var link: String?

    public init(_ text: String, marks: Set<NoteMark> = [], link: String? = nil) {
        self.text = text
        self.marks = marks
        self.link = link
    }
}

public struct NoteBlock: Codable, Equatable, Sendable {
    public var style: NoteBlockStyle
    public var runs: [NoteRun]
    public var checked: Bool
    public var text: String { runs.map(\.text).joined() }
    public var editorText: String { (style.prefixLength == 0 ? "" : "\u{fffc}\u{200b}") + text }

    public init(style: NoteBlockStyle = .body, text: String = "", checked: Bool = false) {
        self.style = style
        self.runs = text.isEmpty ? [] : [NoteRun(text)]
        self.checked = checked
    }

    func slice(_ range: NSRange) -> [NoteRun] {
        var offset = 0
        return runs.compactMap { run in
            defer { offset += (run.text as NSString).length }
            let intersection = NSIntersectionRange(range, NSRange(location: offset, length: (run.text as NSString).length))
            guard intersection.length > 0 else { return nil }
            return NoteRun((run.text as NSString).substring(with: NSRange(location: intersection.location - offset, length: intersection.length)),
                           marks: run.marks, link: run.link)
        }
    }

    mutating func normalize() {
        var result: [NoteRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = result.last, last.marks == run.marks, last.link == run.link {
                result[result.count - 1].text += run.text
            } else { result.append(run) }
        }
        runs = result
    }
}

public struct NoteContent: Codable, Equatable, Sendable {
    public private(set) var blocks: [NoteBlock]
    public var plainText: String { blocks.map(\.text).joined(separator: "\n") }
    public var editorText: String { blocks.map(\.editorText).joined(separator: "\n") }

    public init(blocks: [NoteBlock]) {
        self.blocks = blocks.isEmpty ? [NoteBlock(style: .display)] : blocks
        for index in self.blocks.indices { self.blocks[index].normalize() }
    }

    public init(plainText: String) {
        blocks = plainText.components(separatedBy: "\n").enumerated().map {
            NoteBlock(style: $0.offset == 0 ? .display : .body, text: $0.element)
        }
    }

    public func range(of index: Int) -> NSRange {
        let offset = blocks.prefix(index).reduce(0) { $0 + ($1.editorText as NSString).length + 1 }
        return NSRange(location: offset, length: (blocks[index].editorText as NSString).length)
    }

    public func position(at offset: Int) -> (block: Int, character: Int) {
        var location = 0
        for index in blocks.indices {
            let length = (blocks[index].editorText as NSString).length
            if offset <= location + length || index == blocks.count - 1 {
                return (index, max(0, min((blocks[index].text as NSString).length,
                                         offset - location - blocks[index].style.prefixLength)))
            }
            location += length + 1
        }
        return (0, 0)
    }

    @discardableResult
    public mutating func replace(_ range: NSRange, with text: String, marks: Set<NoteMark> = [],
                                 link: String? = nil, continuation: NoteBlockStyle? = nil) -> Int {
        let start = position(at: range.location)
        let end = position(at: NSMaxRange(range))
        let first = blocks[start.block]
        let last = blocks[end.block]
        let prefix = first.slice(NSRange(location: 0, length: start.character))
        let suffix = last.slice(NSRange(location: end.character, length: (last.text as NSString).length - end.character))
        let lines = text.components(separatedBy: "\n")
        var replacements = lines.enumerated().map { index, line in
            var block = NoteBlock(style: index == 0 ? first.style : continuation ?? .body,
                                  checked: index == 0 && first.checked)
            block.runs = (index == 0 ? prefix : []) + (line.isEmpty ? [] : [NoteRun(line, marks: marks, link: link)])
            return block
        }
        replacements[replacements.count - 1].runs += suffix
        for index in replacements.indices { replacements[index].normalize() }
        blocks.replaceSubrange(start.block...end.block, with: replacements)
        let finalIndex = start.block + replacements.count - 1
        let insertedLength = (lines.last! as NSString).length
        return self.range(of: finalIndex).location + blocks[finalIndex].style.prefixLength
            + (lines.count == 1 ? start.character : 0) + insertedLength
    }

    public mutating func setStyle(_ style: NoteBlockStyle, at index: Int) {
        blocks[index].style = style
        if style != .task { blocks[index].checked = false }
    }

    public mutating func toggleTask(at index: Int) {
        guard blocks[index].style == .task else { return }
        blocks[index].checked.toggle()
    }

    public mutating func consumeTrigger(at index: Int) -> Bool {
        guard let style = NoteBlockStyle.trigger(blocks[index].text) else { return false }
        blocks[index] = NoteBlock(style: style)
        return true
    }

    public func selectedRuns(in selection: NSRange) -> [NoteRun] {
        blocks.indices.flatMap { index -> [NoteRun] in
            let block = blocks[index]
            let textRange = NSRange(location: range(of: index).location + block.style.prefixLength, length: (block.text as NSString).length)
            let intersection = NSIntersectionRange(selection, textRange)
            guard intersection.length > 0 else { return [] }
            return block.slice(NSRange(location: intersection.location - textRange.location, length: intersection.length))
        }
    }

    public mutating func format(_ selection: NSRange, mark: NoteMark?) {
        let selected = selectedRuns(in: selection)
        let remove = mark.map { mark in !selected.isEmpty && selected.allSatisfy { $0.marks.contains(mark) } } ?? true
        for index in blocks.indices {
            let block = blocks[index]
            let textRange = NSRange(location: range(of: index).location + block.style.prefixLength, length: (block.text as NSString).length)
            let intersection = NSIntersectionRange(selection, textRange)
            guard intersection.length > 0 else { continue }
            let local = NSRange(location: intersection.location - textRange.location, length: intersection.length)
            var middle = block.slice(local)
            for run in middle.indices {
                if let mark {
                    if remove { middle[run].marks.remove(mark) } else { middle[run].marks.insert(mark) }
                } else {
                    middle[run].marks = []
                    middle[run].link = nil
                }
            }
            blocks[index].runs = block.slice(NSRange(location: 0, length: local.location)) + middle
                + block.slice(NSRange(location: NSMaxRange(local), length: (block.text as NSString).length - NSMaxRange(local)))
            blocks[index].normalize()
        }
    }

    public func markdown() -> String {
        blocks.map { block in
            let prefix: String
            switch block.style {
            case .display: prefix = "# "
            case .headline: prefix = "## "
            case .subheader: prefix = "### "
            case .body: prefix = ""
            case .list: prefix = "- "
            case .task: prefix = block.checked ? "- [x] " : "- [ ] "
            }
            let text = block.runs.map { run in
                var text = run.text
                if run.marks.contains(.bold) { text = "**" + text + "**" }
                if run.marks.contains(.italic) { text = "*" + text + "*" }
                if run.marks.contains(.underline) { text = "<u>" + text + "</u>" }
                if run.marks.contains(.strikethrough) { text = "~~" + text + "~~" }
                if run.marks.contains(.highlight) { text = "==" + text + "==" }
                if let link = run.link { text = "[" + text + "](" + link + ")" }
                return text
            }.joined()
            return prefix + text
        }.joined(separator: "\n")
    }

    @discardableResult
    public func exportMarkdown(downloads: URL = .downloadsDirectory, date: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        let folder = downloads.appendingPathComponent("Ray Lite Export " + formatter.string(from: date), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = String(plainText.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(20))
        let base = name.isEmpty ? "Untitled" : name
        var url = folder.appendingPathComponent(base + ".md")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(base + " \(number).md")
            number += 1
        }
        try markdown().write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
