import AppFoundation
import Foundation
import SwiftData

/// Registers the Notes feature into a `Container`: the composition root is the only place
/// that knows `SwiftDataNotesStore`/`ModelContainer` behind `NotesStoring` (M4).
///
/// ```swift
/// Container.shared.register(modules: [try! NotesModule()])
/// // Root view:
/// NotesView(viewModel: Container.shared.resolve())
/// ```
public struct NotesModule: DependencyModule {
    private let modelContainer: ModelContainer

    /// - Parameter modelContainer: Defaults to a persisted, on-disk container for
    ///   `NoteRecord`. Tests pass an in-memory one instead
    ///   (`ModelConfiguration(isStoredInMemoryOnly: true)`).
    public init(modelContainer: ModelContainer? = nil) throws {
        self.modelContainer = try modelContainer ?? ModelContainer(for: NoteRecord.self)
    }

    public func register(in container: Container) {
        container.register(NotesStoring.self) { [modelContainer] _ in
            SwiftDataNotesStore(modelContainer: modelContainer)
        }
        container.register(NotesLogicProtocol.self) { c in
            NotesLogic(notesStore: c.resolve())
        }
        container.register(NotesViewModel.self, lifecycle: .transient) { c in
            NotesViewModel(logic: c.resolve())
        }
    }
}
