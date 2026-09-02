import Foundation
import os

/// A `Clock<Duration>` that only advances when the test tells it to.
///
/// Inject it wherever this package accepts `any Clock<Duration>` —
/// `BaseViewModel(clock:)` (a banner's auto-dismiss), `Debouncer`/`Throttler`, or a
/// `Logic`/`Store` a feature declares its own `Clock` dependency for — so a test asserts
/// *behavior* (did the timer fire, after how long was it requested) instead of measuring
/// wall time: no `Task.sleep` on the real clock, no flakiness under CI load.
///
/// ## Example — drive a banner's auto-dismiss to completion
/// ```swift
/// let clock = ManualClock()
/// let viewModel = SomeViewModel(clock: clock)
///
/// viewModel.showBanner(.success("Saved", duration: .seconds(3)))
/// await clock.waitUntilSleeping()   // the dismiss task reached its sleep
/// clock.advance(by: .seconds(3))    // fires it — not async
/// #expect(viewModel.banner == nil)
/// ```
///
/// This is the same type CoreNetworkingTestSupport ships (`RetryPolicy`/`APIService`
/// tests use it for backoff) — duplicated here, not shared, because AppFoundation does
/// not depend on CoreNetworking and neither package should depend on the other just to
/// share a test double.
///
/// `@unchecked Sendable` JUSTIFICADO: all mutable state (the clock and its waiters) lives
/// behind `OSAllocatedUnfairLock`; there is no access without the lock.
public final class ManualClock: Clock, @unchecked Sendable {
    public struct Instant: InstantProtocol {
        fileprivate var offset: Duration

        public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
        public static func == (lhs: Instant, rhs: Instant) -> Bool { lhs.offset == rhs.offset }

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }
    }

    private struct Waiter {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var waiters: [Waiter] = []
        var watchers: [CheckedContinuation<Void, Never>] = []
        var nextID = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public var now: Instant { state.withLock { $0.now } }

    public var minimumResolution: Duration { .zero }

    /// Deadlines of every `sleep(until:)` currently pending, in registration order.
    /// Useful to inspect what delay the caller actually requested
    /// (`clock.now.duration(to: deadline)`) before deciding how much to `advance(by:)`.
    public var pendingDeadlines: [Instant] {
        state.withLock { $0.waiters.map(\.deadline) }
    }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()

        let id = state.withLock { s -> Int? in
            guard deadline > s.now else { return nil }
            s.nextID += 1
            return s.nextID
        }
        guard let id else { return }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let watchersToWake: [CheckedContinuation<Void, Never>] = state.withLock { s in
                    guard deadline > s.now else {
                        continuation.resume()
                        return []
                    }
                    s.waiters.append(Waiter(id: id, deadline: deadline, continuation: continuation))
                    let watchers = s.watchers
                    s.watchers.removeAll()
                    return watchers
                }
                for watcher in watchersToWake { watcher.resume() }
            }
        } onCancel: {
            let cancelled = state.withLock { s -> CheckedContinuation<Void, Error>? in
                guard let index = s.waiters.firstIndex(where: { $0.id == id }) else { return nil }
                return s.waiters.remove(at: index).continuation
            }
            cancelled?.resume(throwing: CancellationError())
        }
    }

    /// Advances the clock by `duration` and resumes every sleeper whose deadline is now
    /// due, in deadline order.
    ///
    /// Does NOT wait for the resumed task to make progress — call `waitUntilSleeping()`
    /// afterwards if you need to synchronize with its next `sleep(until:)`.
    public func advance(by duration: Duration) {
        let ready = state.withLock { s -> [Waiter] in
            s.now = s.now.advanced(by: duration)
            let due = s.waiters.filter { $0.deadline <= s.now }
            s.waiters.removeAll { $0.deadline <= s.now }
            return due.sorted { $0.deadline < $1.deadline }
        }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }

    /// Suspends (no real waiting: a continuation resumed the instant a sleeper
    /// registers) until at least one `sleep(until:)` is pending.
    ///
    /// Call it before `advance(by:)` to avoid the race of advancing before the
    /// operation under test reached its backoff/timer.
    public func waitUntilSleeping() async {
        while true {
            let alreadyWaiting = state.withLock { !$0.waiters.isEmpty }
            if alreadyWaiting { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let stillNeeded = state.withLock { s -> Bool in
                    guard s.waiters.isEmpty else { return false }
                    s.watchers.append(continuation)
                    return true
                }
                if !stillNeeded { continuation.resume() }
            }
        }
    }
}
