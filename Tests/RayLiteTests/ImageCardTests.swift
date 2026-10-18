import AppKit
import CoreData
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import RayLite

@MainActor
struct ImageCardTests {
    private func bytes(_ type: UTType = .png, orientation: Int = 1, frames: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, frames, nil))
        for frame in 0..<frames {
            if frame > 0 {
                context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
            CGImageDestinationAddImage(destination, try #require(context.makeImage()),
                [kCGImagePropertyOrientation: orientation] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func imageRoundTripPreservesOriginalBytesAndGeometryThroughRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("images.sqlite")
        let image = try #require(ImageAttachment(data: bytes(), name: "Source.png"))
        let note = NoteRecord(id: UUID(), text: "Keep this note", frame: CGRect(x: 10, y: 15, width: 141, height: 200), order: 0)
        var record = NoteRecord(id: UUID(), text: "", frame: CGRect(origin: CGPoint(x: -40, y: 90), size: image.cardSize), order: 1, image: image)
        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            try store.insert(note).get()
            try store.insert(record).get()
            #expect(try store.load().get() == [note, record])
        }
        record.frame = ResizeHandle.topLeft.resizeImage(record.frame, by: CGSize(width: -80, height: 30))
        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.load().get().last?.image?.data == image.data)
            try store.update(record).get()
        }
        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.load().get() == [note, record])
            #expect(try store.load().get().last?.kind == .image)
            try store.delete(id: record.id).get()
        }
        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.load().get() == [note])
            try store.insert(record).get()
        }
        #expect(try NoteStore(storeURL: url).load().get() == [note, record])
        let attribute = try #require(CoreDataStack.makeModel().entitiesByName["Item"]?.attributesByName["imageData"])
        #expect(attribute.allowsExternalBinaryDataStorage)
    }

    @Test func migrationPreservesExistingSpacesAndNotesThroughRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old.sqlite")
        let space = SpaceRecord(name: "Space02", order: 1)
        let note = NoteRecord(id: UUID(), text: "Old note", frame: CGRect(x: 10, y: 20, width: 141, height: 200), order: 5, spaceID: space.id)
        try autoreleasepool {
            let model = CoreDataStack.makeModel(includeImages: false)
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let persistent = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            for record in [SpaceRecord(id: SpaceRecord.firstID, name: "Space01", order: 0), space] {
                let object = SpaceMO(entity: model.entitiesByName["Space"]!, insertInto: context)
                object.id = record.id
                object.name = record.name
                object.order = Int64(record.order)
                if record.id == space.id {
                    let item = ItemMO(entity: model.entitiesByName["Item"]!, insertInto: context)
                    item.identifier = note.id
                    item.canvasIdentifier = record.id
                    item.kind = "note"
                    item.text = note.text
                    item.pointX = note.frame.minX
                    item.pointY = note.frame.minY
                    item.width = note.frame.width
                    item.height = note.frame.height
                    item.zIndex = Int64(note.order)
                    item.rotation = 0
                    item.isHiddenFromFolders = false
                    item.space = object
                }
            }
            try context.save()
            try coordinator.remove(persistent)
        }
        let image = try #require(ImageAttachment(data: bytes(), name: "New.png"))
        let record = NoteRecord(id: UUID(), text: "", frame: CGRect(origin: .zero, size: image.cardSize), order: 6, spaceID: space.id, image: image)
        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.loadSpaces().get().last == space)
            #expect(try store.load(spaceID: space.id).get() == [note])
            try store.insert(record).get()
        }
        #expect(try NoteStore(storeURL: url).load(spaceID: space.id).get() == [note, record])
    }

    @Test func importAndDeleteEachUseOneUndoStepAcrossSpaces() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [directory.appendingPathComponent("First.png"), directory.appendingPathComponent("Second.png")]
        let data = try bytes()
        for url in urls { try data.write(to: url) }
        let store = NoteStore(inMemory: true)
        let canvas = CanvasView(store: store)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.contentView = nil }
        canvas.loadNotes()
        canvas.layoutSubtreeIfNeeded()
        canvas.setViewport(Viewport(scale: 0.5, translation: CGPoint(x: 80, y: -20)))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects(urls as [NSURL])
        let point = CGPoint(x: 220, y: 350)
        let expected = canvas.canvasPoint(from: point)
        #expect(canvas.importImages(from: pasteboard, at: point))
        let records = canvas.notes
        #expect(records.count == 2)
        #expect(records[0].frame.minX == expected.x)
        #expect(records[0].frame.maxY == expected.y)
        #expect(records[0].frame.width == 320)
        #expect(records.allSatisfy { $0.image?.data == data })
        let manager = try #require(window.undoManager)
        manager.undo()
        #expect(canvas.notes.isEmpty)
        #expect(!manager.canUndo)
        manager.redo()
        #expect(canvas.notes == records)
        canvas.delete(nil)
        #expect(canvas.notes.isEmpty)
        manager.undo()
        #expect(canvas.notes == records)
        #expect(canvas.newSpace() != nil)
        manager.removeAllActions()
        #expect(canvas.switchSpace(SpaceRecord.firstID))
        canvas.select(Set(records.map(\.id)))
        canvas.delete(nil)
        let space = try #require(canvas.spaces.last)
        #expect(canvas.switchSpace(space.id))
        manager.undo()
        #expect(canvas.currentSpaceID == SpaceRecord.firstID)
        #expect(canvas.notes == records)
    }

    @Test func clipboardPasteUsesBoardCenterAndInvalidBytesCreateNoItem() throws {
        let canvas = CanvasView(store: NoteStore(inMemory: true))
        canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        canvas.layoutSubtreeIfNeeded()
        canvas.loadNotes()
        canvas.setViewport(Viewport(scale: 2, translation: CGPoint(x: -100, y: 40)))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally(); VerificationRuntime.imagePasteboard = nil }
        pasteboard.setData(try bytes(), forType: .png)
        VerificationRuntime.imagePasteboard = pasteboard
        canvas.paste(nil)
        let image = try #require(canvas.notes.first)
        let center = canvas.canvasPoint(from: CGPoint(x: 400, y: 300))
        #expect(image.frame.midX == center.x)
        #expect(image.frame.midY == center.y)
        pasteboard.clearContents()
        pasteboard.setData(Data("Invalid image".utf8), forType: .png)
        #expect(!canvas.importImages(from: pasteboard, at: .zero))
        #expect(canvas.notes == [image])
    }

    @Test func allImageResizeHandlesPreserveAspectAndOppositeAnchor() {
        let frame = CGRect(x: 10, y: 20, width: 180, height: 270)
        for handle in ResizeHandle.allCases {
            let resized = handle.resizeImage(frame, by: CGSize(width: -300, height: 500))
            #expect(abs(resized.width / resized.height - frame.width / frame.height) < 0.000001)
            #expect(min(resized.width, resized.height) >= 32)
            if [.left, .bottomLeft, .topLeft].contains(handle) { #expect(resized.maxX == frame.maxX) }
            if [.right, .bottomRight, .topRight].contains(handle) { #expect(resized.minX == frame.minX) }
            if [.bottom, .bottomLeft, .bottomRight].contains(handle) { #expect(resized.maxY == frame.maxY) }
            if [.top, .topLeft, .topRight].contains(handle) { #expect(resized.minY == frame.minY) }
        }
    }

    @Test func fileImportsAcceptAllRequiredImageIOFormats() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let canvas = CanvasView(store: NoteStore(inMemory: true))
        canvas.loadNotes()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var urls: [NSURL] = []
        for type in [UTType.png, .jpeg, .heic, .gif] {
            let url = directory.appendingPathComponent("Source." + type.preferredFilenameExtension!)
            try bytes(type).write(to: url)
            urls.append(url as NSURL)
        }
        pasteboard.writeObjects(urls)
        #expect(canvas.importImages(from: pasteboard, at: CGPoint(x: 200, y: 300)))
        #expect(canvas.notes.count == 4)
        #expect(canvas.notes.compactMap { $0.image?.contentType } == [.png, .jpeg, .heic, .gif])
    }

    @Test func formatsOrientationAndThumbnailUseSourcePixels() throws {
        for type in [UTType.png, .jpeg, .heic, .gif] {
            let data = try bytes(type, frames: type == .gif ? 2 : 1)
            let image = try #require(ImageAttachment(data: data, name: "Source." + type.preferredFilenameExtension!))
            #expect(image.pixelSize == CGSize(width: 1200, height: 800))
            let thumbnail = try #require(image.thumbnail(maxPixels: 160))
            #expect(max(thumbnail.width, thumbnail.height) == 160)
            #expect(image.cardSize.width == 320)
            #expect(image.contentType == type)
            if type == .gif {
                let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
                #expect(CGImageSourceGetCount(source) == 2)
                let first = try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary))
                #expect(thumbnail.dataProvider?.data as Data? == first.dataProvider?.data as Data?)
            }
        }
        let rotated = try #require(ImageAttachment(data: bytes(.jpeg, orientation: 6), name: "Rotated.jpg"))
        #expect(rotated.pixelSize == CGSize(width: 800, height: 1200))
        let thumbnail = try #require(rotated.thumbnail(maxPixels: 120))
        #expect(thumbnail.width == 80)
        #expect(thumbnail.height == 120)
    }
}
