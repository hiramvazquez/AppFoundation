import Foundation
@testable import AppFoundation

/// Polls `condition` until it is true or `timeout` elapses.
///
/// Transitional helper while `performLoad`/`performActivity` are fire-and-forget;
/// Phase 3 makes them return their `Task` and callers await it deterministically.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() && clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Simple error with a stable message for asserting error propagation.
nonisolated struct TestError: Error, LocalizedError, Equatable {
    let message: String
    init(_ message: String = "Test error") { self.message = message }
    var errorDescription: String? { message }
}
