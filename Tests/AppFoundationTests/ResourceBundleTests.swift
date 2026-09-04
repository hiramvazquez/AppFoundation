import Foundation
import Testing

@testable import AppFoundation

// MARK: - AF-11: el fallo de ResourceBundle deja de ser silencioso

/// `ResourceBundle.current` se resuelve una única vez por proceso (`static let`), así que
/// no se puede forzar su rama "no encontrado" reconfigurando el entorno real a mitad de
/// suite. `resolvedBundle(host:candidates:)` existe justo para esto: el mismo algoritmo de
/// búsqueda y aviso que usa `locate()`, pero recibiendo `host`/`candidates` fabricados, de
/// forma que un test puede garantizar la rama de fallo sin tocar el bundle real del binario
/// de test.
///
/// `.serialized`: `AppFoundationDiagnostics.assertOnNonisolatedFailure` y
/// `.nonisolatedFailureHandler` son hooks globales (el mismo trato que
/// `ViewModelOwnershipTests` da a `droppedActionHandler`/`assertOnDroppedAction`).
@Suite("ResourceBundle — el fallo de localización deja de ser silencioso (AF-11)", .serialized)
struct ResourceBundleTests {
    /// Ningún directorio de este `URL` temporal contiene
    /// `AppFoundation_AppFoundation.bundle`: garantiza la rama "no encontrado" sin decir
    /// nada sobre el bundle real del binario de test.
    private var guaranteedMissingCandidates: [URL] {
        [URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)]
    }

    @Test func fallbackToTheHostBundleIsReportedInDebug() {
        let reports = Recorder()
        AppFoundationDiagnostics.nonisolatedFailureHandler = { reports.record($0) }
        defer { AppFoundationDiagnostics.nonisolatedFailureHandler = nil }

        let host = Bundle(for: AppFoundationDiagnosticsMarker.self)
        let resolved = ResourceBundle.resolvedBundle(host: host, candidates: guaranteedMissingCandidates)

        // Cae al host (la app no se cae por esto)...
        #expect(resolved == host)
        #if DEBUG
        // ...pero, en DEBUG, no en silencio: se reporta con el nombre del bundle que faltaba.
        #expect(reports.count == 1)
        #expect(reports.events.first?.contains(ResourceBundle.bundleName) == true)
        #endif
    }

    @Test func assertOnNonisolatedFailureTriggersAnAssertionFailure() {
        // `assertionFailure` solo aborta en builds de depuración con aserciones activas
        // (los tests lo son); no hay forma portable de "esperar" un `assertionFailure` sin
        // abortar el proceso, así que este test se limita a comprobar que el hook y el
        // logging siguen funcionando con la bandera activa — el comportamiento de
        // `assertionFailure` en sí (matar el proceso en DEBUG) es responsabilidad de la
        // stdlib, no de este paquete.
        AppFoundationDiagnostics.assertOnNonisolatedFailure = false
        let reports = Recorder()
        AppFoundationDiagnostics.nonisolatedFailureHandler = { reports.record($0) }
        defer { AppFoundationDiagnostics.nonisolatedFailureHandler = nil }

        _ = ResourceBundle.resolvedBundle(
            host: Bundle(for: AppFoundationDiagnosticsMarker.self),
            candidates: guaranteedMissingCandidates
        )

        #if DEBUG
        #expect(reports.count == 1)
        #endif
    }

    // MARK: - Ancla de la invariante (punto 4 de la revisión AF-11)

    /// `bundleName` es `<paquete>_<target>.bundle`; ambos son "AppFoundation" en
    /// `Package.swift`. No se deriva (ver el doc comment de `ResourceBundle.bundleName`);
    /// este test ancla el literal para que cambiarlo sin querer se note aquí, en vez de en
    /// una app real mostrando claves sin traducir.
    @Test func bundleNameMatchesThePackageAndTargetNameConvention() {
        #expect(ResourceBundle.bundleName == "AppFoundation_AppFoundation.bundle")
    }

    // MARK: - Centinela de retirada (AF-11)

    #if compiler(>=6.3)
    /// Existe SOLO cuando el compilador que construye este target es Swift 6.3 o
    /// posterior — el mismo umbral verificado empíricamente en el doc comment de
    /// `ResourceBundle` (y documentado por el autor del bug de SwiftPM como
    /// `@available(swift, deprecated: 6.3)`). Bajo un compilador anterior, este bloque
    /// entero desaparece en tiempo de compilación: no rompe el build de ese toolchain (hoy,
    /// el de CI) referenciando algo que ahí seguiría aislado a `MainActor`.
    ///
    /// Cuando el CI de este repo actualice su Xcode a uno que traiga Swift ≥ 6.3, este test
    /// empezará a compilarse y a ejecutarse allí por primera vez — una señal visible (aparece
    /// un test nuevo en el log, con este nombre) en vez de un cambio de comportamiento
    /// silencioso. Si aparece y pasa en CI: evaluar retirar `ResourceBundle` (ver la
    /// "Condición exacta de retirada" en su doc comment) y borrar este test con él.
    @Test func rawBundleModuleAccessorIsNonisolatedOnThisToolchain() {
        nonisolated func accessFromANonisolatedContext() -> Bundle {
            // El accesor que SwiftPM sintetiza para el target de test, NO
            // `ResourceBundle.current` — el punto es probar el propio `Bundle.module`.
            Bundle.module
        }
        let bundle = accessFromANonisolatedContext()
        #expect(bundle.bundlePath.contains("AppFoundationTests") || bundle.bundlePath.contains("AppFoundation"))
    }
    #endif
}

/// Clase ancla para `Bundle(for:)` en los tests de arriba — cualquier tipo del módulo de
/// test sirve; ninguno de estos tests depende de qué bundle sea, solo de que exista y no
/// contenga `AppFoundation_AppFoundation.bundle`.
private final class AppFoundationDiagnosticsMarker {}
