import Testing
import Foundation
@testable import AppFoundation

// MARK: - Fase 4 (A13): el String Catalog ES+EN existe y resuelve

@Suite("Localization")
struct LocalizationTests {
    private func localizedBundle(_ language: String) throws -> Bundle {
        let path = try #require(
            L10n.bundle.path(forResource: language, ofType: "lproj"),
            "Falta el \(language).lproj compilado del String Catalog"
        )
        return try #require(Bundle(path: path))
    }

    @Test func spanishCatalogTranslatesEveryDefaultString() throws {
        let es = try localizedBundle("es")
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
            "Close": "Cerrar"
        ]
        for (key, value) in expected {
            #expect(es.localizedString(forKey: key, value: nil, table: nil) == value)
        }
    }

    @Test func englishCatalogCoversEveryDefaultString() throws {
        let en = try localizedBundle("en")
        for key in ["Error", "OK", "Retry", "Updating…", "Nothing to show yet", "Search", "Cancel", "Back", "Close"] {
            #expect(en.localizedString(forKey: key, value: nil, table: nil) == key)
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
    }
}
