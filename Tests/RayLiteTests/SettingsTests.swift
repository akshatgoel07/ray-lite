import AppKit
import Testing
@testable import RayLite

@MainActor
struct SettingsTests {
    @Test func preferencesPersistAndRecoverInvalidValues() throws {
        let name = "RayLite.SettingsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.cornerStyle == .sharp)
        #expect(preferences.noteFont == .mixed)
        #expect(preferences.theme == .auto)
        preferences.cornerStyle = .round
        preferences.noteFont = .mono
        preferences.theme = .light
        let restored = AppPreferences(defaults: defaults)
        #expect(restored.cornerStyle == .round)
        #expect(restored.noteFont == .mono)
        #expect(restored.font(size: 16).isFixedPitch)
        #expect(restored.appearance?.name == .aqua)
        restored.noteFont = .sans
        restored.theme = .dark
        #expect(!restored.font(size: 16).isFixedPitch)
        #expect(restored.appearance?.name == .darkAqua)
        defaults.set("Invalid", forKey: "cornerStyle")
        defaults.set("Invalid", forKey: "noteFont")
        defaults.set("Invalid", forKey: "appearance")
        #expect(restored.cornerStyle == .sharp)
        #expect(restored.noteFont == .mixed)
        #expect(restored.appearance == nil)
    }

    @Test func deletionAndRestorePreserveOtherSpacesThroughRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("spaces.sqlite")
        let space = SpaceRecord(id: SpaceRecord.firstID, name: "Ideas", order: 0)
        let other = SpaceRecord(name: "Other", order: 1)
        let note = NoteRecord(id: UUID(), text: "Keep this note", frame: CGRect(x: 1, y: 2, width: 240, height: 150), order: 3)
        let otherNote = NoteRecord(id: UUID(), text: "Other note", frame: note.frame, order: 0, spaceID: other.id)
        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            _ = try store.loadSpaces().get()
            try store.renameSpace(id: space.id, name: space.name).get()
            try store.insertSpace(other).get()
            try store.insert(note).get()
            try store.insert(otherNote).get()
            try store.replaceSpaces(removing: space.id, inserting: [], notes: []).get()
            #expect(try store.loadSpaces().get() == [other])
            #expect(try store.load().get() == [otherNote])
        }
        try autoreleasepool {
            let store = NoteStore(storeURL: url)
            #expect(try store.loadSpaces().get() == [other])
            try store.restoreSpace(space, notes: [note]).get()
            #expect(try store.loadSpaces().get() == [space, other])
            #expect(try store.load(spaceID: space.id).get() == [note])
            #expect(try store.load(spaceID: other.id).get() == [otherNote])
        }
    }

    @Test func failedReplacementRollsBackTheSpaceAndNotes() throws {
        let store = NoteStore(inMemory: true)
        let spaces = try store.loadSpaces().get()
        let note = NoteRecord(id: UUID(), text: "Keep", frame: CGRect(x: 0, y: 0, width: 240, height: 150), order: 0)
        try store.insert(note).get()
        let duplicate = SpaceRecord(name: "Duplicate", order: 1)
        let result = store.replaceSpaces(removing: SpaceRecord.firstID, inserting: [duplicate, duplicate], notes: [])
        guard case .failure = result else { Issue.record("The store must reject a duplicate space."); return }
        #expect(try store.loadSpaces().get() == spaces)
        #expect(try store.load().get() == [note])
    }
}
