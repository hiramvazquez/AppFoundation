import Foundation
import Testing

@testable import NotesApp

@Suite("NotesViewModel")
@MainActor
struct NotesViewModelTests {
    @Test("handle(.load) calls logic.loadNotes and reaches .content when non-empty")
    func loadReachesContent() async {
        let mock = NotesLogicMock()
        let note = Note(text: "First")
        mock.notesToReturn = [note]
        let viewModel = NotesViewModel(logic: mock)

        viewModel.handle(.load)
        await viewModel.inFlightLoad?.value

        #expect(mock.loadCallCount == 1)
        #expect(viewModel.phase == .content)
        #expect(viewModel.notes == [note])
    }

    @Test("handle(.load) reaches .empty when there are no notes")
    func loadReachesEmptyWhenNoNotes() async {
        let mock = NotesLogicMock()
        mock.notesToReturn = []
        let viewModel = NotesViewModel(logic: mock)

        viewModel.handle(.load)
        await viewModel.inFlightLoad?.value

        #expect(viewModel.phase == .empty)
    }

    @Test("handle(.add) calls logic.addNote and inserts the result at the front")
    func addInsertsNoteAtFront() async {
        let mock = NotesLogicMock()
        let newNote = Note(text: "New note")
        mock.noteToReturn = newNote
        let viewModel = NotesViewModel(logic: mock)

        viewModel.handle(.add("New note"))
        await viewModel.inFlightActivity?.value

        #expect(mock.addCalls == ["New note"])
        #expect(viewModel.notes.first == newNote)
    }

    @Test("handle(.delete) calls logic.deleteNote and removes the note locally")
    func deleteRemovesNoteLocally() async {
        let mock = NotesLogicMock()
        let note = Note(text: "To delete")
        mock.notesToReturn = [note]
        let viewModel = NotesViewModel(logic: mock)
        viewModel.handle(.load)
        await viewModel.inFlightLoad?.value

        viewModel.handle(.delete(note.id))
        await viewModel.inFlightActivity?.value

        #expect(mock.deleteCalls == [note.id])
        #expect(viewModel.notes.isEmpty)
    }
}
