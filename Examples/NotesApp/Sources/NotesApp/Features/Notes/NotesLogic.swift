import AppFoundation
import Foundation

// MARK: - The domain model

/// What `NotesView` renders. `Sendable`/`Equatable`, like every domain model in this kit —
/// never the SwiftData `@Model` itself, which stays private to `Stores/NotesStore.swift`
/// (M2: a persistence model is a DTO, the same way a network `Response` is).
public nonisolated struct Note: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

// MARK: - Domain errors (M1)

/// Every way a notes operation can fail — never a raw SwiftData `Error`, which stops at
/// the `Logic`/`Store` boundary.
public enum NotesError: DomainError, Equatable {
    case emptyText
    case storageFailure

    public var isRetryable: Bool {
        switch self {
        case .storageFailure: true
        case .emptyText: false
        }
    }

    public var screenError: ScreenError {
        switch self {
        case .emptyText:
            return ScreenError(title: "Empty note", message: "Write something before saving.")
        case .storageFailure:
            return ScreenError(title: "Couldn't save", message: "Please try again.")
        }
    }
}

// MARK: - Logic

/// Every operation `NotesViewModel` can ask its `Logic` for.
public protocol NotesLogicProtocol: Logic {
    func loadNotes() async throws -> [Note]
    func addNote(text: String) async throws -> Note
    func deleteNote(id: UUID) async throws
}

/// ALL of the feature's business logic: validates the note text, delegates to
/// `NotesStoring`, and maps any storage failure to `NotesError` (M1).
///
/// `nonisolated` (M5): not tied to the main actor; its `async` methods run on whichever
/// actor calls them.
public nonisolated final class NotesLogic: NotesLogicProtocol {
    private let notesStore: any NotesStoring
    private let notesSettingsStore: any NotesSettingsStoring

    /// - Parameters:
    ///   - notesStore: Where notes themselves live — injected as a protocol, never the
    ///     concrete `SwiftDataNotesStore`/`InMemoryNotesStore`
    ///     (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 3).
    ///   - notesSettingsStore: The sort-order preference, a second local Store over a
    ///     different mechanism (`UserDefaults`, `Stores/NotesSettingsStore.swift`) — same
    ///     rule, same reason: `NotesLogic` only ever sees it through its protocol.
    public init(notesStore: any NotesStoring, notesSettingsStore: any NotesSettingsStoring) {
        self.notesStore = notesStore
        self.notesSettingsStore = notesSettingsStore
    }

    public func loadNotes() async throws -> [Note] {
        let notes: [Note]
        do {
            notes = try await notesStore.fetchAll()
        } catch {
            throw NotesError.storageFailure
        }
        guard await notesSettingsStore.sortOldestFirst() else { return notes }
        return notes.sorted { $0.createdAt < $1.createdAt }
    }

    public func addNote(text: String) async throws -> Note {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NotesError.emptyText }

        let note = Note(text: trimmed)
        do {
            try await notesStore.save(note)
            return note
        } catch {
            throw NotesError.storageFailure
        }
    }

    public func deleteNote(id: UUID) async throws {
        do {
            try await notesStore.delete(id)
        } catch {
            throw NotesError.storageFailure
        }
    }
}
