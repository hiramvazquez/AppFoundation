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

/// Actor-based debouncer for rate-limiting operations.
///
/// Use this to prevent rapid-fire calls to expensive operations like
/// search filtering, API calls, or UI updates.
///
/// The clock is injectable (C13): production uses `ContinuousClock` through the
/// convenience initializers; tests inject a manual clock and advance time
/// deterministically — no real sleeps.
///
/// ## Example - Trailing Edge (Default)
/// ```swift
/// let debouncer = Debouncer(delay: .milliseconds(300))
///
/// func searchTextChanged() {
///     Task {
///         await debouncer.debounce { [weak self] in
///             await self?.performSearch()
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
public actor Debouncer<C: Clock> where C.Duration == Duration {
    private let clock: C
    private let delay: Duration
    private let edge: DebouncerEdge

    /// Pending trailing execution.
    private var trailingTask: Task<Void, Never>?

    /// In-flight leading execution — tracked so `cancel()` can actually cancel it (C13).
    private var leadingTask: Task<Void, Never>?

    /// Last time an operation EXECUTED (leading or trailing — C13: trailing counts too).
    private var lastExecutionTime: C.Instant?

    private var pendingOperation: (@Sendable () async -> Void)?

    /// Creates a debouncer with an explicit clock.
    ///
    /// - Parameters:
    ///   - delay: The duration to wait before executing the operation.
    ///   - edge: When to execute the operation. Defaults to `.trailing`.
    ///   - clock: The clock used for delays and cooldown measurement.
    public init(delay: Duration, edge: DebouncerEdge = .trailing, clock: C) {
        self.delay = delay
        self.edge = edge
        self.clock = clock
    }

    /// Debounces the given operation according to the configured edge behavior.
    ///
    /// - Parameter operation: The async operation to execute.
    public func debounce(_ operation: @escaping @Sendable () async -> Void) {
        switch edge {
        case .trailing:
            debounceTrailing(operation)
        case .leading:
            _ = executeLeadingIfReady(operation)
        case .both:
            debounceBoth(operation)
        }
    }

    private func debounceTrailing(_ operation: @escaping @Sendable () async -> Void) {
        trailingTask?.cancel()
        trailingTask = Task {
            do {
                try await clock.sleep(for: delay)
                guard !Task.isCancelled else { return }
                lastExecutionTime = clock.now
                await operation()
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }

    /// Executes on the leading edge when outside the cooldown window.
    /// - Returns: `true` if the operation was started.
    private func executeLeadingIfReady(_ operation: @escaping @Sendable () async -> Void) -> Bool {
        if let lastTime = lastExecutionTime, lastTime.duration(to: clock.now) < delay {
            return false // Still in cooldown.
        }

        lastExecutionTime = clock.now
        leadingTask = Task {
            await operation()
        }
        return true
    }

    private func debounceBoth(_ operation: @escaping @Sendable () async -> Void) {
        let executedLeading = executeLeadingIfReady(operation)

        // Only calls that did NOT run on the leading edge become the trailing candidate.
        pendingOperation = executedLeading ? nil : operation

        trailingTask?.cancel()
        trailingTask = Task {
            do {
                try await clock.sleep(for: delay)
                guard !Task.isCancelled else { return }
                if let pending = pendingOperation {
                    pendingOperation = nil
                    lastExecutionTime = clock.now
                    await pending()
                }
            } catch {
                // Task was cancelled
            }
        }
    }

    /// Cancels any pending or in-flight debounced operation — leading included (C13).
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
    public func executeImmediately(_ operation: @escaping @Sendable () async -> Void) async {
        cancel()
        lastExecutionTime = clock.now
        await operation()
    }
}

public extension Debouncer where C == ContinuousClock {
    /// Creates a new debouncer with the specified delay and edge behavior.
    ///
    /// - Parameters:
    ///   - delay: The duration to wait before executing the operation.
    ///   - edge: When to execute the operation. Defaults to `.trailing`.
    init(delay: Duration, edge: DebouncerEdge = .trailing) {
        self.init(delay: delay, edge: edge, clock: ContinuousClock())
    }

    /// Creates a new debouncer with delay in milliseconds.
    ///
    /// - Parameters:
    ///   - milliseconds: The delay in milliseconds before executing.
    ///   - edge: When to execute the operation. Defaults to `.trailing`.
    init(milliseconds: Int, edge: DebouncerEdge = .trailing) {
        self.init(delay: .milliseconds(milliseconds), edge: edge, clock: ContinuousClock())
    }
}

// MARK: - Throttler

/// Actor-based throttler for rate-limiting operations.
///
/// Unlike Debouncer which waits for a pause in calls, Throttler ensures
/// operations execute at most once per time period. The clock is injectable
/// for deterministic tests.
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
public actor Throttler<C: Clock> where C.Duration == Duration {
    private var lastExecutionTime: C.Instant?
    private let interval: Duration
    private let clock: C

    /// Creates a throttler with an explicit clock.
    ///
    /// - Parameters:
    ///   - interval: The minimum time between executions.
    ///   - clock: The clock used to measure the interval.
    public init(interval: Duration, clock: C) {
        self.interval = interval
        self.clock = clock
    }

    /// Throttles the given operation.
    ///
    /// The operation will only execute if enough time has passed
    /// since the last execution.
    ///
    /// - Parameter operation: The async operation to execute.
    /// - Returns: `true` if the operation was executed, `false` if throttled.
    @discardableResult
    public func throttle(_ operation: @escaping @Sendable () async -> Void) async -> Bool {
        if let lastTime = lastExecutionTime, lastTime.duration(to: clock.now) < interval {
            return false // Throttled
        }

        lastExecutionTime = clock.now
        await operation()
        return true
    }

    /// Resets the throttler, allowing the next operation to execute immediately.
    public func reset() {
        lastExecutionTime = nil
    }
}

public extension Throttler where C == ContinuousClock {
    /// Creates a new throttler with the specified interval.
    ///
    /// - Parameter interval: The minimum time between executions.
    init(interval: Duration) {
        self.init(interval: interval, clock: ContinuousClock())
    }
}
