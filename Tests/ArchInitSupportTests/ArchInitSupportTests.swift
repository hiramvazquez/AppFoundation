import Foundation
import Testing

@testable import ArchInitSupport

/// Unit tests for `archinit --multi`'s (PRD-AF-10) pure content builders. `plugin.swift`
/// itself has no direct unit tests — `PackagePlugin.PluginContext` can't be constructed
/// outside a real plugin invocation — so this is what actually exercises the generated
/// `Package.swift`/`.archlint.yml`/`AGENTS.md` content and the markers the other PRD-AF-10
/// agents parse (`archinit:features-begin`/`end`, `archinit:products-begin`/`end`,
/// `archinit:modules`, `archinit:routes`, the `.archlint.yml` `modules:` section). The
/// end-to-end path (a real `swift package archinit --multi`, `swift build`/`swift test`
/// on the generated packages, `xcodebuild` on the generated app) is the manual
/// integration test documented in the PRD-AF-10 report — this suite is the fast,
/// deterministic layer under it.
@Suite("ArchInitSupport (PRD-AF-10)")
struct ArchInitSupportTests {
    // MARK: - Naming

    @Test("pascalCase uppercases only the first letter")
    func pascalCaseUppercasesFirstLetter() {
        #expect(ArchInitSupport.pascalCase("camera") == "Camera")
        #expect(ArchInitSupport.pascalCase("Camera") == "Camera")
        #expect(ArchInitSupport.pascalCase("") == "")
    }

    @Test("dedupPascalCase removes case-insensitive-by-casing duplicates, keeping order")
    func dedupPascalCaseDeduplicatesPreservingOrder() {
        let result = ArchInitSupport.dedupPascalCase(["camera", "Location", "Camera", "location"])
        #expect(result == ["Camera", "Location"])
    }

    @Test("displayPath strips the root prefix")
    func displayPathStripsRoot() {
        let root = URL(fileURLWithPath: "/tmp/DemoMulti")
        let file = root.appendingPathComponent("App/AppRoute.swift")
        #expect(ArchInitSupport.displayPath(file, root: root) == "App/AppRoute.swift")
    }

    // MARK: - Packages/Features/Package.swift (the marker contract other PRD-AF-10 agents rely on)

    @Test("Features/Package.swift carries both marker pairs at the documented indentation")
    func featuresPackageSwiftHasBothMarkerPairs() {
        let contents = ArchInitSupport.buildFeaturesPackageSwift()
        #expect(contents.contains("        // archinit:features-begin\n        // archinit:features-end"))
        #expect(contents.contains("        // archinit:products-begin\n        // archinit:products-end"))
        // Both marker pairs sit inside their respective 4-space-indented arrays.
        #expect(contents.contains("    products: [\n        // archinit:products-begin"))
        #expect(contents.contains("    targets: [\n        // archinit:features-begin"))
        #expect(contents.contains(".package(path: \"../Platform\")"))
    }

    @Test("Features/Package.swift depends on AppFoundation, CoreNetworking, and Platform")
    func featuresPackageSwiftDeclaresExpectedDependencies() {
        let contents = ArchInitSupport.buildFeaturesPackageSwift()
        #expect(contents.contains("AppFoundation.git"))
        #expect(contents.contains("CoreNetworking.git"))
        #expect(contents.contains(".package(path: \"../Platform\")"))
    }

    // MARK: - Packages/Platform/Package.swift

    @Test("buildPlatformPackageSwift with no capabilities/adapters still declares Domain + DomainTests, nothing else")
    func platformPackageSwiftWithNothingExtra() {
        let contents = ArchInitSupport.buildPlatformPackageSwift(capabilities: [], adapters: [])
        #expect(contents.contains(".library(name: \"Domain\", targets: [\"Domain\"])"))
        #expect(contents.contains("name: \"DomainTests\""))
        // Exactly one product (Domain) and no Firebase SDK dependency — no Kit/Adapter noise.
        let productLines = contents.components(separatedBy: "\n").filter { $0.contains(".library(name:") }
        #expect(productLines.count == 1)
        #expect(!contents.contains("firebase-ios-sdk"))
    }

    @Test("buildPlatformPackageSwift adds one product and target per capability")
    func platformPackageSwiftPerCapability() {
        let contents = ArchInitSupport.buildPlatformPackageSwift(capabilities: ["Camera", "Location"], adapters: [])
        #expect(contents.contains(".library(name: \"CameraKit\", targets: [\"CameraKit\"])"))
        #expect(contents.contains(".library(name: \"LocationKit\", targets: [\"LocationKit\"])"))
        #expect(contents.contains("name: \"CameraKit\""))
        #expect(contents.contains("name: \"LocationKit\""))
        #expect(contents.contains("dependencies: [\"Domain\"]"))
        #expect(contents.contains("plugins: [.plugin(name: \"ArchitectureLint\", package: \"AppFoundation\")]"))
    }

