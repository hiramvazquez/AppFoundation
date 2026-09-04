import Foundation

/// Determines when the debounced operation should execute.
public nonisolated enum DebouncerEdge: Sendable {
    /// Execute after the delay period passes with no new calls (default).
    /// The LAST call within the period will be executed.
    ///
    /// Timeline: [call]--[call]--[call]--------[EXECUTE]
    case trailing

    /// Execute immediately on first call, then ignore subsequent calls
    /// until the delay period passes.
    ///
    /// Timeline: [EXECUTE]--[ignored]--[ignored]--------[ready]
    case leading

    /// Execute immediately AND, if more calls arrive within the window,
    /// execute the last of them after the delay.
    ///
    /// Timeline: [EXECUTE]--[call]--[call]--------[EXECUTE last]
    case both
}

// MARK: - Clock helpers

/// Measures elapsed time on an `any Clock<Duration>`.
///
/// The existential hides the clock's `Instant`, so instants cannot be stored or
/// compared through it. Opening the existential once captures a typed origin; from
/// then on "now" is a `Duration` since that origin — enough for cooldown windows.
private nonisolated struct ClockStopwatch: Sendable {
    private let elapsed: @Sendable () -> Duration

    init(_ clock: any Clock<Duration>) {
        self.init(opening: clock)
    }

    private init(opening clock: some Clock<Duration>) {
        let origin = clock.now
        elapsed = { origin.duration(to: clock.now) }
    }

    /// Time elapsed on the clock since the stopwatch was created.
    var now: Duration { elapsed() }
}

// MARK: - Debouncer

/// Main-actor debouncer for rate-limiting operations.
///
/// Use it to coalesce rapid-fire calls to expensive work — filtering, network
/// requests, layout updates — from code that is not a SwiftUI view (view models,
/// coordinators). For a search field inside a view, prefer SwiftUI's own
/// `.task(id: query) { try await Task.sleep(for: .milliseconds(300)); … }`: it
/// cancels itself when the query changes and needs no extra type.
///
/// ## Why a `@MainActor` class and not an actor (audit AF-19)
///
/// The debouncer's state is only ever touched by its owner, which is almost always
/// main-actor code. Modelling it as an `actor` bought no useful isolation and
/// taxed every call site: `Task { await debouncer.debounce { … } }`, a `@Sendable`
/// operation, and a further hop back to the main actor to touch the owner's state.
/// As a `@MainActor` class the call is synchronous and the operation runs on the
/// main actor, so a view model can write `debouncer.debounce { self.query = … }`
/// with no `Task`, no `await`, and no `@Sendable`.
///
/// ## Clock
///
/// The clock is injectable: production uses `ContinuousClock` (the default); tests
/// inject a manual clock and advance time deterministically — no real sleeps. It is
/// typed as `any Clock<Duration>` so a stored property reads `let debouncer: Debouncer`
/// instead of `Debouncer<ContinuousClock>`.
///
/// ## Lifetime
///
/// A pending operation is retained until it runs, is cancelled, or the debouncer is
/// deallocated (`deinit` cancels in-flight work). If the operation captures its owner
/// strongly, the owner lives for at most `delay` longer than it otherwise would; use
/// `[weak self]` when that matters.
///
/// ## Example - Trailing Edge (Default)
/// ```swift
/// @MainActor final class SearchViewModel {
///     private let debouncer = Debouncer(delay: .milliseconds(300))
///     var results: [Item] = []
///
///     func queryChanged(_ query: String) {
///         debouncer.debounce { [weak self] in
///             self?.results = await self?.repository.search(query) ?? []
///         }
///     }
/// }
/// ```
///
/// ## Example - Leading Edge
/// ```swift
/// // Execute immediately, then ignore for 1 second
/// let debouncer = Debouncer(delay: .seconds(1), edge: .leading)
/// ```
@MainActor
public final class Debouncer {
    private let clock: any Clock<Duration>
    private let stopwatch: ClockStopwatch
    private let delay: Duration
    private let edge: DebouncerEdge

    /// Pending trailing execution.
    private var trailingTask: Task<Void, Never>?

    /// In-flight leading execution — tracked so `cancel()` can actually cancel it.
    private var leadingTask: Task<Void, Never>?

    /// Last time an operation EXECUTED (leading or trailing — trailing counts too).
    private var lastExecutionTime: Duration?

    private var pendingOperation: (@MainActor () async -> Void)?

    /// Creates a debouncer.
    ///
    /// - Parameters:
    ///   - delay: The duration to wait before executing the operation.
    ///   - edge: When to execute the operation. Defaults to `.trailing`.
    ///   - clock: The clock used for delays and cooldown measurement. Defaults to
    ///     `ContinuousClock`; tests inject a manual clock.
    public init(
        delay: Duration,
        edge: DebouncerEdge = .trailing,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.delay = delay
        self.edge = edge
        self.clock = clock
        self.stopwatch = ClockStopwatch(clock)
    }

