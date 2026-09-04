# `deinit` aislado sintetizado + shim de back-deploy: abort en iOS 26.2

Fecha: 2026-09-04 · Detectado en el CI de AppStarter (runner `macos-15`, Xcode 26.3, simulador
iPhone 17 Pro con iOS 26.2). No se reproduce en local (Xcode 26.6, iOS 26.5).

## Síntoma

Los snapshot tests de Gallery y Uploads abortaban el proceso host (`SIGABRT`) y XCTest reiniciaba
la suite. Crash report (`.ips` del `.xcresult`):

```
libsystem_malloc  ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED
libswift_Concurrency  swift::TaskLocal::StopLookupScope::~StopLookupScope()
libswift_Concurrency  swift_task_deinitOnExecutorImpl
AppFoundation         swift_task_deinitOnExecutorMainActorBackDeploy
AppFoundation         Coordinator.__deallocating_deinit
libswiftCore          _swift_release_dealloc
GalleryFeature        GalleryViewModel.deinit
GalleryFeature        GalleryViewModel.__isolated_deallocating_deinit
libswift_Concurrency  swift_task_deinitOnExecutorImpl
GalleryFeature        swift_task_deinitOnExecutorMainActorBackDeploy
```

Dos `deinit` aislados anidados (el del ViewModel libera su `Coordinator`), ambos a través del
shim de compatibilidad que el compilador incrusta para sistemas cuyo runtime no tiene
`swift_task_deinitOnExecutor` nativo.

## Causa: el compilador sintetiza un `deinit` AISLADO cuando no hay uno explícito

Experimento con el toolchain de Xcode (`xcrun swiftc -default-isolation MainActor`, iOS 17 target):

| Clase | `deinit` | Símbolos emitidos |
|---|---|---|
| `@MainActor @Observable final class Coord { var x = 0 }` | ninguno | `__deallocating_deinit` **y `__isolated_deallocating_deinit`** |
| `@MainActor final class Sub: Base { var y = 0 }` (Base con `deinit` explícito) | ninguno propio | `__isolated_deallocating_deinit` (el de la base no cuenta) |
| `@MainActor final class WithNoop { var x = 0; deinit {} }` | explícito vacío | solo `__deallocating_deinit` |

Y la librería resultante referencia `_deinitOnExecutorMainActorBackDeploy` (el shim) para las
clases con deinit aislado. Con un `deinit {}` explícito (nonisolated por defecto), la clase no usa
el shim.

## Corrección en AppFoundation 1.2.2

`deinit {}` explícito, con el porqué, en `Coordinator`, `Container`, `Inject`, `LogicViewModel`,
`ObservingScreenState` y `BindingBackedState`; en `Templates/ViewModel.swift.txt` (cada ViewModel
generado lo lleva: la subclase necesita el suyo), en los ejemplos y en los snippets. `BaseViewModel`,
`Debouncer` y `Throttler` ya lo tenían.

## Lo que queda abierto

- No está claro si el fallo es del shim de Xcode 26.3, del runtime de iOS 26.2 o de ambos; solo se
  ha observado en esa combinación y desaparece evitando el shim. Un ViewModel escrito a mano sin
  `deinit` sigue recibiendo el aislado: regla del linter pendiente (R16) para exigirlo.
- Reportar aguas arriba con este repro.
