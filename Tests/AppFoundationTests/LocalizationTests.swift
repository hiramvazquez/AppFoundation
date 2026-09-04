import Foundation
import Testing

@testable import AppFoundation

// MARK: - Fase 4 (A13): el String Catalog ES+EN existe y resuelve
// MARK: - AF-21: Localizable.xcstrings sustituye a los .strings por lproj

/// Reads a translated value for `key`/`language` regardless of which build system
/// produced `Bundle.module`.
///
/// Xcode's build system (`xcodebuild`) compiles `Resources/Localizable.xcstrings`
/// into `en.lproj`/`es.lproj` and drops the source catalog from the bundle. The
/// SwiftPM CLI (`swift build`/`swift test`) does not run that compilation step —
/// as of this toolchain it copies `Localizable.xcstrings` into the bundle verbatim
/// (see `PRD-AF-03.md`). Both are legitimate outputs of the same source catalog, so
/// this helper tries the compiled `.lproj` first and falls back to reading the raw
/// catalog's JSON directly — the tests stay green under either build system instead
/// of asserting a compilation step that is outside this package's control.
private func localizedValue(forKey key: String, language: String) throws -> String {
    if let lprojPath = L10n.bundle.path(forResource: language, ofType: "lproj"),
        let compiled = Bundle(path: lprojPath)
    {
        return compiled.localizedString(forKey: key, value: nil, table: nil)
    }

    let url = try #require(
        L10n.bundle.url(forResource: "Localizable", withExtension: "xcstrings"),
        "Ni \(language).lproj compilado ni Localizable.xcstrings sin compilar: falta el catálogo"
    )
    let data = try Data(contentsOf: url)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(json["strings"] as? [String: Any])
    let entry = try #require(strings[key] as? [String: Any], "\"\(key)\" no está en el catálogo")
    let localizations = try #require(entry["localizations"] as? [String: Any])
    let localization = try #require(
        localizations[language] as? [String: Any],
        "Falta la localización \"\(language)\" de \"\(key)\""
    )
    let stringUnit = try #require(localization["stringUnit"] as? [String: Any])
    return try #require(stringUnit["value"] as? String)
}

@Suite("Localization")
struct LocalizationTests {
    @Test func spanishCatalogTranslatesEveryDefaultString() throws {
        let expected: [String: String] = [
            "Error": "Error",
            "OK": "OK",
            "Retry": "Reintentar",
            "Updating…": "Actualizando…",
            "Nothing to show yet": "Nada que mostrar todavía",
            "The operation succeeded, but there is no content to display.":
                "La operación se completó, pero no hay contenido que mostrar.",
            "Search": "Buscar",
            "Cancel": "Cancelar",
            "Back": "Atrás",
            "Close": "Cerrar",
            "Something went wrong. Please try again.": "Algo ha ido mal. Inténtalo de nuevo.",
            "Dismiss": "Descartar"
        ]
        for (key, value) in expected {
            #expect(try localizedValue(forKey: key, language: "es") == value)
        }
    }

    @Test func englishCatalogCoversEveryDefaultString() throws {
        for key in [
            "Error", "OK", "Retry", "Updating…", "Nothing to show yet", "Search", "Cancel", "Back", "Close",
            "Something went wrong. Please try again.", "Dismiss"
        ] {
            #expect(try localizedValue(forKey: key, language: "en") == key)
        }
    }

    // MARK: - AF-11: ResourceBundle no debe caer en silencio a su bundle de fallback

    /// `ResourceBundle.current` cae a `Bundle(for: Finder.self)` (el binario que contiene
    /// al módulo, sin recursos) cuando no encuentra `AppFoundation_AppFoundation.bundle` en
    /// ninguno de sus candidatos — y entonces cualquier `String(localized:bundle:)` devuelve
    /// su clave literal sin traducir, en silencio. Un `#expect(!texto.isEmpty)` no
    /// distinguiría ese fallback de una traducción real (la clave nunca está vacía). Lo que
    /// SÍ lo distingue es una traducción cuyo valor DIFIERE de su clave en algún idioma: el
    /// fallback nunca puede producir ese valor porque nunca localiza nada. Se usa español
    /// (el inglés coincide con la clave para casi todos los strings del paquete, así que no
    /// serviría como prueba) para que el resultado no dependa del idioma del runner.
    @Test func resourceBundleResolvesToTheRealBundleNotTheFallback() throws {
        // 1) El bundle encontrado es el real, no el binario de fallback (que tendría otro
        //    nombre: el del target de test o el propio módulo, nunca el del paquete).
        #expect(L10n.bundle.bundleURL.lastPathComponent == ResourceBundle.bundleName)

        // 2) Y localiza de verdad: la traducción difiere de la clave.
        let search = try localizedValue(forKey: "Search", language: "es")
        #expect(search == "Buscar")
        #expect(
            search != "Search",
            "Si esto fuera \"Search\", ResourceBundle.current habría caído al bundle de fallback"
        )
    }

    /// Independiente del idioma del runner (el simulador puede correr en español):
    /// los defaults deben resolver a un valor del catálogo de CUALQUIER idioma
    /// soportado. La completitud por idioma la fijan los dos tests de arriba.
    @Test func packageDefaultsResolveThroughTheCatalog() {
        #expect(["Error"].contains(L10n.error))
        #expect(["OK"].contains(L10n.ok))
        #expect(["Search", "Buscar"].contains(L10n.search))
        #expect(["Back", "Atrás"].contains(L10n.back))
        #expect(["Close", "Cerrar"].contains(L10n.close))
        #expect(
            [
                "Something went wrong. Please try again.",
                "Algo ha ido mal. Inténtalo de nuevo."
            ]
            .contains(L10n.genericErrorMessage)
        )
    }
}
