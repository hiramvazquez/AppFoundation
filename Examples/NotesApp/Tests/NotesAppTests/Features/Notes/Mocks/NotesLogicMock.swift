import Foundation

@testable import NotesApp

/// Spy standing in for `NotesLogicProtocol` in `NotesViewModelTests` — the view model
/// under test never touches a real `NotesStoring`.
final class NotesLogicMock: NotesLogicProtocol {
    private(set) var loadCallCount = 0
    private(set) var addCalls: [String] = []
    private(set) var deleteCalls: [UUID] = []

    var notesToReturn: [Note] = []
    var noteToReturn = Note(text: "stub")
    var errorToThrow: (any Error)?

    func loadNotes() async throws -> [Note] {
        loadCallCount += 1
        if let errorToThrow { throw errorToThrow }
        return notesToReturn
    }

    func addNote(text: String) async throws -> Note {
        addCalls.append(text)
        if let errorToThrow { throw errorToThrow }
        return noteToReturn
    }

    func deleteNote(id: UUID) async throws {
        deleteCalls.append(id)
        if let errorToThrow { throw errorToThrow }
    }
}
