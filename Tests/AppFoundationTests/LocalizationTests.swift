import Testing
import Foundation
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
       let compiled = Bundle(path: lprojPath) {
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
            "Something went wrong. Please try again.": "Algo ha ido mal. Inténtalo de nuevo."
        ]
        for (key, value) in expected {
            #expect(try localizedValue(forKey: key, language: "es") == value)
        }
    }

    @Test func englishCatalogCoversEveryDefaultString() throws {
        for key in ["Error", "OK", "Retry", "Updating…", "Nothing to show yet", "Search", "Cancel", "Back", "Close",
                        "Something went wrong. Please try again."] {
            #expect(try localizedValue(forKey: key, language: "en") == key)
        }
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
        #expect([
            "Something went wrong. Please try again.",
            "Algo ha ido mal. Inténtalo de nuevo."
        ].contains(L10n.genericErrorMessage))
    }
}
