import Foundation
import Testing

@testable import GenerateFeatureSupport

@Suite("ManifestEditor")
struct ManifestEditorTests {
    // MARK: - insertBetweenMarkers (Package.swift's targets:/products: archinit blocks)

    @Test("Inserts an entry right before the end marker, between the pair")
    func insertsBetweenMarkers() throws {
        let manifest = """
            let package = Package(
                targets: [
                    .target(name: "AppFoundation"),
                    // archinit:features-begin
                    // archinit:features-end
                ]
            )
            """

        let result = try ManifestEditor.insertBetweenMarkers(
            ".target(name: \"LoginFeature\"),",
            duplicateMarker: "name: \"LoginFeature\"",
            beginMarker: "// archinit:features-begin",
            endMarker: "// archinit:features-end",
            in: manifest
        )

        guard case .inserted(let newText) = result else {
            Issue.record("Expected .inserted, got \(result)")
            return
        }
        #expect(newText.contains(".target(name: \"LoginFeature\"),"))
        // The inserted line sits between the two markers, not after the closing one.
        let beginIndex = newText.range(of: "// archinit:features-begin")!.lowerBound
        let entryIndex = newText.range(of: "LoginFeature")!.lowerBound
        let endIndex = newText.range(of: "// archinit:features-end")!.lowerBound
        #expect(beginIndex < entryIndex)
        #expect(entryIndex < endIndex)
    }

    @Test("Appends after an entry inserted by a previous call, preserving order")
    func appendsInOrderAcrossCalls() throws {
        let manifest = """
            targets: [
                // archinit:features-begin
                // archinit:features-end
            ]
            """

        let afterFirst = try ManifestEditor.insertBetweenMarkers(
            ".target(name: \"ContratosFeature\"),",
            duplicateMarker: "name: \"ContratosFeature\"",
            beginMarker: "// archinit:features-begin",
            endMarker: "// archinit:features-end",
            in: manifest
        )
        guard case .inserted(let firstText) = afterFirst else {
            Issue.record("Expected .inserted")
            return
        }
        let afterSecond = try ManifestEditor.insertBetweenMarkers(
            ".target(name: \"MisCasosFeature\"),",
            duplicateMarker: "name: \"MisCasosFeature\"",
            beginMarker: "// archinit:features-begin",
            endMarker: "// archinit:features-end",
            in: firstText
        )
        guard case .inserted(let finalText) = afterSecond else {
            Issue.record("Expected .inserted")
            return
        }

        let firstIndex = finalText.range(of: "ContratosFeature")!.lowerBound
        let secondIndex = finalText.range(of: "MisCasosFeature")!.lowerBound
        #expect(firstIndex < secondIndex)
    }

    @Test("Idempotent: an entry already present between the markers is left unchanged")
    func idempotentWhenAlreadyPresent() throws {
        let manifest = """
            targets: [
                // archinit:features-begin
                .target(name: "LoginFeature"),
                // archinit:features-end
            ]
            """

        let result = try ManifestEditor.insertBetweenMarkers(
            ".target(name: \"LoginFeature\"),",
            duplicateMarker: "name: \"LoginFeature\"",
            beginMarker: "// archinit:features-begin",
            endMarker: "// archinit:features-end",
            in: manifest
        )

        #expect(result == .alreadyPresent)
    }

