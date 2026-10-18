import AppKit
import CoreData
import Testing
@testable import RayLite

@MainActor
struct NoteBlockTests {
    @Test func contentRoundTripPreservesBlocksMarksAndPlainText() throws {
        var title = NoteBlock(style: .display, text: "Notes 📝")
        title.runs = [NoteRun("Notes ", marks: [.bold]), NoteRun("📝", marks: [.italic, .highlight])]
        var task = NoteBlock(style: .task, text: "Read", checked: true)
        task.runs = [NoteRun("Read", marks: [.underline, .strikethrough], link: "https://example.com")]
        let content = NoteContent(blocks: [title, NoteBlock(style: .headline, text: "Heading"),
                                            NoteBlock(style: .subheader, text: "Section"),
                                            NoteBlock(text: ""), NoteBlock(style: .list, text: "Item"), task])
        #expect(try JSONDecoder().decode(NoteContent.self, from: JSONEncoder().encode(content)) == content)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let note = NoteRecord(id: UUID(), text: "", frame: CGRect(x: 0, y: 0, width: 140, height: 200), order: 0, content: content)
        try autoreleasepool { try NoteStore(storeURL: url).insert(note).get() }
        let restored = try NoteStore(storeURL: url).load().get()
        #expect(restored == [note])
        #expect(restored.first?.text == "Notes 📝\nHeading\nSection\n\nItem\nRead")
    }

