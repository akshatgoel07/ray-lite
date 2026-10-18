import CoreData

@MainActor
public final class CoreDataStack {
    static func makeModel(includeSpaces: Bool = true, includeImages: Bool = true, includeNoteBlocks: Bool = true) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let item = itemEntity(includeImages: includeImages, includeNoteBlocks: includeNoteBlocks)
        model.entities = [canvasEntity(), item]
        if includeSpaces {
            let space = NSEntityDescription()
            space.name = "Space"
            space.managedObjectClassName = "SpaceMO"
            space.properties = [
                attribute("id", .UUIDAttributeType, optional: false),
                attribute("name", .stringAttributeType, optional: false),
                attribute("order", .integer64AttributeType, optional: false)
            ]
            let relation = NSRelationshipDescription()
            relation.name = "space"
            relation.destinationEntity = space
            relation.minCount = 0
            relation.maxCount = 1
            relation.isOptional = true
            relation.deleteRule = .nullifyDeleteRule
            let items = NSRelationshipDescription()
            items.name = "items"
            items.destinationEntity = item
            items.minCount = 0
            items.maxCount = 0
            items.isOptional = true
            items.deleteRule = .denyDeleteRule
            relation.inverseRelationship = items
            items.inverseRelationship = relation
            item.properties.append(relation)
            space.properties.append(items)
            model.entities.append(space)
        }
        return model
    }

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = optional
        return a
    }

    private static func canvasEntity() -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = "Canvas"
        e.managedObjectClassName = "CanvasMO"
        e.properties = [
            attribute("identifier", .UUIDAttributeType, optional: false),
            attribute("title", .stringAttributeType, optional: true),
            attribute("iconHex", .stringAttributeType, optional: true),
            attribute("index", .integer64AttributeType, optional: false),
            attribute("lastSeen", .doubleAttributeType, optional: false)
        ]
        return e
    }

    private static func itemEntity(includeImages: Bool, includeNoteBlocks: Bool) -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = "Item"
        e.managedObjectClassName = "ItemMO"
        e.properties = [
            attribute("identifier", .UUIDAttributeType, optional: false),
            attribute("canvasIdentifier", .UUIDAttributeType, optional: false),
            attribute("kind", .stringAttributeType, optional: false),
            attribute("pointX", .doubleAttributeType, optional: false),
            attribute("pointY", .doubleAttributeType, optional: false),
            attribute("width", .doubleAttributeType, optional: false),
            attribute("height", .doubleAttributeType, optional: false),
            attribute("rotation", .doubleAttributeType, optional: false),
            attribute("colorHex", .stringAttributeType, optional: true),
            attribute("zIndex", .integer64AttributeType, optional: false),
            attribute("text", .stringAttributeType, optional: true),
            attribute("videoURLString", .stringAttributeType, optional: true),
            attribute("parentFolderIdentifier", .UUIDAttributeType, optional: true),
            attribute("isHiddenFromFolders", .booleanAttributeType, optional: false)
        ]
        if includeNoteBlocks {
            e.properties.append(attribute("noteContent", .binaryDataAttributeType, optional: true))
        }
        if includeImages {
            let bytes = attribute("imageData", .binaryDataAttributeType, optional: true)
            bytes.allowsExternalBinaryDataStorage = true
            e.properties.append(bytes)
            e.properties.append(attribute("imageName", .stringAttributeType, optional: true))
        }
        return e
    }
}

public struct SpaceRecord: Equatable, Identifiable {
    public static let firstID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    public let id: UUID
    public var name: String
    public var order: Int

    public init(id: UUID = UUID(), name: String, order: Int) {
        self.id = id
        self.name = name
        self.order = order
    }
}

public struct NoteRecord: Equatable, Identifiable {
    public let id: UUID
    public var content: NoteContent
    public var text: String {
        get { content.plainText }
        set { content = NoteContent(plainText: newValue) }
    }
    public var frame: CGRect
    public var order: Int
    public var spaceID: UUID
    public var image: ImageAttachment?
    public var kind: ItemKind { image == nil ? .note : .image }

    public init(id: UUID, text: String, frame: CGRect, order: Int, spaceID: UUID = SpaceRecord.firstID, image: ImageAttachment? = nil, content: NoteContent? = nil) {
        self.id = id
        self.content = content ?? NoteContent(plainText: text)
        self.frame = frame
        self.order = order
        self.spaceID = spaceID
        self.image = image
    }
}

