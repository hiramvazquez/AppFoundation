# CounterApp

The "sin datos" variant (`docs/ARQUITECTURA-KIT-2026-09-02.md` §1): a screen whose `Logic`
depends on nothing — no `Service`, no `Store` — because the feature genuinely has no data
to fetch or persist. `Logic` still exists as its own type: the rule "increment by one"
belongs there, not in the `ViewModel`, exactly like every other variant.

## Files

```
Sources/CounterApp/
├── CounterModule.swift            DependencyModule: the ONLY place CounterLogic is named (M4)
└── Features/Counter/
    ├── CounterView.swift          ScreenContainer(viewModel) { send in … } + a preview
    ├── CounterViewModel.swift     LogicViewModel<any CounterLogicProtocol>, ActionHandling
    └── CounterLogic.swift         CounterLogicProtocol + CounterLogic (nonisolated, pure — M5)
```

`Tests/CounterAppTests/Features/Counter/` mirrors the same shape:
`CounterViewModelTests.swift` (against `CounterLogicMock`), `CounterLogicTests.swift`
(the real `CounterLogic`, no double needed — it has no collaborators), `Mocks/`.

## Why a Logic for three one-line rules?

Because "sin datos" describes what `Logic` depends on, not whether it has rules worth
isolating. `CounterLogic.increment`/`decrement`/`reset` are one-liners today; the type
still exists so a rule that grows ("never go below zero", "step configured in Settings")
lands in the same place every other feature's business logic lives, tested the same way —
never inside `CounterViewModel`, which stays pure orchestration regardless of how simple or
complex the underlying rule is.

## Tests, by layer

| Layer | Double | What it proves |
|---|---|---|
| `CounterViewModel` | `CounterLogicMock` (spy, plain properties — `CounterLogicProtocol` is synchronous) | `handle(.increment)` calls `logic.increment(count)` and stores whatever it returns |
| `CounterLogic` | none — no collaborators | `increment`/`decrement`/`reset` do what they say |

## Arquitectura

Ver [`AGENTS.md`](../../AGENTS.md) para las reglas completas; este README solo recorre los
ficheros de este ejemplo.
