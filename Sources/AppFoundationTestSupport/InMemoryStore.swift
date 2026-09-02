/// A generic, in-memory `actor` store for testing `Logic` types that depend on a
/// `*Storing` protocol (`ARQUITECTURA-KIT-2026-09-02.md` §1-2 — a "solo local" or
/// "API + local" app's `Logic` takes `any XxxStoring` through `init`; its tests need a
/// fast, deterministic double for that protocol, without SwiftData or a `ModelContainer`).
///
/// `InMemoryStore` is not a `*Store` itself: a real feature declares its own `XxxStoring`
/// protocol and its own implementations (`SwiftDataNotesStore` for production,
/// `InMemoryNotesStore` for tests — see `AppFoundation/Examples/NotesApp`). This type is
/// the reusable dictionary-backed engine a hand-written in-memory `*Store` wraps, keyed
/// however that feature's store finds most natural (an ID, a compound key).
///
/// ```swift
/// final class InMemoryNotesStore: NotesStoring {
///     private let storage = InMemoryStore<UUID, Note>()
///
///     func save(_ note: Note) async { await storage.set(note.id, note) }
///     func fetchAll() async -> [Note] { await storage.values() }
///     func delete(_ id: UUID) async { await storage.remove(id) }
/// }
/// ```
///
/// `actor`, not a lock-protected class: a `*Store` is typically called from `async`
/// `Logic` methods already, so actor isolation costs nothing extra at the call site and
/// needs no `@unchecked Sendable` justification.
public actor InMemoryStore<Key: Hashable & Sendable, Value: Sendable> {
    private var storage: [Key: Value] = [:]
    private var insertionOrder: [Key] = []

    public init() {}

    /// The value for `key`, or `nil` if absent.
    public func get(_ key: Key) -> Value? {
        storage[key]
    }

    /// Inserts or replaces the value for `key`. Preserves the original insertion
    /// position on replace, so `values()` stays stable for list-rendering tests.
    public func set(_ key: Key, _ value: Value) {
        if storage[key] == nil {
            insertionOrder.append(key)
        }
        storage[key] = value
    }

    /// Removes `key`, returning the value that was stored there, if any.
    @discardableResult
    public func remove(_ key: Key) -> Value? {
        insertionOrder.removeAll { $0 == key }
        return storage.removeValue(forKey: key)
    }

    /// Removes every stored value.
    public func removeAll() {
        storage.removeAll()
        insertionOrder.removeAll()
    }

    /// Every stored value, in insertion order.
    public func values() -> [Value] {
        insertionOrder.compactMap { storage[$0] }
    }

    /// Number of stored key/value pairs.
    public var count: Int { storage.count }

    /// Whether `key` currently has a stored value.
    public func contains(_ key: Key) -> Bool {
        storage[key] != nil
    }
}
