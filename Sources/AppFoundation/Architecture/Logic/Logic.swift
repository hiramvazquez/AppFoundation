/// Marker protocol every `XxxLogic` conforms to (`ARQUITECTURA-KIT-2026-09-02.md` §1-2).
///
/// `Logic` carries no requirements on purpose: the architecture this package encodes is
/// View → ViewModel → Logic → Services/Stores, where a `Logic` type holds ALL of a
/// screen's business logic and a `ViewModel` only orchestrates between the view and its
/// `Logic` — it never talks to a `*Service`/`*Store` or to networking/persistence
/// directly. `Logic` exists so:
///
/// - A generator (`swift package generate-feature`, PRD-AF-08) and a linter
///   (`ArchitectureLint`, PRD-AF-08) can recognize "this type is a Logic" without any
///   naming convention alone doing the work.
/// - A human or an agent reading `XxxLogic: XxxLogicProtocol, Logic` sees the intent
///   documented at the declaration, not only in a README.
///
/// `AnyObject`, not `Sendable`: a `Logic` is owned by exactly one `@MainActor` view model
/// (through `LogicViewModel<L>.logic`, held as a `let`) and is never shared or resolved
/// from a `nonisolated` context — the same isolation `BaseViewModel`/`Container` already
/// assume throughout this package. A `Logic` implementation is typically declared
/// `final class`, which conforms to `AnyObject` for free.
///
/// ## Shape
///
/// ```swift
/// protocol LoginLogicProtocol: Logic {
///     func login(email: String, password: String) async throws -> Session
/// }
///
/// final class LoginLogic: LoginLogicProtocol {
///     private let loginService: any LoginServicing
///     private let sessionStore: any SessionStoring
///
///     init(loginService: any LoginServicing, sessionStore: any SessionStoring) {
///         self.loginService = loginService
///         self.sessionStore = sessionStore
///     }
///
///     func login(email: String, password: String) async throws -> Session {
///         let session = try await loginService.login(email: email, password: password)
///         await sessionStore.save(session)
///         return session
///     }
/// }
/// ```
///
/// A `Logic`'s dependencies always arrive through `init` as protocols (`any
/// XxxServicing`, `any XxxStoring`) — never as concrete `Service`/`Store` types, and
/// never as SwiftUI/UIKit imports: a `Logic` has no view-layer concerns and is testable
/// with service/store mocks alone, no view model involved.
public protocol Logic: AnyObject {}
