# NotesApp

The "solo local" variant (`docs/ARQUITECTURA-KIT-2026-09-02.md` §1): a screen backed entirely
by local persistence, no network. SwiftData for real — a `@Model` entity and a real
`ModelContainer` — not a simulation; the only concession in tests is an in-memory
container (`isStoredInMemoryOnly: true`).

## Files

```
Sources/NotesApp/
├── NotesModule.swift              DependencyModule: builds ModelContainer, the ONLY place SwiftDataNotesStore is named (M4)
└── Features/Notes/
    ├── NotesView.swift            ScreenContainer(viewModel) { send in … } with a list and send(.add(text))
    ├── NotesViewModel.swift       LogicViewModel<any NotesLogicProtocol>, ActionHandling
    ├── NotesLogic.swift           NotesLogicProtocol + NotesLogic (nonisolated, M5); Note; NotesError: DomainError (M1)
    └── Stores/
        └── NotesStore.swift       NoteRecord (@Model, private to this file — M2) + NotesStoring + SwiftDataNotesStore (@ModelActor, M5)
```

`Tests/NotesAppTests/Features/Notes/` mirrors the same shape: `NotesViewModelTests.swift`
(against `NotesLogicMock`), `NotesLogicTests.swift` (against `InMemoryNotesStore`, built on
`AppFoundationTestSupport.InMemoryStore`), `Stores/NotesStoreTests.swift` (the real
`SwiftDataNotesStore`, in-memory `ModelContainer`), `Mocks/`.

## The four things worth reading in order

1. **`NotesView.swift`** — `ScreenContainer` bound to `NotesViewModel`, a `List`, and a
   text field that calls `send(.add(text))`.
2. **`NotesViewModel.swift`** — pure orchestration: `handle(_:)` calls `logic`, updates
   `notes`. Never imports SwiftData.
3. **`NotesLogic.swift`** — the business rule (a blank note is rejected) and the ONE place
   a storage failure becomes `NotesError` (`DomainError`, M1) — nothing past this file ever
   sees a raw SwiftData error. `Note` (the domain model) lives here too.
4. **`Stores/NotesStore.swift`** — `NoteRecord`, the `@Model` SwiftData entity, never
   leaves this file (M2): `SwiftDataNotesStore` maps it to `Note` on the way out and back
   on the way in. `@ModelActor` (M5) — SwiftData's `ModelContext` is not `Sendable` and its
   initializer is main-actor-isolated, which is exactly what the macro's generated
   `init(modelContainer:)` accounts for.

## Tests, by layer

| Layer | Double | What it proves |
|---|---|---|
| `NotesViewModel` | `NotesLogicMock` (spy) | `handle(.add(text))`/`handle(.delete(id))` call the right `logic` method and update `notes`; `.content` vs `.empty` follows whether the list is empty |
| `NotesLogic` | `InMemoryNotesStore` (`AppFoundationTestSupport.InMemoryStore`) | blank text is rejected before the store is touched; a store failure maps to `NotesError.storageFailure` |
| `SwiftDataNotesStore` | none — a REAL `ModelContainer`, in-memory only | save/fetch/delete round-trip through actual SwiftData, newest-first ordering |

## Arquitectura

Ver [`AGENTS.md`](../../AGENTS.md) para las reglas completas; este README solo recorre los
ficheros de este ejemplo.
