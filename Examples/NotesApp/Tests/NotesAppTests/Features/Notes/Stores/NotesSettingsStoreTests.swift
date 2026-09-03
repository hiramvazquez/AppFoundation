import Foundation
import Testing

@testable import NotesApp

/// `UserDefaultsNotesSettingsStore` against a REAL `UserDefaults` — isolated per test with
/// `UserDefaults(suiteName:)` so nothing leaks between runs or into `.standard`.
@Suite("UserDefaultsNotesSettingsStore")
struct NotesSettingsStoreTests {
    /// A fresh suite name per test — `String` is `Sendable`, unlike `UserDefaults` itself,
    /// so each call site below builds its own `UserDefaults(suiteName:)` instance right at
    /// the `init(defaults:)` argument instead of passing one already-referenced value to
    /// two actor initializers (which the compiler rejects as a data-race risk: this
    /// package's `defaultIsolation(MainActor)` makes a plain `async` test function
    /// main-actor-isolated by default, and `UserDefaults` isn't `Sendable`). Both
    /// instances still read/write the same on-disk suite, isolated from `.standard` and
    /// from any other test.
    private func makeSuiteName() -> String {
        "NotesSettingsStoreTests.\(UUID().uuidString)"
    }

    @Test("sortOldestFirst() defaults to false when nothing was set")
    func defaultsToFalse() async throws {
        guard let storeDefaults = UserDefaults(suiteName: makeSuiteName()) else {
            Issue.record("UserDefaults(suiteName:) returned nil")
            return
        }
        let store = UserDefaultsNotesSettingsStore(defaults: storeDefaults)

        #expect(await store.sortOldestFirst() == false)
    }

    @Test("setSortOldestFirst(_:) persists across a new store instance over the same UserDefaults")
    func persistsAcrossInstances() async throws {
        let suiteName = makeSuiteName()
        guard let storeDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("UserDefaults(suiteName:) returned nil")
            return
        }
        let store = UserDefaultsNotesSettingsStore(defaults: storeDefaults)

        await store.setSortOldestFirst(true)

        guard let reopenedDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("UserDefaults(suiteName:) returned nil")

            return
        }

        let reopened = UserDefaultsNotesSettingsStore(defaults: reopenedDefaults)
        #expect(await reopened.sortOldestFirst() == true)
    }
}
