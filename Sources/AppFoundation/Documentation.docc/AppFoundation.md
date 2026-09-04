# ``AppFoundation``

Base para apps SwiftUI nuevas: estado de pantalla, navegación, inyección de dependencias,
shell de UI y la arquitectura View → ViewModel → Logic → Services/Stores.

## Overview

AppFoundation da a cada pantalla la misma forma: un `BaseViewModel` con fases (`idle`,
`loading`, `content`, `empty`, `error`), un contrato `ActionHandling` con un único punto de
entrada (`handle(_:)`), un `Container` de inyección de dependencias `@MainActor`, un
`Coordinator` para navegación por pila y deep links, y `ScreenContainer` como cáscara de UI
(barra de navegación, alertas, banners, indicadores de carga).

Sobre esa base, el paquete añade un kit de arquitectura completo: `Logic` y
`LogicViewModel<L>` separan la orquestación de pantalla de la lógica de negocio,
`DomainError` fija cómo cruza un error de capa a capa, y dos plugins de SwiftPM
(`generate-feature` y `ArchitectureLint`) generan el cascarón de un feature y hacen
fallar el build si alguien se sale de la arquitectura.

Compila con Swift 6.2 en modo `defaultIsolation(MainActor)`, sin dependencias externas.
`AppFoundation` (el `enum` vacío que da nombre al módulo) no tiene API propia — es solo el
punto de referencia de este catálogo.

## Topics

### Empieza aquí

- <doc:GettingStarted>
- <doc:Architecture>
- <doc:MultiModule>

### Estado de pantalla

- <doc:ScreenStateAndViewModels>

### Errores

- <doc:ErrorHandling>

### Navegación

- <doc:Navigation>

### Inyección de dependencias

- <doc:DependencyInjection>

### UI

- <doc:UserInterface>
- <doc:Theming>

### Utilidades

- <doc:Utilities>

### Generador y linter

- <doc:Generator>
- <doc:Lint>
- <doc:CodeQuality>

### Recetas y testing

- <doc:Recipes>
- <doc:Testing>
- <doc:FAQ>
