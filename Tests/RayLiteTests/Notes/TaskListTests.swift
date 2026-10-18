import Foundation
import Testing
@testable import RayLite

@MainActor
struct ChecklistTests {
    @Test func progressPersistsWithoutDuplicateCredit() throws {
        let name = "RayLite.ChecklistTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let progress = ChecklistProgress(defaults: defaults)
        var changes = 0
        progress.onChange = { changes += 1 }
        #expect(progress.counter == "00/10")
        progress.complete(.createNote)
        progress.complete(.createNote)
        #expect(changes == 1)
        let restored = ChecklistProgress(defaults: defaults)
        #expect(restored.completed == [.createNote])
        #expect(restored.counter == "01/10")
    }

    @Test func unavailableAndUnknownTasksStayIncomplete() throws {
        let name = "RayLite.ChecklistTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let progress = ChecklistProgress(defaults: defaults)
        for task in ChecklistTask.allCases where !task.isAvailable { progress.complete(task) }
        #expect(progress.completed.isEmpty)
        defaults.set(["createNote", "createNote", "colors", "createSpace", "settings", "unknown"],
                     forKey: "checklistCompletedTasks")
        #expect(progress.completed == [.createNote])
        #expect(progress.counter == "01/10")
        #expect(ChecklistTask.allCases.count == 10)
    }
}