    @Test("Fails without markers, and touches nothing (no text is returned to write)")
    func failsWithoutMarkers() {
        let manifest = """
            let package = Package(targets: [.target(name: "AppFoundation")])
            """

        #expect(throws: ManifestEditor.EditError.markerNotFound("// archinit:features-begin")) {
            _ = try ManifestEditor.insertBetweenMarkers(
                ".target(name: \"LoginFeature\"),",
                duplicateMarker: "name: \"LoginFeature\"",
                beginMarker: "// archinit:features-begin",
                endMarker: "// archinit:features-end",
                in: manifest
            )
        }
    }

    @Test("Fails when only the begin marker is present")
    func failsWithOnlyBeginMarker() {
        let manifest = """
            targets: [
                // archinit:features-begin
            ]
            """

        #expect(throws: ManifestEditor.EditError.markerNotFound("// archinit:features-end")) {
            _ = try ManifestEditor.insertBetweenMarkers(
                ".target(name: \"LoginFeature\"),",
                duplicateMarker: "name: \"LoginFeature\"",
                beginMarker: "// archinit:features-begin",
                endMarker: "// archinit:features-end",
                in: manifest
            )
        }
    }

    @Test("Respects indentation: the inserted entry is prefixed with the end marker's own leading whitespace")
    func respectsIndentation() throws {
        let manifest = "targets: [\n        // archinit:features-begin\n        // archinit:features-end\n    ]"

        let result = try ManifestEditor.insertBetweenMarkers(
            ".target(name: \"LoginFeature\"),",
            duplicateMarker: "name: \"LoginFeature\"",
            beginMarker: "// archinit:features-begin",
            endMarker: "// archinit:features-end",
            in: manifest
        )

        guard case .inserted(let newText) = result else {
            Issue.record("Expected .inserted")
            return
        }
        #expect(newText.contains("        .target(name: \"LoginFeature\"),"))
    }

    @Test("A multi-line entry keeps its own relative indentation once shifted")
    func multiLineEntryKeepsRelativeIndentation() throws {
        let manifest = "targets: [\n        // archinit:features-begin\n        // archinit:features-end\n    ]"
        let entry = ".target(\n    name: \"LoginFeature\",\n    path: \"Sources/LoginFeature\"\n),"

        let result = try ManifestEditor.insertBetweenMarkers(
            entry,
            duplicateMarker: "name: \"LoginFeature\"",
            beginMarker: "// archinit:features-begin",
            endMarker: "// archinit:features-end",
            in: manifest
        )

        guard case .inserted(let newText) = result else {
            Issue.record("Expected .inserted")
            return
        }
        #expect(newText.contains("        .target("))
        #expect(newText.contains("            name: \"LoginFeature\","))
        #expect(newText.contains("            path: \"Sources/LoginFeature\""))
        #expect(newText.contains("        ),"))
    }

    @Test("A same-named target with a longer name (Core suffix) is not mistaken for a duplicate")
    func doesNotFalsePositiveOnLongerName() throws {
        let manifest = """
            targets: [
                // archinit:features-begin
                .target(name: "MisCasosFeatureCore"),
                .target(name: "MisCasosFeatureUI"),
                // archinit:features-end
            ]
            """

        // "MisCasosFeature" (no suffix) is NOT the same target as
        // "MisCasosFeatureCore"/"MisCasosFeatureUI" — the trailing quote in the duplicate
        // marker is what tells them apart.
        let result = try ManifestEditor.insertBetweenMarkers(
            ".target(name: \"MisCasosFeature\"),",
            duplicateMarker: "name: \"MisCasosFeature\"",
            beginMarker: "// archinit:features-begin",
            endMarker: "// archinit:features-end",
            in: manifest
        )

        #expect(result != .alreadyPresent)
    }

    // MARK: - insertBeforeMarker (App/AppModule.swift, App/AppRoute.swift)

    @Test("Inserts an entry right before a single standalone marker")
    func insertsBeforeSingleMarker() throws {
        let manifest = """
            container.register(modules: [
                AppModule(),
                // archinit:modules
            ])
            """

        let result = try ManifestEditor.insertBeforeMarker(
            "LoginModule(),",
            duplicateOf: "LoginModule()",
            marker: "// archinit:modules",
            in: manifest
        )

        guard case .inserted(let newText) = result else {
            Issue.record("Expected .inserted")
            return
        }
        #expect(newText.contains("LoginModule(),"))
        let entryIndex = newText.range(of: "LoginModule()")!.lowerBound
        let markerIndex = newText.range(of: "// archinit:modules")!.lowerBound
        #expect(entryIndex < markerIndex)
    }

    @Test("Idempotent: a case already present is left unchanged, comma or no comma")
    func idempotentBeforeMarkerIgnoresTrailingComma() throws {
        let manifest = """
            enum AppRoute: Hashable {
                case login
                // archinit:routes
            }
            """

        let result = try ManifestEditor.insertBeforeMarker(
            "case login",
            duplicateOf: "case login",
            marker: "// archinit:routes",
            in: manifest
        )

        #expect(result == .alreadyPresent)
    }

    @Test("Fails without the marker")
    func failsWithoutSingleMarker() {
        let manifest = "enum AppRoute: Hashable {}"

        #expect(throws: ManifestEditor.EditError.markerNotFound("// archinit:routes")) {
            _ = try ManifestEditor.insertBeforeMarker(
                "case login",
                duplicateOf: "case login",
                marker: "// archinit:routes",
                in: manifest
            )
        }
    }

    @Test("Respects indentation from the marker line for a single-marker insert")
    func respectsIndentationBeforeMarker() throws {
        let manifest = "enum AppRoute: Hashable {\n    // archinit:routes\n}"

        let result = try ManifestEditor.insertBeforeMarker(
            "case login",
            duplicateOf: "case login",
            marker: "// archinit:routes",
            in: manifest
        )

        guard case .inserted(let newText) = result else {
            Issue.record("Expected .inserted")
            return
        }
        #expect(newText.contains("    case login"))
        #expect(!newText.contains("        case login"))
    }

    // MARK: - insertListElementBeforeMarker (App/AppModule.swift's array of modules)

    @Test("A list whose last element has a trailing comma keeps that style")
    func listElementAfterTrailingComma() throws {
        let appModule = """
            [
                PlatformModule(),
                // archinit:modules
            ]
            """

        let result = try ManifestEditor.insertListElementBeforeMarker(
            "LoginModule()",
            duplicateOf: "LoginModule()",
            marker: "// archinit:modules",
            in: appModule
        )

        #expect(
            result
                == .inserted(
                    """
                    [
                        PlatformModule(),
                        LoginModule(),
                        // archinit:modules
                    ]
                    """
                )
        )
    }

    @Test("A list without trailing comma: the old last element gets its separator, the new one none")
    func listElementWithoutTrailingComma() throws {
        let appModule = """
            [
                SettingsModule(baseURL: apiBaseURL),
                CartModule()
                // archinit:modules
            ]
            """

        let result = try ManifestEditor.insertListElementBeforeMarker(
            "try NotesModule()",
            duplicateOf: "NotesModule(",
            marker: "// archinit:modules",
            in: appModule
        )

        #expect(
            result
                == .inserted(
                    """
                    [
                        SettingsModule(baseURL: apiBaseURL),
                        CartModule(),
                        try NotesModule()
                        // archinit:modules
                    ]
                    """
                )
        )
    }

    @Test("The separator goes before a trailing comment, and blank or comment lines above the marker are skipped")
    func listElementSkipsCommentsAndKeepsTrailingComment() throws {
        let appModule = """
            [
                ImageModule(url: "https://example.com") // último

                // más abajo, las features
                // archinit:modules
            ]
            """

        let result = try ManifestEditor.insertListElementBeforeMarker(
            "LoginModule()",
            duplicateOf: "LoginModule()",
            marker: "// archinit:modules",
            in: appModule
        )

        #expect(
            result
                == .inserted(
                    """
                    [
                        ImageModule(url: "https://example.com"), // último

                        // más abajo, las features
                        LoginModule()
                        // archinit:modules
                    ]
                    """
                )
        )
    }

    @Test("An empty list gets the element with a trailing comma; an existing one is left alone")
    func listElementEmptyListAndDuplicate() throws {
        let empty = "[\n    // archinit:modules\n]"
        let inserted = try ManifestEditor.insertListElementBeforeMarker(
            "LoginModule()",
            duplicateOf: "LoginModule()",
            marker: "// archinit:modules",
            in: empty
        )
        #expect(inserted == .inserted("[\n    LoginModule(),\n    // archinit:modules\n]"))

        let present = "[\n    LoginModule()\n    // archinit:modules\n]"
        let again = try ManifestEditor.insertListElementBeforeMarker(
            "LoginModule()",
            duplicateOf: "LoginModule()",
            marker: "// archinit:modules",
            in: present
        )
        #expect(again == .alreadyPresent)
    }

    // MARK: - insertImport (App/AppModule.swift, App/RootView.swift)

    @Test("Inserts the import in order inside the block, not after the blank line above the marker")
    func insertsImportInOrderAboveBlankLineAndMarker() throws {
        let source = """
            import AppFoundation
            import GalleryFeatureUI
            import SwiftUI

            // archinit:imports

            struct RootView {}
            """

        let result = try ManifestEditor.insertImport("PruebaModFeatureUI", marker: "// archinit:imports", in: source)

        #expect(
            result
                == .inserted(
                    """
                    import AppFoundation
                    import GalleryFeatureUI
                    import PruebaModFeatureUI
                    import SwiftUI

                    // archinit:imports

                    struct RootView {}
                    """
                )
        )
    }

    @Test("Inserts the import in order when the marker sits right below the block")
    func insertsImportInOrderRightAboveMarker() throws {
        let source = "import AppFoundation\nimport SwiftUI\n// archinit:imports\n"

        let result = try ManifestEditor.insertImport("ContratosFeature", marker: "// archinit:imports", in: source)

        #expect(
            result == .inserted("import AppFoundation\nimport ContratosFeature\nimport SwiftUI\n// archinit:imports\n")
        )
    }

    @Test("A module that sorts last goes right after the last import, keeping the blank line before the marker")
    func insertsImportAfterLastImport() throws {
        let source = "import AppFoundation\nimport SwiftUI\n\n// archinit:imports"

        let result = try ManifestEditor.insertImport("ZonasFeature", marker: "// archinit:imports", in: source)

        #expect(result == .inserted("import AppFoundation\nimport SwiftUI\nimport ZonasFeature\n\n// archinit:imports"))
    }

    @Test("Compares like OrderedImports: code-point order, uppercase before lowercase")
    func insertsImportInCodePointOrder() throws {
        let source = "import GalleryFeature\nimport lowercaseKit\n// archinit:imports"

        let result = try ManifestEditor.insertImport("GalleryFeatureUI", marker: "// archinit:imports", in: source)

        #expect(
            result
                == .inserted("import GalleryFeature\nimport GalleryFeatureUI\nimport lowercaseKit\n// archinit:imports")
        )
    }

    @Test("Without imports above the marker, the import goes right before it")
    func insertsImportBeforeMarkerWithoutImportBlock() throws {
        let source = "// Header comment\n\n// archinit:imports\nenum AppModule {}"

        let result = try ManifestEditor.insertImport("ContratosFeature", marker: "// archinit:imports", in: source)

        #expect(
            result == .inserted("// Header comment\n\nimport ContratosFeature\n// archinit:imports\nenum AppModule {}")
        )
    }

    @Test("Idempotent: an import already present is left unchanged")
    func insertImportIsIdempotent() throws {
        let source = "import AppFoundation\nimport ContratosFeature\n\n// archinit:imports"

        let result = try ManifestEditor.insertImport("ContratosFeature", marker: "// archinit:imports", in: source)

        #expect(result == .alreadyPresent)
    }

    @Test("Fails without the imports marker")
    func insertImportFailsWithoutMarker() {
        #expect(throws: ManifestEditor.EditError.markerNotFound("// archinit:imports")) {
            _ = try ManifestEditor.insertImport("ContratosFeature", marker: "// archinit:imports", in: "import SwiftUI")
        }
    }
    // MARK: - existingPluginLiteral

    @Test("Finds and collapses an existing plugin literal to one line")
    func findsExistingPluginLiteral() {
        let manifest = """
            .target(
                name: "SomeFeature",
                plugins: [
                    .plugin(
                        name: "SwiftLintBuildToolPlugin",
                        package: "SwiftLintPlugins"
                    )
                ]
            )
            """

        let literal = ManifestEditor.existingPluginLiteral(named: "SwiftLintBuildToolPlugin", in: manifest)

        #expect(literal == ".plugin( name: \"SwiftLintBuildToolPlugin\", package: \"SwiftLintPlugins\" )")
    }

    @Test("Returns nil when the plugin isn't declared anywhere in the manifest")
    func returnsNilWhenPluginMissing() {
        let manifest = ".target(name: \"SomeFeature\")"

        #expect(ManifestEditor.existingPluginLiteral(named: "SwiftLintBuildToolPlugin", in: manifest) == nil)
    }
}

