import CoreData

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
            let request = NSFetchRequest<ArchivedCard>(entityName: "CardArchive")
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
            let entity = context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["CardArchive"]!
            let item = ArchivedCard(entity: entity, insertInto: context)
            item.identifier = note.id
            item.boardReference = note.spaceID
            item.rotation = 0
            item.excludesFolderList = false
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
            let request = NSFetchRequest<ArchivedWorkspace>(entityName: "WorkspaceArchive")
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
            let space = ArchivedWorkspace(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["WorkspaceArchive"]!, insertInto: context)
            space.id = record.id
            space.name = record.name
            space.order = Int64(record.order)
            try context.save()
        }
    }

    public func restoreSpace(_ record: SpaceRecord, notes: [NoteRecord]) -> Result<Void, NoteStoreError> {
        perform { context in
            guard try self.space(id: record.id, in: context) == nil else { throw NoteStoreError.duplicateID(record.id) }
            let space = ArchivedWorkspace(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["WorkspaceArchive"]!, insertInto: context)
            space.id = record.id
            space.name = record.name
            space.order = Int64(record.order)
            for note in notes {
                guard note.spaceID == record.id, try self.item(id: note.id, in: context) == nil else {
                    throw NoteStoreError.duplicateID(note.id)
                }
                let item = ArchivedCard(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["CardArchive"]!, insertInto: context)
                item.identifier = note.id
                item.boardReference = record.id
                item.rotation = 0
                item.excludesFolderList = false
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
                let space = ArchivedWorkspace(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["WorkspaceArchive"]!, insertInto: context)
                space.id = record.id
                space.name = record.name
                space.order = Int64(record.order)
            }
            for note in notes {
                guard try self.item(id: note.id, in: context) == nil else { throw NoteStoreError.duplicateID(note.id) }
                guard let space = try self.space(id: note.spaceID, in: context) else { throw NoteStoreError.missingID(note.spaceID) }
                let item = ArchivedCard(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["CardArchive"]!, insertInto: context)
                item.identifier = note.id
                item.boardReference = note.spaceID
                item.rotation = 0
                item.excludesFolderList = false
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

    private func space(id: UUID, in context: NSManagedObjectContext) throws -> ArchivedWorkspace? {
        let request = NSFetchRequest<ArchivedWorkspace>(entityName: "WorkspaceArchive")
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
        let model = RecordSchema.makeModel()
        if let storeURL, FileManager.default.fileExists(atPath: storeURL.path) {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: storeURL)
            if !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
                let sources = [RecordSchema.makeModel(includeNoteBlocks: false),
                               RecordSchema.makeModel(includeImages: false, includeNoteBlocks: false),
                               RecordSchema.makeModel(includeSpaces: false, includeImages: false, includeNoteBlocks: false),
                               RecordSchema.makeModel(includeSpaces: false, includeNoteBlocks: false),
                               RecordSchema.makeModel(includeImages: false),
                               RecordSchema.makeModel(includeSpaces: false, includeImages: false),
                               RecordSchema.makeModel(includeSpaces: false)]
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
        let request = NSFetchRequest<ArchivedWorkspace>(entityName: "WorkspaceArchive")
        if try context.count(for: request) == 0 {
            let first = ArchivedWorkspace(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["WorkspaceArchive"]!, insertInto: context)
            first.id = SpaceRecord.firstID
            first.name = "Space01"
            first.order = 0
        }
        let orphans = NSFetchRequest<ArchivedCard>(entityName: "CardArchive")
        orphans.predicate = NSPredicate(format: "kind IN %@ AND space == nil", ["note", "image"])
        for item in try context.fetch(orphans) {
            item.space = try space(id: SpaceRecord.firstID, in: context)
        }
        let plainNotes = NSFetchRequest<ArchivedCard>(entityName: "CardArchive")
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

    private func item(id: UUID, in context: NSManagedObjectContext) throws -> ArchivedCard? {
        let request = NSFetchRequest<ArchivedCard>(entityName: "CardArchive")
        request.predicate = NSPredicate(format: "identifier == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ note: NoteRecord, to item: ArchivedCard) throws {
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

