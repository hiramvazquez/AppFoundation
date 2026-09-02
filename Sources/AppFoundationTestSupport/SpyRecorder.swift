/// Thread-safe call recorder for hand-written spies over a `*LogicProtocol`,
/// `*Servicing` or `*Storing` conformance (`ARQUITECTURA-KIT-2026-09-02.md` §1).
///
/// A spy needs to answer two questions from a test: "was this called, and with what?".
/// `SpyRecorder` is the reusable engine for the second half — record each call's
/// arguments (or `Void`, via the `Call == Void` overload, when only the count matters)
/// from the spy's method body, and read them back from an `async` test:
///
/// ```swift
/// final class LoginLogicMock: LoginLogicProtocol {
///     let logins = SpyRecorder<String>()
///     var result: Result<Session, any Error> = .failure(CancellationError())
///
///     func login(email: String, password: String) async throws -> Session {
///         await logins.record(email)
///         return try result.get()
///     }
/// }
///
/// let mock = LoginLogicMock()
/// mock.result = .success(Session(token: "t"))
/// let viewModel = LoginViewModel(logic: mock)
///
/// viewModel.handle(.login(email: "hiram@example.com", password: "secret"))
/// await viewModel.inFlightLoad?.value
///
/// #expect(await mock.logins.calls == ["hiram@example.com"])
/// ```
///
/// `actor`, so recording from an async spy method and reading `calls` from the test body
/// never race, without a lock or `@unchecked Sendable`.
public actor SpyRecorder<Call: Sendable> {
    public private(set) var calls: [Call] = []

    public init() {}

    /// Appends `call` to the recorded history.
    public func record(_ call: Call) {
        calls.append(call)
    }

    /// Number of recorded calls.
    public var count: Int { calls.count }

    /// Whether `record` has been called at least once.
    public var wasCalled: Bool { !calls.isEmpty }

    /// Clears the recorded history.
    public func reset() {
        calls.removeAll()
    }
}

extension SpyRecorder where Call == Void {
    /// Records a call that carries no arguments — only whether, and how many times, it
    /// happened.
    public func record() {
        calls.append(())
    }
}