    @Test(
        "buildPlatformPackageSwift adds the Firebase SDK dependency and both Firebase products only for --adapter Firebase"
    )
    func platformPackageSwiftFirebaseAdapter() {
        let contents = ArchInitSupport.buildPlatformPackageSwift(capabilities: [], adapters: ["Firebase"])
        #expect(contents.contains(".library(name: \"FirebaseAdapters\", targets: [\"FirebaseAdapters\"])"))
        #expect(contents.contains("firebase-ios-sdk"))
        #expect(contents.contains(".product(name: \"FirebaseAnalytics\", package: \"firebase-ios-sdk\")"))
        #expect(contents.contains(".product(name: \"FirebaseCrashlytics\", package: \"firebase-ios-sdk\")"))
    }

    @Test(
        "buildPlatformPackageSwift adds a generic <Sdk>Adapters target for a non-Firebase adapter, without the Firebase SDK"
    )
    func platformPackageSwiftGenericAdapter() {
        let contents = ArchInitSupport.buildPlatformPackageSwift(capabilities: [], adapters: ["Analytics"])
        #expect(contents.contains(".library(name: \"AnalyticsAdapters\", targets: [\"AnalyticsAdapters\"])"))
        #expect(!contents.contains("firebase-ios-sdk"))
        #expect(!contents.contains("FirebaseAnalytics"))
    }

    @Test("buildPlatformPackageSwift with capabilities AND both kinds of adapters combines everything")
    func platformPackageSwiftCombined() {
        let contents = ArchInitSupport.buildPlatformPackageSwift(
            capabilities: ["Camera"],
            adapters: ["Firebase", "Analytics"]
        )
        #expect(contents.contains("CameraKit"))
        #expect(contents.contains("FirebaseAdapters"))
        #expect(contents.contains("AnalyticsAdapters"))
    }

    // `swift format lint --strict` with the `.swift-format` archinit copies into the project
    // (`multiElementCollectionTrailingCommas: false`) failed on a fresh
    // `Packages/Platform/Package.swift` with `[TrailingComma]`: the last product, the last
    // package dependency, the last target and, with `--adapter Firebase`, the last dependency
    // of `FirebaseAdapters` all ended in a comma.

    @Test("commaSeparated puts a comma after the last line of every element but the last")
    func commaSeparatedSkipsTheLastElement() {
        #expect(ArchInitSupport.commaSeparated([]) == [])
        #expect(ArchInitSupport.commaSeparated([["a"]]) == ["a"])
        let multiLine = ArchInitSupport.commaSeparated([["// c", "a"], ["b1", "b2"], ["c"]])
        #expect(multiLine == ["// c", "a,", "b1", "b2,", "c"])
        #expect(ArchInitSupport.commaSeparated([["a"], [], ["b"], []]) == ["a,", "b"])
    }

