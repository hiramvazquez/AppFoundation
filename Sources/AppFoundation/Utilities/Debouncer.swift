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

    /// Execute both immediately AND after the delay.
    /// Useful when you need instant feedback plus final confirmation.
    ///
    /// Timeline: [EXECUTE]--[ignored]--[call]--------[EXECUTE]
    case both
}

/// Actor-based debouncer for rate-limiting operations.
///
/// Use this to prevent rapid-fire calls to expensive operations like
/// search filtering, API calls, or UI updates.
///
/// ## Thread Safety
/// This implementation uses Swift's actor model to ensure thread-safe
/// access to the internal task state.
///
/// ## Example - Trailing Edge (Default)
/// ```swift
/// let debouncer = Debouncer(delay: .milliseconds(300))
///
/// // In your ViewModel - executes after user stops typing
/// @Published var searchText = "" {
///     didSet {
///         Task {
///             await debouncer.debounce { [weak self] in
///                 await self?.performSearch()
///             }
///         }
///     }
/// }
/// ```
///
/// ## Example - Leading Edge
/// ```swift
/// // Execute immediately, then ignore for 1 second
/// let debouncer = Debouncer(delay: .seconds(1), edge: .leading)
///
/// func onButtonTap() {
///     Task {
///         await debouncer.debounce {
///             await self.submitForm()  // Executes immediately
///         }
///     }
/// }
/// ```
///
/// ## Example - Both Edges
/// ```swift
/// // Show immediate feedback, then update with final value
/// let debouncer = Debouncer(delay: .milliseconds(500), edge: .both)
///
/// func onSliderChange(_ value: Double) {
///     Task {
///         await debouncer.debounce {
///             await self.updatePreview(value)
///         }
///     }
/// }
/// ```
public actor Debouncer {
    private var task: Task<Void, Never>?
    private let delay: Duration
    private let edge: DebouncerEdge
    private var lastExecutionTime: ContinuousClock.Instant?
    private var pendingOperation: (@Sendable () async -> Void)?

    /// Creates a new debouncer with the specified delay and edge behavior.
    ///
    /// - Parameters:
    ///   - delay: The duration to wait before executing the operation.
    ///   - edge: When to execute the operation. Defaults to `.trailing`.
    public init(delay: Duration, edge: DebouncerEdge = .trailing) {
        self.delay = delay
        self.edge = edge
    }

    /// Creates a new debouncer with delay in milliseconds.
    ///
    /// - Parameters:
    ///   - milliseconds: The delay in milliseconds before executing.
    ///   - edge: When to execute the operation. Defaults to `.trailing`.
    public init(milliseconds: Int, edge: DebouncerEdge = .trailing) {
        self.delay = .milliseconds(milliseconds)
        self.edge = edge
    }

    /// Debounces the given operation according to the configured edge behavior.
    ///
    /// - Parameter operation: The async operation to execute.
    public func debounce(_ operation: @escaping @Sendable () async -> Void) {
        switch edge {
        case .trailing:
            debounceTrailing(operation)
        case .leading:
            debounceLeading(operation)
        case .both:
            debounceBoth(operation)
        }
    }

    private func debounceTrailing(_ operation: @escaping @Sendable () async -> Void) {
        // Cancel any pending operation
        task?.cancel()

        // Schedule new operation
        task = Task {
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await operation()
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }

    private func debounceLeading(_ operation: @escaping @Sendable () async -> Void) {
        let now = ContinuousClock.now

        // Check if we're within the cooldown period
        if let lastTime = lastExecutionTime {
            let elapsed = now - lastTime
            if elapsed < delay {
                // Still in cooldown, ignore this call
                return
            }
        }

        // Execute immediately
        lastExecutionTime = now
        Task {
            await operation()
        }
    }

    private func debounceBoth(_ operation: @escaping @Sendable () async -> Void) {
        let now = ContinuousClock.now

        // Check if we should execute leading edge
        let shouldExecuteLeading: Bool
        if let lastTime = lastExecutionTime {
            shouldExecuteLeading = (now - lastTime) >= delay
        } else {
            shouldExecuteLeading = true
        }

        if shouldExecuteLeading {
            // Execute immediately (leading edge)
            lastExecutionTime = now
            Task {
                await operation()
            }
        }

        // Store pending operation for trailing edge
        pendingOperation = operation

        // Cancel any existing trailing task
        task?.cancel()

        // Schedule trailing execution
        task = Task {
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }

                // Only execute if there's a pending operation different from the leading one
                if let pending = pendingOperation {
                    pendingOperation = nil
                    // Only execute trailing if we didn't just execute leading
                    if !shouldExecuteLeading {
                        await pending()
                    }
                }
            } catch {
                // Task was cancelled
            }
        }
    }

    /// Cancels any pending debounced operation.
    public func cancel() {
        task?.cancel()
        task = nil
        pendingOperation = nil
    }

    /// Resets the debouncer state, allowing immediate execution on next call.
    public func reset() {
        task?.cancel()
        task = nil
        lastExecutionTime = nil
        pendingOperation = nil
    }

    /// Executes the operation immediately, cancelling any pending debounce.
    ///
    /// - Parameter operation: The operation to execute immediately.
    public func executeImmediately(_ operation: @escaping @Sendable () async -> Void) async {
        task?.cancel()
        task = nil
        pendingOperation = nil
        lastExecutionTime = ContinuousClock.now
        await operation()
    }
}

// MARK: - Throttler

/// Actor-based throttler for rate-limiting operations.
///
/// Unlike Debouncer which waits for a pause in calls, Throttler ensures
/// operations execute at most once per time period.
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
public actor Throttler {
    private var lastExecutionTime: ContinuousClock.Instant?
    private let interval: Duration

    /// Creates a new throttler with the specified interval.
    ///
    /// - Parameter interval: The minimum time between executions.
    public init(interval: Duration) {
        self.interval = interval
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
        let now = ContinuousClock.now

        if let lastTime = lastExecutionTime {
            let elapsed = now - lastTime
            guard elapsed >= interval else {
                return false // Throttled
            }
        }

        lastExecutionTime = now
        await operation()
        return true
    }

    /// Resets the throttler, allowing the next operation to execute immediately.
    public func reset() {
        lastExecutionTime = nil
    }
}