    @Test func plainStoreMigrationPreservesAllNewlinesAndPersistsBlocks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.sqlite")
        let id = UUID()
        let text = "Title 📝\nBody\n\nLast\n"
        try autoreleasepool {
            let model = CoreDataStack.makeModel(includeNoteBlocks: false)
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            let item = ItemMO(entity: model.entitiesByName["Item"]!, insertInto: context)
            item.identifier = id
            item.canvasIdentifier = SpaceRecord.firstID
            item.kind = "note"
            item.text = text
            item.pointX = 0
            item.pointY = 0
            item.rotation = 0
            item.zIndex = 0
            item.isHiddenFromFolders = false
            item.width = 140
            item.height = 200
            try context.save()
            try coordinator.remove(store)
        }
        for _ in 0..<2 {
            let note = try #require(try NoteStore(storeURL: url).load().get().first)
            #expect(note.id == id)
            #expect(note.text == text)
            #expect(note.content.blocks.map(\.style) == [.display, .body, .body, .body, .body])
        }
    }

    @Test(arguments: ["# ", "## ", "### ", "- ", "* ", "[] ", "[ ] "])
    func supportedTriggersConsumeOnlyExactPrefix(prefix: String) {
        var content = NoteContent(blocks: [NoteBlock(text: prefix)])
        let consumed = content.consumeTrigger(at: 0)
        #expect(consumed)
        #expect(content.blocks[0].text.isEmpty)
        #expect(content.blocks[0].style == NoteBlockStyle.trigger(prefix))
    }

    @Test(arguments: ["1. ", "> ", "```", "---", "#### ", "body # "])
    func unsupportedTriggersStayLiteral(prefix: String) {
        var content = NoteContent(blocks: [NoteBlock(text: prefix)])
        let consumed = content.consumeTrigger(at: 0)
        #expect(!consumed)
        #expect(content.plainText == prefix)
        #expect(content.blocks[0].style == .body)
    }

    @Test func selectionAcrossBlocksKeepsMarksAndUnicode() {
        var content = NoteContent(plainText: "📝 Title\nBody words")
        content.format(NSRange(location: 3, length: 11), mark: .bold)
        #expect(content.blocks[0].runs == [NoteRun("📝 "), NoteRun("Title", marks: [.bold])])
        #expect(content.blocks[1].runs == [NoteRun("Body ", marks: [.bold]), NoteRun("words")])
        let caret = content.replace(NSRange(location: 9, length: 4), with: "New")
        #expect(content.plainText == "📝 Title\nNew words")
        #expect(caret == 12)
    }

    @Test func exportKeepsPrefixesAndUsesReferenceDestination() throws {
        let content = NoteContent(blocks: [NoteBlock(style: .display, text: "Preview reference"),
            NoteBlock(text: "Body line sample"), NoteBlock(style: .headline, text: "Headline sample"),
            NoteBlock(style: .subheader, text: "Subheader sample"), NoteBlock(style: .list, text: "Bullet sample"),
            NoteBlock(style: .task, text: "Task sample"), NoteBlock(style: .task, text: "Done", checked: true)])
        #expect(content.markdown() == "# Preview reference\nBody line sample\n## Headline sample\n### Subheader sample\n- Bullet sample\n- [ ] Task sample\n- [x] Done")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 18))!
        let url = try content.exportMarkdown(downloads: directory, date: date)
        #expect(url.deletingLastPathComponent().lastPathComponent == "Ray Lite Export Oct 18")
        #expect(url.lastPathComponent == "PreviewreferenceBody.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == content.markdown())
        #expect(try content.exportMarkdown(downloads: directory, date: date) != url)
        if let run = ProcessInfo.processInfo.environment["RUN"] {
            let evidence = URL(fileURLWithPath: run).appendingPathComponent("artifacts/export", isDirectory: true)
            let exported = try content.exportMarkdown(downloads: evidence, date: date)
            let metadata = ["path": exported.path, "bytes": try Data(contentsOf: exported).count] as [String: Any]
            try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
                .write(to: evidence.appendingPathComponent("result.json"))
        }
    }

    @Test func exportPreservesMarkdownBytes() throws {
        let source = "# Project notes\nBody line sample\n## Plan\n### Details\n- First idea\n- [ ] Share the draft\nRésumé and a link: https://example.com/notes"
        var blocks: [NoteBlock] = []
        for line in source.components(separatedBy: "\n") {
            var block = NoteBlock(text: line)
            for (prefix, style) in [("- [ ] ", NoteBlockStyle.task), ("### ", .subheader), ("## ", .headline), ("# ", .display), ("- ", .list)] {
                if line.hasPrefix(prefix) { block = NoteBlock(style: style, text: String(line.dropFirst(prefix.count))); break }
            }
            blocks.append(block)
        }
        let content = NoteContent(blocks: blocks)
        #expect(content.markdown() == source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = ProcessInfo.processInfo.environment["RUN"].map {
            URL(fileURLWithPath: $0).appendingPathComponent("artifacts/export/markdown-" + UUID().uuidString)
        } ?? directory
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 18))!
        let url = try content.exportMarkdown(downloads: base, date: date)
        #expect(url.lastPathComponent == "ProjectnotesBodyline.md")
        #expect(try Data(contentsOf: url).count == 134)
        #expect(try Data(contentsOf: url) == Data(source.utf8))
        if let run = ProcessInfo.processInfo.environment["RUN"] {
            let metadata = ["path": url.path, "bytes": try Data(contentsOf: url).count] as [String: Any]
            try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
                .write(to: URL(fileURLWithPath: run).appendingPathComponent("artifacts/export/markdown.json"))
        }
    }

    private func editor() -> NoteTextView {
        let view = NoteTextView(frame: CGRect(x: 0, y: 0, width: 616, height: 950))
        view.textContainer?.lineFragmentPadding = 8
        view.allowsUndo = false
        view.load(NoteContent(plainText: "Title\n"))
        view.setSelectedRange(NSRange(location: 6, length: 0))
        return view
    }

    private func enter(_ text: String, in view: NoteTextView) {
        for character in text { view.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0)) }
    }

    @Test func undoSeparatesReturnFormatAndPasteFromContinuousEntry() {
        let view = editor()
        enter("alpha", in: view)
        enter(" beta", in: view)
        view.undo(nil)
        #expect(view.content.plainText == "Title\n")
        view.redo(nil)
        #expect(view.content.plainText == "Title\nalpha beta")
        view.insertNewline(nil)
        enter("Next block", in: view)
        view.undo(nil)
        #expect(view.content.plainText == "Title\nalpha beta\n")
        view.undo(nil)
        #expect(view.content.plainText == "Title\nalpha beta")
        view.setSelectedRange(NSRange(location: 6, length: 10))
        view.applyFormat(.bold)
        view.undo(nil)
        #expect(view.content.blocks[1].runs == [NoteRun("alpha beta")])
        #expect(view.selectedRange() == NSRange(location: 16, length: 0))
        view.setSelectedRange(NSRange(location: 16, length: 0))
        view.pastePlainText("Pasted\nText")
        view.undo(nil)
        #expect(view.content.plainText == "Title\nalpha beta")
        view.redo(nil)
        #expect(view.content.plainText == "Title\nalpha betaPasted\nText")
    }

    @Test func listAndTaskRulesKeepLiteralTabsAndReturnBoundaries() {
        let view = editor()
        enter("- ", in: view)
        #expect(view.content.blocks[1].style == .list)
        enter("Item", in: view)
        view.insertNewline(nil)
        #expect(view.content.blocks.map(\.style) == [.display, .list, .list])
        view.insertTab(nil)
        enter("Child", in: view)
        let shiftTab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift,
            timestamp: 0, windowNumber: 0, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: 48)!
        view.keyDown(with: shiftTab)
        #expect(view.content.blocks[2].style == .body)
        #expect(view.content.blocks[2].text == "\tChild")
        view.load(NoteContent(plainText: "Title\n"))
        view.setSelectedRange(NSRange(location: 6, length: 0))
        enter("[] ", in: view)
        view.insertNewline(nil)
        #expect(view.content.blocks.map(\.style) == [.display, .body, .body])
        view.undo(nil)
        view.deleteBackward(nil)
        #expect(view.content.blocks[1].style == .body)
        enter("Body", in: view)
        view.setSelectedRange(NSRange(location: 6, length: 0))
        view.deleteBackward(nil)
        #expect(view.content.blocks.count == 1)
        #expect(view.content.blocks[0].style == .display)
        #expect(view.content.plainText == "TitleBody")
    }

    @Test func pastedURLExposesNativeLinkAndCheckedTaskKeepsText() throws {
        let view = editor()
        view.pastePlainText("https://example.com/notes")
        #expect(view.content.blocks[1].runs.first?.link == "https://example.com/notes")
        #expect(view.textStorage?.attribute(.link, at: 6, effectiveRange: nil) as? URL == URL(string: "https://example.com/notes"))
        view.insertNewline(nil)
        enter("[] Task", in: view)
        var content = view.content
        content.toggleTask(at: 2)
        #expect(content.blocks[2].checked)
        #expect(content.blocks[2].runs == [NoteRun("Task")])
    }

    @Test func formatRemovalKeepsNextEntryPlain() {
        let view = editor()
        enter("Words sample", in: view)
        view.setSelectedRange(NSRange(location: 6, length: 5))
        view.applyFormat(.highlight, collapse: true)
        view.setSelectedRange(NSRange(location: 7, length: 4))
        view.selectionChanged()
        view.applyFormat(nil, collapse: true)
        enter(" more", in: view)
        #expect(view.content.blocks[1].runs == [NoteRun("W", marks: [.highlight]), NoteRun("ords more sample")])
    }

    @Test func headingCaretMatchesTheTextEnd() {
        let view = editor()
        for style in [NoteBlockStyle.display, .headline, .subheader, .body] {
            view.load(NoteContent(blocks: [NoteBlock(style: style, text: "Heading sample")]))
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            let font = NotePageTypography.font(size: style.fontSize, weight: style.fontSize > 16 ? .medium : .regular)
            let width = NSAttributedString(string: "Heading sample", attributes: [.font: font, .kern: style == .display ? -0.5 : -0.25]).size().width
            #expect(abs(view.insertionRect().minX - 8 - width) < 2)
        }
    }

    @Test func previewKeepsNoteRadiusAndClipsLongContent() {
        let frame = CGRect(x: 20, y: 40, width: 140, height: 200)
        #expect(NoteTextLayer.fittedFrame(frame, text: String(repeating: "Line\n", count: 65)) == frame)
        let view = CanvasItemView(note: NoteRecord(id: UUID(), text: "Title", frame: frame, order: 0))
        view.layout()
        #expect(view.container.cornerRadius == 12)
    }
}