    @Test("targetBlock is one element without a trailing comma, and its last dependency has none either")
    func targetBlockHasNoTrailingCommas() {
        let block = ArchInitSupport.targetBlock(
            kind: "target",
            name: "X",
            dependencies: ["\"A\"", "\"B\""],
            path: "Sources/X",
            withArchLint: false
        )
        #expect(
            block == [
                "        .target(",
                "            name: \"X\",",
                "            dependencies: [",
                "                \"A\",",
                "                \"B\"",
                "            ],",
                "            path: \"Sources/X\",",
                "            swiftSettings: swiftSettings",
                "        )"
            ]
        )
    }

    @Test(
        "buildPlatformPackageSwift closes every multi-line collection without a trailing comma",
        arguments: [
            ([String](), [String]()),
            (["Camera"], ["Analytics"]),
            (["Camera", "Location"], ["Firebase", "Analytics"])
        ]
    )
    func platformPackageSwiftHasNoTrailingCommaBeforeClosingBracket(capabilities: [String], adapters: [String]) {
        let lines = ArchInitSupport.buildPlatformPackageSwift(capabilities: capabilities, adapters: adapters)
            .components(separatedBy: "\n")
        for (line, next) in zip(lines, lines.dropFirst())
        where next.trimmingCharacters(in: .whitespaces).hasPrefix("]") {
            #expect(!line.hasSuffix(","), "trailing comma before `\(next)`: \(line)")
        }
    }

    @Test("buildPlatformPackageSwift keeps the comma between elements and drops only the last one")
    func platformPackageSwiftCommasOnlyBetweenElements() {
        let contents = ArchInitSupport.buildPlatformPackageSwift(capabilities: ["Camera"], adapters: ["Analytics"])
        #expect(
            contents.contains(
                "[\"CameraKit\"]),\n        .library(name: \"AnalyticsAdapters\", targets: [\"AnalyticsAdapters\"])\n    ],"
            )
        )
        #expect(contents.contains("from: \"1.2.0\")\n    ],\n    targets: ["))
        #expect(contents.contains("        ),\n        .target(\n            name: \"AnalyticsAdapters\","))
        #expect(contents.hasSuffix("        )\n    ]\n)\n"))

        let firebase = ArchInitSupport.buildPlatformPackageSwift(capabilities: [], adapters: ["Firebase"])
        #expect(firebase.contains("from: \"1.2.0\"),\n        // R14: por tag"))
        #expect(firebase.contains("from: \"11.0.0\")\n    ],"))
        #expect(
            firebase.contains(
                "\"firebase-ios-sdk\"),\n                .product(name: \"FirebaseCrashlytics\", package: \"firebase-ios-sdk\")\n            ],"
            )
        )
    }

    // MARK: - App/AppModule.swift substitutions

    @Test("moduleImports always imports Domain, never the package name 'Platform'")
    func moduleImportsAlwaysIncludesDomain() {
        let imports = ArchInitSupport.moduleImports(capabilities: [], hasFirebase: false, genericAdapters: [])
        #expect(imports == "import AppFoundation\nimport Domain\nimport Foundation")
        #expect(!imports.contains("import Platform"))
    }

    /// `swift format lint --strict` on a fresh `archinit --multi` app failed with
    /// `[OrderedImports]`: the template put `AppFoundation`/`Foundation` first, then Domain,
    /// Kits and Adapters in the order given. `OrderedImports` compares code points, so
    /// `AppFoundation` < `AppcuesAdapters` (`F` < `c`), not the other way round.
    @Test("moduleImports renders the whole import block in the code-point order OrderedImports checks")
    func moduleImportsAreSortedLikeOrderedImports() {
        let imports = ArchInitSupport.moduleImports(
            capabilities: ["Camera", "Fitness"],
            hasFirebase: true,
            genericAdapters: ["Appcues", "Analytics"]
        )
        #expect(
            imports == """
                import AnalyticsAdapters
                import AppFoundation
                import AppcuesAdapters
                import CameraKit
                import Domain
                import FirebaseAdapters
                import FitnessKit
                import Foundation
                """
        )
    }

    @Test("moduleImports adds one import per capability/adapter module actually referenced")
    func moduleImportsPerCapabilityAndAdapter() {
        let imports = ArchInitSupport.moduleImports(
            capabilities: ["Camera"],
            hasFirebase: true,
            genericAdapters: ["Analytics"]
        )
        #expect(imports.contains("import Domain"))
        #expect(imports.contains("import CameraKit"))
        #expect(imports.contains("import FirebaseAdapters"))
        #expect(imports.contains("import AnalyticsAdapters"))
    }

    @Test("kitRegistrations is empty with no capabilities, one registration line per capability otherwise")
    func kitRegistrations() {
        #expect(ArchInitSupport.kitRegistrations(capabilities: []) == "")
        let withCameras = ArchInitSupport.kitRegistrations(capabilities: ["Camera", "Location"])
        #expect(withCameras.contains("container.register(CameraProviding.self) { _ in CameraKitProvider() }"))
        #expect(withCameras.contains("container.register(LocationProviding.self) { _ in LocationKitProvider() }"))
    }

    @Test("adapterRegistrations covers both Firebase's two protocols and a generic adapter's one")
    func adapterRegistrations() {
        #expect(ArchInitSupport.adapterRegistrations(hasFirebase: false, genericAdapters: []) == "")
        let firebase = ArchInitSupport.adapterRegistrations(hasFirebase: true, genericAdapters: [])
        #expect(firebase.contains("container.register(AnalyticsTracking.self) { _ in FirebaseAnalyticsTracker() }"))
        #expect(firebase.contains("container.register(CrashReporting.self) { _ in FirebaseCrashReporter() }"))
        let generic = ArchInitSupport.adapterRegistrations(hasFirebase: false, genericAdapters: ["Analytics"])
        #expect(generic.contains("container.register(AnalyticsAdapting.self) { _ in AnalyticsAdapterStub() }"))
    }

    // MARK: - Root .archlint.yml `modules:` (R13 — the other agent's parser reads this)

    @Test("rootModulesYAML: Domain is a closed allow-list; *Feature is a deny-list of features, Kits and Adapters")
    func rootModulesYAMLBaseline() {
        let yaml = ArchInitSupport.rootModulesYAML(capabilities: [], adapters: [])
        #expect(yaml.contains("modules:\n  Domain:\n    allowedImports: [Foundation]"))
        #expect(yaml.contains("  \"*Feature\":\n    forbiddenImports: [\"*Feature\", \"*Kit\", \"*Adapters\"]"))
        // No allow-list for features: SwiftData/AVFoundation/OSLog must not be false positives.
        #expect(!yaml.contains("*Feature\":\n    allowedImports"))
    }

    @Test("rootModulesYAML: a Kit may use any Apple framework but never a feature, an adapter or an SDK")
    func rootModulesYAMLPerCapability() {
        let yaml = ArchInitSupport.rootModulesYAML(capabilities: ["Camera"], adapters: ["Firebase"])
        #expect(yaml.contains("  CameraKit:\n    forbiddenImports: [\"*Feature\", \"*Adapters\", \"Firebase*\"]"))
    }

    @Test("rootModulesYAML: every --adapter SDK is denied to features and to the other adapters")
    func rootModulesYAMLAdapterScoping() {
        let yaml = ArchInitSupport.rootModulesYAML(capabilities: [], adapters: ["Firebase", "Analytics"])
        #expect(yaml.contains("  FirebaseAdapters:\n    forbiddenImports: [\"*Feature\", \"*Kit\", \"Analytics*\"]"))
        #expect(yaml.contains("  AnalyticsAdapters:\n    forbiddenImports: [\"*Feature\", \"*Kit\", \"Firebase*\"]"))
        #expect(
            yaml.contains(
                "  \"*Feature\":\n    forbiddenImports: [\"*Feature\", \"*Kit\", \"*Adapters\", \"Firebase*\", \"Analytics*\"]"
            )
        )
    }

    // MARK: - project.yml substitutions

    @Test("platformProductDeps lists Domain's siblings only (Domain itself is always explicit in the template)")
    func platformProductDepsListsExtras() {
        #expect(ArchInitSupport.platformProductDeps(capabilities: [], adapters: []) == "")
        let deps = ArchInitSupport.platformProductDeps(capabilities: ["Camera"], adapters: ["Firebase"])
        #expect(deps.contains("      - package: Platform\n        product: CameraKit\n"))
        #expect(deps.contains("      - package: Platform\n        product: FirebaseAdapters\n"))
    }

    @Test("hiddenPackageSchemes emits one isShown:false scheme per Platform product, Domain included")
    func hiddenPackageSchemesCoversDomainAndExtras() {
        let yaml = ArchInitSupport.hiddenPackageSchemes(
            name: "DemoMulti",
            capabilities: ["Camera"],
            adapters: ["Firebase"]
        )
        #expect(
            yaml.contains(
                "  Domain:\n    build:\n      targets:\n        DemoMulti: [build]\n    management:\n      isShown: false"
            )
        )
        #expect(yaml.contains("  CameraKit:"))
        #expect(yaml.contains("  FirebaseAdapters:"))
    }

    // MARK: - AGENTS.md § Módulos de este proyecto

    @Test("modulesSection always includes Domain, the <Nombre>Feature row, and the app row")
    func modulesSectionBaseline() {
        let section = ArchInitSupport.modulesSection(name: "DemoMulti", capabilities: [], adapters: [])
        #expect(section.contains("| Domain | Foundation | nada más |"))
        #expect(section.contains("<Nombre>Feature"))
        #expect(section.contains("| DemoMulti (App) | todo | lógica de negocio |"))
    }

    @Test("modulesSection adds one row per capability and adapter")
    func modulesSectionPerCapabilityAndAdapter() {
        let section = ArchInitSupport.modulesSection(
            name: "DemoMulti",
            capabilities: ["Camera"],
            adapters: ["Firebase"]
        )
        #expect(section.contains("`CameraKit`"))
        #expect(section.contains("`FirebaseAdapters`"))
    }

    // MARK: - Assets.xcassets

    @Test("assetsXcassets produces three valid, non-empty JSON catalogs")
    func assetsXcassetsProducesThreeCatalogs() throws {
        let assets = ArchInitSupport.assetsXcassets()
        #expect(assets.count == 3)
        for (_, contents) in assets {
            let data = Data(contents.utf8)
            let parsed = try JSONSerialization.jsonObject(with: data)
            #expect(parsed is [String: Any])
        }
    }

    // MARK: - Diffing

    @Test("suggestedDiff is empty-message for identical content")
    func suggestedDiffNoDifferences() {
        let diff = ArchInitSupport.suggestedDiff(existing: "a\nb\n", proposed: "a\nb\n")
        #expect(diff.contains("sin diferencias"))
    }

    @Test("suggestedDiff marks changed lines with -/+ at their position")
    func suggestedDiffMarksChangedLines() {
        let diff = ArchInitSupport.suggestedDiff(existing: "a\nb\nc", proposed: "a\nx\nc")
        #expect(diff.contains("  - b"))
        #expect(diff.contains("  + x"))
        #expect(!diff.contains("- a"))
        #expect(!diff.contains("- c"))
    }
}
