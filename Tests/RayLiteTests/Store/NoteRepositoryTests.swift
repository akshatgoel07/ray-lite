import CoreData
import Foundation
import Testing
@testable import RayLite

@MainActor
struct NoteStoreTests {
    @Test func fileRoundTripPreservesNotesThroughRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("notes.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = NoteRecord(id: UUID(), text: "First paragraph.\n\nSecond paragraph. 📝",
                               frame: CGRect(x: -145.5, y: 92.25, width: 240.5, height: 180.75), order: 7)
        let second = NoteRecord(id: UUID(), text: "Keep this note.",
                                frame: CGRect(x: 800, y: -35, width: 320, height: 90), order: -2)
        var edited = first
        edited.text = "New text.\nA second line."
        edited.frame = CGRect(x: 19.25, y: -400.5, width: 520.75, height: 250.5)
        edited.order = -10

        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.load().get().isEmpty)
            try store.insert(first).get()
            try store.insert(second).get()
            #expect(try store.load().get() == [second, first])
        }

        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.load().get() == [second, first])
            try store.update(edited).get()
            #expect(try store.load().get() == [edited, second])
        }

        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.load().get() == [edited, second])
            try store.delete(id: edited.id).get()
            #expect(try store.load().get() == [second])
        }

        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.load().get() == [second])
            try store.insert(edited).get()
            guard case .failure(.duplicateID(edited.id)) = store.insert(edited) else {
                Issue.record("The store must reject a duplicate note ID.")
                return
            }
            #expect(try store.load().get() == [edited, second])
        }

        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            let restored = try store.load().get()
            #expect(restored == [edited, second])
        }
    }

    @Test func legacyMigrationPreservesNotesAndCreatesFirstSpaceThroughRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("legacy.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = [
            NoteRecord(id: UUID(), text: "First paragraph.\n\nA second paragraph. 📝",
                frame: CGRect(x: -42.25, y: 83.5, width: 241.75, height: 190.25), order: -3),
            NoteRecord(id: UUID(), text: "", frame: CGRect(x: 900, y: -85, width: 310, height: 150), order: 8)
        ]
        try autoreleasepool {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: RecordSchema.makeModel(includeSpaces: false, includeImages: false))
            let persistentStore = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            for record in records {
                let item = ArchivedCard(entity: coordinator.managedObjectModel.entitiesByName["CardArchive"]!, insertInto: context)
                item.identifier = record.id
                item.boardReference = UUID()
                item.kind = "note"
                item.text = record.text
                item.pointX = record.frame.minX
                item.pointY = record.frame.minY
                item.width = record.frame.width
                item.height = record.frame.height
                item.zIndex = Int64(record.order)
                item.rotation = 0.125
                item.colorHex = "#abcdef"
                item.excludesFolderList = true
                item.videoURLString = "https://example.com/video"
            }
            let canvas = ArchivedBoard(entity: coordinator.managedObjectModel.entitiesByName["BoardArchive"]!, insertInto: context)
            canvas.identifier = UUID()
            canvas.title = "Legacy canvas"
            canvas.index = 4
            canvas.visitTimestamp = 1234
            try context.save()
            try coordinator.remove(persistentStore)
        }
        let first = SpaceRecord(id: SpaceRecord.firstID, name: "Space01", order: 0)
        let second = SpaceRecord(name: "Space02", order: 1)
        let newNote = NoteRecord(id: UUID(), text: "Second space",
            frame: CGRect(x: 30, y: 50, width: 240, height: 150), order: 0, spaceID: second.id)
        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.loadSpaces().get() == [first])
            #expect(try store.load(spaceID: first.id).get() == records)
            try store.insertSpace(second).get()
            try store.insert(newNote).get()
            #expect(try !store.deleteEmptySpace(id: second.id).get())
        }
        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.loadSpaces().get() == [first, second])
            #expect(try store.load(spaceID: first.id).get() == records)
            #expect(try store.load(spaceID: second.id).get() == [newNote])
            try store.delete(id: newNote.id).get()
            #expect(try store.deleteEmptySpace(id: second.id).get())
            #expect(try !store.deleteEmptySpace(id: first.id).get())
        }
        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.loadSpaces().get() == [first])
            #expect(try store.load().get() == records)
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: RecordSchema.makeModel())
            let persistentStore = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            for item in try context.fetch(NSFetchRequest<ArchivedCard>(entityName: "CardArchive")) {
                #expect(item.space?.id == first.id)
                #expect(item.rotation == 0.125)
                #expect(item.colorHex == "#abcdef")
                #expect(item.excludesFolderList)
                #expect(item.videoURLString == "https://example.com/video")
            }
            let canvases = try context.fetch(NSFetchRequest<ArchivedBoard>(entityName: "BoardArchive"))
            #expect(canvases.count == 1)
            #expect(canvases.first?.title == "Legacy canvas")
            #expect(canvases.first?.index == 4)
            #expect(canvases.first?.visitTimestamp == 1234)
            try coordinator.remove(persistentStore)
        }
    }

    @Test func equalOrderUsesStableIdentityOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("notes.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let first = NoteRecord(id: firstID, text: "First", frame: .zero, order: 3)
        let second = NoteRecord(id: secondID, text: "Second", frame: .zero, order: 3)

        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            try store.insert(second).get()
            try store.insert(first).get()
            #expect(try store.load().get() == [first, second])
        }
        try autoreleasepool {
            let restored = try NoteStore(storeURL: url).load().get()
            #expect(restored == [first, second])
        }
    }

    @Test func memoryStoreRejectsChangesToMissingNotes() throws {
        let store = NoteStore(inMemory: true)
        let note = NoteRecord(id: UUID(), text: "", frame: .zero, order: 0)
        guard case .failure(.missingID(note.id)) = store.update(note),
              case .failure(.missingID(note.id)) = store.delete(id: note.id) else {
            Issue.record("The store must reject a missing note ID.")
            return
        }
        #expect(try store.load().get().isEmpty)
        try store.insert(note).get()
        #expect(try store.load().get() == [note])
        #expect(try NoteStore(inMemory: true).load().get().isEmpty)
    }

    @Test func corruptFileReturnsFailureAndPreservesFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("notes.sqlite")
        let bytes = Data("This file is not a SQLite database.".utf8)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = NoteStore(storeURL: url)
        guard case .failure(let error) = store.load() else {
            Issue.record("A corrupt store must return a load failure.")
            return
        }
        #expect(!error.message.isEmpty)
        #expect(try Data(contentsOf: url) == bytes)
        let note = NoteRecord(id: UUID(), text: "", frame: .zero, order: 0)
        guard case .failure = store.insert(note),
              case .failure = store.update(note),
              case .failure = store.delete(id: note.id) else {
            Issue.record("A corrupt store must return a write failure.")
            return
        }
    }

    @Test func inaccessibleStorePathReturnsFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let parent = directory.appendingPathComponent("file")
        try Data("The parent is a file.".utf8).write(to: parent)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(storeURL: parent.appendingPathComponent("notes.sqlite"))
        guard case .failure(let error) = store.load() else {
            Issue.record("An inaccessible store must return a load failure.")
            return
        }
        #expect(!error.message.isEmpty)
    }
}