@Suite("ManifestEditor.moduleInitExpression")
struct ModuleInitExpressionTests {
    @Test("api + local: baseURL and try")
    func apiLocal() {
        let src = "public init(baseURL: URL, modelContainer: ModelContainer? = nil) throws {"
        #expect(
            ManifestEditor.moduleInitExpression(
                feature: "MisCasos",
                moduleSource: src,
                baseURLExpression: "AppModule.apiBaseURL"
            )
                == "try MisCasosModule(baseURL: AppModule.apiBaseURL)"
        )
    }

    @Test("api only: baseURL, no try")
    func apiOnly() {
        let src = "public init(baseURL: URL) {"
        #expect(
            ManifestEditor.moduleInitExpression(
                feature: "Contratos",
                moduleSource: src,
                baseURLExpression: "AppModule.apiBaseURL"
            )
                == "ContratosModule(baseURL: AppModule.apiBaseURL)"
        )
    }

    @Test("local only: try, no baseURL")
    func localOnly() {
        let src = "public init(modelContainer: ModelContainer? = nil) throws {"
        #expect(
            ManifestEditor.moduleInitExpression(feature: "Notas", moduleSource: src, baseURLExpression: "x")
                == "try NotasModule()"
        )
    }

    @Test("no data: plain init")
    func none() {
        #expect(
            ManifestEditor.moduleInitExpression(
                feature: "Contador",
                moduleSource: "public init() {}",
                baseURLExpression: "x"
            ) == "ContadorModule()"
        )
    }
}
