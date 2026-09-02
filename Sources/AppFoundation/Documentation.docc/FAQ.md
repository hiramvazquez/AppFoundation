# Preguntas frecuentes

## ¿Por qué `performLoad`/`performActivity` reciben el view model como parámetro, en vez de que el closure capture `self`?

Un closure que captura `self` en vez de usar el `vm` recibido puede recrear el ciclo
`self → phase → retry → work → self`: la fase `.error` guarda una acción de reintento que,
si captura `self` directamente, mantiene vivo al view model para siempre mientras la
pantalla muestra un error. Con `vm` como parámetro, nada en `work` referencia `self`, así
que soltar la última referencia externa libera el view model normalmente — y su `deinit`
cancela el trabajo en vuelo. Ver <doc:ScreenStateAndViewModels>.

## Localización: `Bundle.module` devuelve la cadena por defecto en vez de la traducida

Un `.build` stale puede tener `en.lproj`/`es.lproj` compilados de una build vieja junto al
bundle de recursos del catálogo actual (`Localizable.xcstrings`) — `Bundle.module`
encuentra los dos, y el desajuste solo se nota como una búsqueda de cadena inesperada,
nunca como un error de compilación. Un build limpio (`rm -rf .build`, o "Clean Build
Folder" en Xcode) lo resuelve; no es un bug del catálogo.

La SwiftPM CLI (`swift build`/`swift test`) no compila el `.xcstrings` a `.lproj` — envía
el catálogo crudo tal cual; Xcode sí lo compila al construir la app. Ambos caminos exponen
las mismas claves a través de `Bundle.module`.

## ¿Por qué `Debouncer`/`Throttler` son `@MainActor final class` y no `actor`?

Su estado (el `Task` pendiente, el último tiempo de ejecución) solo lo toca el llamador —
nunca dos tareas concurrentes a la vez — así que `debounce`/`throttle` corren
síncronamente en el main actor: sin `Task`, sin `await` en el call site. Un `actor` habría
forzado a cada llamada a ser `async` por una sincronización que el tipo no necesita.

## ¿Por qué `AppEnvironment` no tiene una bandera "¿esto corre bajo tests/previews?"

Detectar el test runner o Xcode Previews por heurística en código de producción es un
camino que se cuela fácilmente en lógica que debería estar inyectada. Si un test necesita
comportarse distinto, inyecta esa diferencia (un protocolo, un valor por defecto distinto)
en vez de preguntarle al entorno en qué está corriendo.

## Un `ScreenState` de solo lectura, sin acciones — ¿necesito `ActionHandling`?

No. `ScreenContainer(observing:)` y el modifier `.screen(_:chrome:)` toman un `ScreenState`
plano, sin `ActionSender` en `content`: no hay nada que enviar. Reserva `ActionHandling`
para pantallas que de verdad reciben gestos del usuario. Ver <doc:UserInterface>.

## ¿Por qué los ejemplos de código están en línea en los artículos Y también en `Snippets/`?

La directiva de DocC que referencia un fichero de `Snippets/` por ruta no se resuelve en el
**primer** `xcodebuild docbuild` sobre DerivedData limpio (la extracción de símbolos de
`Snippets/` termina después de compilar la documentación) — quien integra el paquete y
pulsa "Build Documentation" una sola vez ve artículos sin código. Cada bloque en línea va
precedido de un comentario HTML que lo asocia por nombre con su fichero en `Snippets/`, y
`Scripts/check-doc-snippets.sh` (job `docs` de CI, antes de `docbuild`) compara ese bloque
con el fichero correspondiente y falla si divergen — editar un snippet sin actualizar el
artículo (o al revés) rompe el build, no solo el code review. `Snippets/` se conserva
porque es lo único que garantiza que el ejemplo compila de verdad con `swift build`; el
bloque en línea es lo que garantiza que se ve en el primer intento.
