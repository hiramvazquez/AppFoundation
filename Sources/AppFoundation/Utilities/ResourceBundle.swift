import Foundation

/// Localiza el bundle de recursos del paquete (`AppFoundation_AppFoundation.bundle`) sin
/// depender de `Bundle.module`.
///
/// ## Por qué existe
///
/// Bajo `defaultIsolation(MainActor.self)`, el accesor `Bundle.module` que sintetiza SwiftPM
/// no declaraba `nonisolated` explícitamente y quedaba implícitamente aislado a `MainActor`
/// — este paquete lee cadenas desde contextos no aislados (`L10n`, `DefaultErrorPresenter`,
/// `WrappedError`), así que un `Bundle.module` aislado no sirve. Este localizador reproduce
/// la búsqueda estándar de SwiftPM y de Xcode (bundle junto al ejecutable, en los recursos
/// del binario que contiene al módulo, en la app principal) y es `nonisolated` en cualquier
/// toolchain.
///
/// ## Verificación empírica (2026-09-04)
///
/// Antes de dar el workaround por permanente se comprobó, con un paquete mínimo fuera de
/// este repo (`defaultIsolation(MainActor.self)` + un recurso + una función `nonisolated`
/// que accede a `Bundle.module`):
///
/// - **Toolchain local (Xcode 26.6 / Swift 6.3.3)**: `resource_bundle_accessor.swift`
///   genera `static nonisolated let module`; el acceso desde `nonisolated` compila limpio.
///   El workaround YA NO hace falta con este compilador.
/// - **El error que este fichero evita** (reproducido a mano, con un accesor sin
///   `nonisolated` bajo el mismo flag `-default-isolation MainActor`):
///   ```
///   error: main actor-isolated static property 'module' can not be referenced from a
///   nonisolated context
///   ```
///   Esto coincide con el bug reportado en Swift Forums, ["Synthesized Bundle.module is
///   not usable in nonisolated code in packages with MainActor default
///   isolation"](https://forums.swift.org/t/synthesized-bundle-module-is-not-usable-in-nonisolated-code-in-packages-with-mainactor-default-isolation/84416)
///   (ene. 2026): el propio autor del bug documentó su workaround como
///   `@available(swift, deprecated: 6.3)`, es decir, el compilador de Swift 6.3 es donde
///   se reconoce corregido.
/// - **El CI de este repo** (`.github/workflows/ci.yml`, `XCODE_VERSION: latest-stable`
///   sobre `macos-15`) usaba, a fecha de esta verificación, Xcode 26.3 — Swift 6.2.x, según
///   Apple — anterior al fix (lección registrada en `docs/prd/CIERRE.md:465`, encontrada
///   de forma empírica al publicar 1.0.0). El workaround SIGUE haciendo falta ahí: no se
///   retira solo porque compile en el toolchain local.
///
/// ## Condición exacta de retirada
///
/// Cuando el Xcode que usa el job `test` de `ci.yml` traiga Swift ≥ 6.3 (comprobar con
/// `swift --version` en el paso "Versiones" de ese job, o en el log de
/// `LocalizationTests.rawBundleModuleAccessorIsNonisolatedOnThisToolchain` — ver su doc
/// comment): sustituir cada uso de `ResourceBundle.current` (`L10n.bundle`,
/// `DefaultErrorPresenter`, `WrappedError`) por `Bundle.module` directamente, y borrar este
/// fichero junto con ese test centinela.
nonisolated enum ResourceBundle {
    // R16 no aplica: `nonisolated` explícito, no hay actor del que aislarse (archlint exige
    // el modificador en la propia declaración, no basta con heredarlo del enum contenedor).
    private nonisolated final class Finder {}

    /// El bundle de recursos del paquete. Se resuelve una vez.
    static let current: Bundle = locate()

    /// Nombre del bundle que genera SwiftPM: `<paquete>_<target>.bundle`, y ambos son
    /// "AppFoundation" en `Package.swift`. Queda como literal en vez de derivarse porque
    /// derivarlo sin pasar por `Bundle.module` — justo lo que este fichero existe para
    /// evitar — añadiría la misma complejidad que se está esquivando, para un evento raro
    /// y que pasa por code review (renombrar el paquete o el target). La invariante queda
    /// anclada por dos redes en vez de por una comprobación de nombre: si algún día
    /// diverge, `LocalizationTests.resourceBundleResolvesToTheRealBundleNotTheFallback`
    /// (que exige una traducción DISTINTA de su clave, no solo "no vacía") lo detecta en
    /// CI, y `AppFoundationDiagnostics.reportNonisolatedFailure` lo detecta en runtime real.
    static let bundleName = "AppFoundation_AppFoundation.bundle"

    private static func locate() -> Bundle {
        let host = Bundle(for: Finder.self)
        return resolvedBundle(host: host, candidates: candidateDirectories(host: host))
    }

    /// Directorios donde SwiftPM y Xcode pueden colocar el bundle de recursos, en orden de
    /// preferencia. Separado de `locate()` (que además cachea el resultado una sola vez por
    /// proceso, vía `current`) para que un test pueda ejercer la lista con un `host`
    /// fabricado, sin depender del layout real del binario de test.
    static func candidateDirectories(host: Bundle) -> [URL] {
        var candidates: [URL] = [
            host.bundleURL.deletingLastPathComponent(),  // SwiftPM CLI: `.build/<config>/`
            host.bundleURL,
            Bundle.main.bundleURL
        ]
        if let resources = host.resourceURL { candidates.append(resources) }
        if let resources = Bundle.main.resourceURL { candidates.append(resources) }
        return candidates
    }

    /// Busca `bundleName` en `candidates` y, si no aparece en ninguno, reporta el fallo
    /// (`AppFoundationDiagnostics.reportNonisolatedFailure`, solo en `DEBUG`) y cae a
    /// `host`. Separado de `locate()`/`current` para que un test pueda invocarlo con un
    /// `host`/`candidates` fabricados que garanticen la rama "no encontrado", sin depender
    /// de la caché de una sola vez por proceso de `current`.
    static func resolvedBundle(host: Bundle, candidates: [URL]) -> Bundle {
        for directory in candidates {
            if let bundle = Bundle(url: directory.appendingPathComponent(bundleName)) {
                return bundle
            }
        }
        // Último recurso: el binario que contiene al módulo. Las cadenas saldrían con su
        // clave literal en vez de traducidas, pero la app no se cae — es exactamente el
        // fallo silencioso que preocupa, así que en DEBUG se reporta en voz alta en vez de
        // dejar que un usuario sea el primero en notarlo.
        AppFoundationDiagnostics.reportNonisolatedFailure(
            "ResourceBundle: no se encontró \"\(bundleName)\" en ninguno de sus directorios "
                + "candidatos (\(candidates.map(\.path))); las cadenas de AppFoundation van a "
                + "salir con su clave literal sin traducir."
        )
        return host
    }
}
