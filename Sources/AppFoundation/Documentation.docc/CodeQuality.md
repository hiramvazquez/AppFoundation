# Calidad de código

SwiftLint con una configuración curada, instalada por `archinit`, junto a `ArchitectureLint`.
Tres capas, cada una con su herramienta; nosotros solo mantenemos el criterio.

## Overview

Las reglas de arquitectura son nuestras porque no las conoce ninguna herramienta:
`ArchitectureLint` (<doc:Lint>) valida DÓNDE está el código. Todo lo demás (`try!`, casts y
desempaquetados forzados, `[unowned]`, tamaños, complejidad, idioms) exige un parser real de
Swift y años de depuración de falsos positivos: eso es SwiftLint. Reescribirlo sería mantener
un parser con cada versión de Swift para llegar peor. Lo que sí es nuestro es el criterio: qué
bloquea, qué avisa, con qué umbrales, y que se instale en un paso.

| Capa | Herramienta | Valida | Quién la mantiene |
|---|---|---|---|
| Arquitectura | `ArchitectureLint` / `archlint` | DÓNDE está el código (R1-R12) | este paquete |
| Calidad | SwiftLint + `.swiftlint.yml` curado | CÓMO está escrito | SwiftLint; aquí solo la configuración |
| Concurrencia y warnings | el compilador (Swift 6, `SWIFT_STRICT_WARNINGS=1`) | Sendable, aislamiento, data races | Apple |

Los ciclos de retención reales no los detecta ningún linter (requieren análisis semántico entre
ficheros): las reglas cubren los patrones típicos (`weak_delegate`, `unowned_variable_capture`)
y el resto lo cazan los tests de fugas (`weak var` + `#expect(vm == nil)`, ver <doc:Testing>).

## Instalación

`swift package --allow-writing-to-package-directory archinit` deja `.swiftlint.yml` en la raíz
del proyecto (si ya existe, no lo pisa) e imprime los pasos manuales:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.65.0")
],
targets: [
    .target(
        name: "MiAppKit",
        plugins: [
            .plugin(name: "ArchitectureLint", package: "AppFoundation"),
            .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
        ]
    )
]
```

El plugin descarga el binario de SwiftLint como artefacto y lo ejecuta en cada build, igual que
`ArchitectureLint`: un `try!` en un ViewModel rompe el build con un diagnóstico navegable en
Xcode (`error: Force Try Violation … (force_try)`). En CI, `--strict` promueve los avisos a
error:

```bash
brew install swiftlint
swiftlint lint --strict Sources Tests
```

## Qué bloquea y qué avisa

La configuración usa `only_rules` explícito: una versión nueva de SwiftLint no activa reglas sin
que lo decidamos. Cada regla lleva en el propio fichero el porqué.

**Bloquean (`error`)**, porque esconden un crash o una fuga: `force_try`, `force_cast`,
`force_unwrapping`, `implicitly_unwrapped_optional`, `unowned_variable_capture`,
`weak_delegate`, `unhandled_throwing_task`, `self_in_property_initialization`,
`private_swiftui_state` (la View es dueña de su ViewModel con `@State private`, ver
<doc:Architecture>), `duplicate_imports`, `fatal_error_message`.

**Avisan (`warning`)**, y solo bloquean en CI con `--strict`:

| Regla | Aviso | Error |
|---|---|---|
| `function_body_length` | 50 líneas | 100 |
| `type_body_length` | 250 | 400 |
| `file_length` | 400 (sin contar comentarios) | 600 |
| `cyclomatic_complexity` | 10 (sin contar `case`) | 20 |
| `line_length` | 120 (ignora comentarios, URLs e interpolaciones) | 160 |
| `function_parameter_count` | 6 | 8 |
| `large_tuple` | 2 | 3 |
| `nesting` | tipos 2, funciones 3 | |

Y los idioms: `identifier_name` (con `c` y `vm` excluidos: `{ c in c.resolve() }` en los
Modules y `performLoad { vm in … }` son la convención del kit), `todo`,
`void_function_in_ternary`, `legacy_swiftui_aspect_ratio`, `empty_count`, `first_where`,
`toggle_bool`, `accessibility_label_for_image`, `accessibility_trait_for_button`, y el resto
que está en el fichero.

**Reglas propias** (`custom_rules`, expresiones regulares, sin código): `no_print_in_production`
(`print(` fuera de tests) y `os_log_public_interpolation` (`privacy: .public` exige un
comentario que lo justifique). Añadir una regla del equipo es añadir un bloque así:

```yaml
custom_rules:
  no_hardcoded_api_host:
    regex: 'https://api\.'
    excluded: '.*(Tests|Mocks)/.*'
    message: "La URL base viene de NetworkingConfiguration, no de un literal."
    severity: warning
```

## Excepciones

Una excepción se documenta en el sitio, no bajando el umbral para todos:

```swift
// Composition root: the seven collaborators are injected explicitly on purpose (DI by init,
// no hidden globals); grouping them in a struct would only move the same seven names.
// swiftlint:disable:next function_parameter_count
func makeAuthenticatedAPIService(
```

## Calibración

Los umbrales se fijaron contra código real (AppStarter: seis features generadas por el kit y
completadas a mano) antes de convertirse en plantilla: 53 avisos con las reglas por defecto,
63 con la primera versión curada, 0 tras clasificar cada uno. Tres reglas se descartaron con
motivo, anotado en el fichero:

- `async_without_await`: en esta arquitectura el `async` viene del protocolo
  (`Servicing`/`Storing`/`Logic`); mocks, actores y previews lo implementan sin `await` por
  contrato. 32 falsos positivos.
- `closure_body_length`: los `body` de SwiftUI con `ScreenContainer { send in … }` son closures
  de 30-40 líneas por naturaleza; `type_body_length` y `function_body_length` ya acotan.
- Una regla propia para `Text("literal")` sin localizar: premisa falsa, `Text("literal")` YA es
  `LocalizedStringKey`; lo no localizable es `Text(verbatim:)` o `Text(variable)`.

Los umbrales de tamaño y complejidad no se tensaron con ese código: quedan en los valores de la
tabla hasta que un proyecto real los tense. El generador y los cuatro ejemplos pasan la
configuración sin avisos, y CI lo comprueba (`Scripts/verify-generator.sh`, job `quality`).

## Ver también

- <doc:Lint> — la otra capa: las reglas de arquitectura R1-R12.
- <doc:Generator> — el cascarón que ya cumple ambas.
- [AppStarter](https://github.com/hiramvazquez/AppStarter) — `docs/INFORME-CALIDAD.md`, la calibración con salidas reales.
