# CatalogApp

The "API + local" variant (`docs/ARQUITECTURA-KIT-2026-09-02.md` §1): a screen backed by both a
network call and a local cache, following the cache-then-network contract (§8, M7): show
whatever is cached immediately, refresh from the network, persist what comes back.

## Files

```
Sources/CatalogApp/
├── CatalogModule.swift            DependencyModule: builds APIService/ModelContainer, the ONLY place concrete types are named (M4)
└── Features/Catalog/
    ├── CatalogView.swift          ScreenContainer(viewModel) { send in … } — a List, send(.load) on appear
    ├── CatalogViewModel.swift     LogicViewModel<any CatalogLogicProtocol>; sequences cached()/refresh() (the M7 policy)
    ├── CatalogLogic.swift         CatalogLogicProtocol + CatalogLogic (nonisolated, M5); Item; CatalogError: DomainError (M1)
    ├── Services/
    │   └── CatalogService.swift   CatalogServicing + CatalogService: EndpointService; GetCatalogRequest (DTOs stay here, M2)
    └── Stores/
        └── CatalogStore.swift     ItemRecord (@Model, private to this file — M2) + CatalogStoring + SwiftDataCatalogStore (@ModelActor, M5)
```

`Tests/CatalogAppTests/Features/Catalog/` mirrors the same shape:
`CatalogViewModelTests.swift` (the cache-then-network POLICY, against `CatalogLogicMock`),
`CatalogLogicTests.swift` (against `CatalogServiceMock`/`InMemoryCatalogStore`),
`Services/CatalogServiceTests.swift` (against `MockAPIService`),
`Stores/CatalogStoreTests.swift` (a real, in-memory `ModelContainer`), `Mocks/`.

## The cache-then-network policy, and where each half of it lives

`CatalogLogic` exposes exactly two calls — `cached()` (never throws, `[]` if there's
nothing) and `refresh()` (throws `CatalogError` on failure) — deliberately not an
`AsyncStream`: simpler to call, simpler to test (M7). `CatalogViewModel.handle(.load)`
sequences them and owns the POLICY of what a `refresh()` failure means for the screen:

- Cache present, `refresh()` fails → a **banner** (`handleActivityError(_:strategy: .banner)`);
  content stays exactly as cached.
- Cache empty, `refresh()` fails → the error is **rethrown** from the `performLoad` work
  closure, which turns it into the screen's `.error` phase.

`CatalogViewModelTests.swift` is the test for this policy — all four combinations, against
`CatalogLogicMock` so it never depends on what `CatalogLogic` itself does with the network
or SwiftData.

## Tests, by layer

| Layer | Double | What it proves |
|---|---|---|
| `CatalogViewModel` | `CatalogLogicMock` (spy) | the four cache/refresh outcome combinations above |
| `CatalogLogic` | `CatalogServiceMock` + `InMemoryCatalogStore` | `cached()` never throws; `refresh()` persists and returns fresh items; `APIError.category` maps to the right `CatalogError` |
| `CatalogService` | `MockAPIService` | DTO → `Item` mapping, happy and error path |
| `SwiftDataCatalogStore` | none — a REAL `ModelContainer`, in-memory only | `replaceAll` is a full snapshot, not a merge |

## Arquitectura

Ver [`AGENTS.md`](../../AGENTS.md) (AppFoundation) y
[`AGENTS.md`](../../../CoreNetworking/AGENTS.md) (CoreNetworking) para las reglas
completas; este README solo recorre los ficheros de este ejemplo.
