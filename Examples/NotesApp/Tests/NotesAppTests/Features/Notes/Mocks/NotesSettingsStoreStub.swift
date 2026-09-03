@testable import NotesApp

/// Stub `NotesSettingsStoring` — an in-memory flag, no `UserDefaults` — for
/// `NotesLogicTests`. `actor`, inline conformance: the ONE stored property (`oldestFirst`)
/// is `Bool`, which IS `Sendable`, so this does not hit the `init` problem
/// `docs/repros/actor-inline-conformance.md` documents (variant 3 there) — only a
/// non-`Sendable` stored property does.
actor NotesSettingsStoreStub: NotesSettingsStoring {
    private var oldestFirst: Bool

    init(sortOldestFirst: Bool = false) {
        self.oldestFirst = sortOldestFirst
    }

    func sortOldestFirst() async -> Bool { oldestFirst }
    func setSortOldestFirst(_ value: Bool) async { oldestFirst = value }
}
