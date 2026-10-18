import CoreData

@MainActor
public final class RecordSchema {
    static func makeModel(includeSpaces: Bool = true, includeImages: Bool = true, includeNoteBlocks: Bool = true) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let item = cardArchiveEntity(includeImages: includeImages, includeNoteBlocks: includeNoteBlocks)
        model.entities = [boardArchiveEntity(), item]
        if includeSpaces {
            let space = NSEntityDescription()
            space.name = "WorkspaceArchive"
            space.managedObjectClassName = "ArchivedWorkspace"
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

    private static func boardArchiveEntity() -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = "BoardArchive"
        e.managedObjectClassName = "ArchivedBoard"
        e.properties = [
            attribute("identifier", .UUIDAttributeType, optional: false),
            attribute("title", .stringAttributeType, optional: true),
            attribute("iconHex", .stringAttributeType, optional: true),
            attribute("index", .integer64AttributeType, optional: false),
            attribute("visitTimestamp", .doubleAttributeType, optional: false)
        ]
        return e
    }

    private static func cardArchiveEntity(includeImages: Bool, includeNoteBlocks: Bool) -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = "CardArchive"
        e.managedObjectClassName = "ArchivedCard"
        e.properties = [
            attribute("identifier", .UUIDAttributeType, optional: false),
            attribute("boardReference", .UUIDAttributeType, optional: false),
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
            attribute("enclosingFolderID", .UUIDAttributeType, optional: true),
            attribute("excludesFolderList", .booleanAttributeType, optional: false)
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

