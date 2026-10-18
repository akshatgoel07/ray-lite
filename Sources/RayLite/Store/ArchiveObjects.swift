import CoreData

@objc(ArchivedBoard)
public final class ArchivedBoard: NSManagedObject {
    @NSManaged public var identifier: UUID
    @NSManaged public var title: String?
    @NSManaged public var iconHex: String?
    @NSManaged public var index: Int64
    @NSManaged public var visitTimestamp: Double
}

@objc(ArchivedWorkspace)
public final class ArchivedWorkspace: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var order: Int64
    @NSManaged public var items: Set<ArchivedCard>
}

@objc(ArchivedCard)
public final class ArchivedCard: NSManagedObject {
    @NSManaged public var space: ArchivedWorkspace?
    @NSManaged public var identifier: UUID
    @NSManaged public var boardReference: UUID
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
    @NSManaged public var enclosingFolderID: UUID?
    @NSManaged public var excludesFolderList: Bool
}
