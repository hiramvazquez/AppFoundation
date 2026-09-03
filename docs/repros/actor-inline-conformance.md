# Repro: `defaultIsolation(MainActor)` + conformidad inline rompe el `init` de un `actor` con una propiedad no-`Sendable`

Repro mínimo, listo para reportar aguas arriba (swiftlang/swift). Encontrado integrando
AppFoundation desde una app real ([AppStarter](https://github.com/hiramvazquez/AppStarter),
`SessionStore.swift`); la guía para consumidores está en `AGENTS.md` (sección Store) y en
el artículo `Architecture` de DocC. Este fichero recoge el código exacto, el error exacto y
las variantes probadas.

## Entorno

```
$ swift --version
Apple Swift version 6.3.3 (swift-6.3.3-RELEASE)
Target: arm64-apple-macosx26.0
$ xcodebuild -version
Xcode 26.6
Build version 17F113
```

`swift-tools-version: 6.2`. Las `swiftSettings` son las que este paquete recomienda copiar
a cada consumidor (artículo `GettingStarted`):

```swift
// Package.swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Repro",
    platforms: [.iOS(.v17), .macOS(.v14)],
    targets: [
        .target(
            name: "Repro",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        )
    ]
)
```

## Código que falla

`Sources/Repro/SettingsStore.swift` (17 líneas, sin nada de AppFoundation):

```swift
import Foundation

protocol SettingsStoring: Sendable {
    func isEnabled() async -> Bool
}

actor UserDefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled() async -> Bool {
        defaults.bool(forKey: "enabled")
    }
}
```

## Error exacto

```
$ swift build
Building for debugging...
error: emit-module command failed with exit code 1 (use -v to see invocation)
Sources/Repro/SettingsStore.swift:11:14: error: actor-isolated property 'defaults' can not be mutated from the main actor
 6 |
 7 | actor UserDefaultsSettingsStore: SettingsStoring {
 8 |     private let defaults: UserDefaults
   |                 `- note: mutation of this property is only permitted within the actor
 9 |
10 |     init(defaults: UserDefaults = .standard) {
11 |         self.defaults = defaults
   |              `- error: actor-isolated property 'defaults' can not be mutated from the main actor
12 |     }
13 |
```

El `init` síncrono de un `actor` está, por semántica normal, aislado a la instancia que
construye; aquí el compilador lo trata como aislado al actor global por defecto
(`MainActor`) y rechaza la asignación de la propia propiedad almacenada.

`InferIsolatedConformances` (la upcoming feature que este paquete y sus consumidores
activan, variante 4 abajo) es la implementación de
[SE-0470](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0470-global-actor-isolated-conformances.md)
("Global-actor isolated conformances"): infiere el aislamiento de una conformidad de
protocolo a partir del contexto de aislamiento por defecto del módulo cuando el propio
protocolo no fija uno. La variante 4 confirma que SE-0470/`InferIsolatedConformances` NO
es la causa de este bug — el mismo error aparece sin la upcoming feature activada, solo
con `defaultIsolation(MainActor)` — así que esto no es (solo) el comportamiento que
SE-0470 describe, sino una interacción con el aislamiento del `init` síncrono del propio
`actor`.

## Variantes probadas

Cada variante es el mismo paquete con un único cambio sobre el código de arriba.

| # | Cambio | Resultado |
|---|---|---|
| 1 | Ninguno (el código de arriba) | **Falla** (error de arriba) |
| 2 | La conformidad `SettingsStoring` se declara en una `extension` separada | Compila |
| 3 | La propiedad almacenada es `Sendable` (`private var enabled: Bool`) en vez de `UserDefaults` | Compila |
| 4 | Sin `.enableUpcomingFeature("InferIsolatedConformances")` | **Falla** (mismo error) |
| 5 | `nonisolated init(defaults:)` | **Falla**: `error: 'nonisolated' on an actor's synchronous initializer is invalid` (más el error original) |
| 6 | Sin `.defaultIsolation(MainActor.self)` | Compila |
| 7 | El protocolo sin `Sendable` (`protocol SettingsStoring { … }`) | **Falla** (mismo error) |
| 8 | `nonisolated actor UserDefaultsSettingsStore: SettingsStoring` | **Falla**: `error: 'nonisolated' modifier cannot be applied to this declaration` (más el error original) |
| 9 | Sin ninguna conformidad (`actor UserDefaultsSettingsStore { … }`) | Compila |
| 10 | El protocolo declarado `nonisolated protocol SettingsStoring: Sendable` | Compila |
| 11 | Conformidad inline marcada `nonisolated` (`actor X: nonisolated SettingsStoring`) | **Falla** (mismo error) |
| 12 | `FileManager` en vez de `UserDefaults` | **Falla** (`actor-isolated property 'fileManager' can not be mutated from the main actor`) |
| 13 | La propiedad con valor por defecto en la declaración (`private let defaults = UserDefaults.standard`, sin parámetro en `init`) | Compila |

Conclusiones:

- Los tres ingredientes son `defaultIsolation(MainActor)`, una conformidad declarada **en la
  propia declaración del actor** a un protocolo del mismo módulo (que hereda el aislamiento
  por defecto), y una **propiedad almacenada no-`Sendable`** asignada en el `init`.
- `InferIsolatedConformances` no es la causa (variante 4); `Sendable` en el protocolo
  tampoco (variante 7).
- `nonisolated init` no es una salida: no está permitido en el `init` síncrono de un actor
  (variante 5).
- Salidas que compilan: la conformidad en una `extension` (2, la que usa este paquete y
  AppStarter), inyectar un valor `Sendable` (3), declarar el protocolo `nonisolated` (10),
  o no recibir la dependencia por `init` (13 — pierde la inyección, así que no sirve para
  un Store testeable).

## Por qué importa a este paquete

Un Store es «la ÚNICA capa que toca SwiftData/CoreData/UserDefaults/Keychain/FileManager»
y recibe esa dependencia por `init` para poder testearse (`UserDefaults(suiteName:)`, un
`FileManager` temporal). Las plantillas de `generate-feature --local` no lo sufren
(`@ModelActor` genera su propio `init(modelContainer:)`; `ModelContainer` es `Sendable`),
pero el primer Store sobre `UserDefaults` que alguien escribe a mano siguiendo `AGENTS.md`
cae en la variante 1. `Examples/NotesApp/Sources/NotesApp/Features/Notes/Stores/NotesSettingsStore.swift`
es el ejemplo de referencia con la variante 2.

## Reproducir

```bash
mkdir -p Repro/Sources/Repro && cd Repro
# pega Package.swift y Sources/Repro/SettingsStore.swift de arriba
swift build
```
