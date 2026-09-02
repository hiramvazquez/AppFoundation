import Foundation

@testable import AppFoundation

/// Simple error with a stable message for asserting error propagation.
nonisolated struct TestError: Error, LocalizedError, Equatable {
    let message: String
    init(_ message: String = "Test error") { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - TestClock (reloj manual para tests deterministas — C13)

/// Manual clock: time only moves when the test calls `advance(by:)`.
/// Sleepers registered with `sleep(until:)` wake when the deadline is reached,
/// and resume throwing `CancellationError` when their task is cancelled.
nonisolated final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol, Hashable, Sendable {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    // @unchecked Sendable: todo acceso a _now/sleepers pasa por `lock`.
    private let lock = NSLock()
    private var _now = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []

    var now: Instant { lock.withLock { _now } }
    var minimumResolution: Duration { .zero }

    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let resumeNow: Bool = lock.withLock {
                    if deadline <= _now { return true }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            let cancelled: CheckedContinuation<Void, any Error>? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index).continuation
            }
            cancelled?.resume(throwing: CancellationError())
        }
    }

    /// Advances time, waking every sleeper whose deadline is reached.
    func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock {
            _now = _now.advanced(by: duration)
            let ready = sleepers.filter { $0.deadline <= _now }
            sleepers.removeAll { $0.deadline <= _now }
            return ready.sorted { $0.deadline < $1.deadline }
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    /// Yields until `count` sleepers are registered — the code under test must reach
    /// its `clock.sleep` before the test advances time.
    func waitForSleepers(_ count: Int = 1) async {
        while sleeperCount < count { await Task.yield() }
    }
}

/// Thread-safe event recorder for operations running off the test's actor.
nonisolated final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []

    var events: [String] { lock.withLock { _events } }
    var count: Int { events.count }

    func record(_ event: String) {
        lock.withLock { _events.append(event) }
    }
}

/// Spins (yield-first, tiny real sleeps as fallback) until `condition` holds.
nonisolated func spin(until condition: @Sendable () -> Bool) async {
    for _ in 0..<10_000 where !condition() {
        await Task.yield()
    }
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while !condition() && clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}