public enum NoteStoreError: Error {
    case storage(String)
    case duplicateID(UUID)
    case missingID(UUID)

    public var message: String {
        switch self {
        case .storage(let description):
            return "Cannot access the note store. \(description)"
        case .duplicateID(let id):
            return "A note with ID \(id) already exists."
        case .missingID(let id):
            return "No note with ID \(id) exists."
        }
    }
}

@MainActor
public final class NoteStore {
    public nonisolated static var defaultStoreURL: URL {
        if let path = ProcessInfo.processInfo.environment["RAY_LITE_STORE_URL"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL.applicationSupportDirectory
            .appendingPathComponent("RayLite", isDirectory: true)
            .appendingPathComponent("store.sqlite")
    }

    private let storeURL: URL?
    private var context: NSManagedObjectContext?

    public convenience init(storeURL: URL = NoteStore.defaultStoreURL) {
        self.init(url: storeURL)
    }

    public convenience init(inMemory: Bool) {
        self.init(url: inMemory ? nil : Self.defaultStoreURL)
    }

    private init(url: URL?) {
        storeURL = url
    }

    public func load(spaceID: UUID? = nil) -> Result<[NoteRecord], NoteStoreError> {
        perform { context in
            let request = NSFetchRequest<ItemMO>(entityName: "Item")
            request.predicate = spaceID.map {
                NSPredicate(format: "kind IN %@ AND space.id == %@", ["note", "image"], $0 as CVarArg)
            } ?? NSPredicate(format: "kind IN %@", ["note", "image"])
            request.sortDescriptors = [NSSortDescriptor(key: "zIndex", ascending: true)]
            return try context.fetch(request).map { item in
                let image: ImageAttachment?
                if item.kind == "image" {
                    guard let bytes = item.imageData, let decoded = ImageAttachment(data: bytes, name: item.imageName ?? "Image") else {
                        throw NoteStoreError.storage("Cannot read the image bytes.")
                    }
                    image = decoded
                } else {
                    image = nil
                }
                return NoteRecord(id: item.identifier, text: item.text ?? "",
                           frame: CGRect(x: item.pointX, y: item.pointY,
                                         width: item.width, height: item.height),
                           order: Int(item.zIndex), spaceID: item.space!.id, image: image,
                           content: try item.noteContent.map { try JSONDecoder().decode(NoteContent.self, from: $0) })
            }.sorted {
                $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
            }
        }
    }

    public func insert(_ note: NoteRecord) -> Result<Void, NoteStoreError> {
        perform { context in
            guard try self.item(id: note.id, in: context) == nil else {
                throw NoteStoreError.duplicateID(note.id)
            }
            let entity = context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Item"]!
            let item = ItemMO(entity: entity, insertInto: context)
            item.identifier = note.id
            item.canvasIdentifier = note.spaceID
            item.rotation = 0
            item.isHiddenFromFolders = false
            guard let space = try self.space(id: note.spaceID, in: context) else {
                throw NoteStoreError.storage("The space does not exist.")
            }
            item.space = space
            try self.apply(note, to: item)
            try context.save()
        }
    }

    public func update(_ note: NoteRecord) -> Result<Void, NoteStoreError> {
        perform { context in
            guard let item = try self.item(id: note.id, in: context) else {
                throw NoteStoreError.missingID(note.id)
            }
            guard let space = try self.space(id: note.spaceID, in: context) else {
                throw NoteStoreError.storage("The space does not exist.")
            }
            item.space = space
            try self.apply(note, to: item)
            try context.save()
        }
    }

    public func delete(id: UUID) -> Result<Void, NoteStoreError> {
        perform { context in
            guard let item = try self.item(id: id, in: context) else {
                throw NoteStoreError.missingID(id)
            }
            context.delete(item)
            try context.save()
        }
    }

    public func loadSpaces() -> Result<[SpaceRecord], NoteStoreError> {
        perform { context in
            let request = NSFetchRequest<SpaceMO>(entityName: "Space")
            request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true),
                                       NSSortDescriptor(key: "name", ascending: true)]
            return try context.fetch(request).map { SpaceRecord(id: $0.id, name: $0.name, order: Int($0.order)) }
        }
    }

    public func insertSpace(_ record: SpaceRecord) -> Result<Void, NoteStoreError> {
        perform { context in
            guard try self.space(id: record.id, in: context) == nil else {
                throw NoteStoreError.duplicateID(record.id)
            }
            let space = SpaceMO(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Space"]!, insertInto: context)
            space.id = record.id
            space.name = record.name
            space.order = Int64(record.order)
            try context.save()
        }
    }

    public func restoreSpace(_ record: SpaceRecord, notes: [NoteRecord]) -> Result<Void, NoteStoreError> {
        perform { context in
            guard try self.space(id: record.id, in: context) == nil else { throw NoteStoreError.duplicateID(record.id) }
            let space = SpaceMO(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Space"]!, insertInto: context)
            space.id = record.id
            space.name = record.name
            space.order = Int64(record.order)
            for note in notes {
                guard note.spaceID == record.id, try self.item(id: note.id, in: context) == nil else {
                    throw NoteStoreError.duplicateID(note.id)
                }
                let item = ItemMO(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Item"]!, insertInto: context)
                item.identifier = note.id
                item.canvasIdentifier = record.id
                item.rotation = 0
                item.isHiddenFromFolders = false
                item.space = space
                try self.apply(note, to: item)
            }
            try context.save()
        }
    }

    public func renameSpace(id: UUID, name: String) -> Result<Void, NoteStoreError> {
        perform { context in
            guard let space = try self.space(id: id, in: context) else { throw NoteStoreError.missingID(id) }
            space.name = name
            try context.save()
        }
    }

    public func replaceSpaces(removing id: UUID, inserting spaces: [SpaceRecord], notes: [NoteRecord]) -> Result<Void, NoteStoreError> {
        perform { context in
            guard let removed = try self.space(id: id, in: context) else { throw NoteStoreError.missingID(id) }
            for item in removed.items { context.delete(item) }
            context.delete(removed)
            for record in spaces {
                guard try self.space(id: record.id, in: context) == nil else { throw NoteStoreError.duplicateID(record.id) }
                let space = SpaceMO(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Space"]!, insertInto: context)
                space.id = record.id
                space.name = record.name
                space.order = Int64(record.order)
            }
            for note in notes {
                guard try self.item(id: note.id, in: context) == nil else { throw NoteStoreError.duplicateID(note.id) }
                guard let space = try self.space(id: note.spaceID, in: context) else { throw NoteStoreError.missingID(note.spaceID) }
                let item = ItemMO(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Item"]!, insertInto: context)
                item.identifier = note.id
                item.canvasIdentifier = note.spaceID
                item.rotation = 0
                item.isHiddenFromFolders = false
                item.space = space
                try self.apply(note, to: item)
            }
            try context.save()
        }
    }

    public func deleteEmptySpace(id: UUID) -> Result<Bool, NoteStoreError> {
        perform { context in
            guard id != SpaceRecord.firstID, let space = try self.space(id: id, in: context),
                  space.items.isEmpty else { return false }
            context.delete(space)
            try context.save()
            return true
        }
    }

    private func space(id: UUID, in context: NSManagedObjectContext) throws -> SpaceMO? {
        let request = NSFetchRequest<SpaceMO>(entityName: "Space")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func openContext() throws -> NSManagedObjectContext {
        if let context { return context }
        if let storeURL {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let model = CoreDataStack.makeModel()
        if let storeURL, FileManager.default.fileExists(atPath: storeURL.path) {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: storeURL)
            if !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
                let sources = [CoreDataStack.makeModel(includeNoteBlocks: false),
                               CoreDataStack.makeModel(includeImages: false, includeNoteBlocks: false),
                               CoreDataStack.makeModel(includeSpaces: false, includeImages: false, includeNoteBlocks: false),
                               CoreDataStack.makeModel(includeSpaces: false, includeNoteBlocks: false),
                               CoreDataStack.makeModel(includeImages: false),
                               CoreDataStack.makeModel(includeSpaces: false, includeImages: false),
                               CoreDataStack.makeModel(includeSpaces: false)]
                guard let legacy = sources.first(where: { $0.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) }) else {
                    throw NoteStoreError.storage("The store model is unknown.")
                }
                let mapping = try NSMappingModel.inferredMappingModel(forSourceModel: legacy, destinationModel: model)
                let temporary = storeURL.deletingLastPathComponent().appendingPathComponent("migration-\(UUID()).sqlite")
                let manager = NSMigrationManager(sourceModel: legacy, destinationModel: model)
                defer {
                    for suffix in ["", "-wal", "-shm"] {
                        try? FileManager.default.removeItem(atPath: temporary.path + suffix)
                    }
                }
                try manager.migrateStore(from: storeURL, sourceType: NSSQLiteStoreType,
                    options: nil, with: mapping, toDestinationURL: temporary,
                    destinationType: NSSQLiteStoreType, destinationOptions: nil)
                let replacement = NSPersistentStoreCoordinator(managedObjectModel: model)
                try replacement.replacePersistentStore(at: storeURL, destinationOptions: nil,
                    withPersistentStoreFrom: temporary, sourceOptions: nil, ofType: NSSQLiteStoreType)
            }
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: storeURL == nil ? NSInMemoryStoreType : NSSQLiteStoreType,
                                           configurationName: nil, at: storeURL)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let request = NSFetchRequest<SpaceMO>(entityName: "Space")
        if try context.count(for: request) == 0 {
            let first = SpaceMO(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Space"]!, insertInto: context)
            first.id = SpaceRecord.firstID
            first.name = "Space01"
            first.order = 0
        }
        let orphans = NSFetchRequest<ItemMO>(entityName: "Item")
        orphans.predicate = NSPredicate(format: "kind IN %@ AND space == nil", ["note", "image"])
        for item in try context.fetch(orphans) {
            item.space = try space(id: SpaceRecord.firstID, in: context)
        }
        let plainNotes = NSFetchRequest<ItemMO>(entityName: "Item")
        plainNotes.predicate = NSPredicate(format: "kind == %@ AND noteContent == nil", "note")
        for item in try context.fetch(plainNotes) {
            item.noteContent = try JSONEncoder().encode(NoteContent(plainText: item.text ?? ""))
        }
        if context.hasChanges { try context.save() }
        self.context = context
        return context
    }

    private func perform<Value>(_ action: (NSManagedObjectContext) throws -> Value) -> Result<Value, NoteStoreError> {
        do {
            return .success(try action(openContext()))
        } catch {
            context?.rollback()
            return .failure(error as? NoteStoreError ?? .storage(error.localizedDescription))
        }
    }

    private func item(id: UUID, in context: NSManagedObjectContext) throws -> ItemMO? {
        let request = NSFetchRequest<ItemMO>(entityName: "Item")
        request.predicate = NSPredicate(format: "identifier == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ note: NoteRecord, to item: ItemMO) throws {
        item.kind = note.kind.rawValue
        if item.imageData != note.image?.data { item.imageData = note.image?.data }
        item.imageName = note.image?.name
        item.noteContent = note.image == nil ? try JSONEncoder().encode(note.content) : nil
        item.text = note.text
        item.pointX = note.frame.origin.x
        item.pointY = note.frame.origin.y
        item.width = note.frame.width
        item.height = note.frame.height
        item.zIndex = Int64(note.order)
    }
}

@objc(CanvasMO)
public final class CanvasMO: NSManagedObject {
    @NSManaged public var identifier: UUID
    @NSManaged public var title: String?
    @NSManaged public var iconHex: String?
    @NSManaged public var index: Int64
    @NSManaged public var lastSeen: Double
}

@objc(SpaceMO)
public final class SpaceMO: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var order: Int64
    @NSManaged public var items: Set<ItemMO>
}

@objc(ItemMO)
public final class ItemMO: NSManagedObject {
    @NSManaged public var space: SpaceMO?
    @NSManaged public var identifier: UUID
    @NSManaged public var canvasIdentifier: UUID
    @NSManaged public var kind: String
    @NSManaged public var pointX: Double
    @NSManaged public var pointY: Double
    @NSManaged public var width: Double
    @NSManaged public var height: Double
    @NSManaged public var rotation: Double
    @NSManaged public var colorHex: String?
    @NSManaged public var zIndex: Int64
    @NSManaged public var text: String?
    @NSManaged public var noteContent: Data?
    @NSManaged public var imageData: Data?
    @NSManaged public var imageName: String?
    @NSManaged public var videoURLString: String?
    @NSManaged public var parentFolderIdentifier: UUID?
    @NSManaged public var isHiddenFromFolders: Bool
}
