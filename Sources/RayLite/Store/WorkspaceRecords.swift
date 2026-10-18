import CoreData

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

