# LoginApp

The "solo API" variant (`docs/ARQUITECTURA-KIT-2026-09-02.md` §1): a screen backed entirely by
a network call, no local persistence beyond the session token. Replaces the former
`Examples/IntegrationExample` — still the proof that AppFoundation and CoreNetworking
compose without friction, now built through the full View → ViewModel → Logic
→ Service/Store stack instead of a `BaseViewModel` calling `APIServiceProtocol` directly.
`Package.swift` resolves both dependencies by looking at where it is: inside the `spm-pro`
monorepo, CoreNetworking is a sibling directory and is used through `path:`, so this proof
runs against the working tree of each package rather than against whatever CoreNetworking
version last got tagged; in the published AppFoundation repository that sibling does not
exist and the same manifest falls back to the released version by URL. One manifest, both
places, no substitution step at publish time.

## Files

```
Sources/LoginApp/
├── AppErrorPresenter.swift        ErrorPresenting: DomainError → ScreenError (never APIError, M1)
├── AppCancellationRecognizer.swift CancellationRecognizing: understands APIError.isCancellation
│                                  AND LoginError.cancelled — the seam a consumer of BOTH
│                                  AppFoundation and CoreNetworking has to wire up itself
├── AppSessionState.swift          SessionExpiring + the @Observable a root view watches (M6)
├── LoginModule.swift              DependencyModule: the ONLY place concrete types are named (M4)
└── Features/Login/
    ├── LoginView.swift            ScreenContainer(viewModel) { send in … } + a preview over MockAPIService
    ├── LoginViewModel.swift       LogicViewModel<any LoginLogicProtocol>, ActionHandling
    ├── LoginLogic.swift           LoginLogicProtocol + LoginLogic (nonisolated, M5); Session; LoginError: DomainError (M1)
    ├── Services/
    │   └── LoginService.swift     LoginServicing + LoginService: EndpointService; LoginRequest: BaseRequest (DTOs stay here, M2);
    │                              makeAPIService(...) — bearer auth, refresh-on-401, logout-on-refresh-failure (M6)
    └── Stores/
        └── SessionStore.swift     SessionStoring + SessionStore (actor) — the session token, read by BearerTokenInterceptor
```

`Tests/LoginAppTests/Features/Login/` mirrors the same shape: `LoginViewModelTests.swift`
(against `LoginLogicMock`), `LoginLogicTests.swift` (against `LoginServiceMock`/
`SessionStoreSpy`), `Services/LoginServiceTests.swift` (against `MockAPIService` and
`InMemoryTransport`), `Mocks/` (one mock/spy per protocol).

## The four things worth reading in order

1. **`LoginView.swift`** — the piece an integrator copies first: `ScreenContainer` bound
   to `LoginViewModel`, `send(.login)`, a preview wired to `MockAPIService`.
2. **`LoginViewModel.swift`** — pure orchestration: `handle(_:)` calls `logic.login`,
   updates `email`/`password`/`session`. Never imports CoreNetworking.
3. **`LoginLogic.swift`** — ALL the business logic: local validation (empty
   email/password), calls `LoginServicing`, persists the session via `SessionStoring`, and
   is the ONE place `APIError` becomes `LoginError` (`DomainError`, M1) — nothing past this
   file ever sees `APIError`. Cancellation gets its own case, `LoginError.cancelled` — never
   `.unknown` — precisely because it stops being an `APIError` right here.
4. **`Services/LoginService.swift`** — the ONE type that touches `APIServiceProtocol`/
   `BaseRequest`; `makeAPIService(...)` is the production wiring: bearer token from
   `SessionStoring`, refresh-on-401, and — when the refresh itself fails — invalidates the
   session and notifies `SessionExpiring` so the app can log the user out globally (M6).
5. **`AppCancellationRecognizer.swift`** — AppFoundation's `DefaultCancellationRecognizer`
   only knows `CancellationError`/`URLError(.cancelled)`; it can't know about
   `CoreNetworking.APIError` (AppFoundation doesn't depend on CoreNetworking) or about this
   feature's own `LoginError.cancelled`. Any app combining both packages needs one of these,
   registered as `BaseViewModel.cancellationRecognizer` — see `LoginModule.swift`'s doc
   comment for where a real `@main` would do it.

## Tests, by layer

| Layer | Double | What it proves |
|---|---|---|
| `LoginViewModel` | `LoginLogicMock` (spy) | `handle(.login)` calls `logic.login` with the current fields; `.content`/`.error` follow the result |
| `LoginLogic` | `LoginServiceMock` + `SessionStoreSpy` | validation short-circuits before the service; a success persists the session; `APIError.category` maps to the right `LoginError`, including `.cancelled` (never `.unknown`) |
| `LoginViewModel` (integration) | real `LoginLogic` + `LoginServiceMock` + `AppCancellationRecognizer` | a cancelled `APIError` from the service never reaches `phase == .error` |
| `LoginService` | `MockAPIService` | request/response mapping, happy and error path |
| `LoginService` (pipeline) | `InMemoryTransport` + `ManualClock` | 401 → refresh → 200 with the new token; a failed refresh invalidates the session and notifies `SessionExpiring`, with no extra request (POST is non-idempotent) |

No test sleeps or polls — every async assertion awaits `inFlightLoad` (ViewModel level) or
the `Task`/`async let` the call already returns.

## Arquitectura

Ver [`AGENTS.md`](../../AGENTS.md) (AppFoundation) y
[`AGENTS.md`](../../../CoreNetworking/AGENTS.md) (CoreNetworking) para las reglas
completas; este README solo recorre los ficheros de este ejemplo.
