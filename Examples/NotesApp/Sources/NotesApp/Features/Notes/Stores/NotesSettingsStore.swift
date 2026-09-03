import Foundation

// MARK: - The store

/// Per-device notes display preference — sort oldest-first instead of `NotesStoring`'s own
/// newest-first order. Persisted with `UserDefaults`, not SwiftData: a different local
/// persistence mechanism than `Stores/NotesStore.swift`, so it gets its own `*Storing`
/// protocol and its own implementation (same rule, M3 in `AGENTS.md` — a Store is the ONLY
/// place that touches a given mechanism — applied to `UserDefaults` this time).
public protocol NotesSettingsStoring: Sendable {
    /// `true` sorts `NotesLogic.loadNotes()` oldest-first; `false` (the default, nothing
    /// set yet) keeps `NotesStoring`'s own newest-first order.
    func sortOldestFirst() async -> Bool
    func setSortOldestFirst(_ value: Bool) async
}

/// The `NotesSettingsStoring` this app runs with, over `UserDefaults`.
///
/// The conformance below is declared in a separate `extension`, not inline on this
/// `actor` declaration. That is not a style choice: this package's `swiftSettings`
/// (`.defaultIsolation(MainActor.self)`) make an INLINE `actor X: XStoring` with a
/// non-`Sendable` stored property (`UserDefaults` here) assigned in `init` fail to
/// compile — `error: actor-isolated property 'defaults' can not be mutated from the main
/// actor` on the property's own assignment. Full repro, exact compiler error, and every
/// variant tried live in `docs/repros/actor-inline-conformance.md`; the rule is in
/// `AGENTS.md` (sección Store) and `Architecture.md`. Moving the conformance here — same
/// actor, same stored properties, same `init` — is the fix.
public actor UserDefaultsNotesSettingsStore {
    private let defaults: UserDefaults
    private let key = "com.appfoundation.notesapp.sortOldestFirst"

    /// - Parameter defaults: `.standard` in production; tests pass an isolated instance
    ///   (`UserDefaults(suiteName:)`) so no state leaks between test runs.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func sortOldestFirst() async -> Bool {
        defaults.bool(forKey: key)
    }

    public func setSortOldestFirst(_ value: Bool) async {
        defaults.set(value, forKey: key)
    }
}

extension UserDefaultsNotesSettingsStore: NotesSettingsStoring {}
