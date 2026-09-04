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