    deinit {
        trailingTask?.cancel()
        leadingTask?.cancel()
    }

    /// Debounces the given operation according to the configured edge behavior.
    ///
    /// - Parameter operation: The operation to execute, on the main actor.
    public func debounce(_ operation: @escaping @MainActor () async -> Void) {
        switch edge {
        case .trailing:
            debounceTrailing(operation)
        case .leading:
            _ = executeLeadingIfReady(operation)
        case .both:
            debounceBoth(operation)
        }
    }

    private func debounceTrailing(_ operation: @escaping @MainActor () async -> Void) {
        trailingTask?.cancel()
        trailingTask = Task { [weak self, clock, delay] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return  // Cancelled: nothing to run.
            }
            guard let self, !Task.isCancelled else { return }
            lastExecutionTime = stopwatch.now
            await operation()
        }
    }

    /// Executes on the leading edge when outside the cooldown window.
    /// - Returns: `true` if the operation was started.
    private func executeLeadingIfReady(_ operation: @escaping @MainActor () async -> Void) -> Bool {
        if let lastTime = lastExecutionTime, stopwatch.now - lastTime < delay {
            return false  // Still in cooldown.
        }

        lastExecutionTime = stopwatch.now
        leadingTask = Task {
            await operation()
        }
        return true
    }

    private func debounceBoth(_ operation: @escaping @MainActor () async -> Void) {
        let executedLeading = executeLeadingIfReady(operation)

        // Only calls that did NOT run on the leading edge become the trailing candidate.
        pendingOperation = executedLeading ? nil : operation

        trailingTask?.cancel()
        trailingTask = Task { [weak self, clock, delay] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return  // Cancelled: nothing to run.
            }
            guard let self, !Task.isCancelled, let pending = pendingOperation else { return }
            pendingOperation = nil
            lastExecutionTime = stopwatch.now
            await pending()
        }
    }

    /// Cancels any pending or in-flight debounced operation — leading included.
    public func cancel() {
        trailingTask?.cancel()
        trailingTask = nil
        leadingTask?.cancel()
        leadingTask = nil
        pendingOperation = nil
    }

    /// Resets the debouncer state, allowing immediate execution on next call.
    public func reset() {
        cancel()
        lastExecutionTime = nil
    }

    /// Executes the operation immediately, cancelling any pending debounce.
    ///
    /// - Parameter operation: The operation to execute immediately.
    public func executeImmediately(_ operation: @MainActor () async -> Void) async {
        cancel()
        lastExecutionTime = stopwatch.now
        await operation()
    }
}

// MARK: - Throttler

/// Main-actor throttler for rate-limiting operations.
///
/// Unlike `Debouncer`, which waits for a pause in calls, `Throttler` ensures
/// operations execute at most once per interval. Same design as `Debouncer`
/// (audit AF-19): a `@MainActor` class instead of an actor, so the call site needs
/// no `Task`, no `@Sendable`, and the operation runs on the main actor; the clock
/// is injectable for deterministic tests.
///
/// ## Example
/// ```swift
/// let throttler = Throttler(interval: .seconds(1))
///
/// // Will execute at most once per second
/// for _ in 0..<100 {
///     await throttler.throttle {
///         print("Executed")
///     }
/// }
/// ```
@MainActor
public final class Throttler {
    // Explicit, nonisolated on purpose (R16): without it the compiler synthesizes an isolated
    // deinit that goes through a back-deploy shim on older OS versions — the exact frame
    // under `GalleryViewModel.deinit` in the iOS 26.2 abort. Nothing to cancel here.
    deinit {}

    private let stopwatch: ClockStopwatch
    private let interval: Duration
    private var lastExecutionTime: Duration?

    /// Creates a throttler.
    ///
    /// - Parameters:
    ///   - interval: The minimum time between executions.
    ///   - clock: The clock used to measure the interval. Defaults to
    ///     `ContinuousClock`; tests inject a manual clock.
    public init(interval: Duration, clock: any Clock<Duration> = ContinuousClock()) {
        self.interval = interval
        self.stopwatch = ClockStopwatch(clock)
    }

    /// Throttles the given operation.
    ///
    /// The operation will only execute if enough time has passed
    /// since the last execution.
    ///
    /// - Parameter operation: The operation to execute, on the main actor.
    /// - Returns: `true` if the operation was executed, `false` if throttled.
    @discardableResult
    public func throttle(_ operation: @MainActor () async -> Void) async -> Bool {
        if let lastTime = lastExecutionTime, stopwatch.now - lastTime < interval {
            return false  // Throttled
        }

        lastExecutionTime = stopwatch.now
        await operation()
        return true
    }

    /// Resets the throttler, allowing the next operation to execute immediately.
    public func reset() {
        lastExecutionTime = nil
    }
}
