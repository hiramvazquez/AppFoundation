import Foundation
import Testing

@testable import archlint

/// Fixture-based tests: one "bad" file per rule (`Fixtures/Bad/Rn_*.swift`) proves the rule
/// fires, and the "good" feature (`Fixtures/Good/*`, a small but complete Login feature
/// shaped exactly like `AppFoundation/Examples/LoginApp`) proves none of R1-R12 false-fire
/// on code that actually follows the architecture — including its `#if DEBUG`/`#Preview`
/// block, which references the concrete Logic/Service/Store on purpose (same pattern as
/// `LoginApp`'s `LoginPreview`).
@Suite("ArchLint rules")
struct ArchLintRuleTests {
    private func fixtureURL(_ name: String, in subdirectory: String) -> URL {
        guard
            let url = Bundle.module.url(
                forResource: name,
                withExtension: "swift",
                subdirectory: "Fixtures/\(subdirectory)"
            )
        else {
            Issue.record("Missing fixture Fixtures/\(subdirectory)/\(name).swift")
            return URL(fileURLWithPath: "/dev/null")
        }
        return url
    }

    private func parse(_ name: String, in subdirectory: String) -> ParsedFile {
        let url = fixtureURL(name, in: subdirectory)
        let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return FileParser.parse(path: url.path, relativePath: "\(subdirectory)/\(name).swift", source: source)
    }

    private func diagnostics(for files: [ParsedFile], config: ArchLintConfig = ArchLintConfig()) -> [Diagnostic] {
        RuleEngine.run(files: files, config: config)
    }

    // MARK: - One violation per rule

    @Test("R1: a ViewModel importing CoreNetworking / referencing APIService")
    func r1Fires() {
        let file = parse("R1_BadViewModel", in: "Bad")
        let diags = diagnostics(for: [file])
        #expect(diags.contains { $0.rule == "R1" && $0.severity == .error })
        #expect(diags.filter { $0.rule == "R1" }.count >= 2)
    }

    @Test("R2: a Logic importing SwiftUI / referencing a ViewModel / missing its protocol")
    func r2Fires() {
        let file = parse("R2_BadLogic", in: "Bad")
        let diags = diagnostics(for: [file])
        #expect(diags.contains { $0.rule == "R2" })
    }

    @Test("R3: a Logic touching APIServiceProtocol/BaseRequest directly")
    func r3Fires() {
        let file = parse("R3_BadLogic", in: "Bad")
        let diags = diagnostics(for: [file])
        #expect(diags.contains { $0.rule == "R3" })
    }

    @Test("R4: a View referencing its Logic outside #Preview/#if DEBUG")
    func r4Fires() {
        let file = parse("R4_BadView", in: "Bad")
        let diags = diagnostics(for: [file])
        #expect(diags.contains { $0.rule == "R4" })
    }

    @Test("R5: a ViewModel with no matching Logic file")
    func r5Fires() {
        let file = parse("R5_OrphanViewModel", in: "Bad")
        let diags = diagnostics(for: [file])
        #expect(diags.contains { $0.rule == "R5" })
    }

    @Test("R5 does not fire for a --no-logic ViewModel (BaseViewModel, not LogicViewModel)")
    func r5DoesNotFireForNoLogicViewModel() {
        let source = """
            @MainActor
            public final class ProfileViewModel: BaseViewModel, ActionHandling {
                public enum Action: Sendable { case load }
                public func handle(_ action: Action) {}
            }
            """
        let file = FileParser.parse(
            path: "ProfileViewModel.swift",
            relativePath: "ProfileViewModel.swift",
            source: source
        )
        let diags = diagnostics(for: [file])
        #expect(!diags.contains { $0.rule == "R5" })
    }

    @Test("R6: init receives a concrete Logic instead of any XxxLogicProtocol")
    func r6Fires() {
        let file = parse("R6_BadViewModel", in: "Bad")
        let diags = diagnostics(for: [file])
        #expect(diags.contains { $0.rule == "R6" })
    }

    @Test("R7: an APIError reference reaching the ViewModel")
    func r7Fires() {
        let file = parse("R7_BadViewModel", in: "Bad")
        let diags = diagnostics(for: [file])
        #expect(diags.contains { $0.rule == "R7" })
    }

    @Test("R8: a DTO (*Request/*Response) reaching the Logic")
    func r8Fires() {
        let file = parse("R8_BadLogic", in: "Bad")
        let diags = diagnostics(for: [file])
        #expect(diags.contains { $0.rule == "R8" })
    }

    @Test("R9: a Logic referencing Router")
    func r9Fires() {
        let file = parse("R9_BadLogic", in: "Bad")
        let diags = diagnostics(for: [file])
        #expect(diags.contains { $0.rule == "R9" })
    }

    @Test("R10: Container.shared, resolve(, and @Inject outside the composition root")
    func r10Fires() {
        let file = parse("R10_BadLogic", in: "Bad")
        let diags = diagnostics(for: [file])
        let r10 = diags.filter { $0.rule == "R10" }
        #expect(r10.count == 3, "expected Container.shared + resolve( + @Inject, got \(r10.map(\.message))")
    }

    @Test("R11: a Logic pinned to @MainActor is a warning, not an error")
    func r11FiresAsWarning() {
        let file = parse("R11_BadLogic", in: "Bad")
        let diags = diagnostics(for: [file])
        let r11 = diags.filter { $0.rule == "R11" }
        #expect(r11.count == 1)
        #expect(r11.first?.severity == .warning)
        // A warning never fails the build on its own.
        #expect(diags.filter { $0.severity == .error }.isEmpty)
    }

    @Test("R12: a View's `let viewModel:` (no @State) is a warning, not an error")
    func r12FiresAsWarning() {
        let file = parse("R12_BadView", in: "Bad")
        let diags = diagnostics(for: [file])
        let r12 = diags.filter { $0.rule == "R12" }
        #expect(r12.count == 1)
        #expect(r12.first?.severity == .warning)
        #expect(diags.filter { $0.severity == .error }.isEmpty)
    }

    @Test("R15: a ViewModel subclass without @Observable is an error")
    func r15FiresWithoutObservable() {
        let file = parse("R15_UnobservedViewModel", in: "Bad")
        let diags = diagnostics(for: [file])
        let r15 = diags.filter { $0.rule == "R15" }
        #expect(r15.count == 1)
        #expect(r15.first?.severity == .error)
        #expect(r15.first?.message.contains("@Observable") == true)
    }

    @Test("R16: a class without an explicit deinit is an error")
    func r16FiresWithoutDeinit() {
        let file = parse("R16_NoDeinitViewModel", in: "Bad")
        let diags = diagnostics(for: [file])
        let r16 = diags.filter { $0.rule == "R16" }
        #expect(r16.count == 1)
        #expect(r16.first?.severity == .error)
    }

    @Test("R16 does not fire on a class with deinit nor on a nonisolated class")
    func r16DoesNotFireWithDeinitOrNonisolated() {
        let good = parse("LoginViewModel", in: "Good")
        #expect(!diagnostics(for: [good]).contains { $0.rule == "R16" })
        let helper = parse("NonisolatedHelper", in: "Good")
        #expect(!diagnostics(for: [helper]).contains { $0.rule == "R16" })
    }

    @Test("R15 does not fire on a ViewModel that declares @Observable (the Good fixture)")
    func r15DoesNotFireWithObservable() {
        let file = parse("LoginViewModel", in: "Good")
        let diags = diagnostics(for: [file])
        #expect(!diags.contains { $0.rule == "R15" })
    }

    @Test("R12 does not fire on `@State private var viewModel:` (same line)")
    func r12DoesNotFireOnSameLineState() {
        let source = """
            import SwiftUI

            public struct BadView: View {
                @State private var viewModel: BadViewModel

                public var body: some View { Text("ok") }
            }
            """
        let file = FileParser.parse(path: "BadView.swift", relativePath: "BadView.swift", source: source)
        let diags = diagnostics(for: [file])
        #expect(!diags.contains { $0.rule == "R12" })
    }

    @Test("R12 does not fire when @State sits on the line above `var viewModel:`")
    func r12DoesNotFireOnPreviousLineState() {
        let source = """
            import SwiftUI

            public struct BadView: View {
                @State
                private var viewModel: BadViewModel

                public var body: some View { Text("ok") }
            }
            """
        let file = FileParser.parse(path: "BadView.swift", relativePath: "BadView.swift", source: source)
        let diags = diagnostics(for: [file])
        #expect(!diags.contains { $0.rule == "R12" })
    }

    // MARK: - strict: true extends R1

    @Test("strict: true requires LogicViewModel; the default config does not")
    func strictRequiresLogicViewModel() {
        let file = parse("StrictBadViewModel", in: "Bad")

        let defaultDiags = diagnostics(for: [file], config: ArchLintConfig())
        #expect(!defaultDiags.contains { $0.rule == "R1" })

        var strict = ArchLintConfig()
        strict.strict = true
        let strictDiags = diagnostics(for: [file], config: strict)
        #expect(strictDiags.contains { $0.rule == "R1" })
    }

    // MARK: - Disabling a rule

    @Test("disabled: [Rn] suppresses that rule")
    func disabledRuleIsSuppressed() {
        let file = parse("R9_BadLogic", in: "Bad")
        var config = ArchLintConfig()
        config.disabledRules = ["R9"]
        let diags = diagnostics(for: [file], config: config)
        #expect(!diags.contains { $0.rule == "R9" })
    }

    // MARK: - The Good fixture: a complete, compliant feature never false-fires

    @Test("A compliant Login feature (View/ViewModel/Logic/Service/Store/Module) passes with zero errors")
    func goodFeaturePassesCleanly() {
        let files = [
            parse("LoginView", in: "Good"),
            parse("LoginViewModel", in: "Good"),
            parse("LoginLogic", in: "Good"),
            parse("LoginModule", in: "Good"),
            FileParser.parse(
                path: "Good/Services/LoginService.swift",
                relativePath: "Good/Services/LoginService.swift",
                source: (try? String(contentsOf: fixtureURL("LoginService", in: "Good/Services"), encoding: .utf8))
                    ?? ""
            ),
            FileParser.parse(
                path: "Good/Stores/LoginStore.swift",
                relativePath: "Good/Stores/LoginStore.swift",
                source: (try? String(contentsOf: fixtureURL("LoginStore", in: "Good/Stores"), encoding: .utf8)) ?? ""
            )
        ]

        let diags = diagnostics(for: files)
        let errors = diags.filter { $0.severity == .error }
        #expect(errors.isEmpty, "unexpected errors: \(errors.map(\.formatted))")
    }

    @Test("The Good fixture's #if DEBUG preview references the real Logic/Service/Store and is exempt from R4")
    func debugPreviewIsExemptFromR4() {
        let view = parse("LoginView", in: "Good")
        let url = fixtureURL("LoginView", in: "Good")
        let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // Sanity: the fixture really does reference LoginService/LoginStore inside its
        // #Preview (in the raw source) — if this ever stops being true, the exemption
        // proven below is vacuous. It must NOT show up in `references`: that's exactly
        // what "exempt" means (see the internals test below for the mechanism itself).
        #expect(source.contains("LoginService(api: mock)"))
        #expect(source.contains("LoginStore()"))
        #expect(!view.references.contains { $0.name == "LoginService" })
        #expect(!view.references.contains { $0.name == "LoginStore" })

        let diags = diagnostics(for: [view, parse("LoginLogic", in: "Good")])
        #expect(!diags.contains { $0.rule == "R4" })
    }
}

/// Unit tests for the pieces `RuleEngine` is built on: the lexer, the config reader, and
/// the glob matcher.
@Suite("archlint internals")
struct ArchLintInternalsTests {
    @Test("The lexer ignores line comments")
    func lexerIgnoresLineComments() {
        let tokens = Lexer.tokenize("let x = 1 // Container.shared should not be seen here")
        #expect(!tokens.contains { $0.text == "Container" })
    }

    @Test("The lexer ignores block comments, including nested ones")
    func lexerIgnoresNestedBlockComments() {
        let tokens = Lexer.tokenize("/* outer /* inner Container.shared */ still comment */ let x = 1")
        #expect(!tokens.contains { $0.text == "Container" })
        #expect(tokens.contains { $0.text == "let" })
    }

    @Test("The lexer collapses string contents to one opaque token")
    func lexerCollapsesStrings() {
        let tokens = Lexer.tokenize(#"let s = "Container.shared and APIError, all inside a string""#)
        #expect(!tokens.contains { $0.text == "Container" })
        #expect(!tokens.contains { $0.text == "APIError" })
        #expect(tokens.contains { $0.kind == .stringLiteral })
    }

    @Test("A #Preview block is recognized as an exempt region")
    func previewBlockIsExempt() {
        let source = """
            struct X {
                var body: Int { 1 }
            }
            #Preview {
                APIService()
            }
            """
        let file = FileParser.parse(path: "X.swift", relativePath: "X.swift", source: source)
        #expect(!file.references.contains { $0.name == "APIService" })
    }

    @Test("Config: dotted keys, inline lists, and block lists all parse")
    func configParsesAllShapes() {
        let text = """
            strict: true
            suffixes.viewModel: Screen
            disabled: [R9, R11]
            ignore:
              - Generated/**
              - "**/Legacy/**"
            """
        let config = ArchLintConfig.parse(text)
        #expect(config.strict)
        #expect(config.viewModelSuffix == "Screen")
        #expect(config.disabledRules == ["R9", "R11"])
        #expect(config.ignoreGlobs == ["Generated/**", "**/Legacy/**"])
    }

    @Test("Config: a '#' inside a quoted ignore entry is not treated as a comment")
    func configHandlesHashInsideQuotes() {
        let text = #"""
            ignore:
              - "Generated/**"
            strict: true # this really is a comment
            """#
        let config = ArchLintConfig.parse(text)
        #expect(config.strict)
        #expect(config.ignoreGlobs == ["Generated/**"])
    }

    @Test("Glob: ** matches any depth, * matches one path segment")
    func globMatching() {
        #expect(Glob.matches("Tests/**", path: "Tests/Foo/Bar.swift"))
        #expect(Glob.matches("**/Mocks/**", path: "Features/Login/Tests/Mocks/LoginMock.swift"))
        #expect(Glob.matches("**/*Tests.swift", path: "Features/Login/LoginLogicTests.swift"))
        #expect(!Glob.matches("Tests/**", path: "Sources/LoginLogic.swift"))
        #expect(Glob.matches("*.swift", path: "Package.swift"))
        // Corchetes literales en un segmento: no son una clase de caracteres.
        #expect(Glob.matches("Legacy[old]/**", path: "Legacy[old]/Thing.swift"))
        #expect(!Glob.matches("Legacy[old]/**", path: "Legacyo/Thing.swift"))
        #expect(!Glob.matches("*.swift", path: "Sources/Package.swift"))
    }

    @Test("Glob: a leading '**/' also matches zero path segments, not just one-or-more")
    func globLeadingDoubleStarMatchesZeroSegments() {
        // Regression: "**/Tests/**" must match a TOP-LEVEL Tests/ directory
        // ("Tests/Foo.swift"), not only a nested one ("Sub/Tests/Foo.swift") — otherwise
        // the default config silently fails to ignore the most common case.
        #expect(Glob.matches("**/Tests/**", path: "Tests/DemoAppTests/LoginLogicTests.swift"))
        #expect(Glob.matches("**/Tests/**", path: "Sub/Tests/DemoAppTests/LoginLogicTests.swift"))
        #expect(Glob.matches("**/Mocks/**", path: "Mocks/LoginMock.swift"))
    }

    @Test("Default config ignores Tests/ and test-double files")
    func defaultConfigIgnoresTestsByDefault() {
        let config = ArchLintConfig()
        #expect(
            config.ignoreGlobs.contains {
                Glob.matches($0, path: "Tests/LoginAppTests/Features/Login/LoginLogicTests.swift")
            }
        )
        #expect(
            config.ignoreGlobs.contains {
                Glob.matches($0, path: "Tests/LoginAppTests/Features/Login/Mocks/LoginServiceMock.swift")
            }
        )
    }

    // MARK: - A1 (PRD-X-05): .build/.swiftpm/DerivedData/.git are never analyzed

    @Test("An explicit ignore: of only Tests/** still never analyzes .build/.swiftpm/DerivedData/.git")
    func explicitIgnoreNeverReachesBuildProducts() {
        // Exactly what `archinit`'s generated `.archlint.yml` amounts to: an `ignore:` that
        // REPLACES the defaults. Before `alwaysIgnoreGlobs` this dropped `**/.build/**`
        // with the rest, and `swift package archlint` walked into every checkout.
        let config = ArchLintConfig.parse("ignore:\n  - Tests/**\n")
        #expect(config.ignoreGlobs == ["Tests/**"])

        let checkout = ".build/checkouts/AppFoundation/Tests/ArchLintTests/Fixtures/Bad/R1_BadViewModel.swift"
        #expect(config.isIgnored(relativePath: checkout))
        #expect(
            config.isIgnored(
                relativePath: ".build/checkouts/AppFoundation/Examples/LoginApp/Sources/LoginApp/LoginViewModel.swift"
            )
        )
        #expect(config.isIgnored(relativePath: ".swiftpm/xcode/Scratch/ScratchViewModel.swift"))
        #expect(config.isIgnored(relativePath: "DerivedData/DemoApp/Build/GeneratedViewModel.swift"))
        #expect(config.isIgnored(relativePath: ".git/hooks/HookViewModel.swift"))
        // Nested, and absolute (a file outside --root keeps its absolute path).
        #expect(config.isIgnored(relativePath: "Modules/Feature/.build/checkouts/Dep/DepViewModel.swift"))
        #expect(config.isIgnored(relativePath: "/Users/me/Project/.build/checkouts/Dep/DepViewModel.swift"))

        // The user's own entry still applies, and the replaced defaults really are gone.
        #expect(config.isIgnored(relativePath: "Tests/DemoAppTests/LoginLogicTests.swift"))
        #expect(!config.isIgnored(relativePath: "Sources/DemoApp/Features/Login/LoginServiceMock.swift"))
        #expect(!config.isIgnored(relativePath: "Sources/DemoApp/Features/Login/LoginViewModel.swift"))
    }

    @Test("Without a config file, .build/checkouts is never analyzed either")
    func missingConfigNeverReachesBuildProducts() {
        let config = ArchLintConfig.load(from: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(config.isIgnored(relativePath: ".build/checkouts/Dep/Sources/Dep/DepViewModel.swift"))
        #expect(config.isIgnored(relativePath: "Tests/DemoAppTests/LoginLogicTests.swift"))
        #expect(!config.isIgnored(relativePath: "Sources/DemoApp/Features/Login/LoginViewModel.swift"))
    }

    @Test("alwaysIgnoreGlobs is not part of ignoreGlobs, so an explicit ignore: cannot drop it")
    func alwaysIgnoreIsSeparateFromUserIgnore() {
        #expect(
            ArchLintConfig.alwaysIgnoreGlobs == ["**/.build/**", "**/.swiftpm/**", "**/DerivedData/**", "**/.git/**"]
        )
        let defaults = ArchLintConfig()
        #expect(!defaults.ignoreGlobs.contains("**/.build/**"))
        #expect(!defaults.ignoreGlobs.contains("**/.swiftpm/**"))
    }
}

/// R13/R14 (PRD-AF-10): module isolation and branch/revision dependencies. Fixtures under
/// `Fixtures/Multi/` — a repo-root `.archlint.yml` with `modules:`, a small `AFeature` that
/// breaks two different ways, a clean `Domain`, and a `Package.swift` pinned to a branch.
@Suite("ArchLint R13/R14 — module isolation and branch dependencies")
struct ArchLintModuleRuleTests {
    /// `Fixtures/Multi/.archlint.yml` and `Fixtures/Multi/Package.swift` are read directly
    /// (not through `Bundle.module`, unlike every other fixture in this file): a leading-dot
    /// filename is awkward as a `forResource:withExtension:` resource name, and reading the
    /// checked-in fixture straight from disk — relative to this test file's own `#filePath`
    /// — works just as well for plain text either way.
    private func multiFixtureURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Multi/\(relativePath)")
    }

    private func multiConfig() -> ArchLintConfig {
        let text = (try? String(contentsOf: multiFixtureURL(".archlint.yml"), encoding: .utf8)) ?? ""
        return ArchLintConfig.parse(text)
    }

    private func parseSource(_ relativePathUnderMulti: String) -> ParsedFile {
        let url = multiFixtureURL(relativePathUnderMulti)
        let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return FileParser.parse(path: url.path, relativePath: relativePathUnderMulti, source: source)
    }

    // MARK: - Config parsing: the nested `modules:` block and the flat dotted form agree

    @Test("modules: nested block form parses pattern, allowedImports, forbiddenImports")
    func nestedModulesBlockParses() {
        let config = multiConfig()
        #expect(config.modules.count == 2)

        let domain = config.moduleRule(for: "Domain")
        #expect(domain?.allowedImports == ["Foundation"])
        #expect(domain?.forbiddenImports.isEmpty == true)

        let feature = config.moduleRule(for: "AFeature")
        #expect(feature?.allowedImports == ["Foundation", "SwiftUI", "Domain"])
        #expect(feature?.forbiddenImports == ["*Feature", "Firebase*"])
    }

    @Test("modules.<glob>.allowedImports: [...] (flat dotted form) is equivalent to the nested block")
    func flatDottedFormIsEquivalent() {
        let text = """
            modules.Domain.allowedImports: [Foundation]
            modules.*Feature.allowedImports: [Foundation, SwiftUI, Domain]
            modules.*Feature.forbiddenImports: [*Feature, Firebase*]
            """
        let config = ArchLintConfig.parse(text)
        #expect(config.moduleRule(for: "Domain")?.allowedImports == ["Foundation"])
        let feature = config.moduleRule(for: "AFeature")
        #expect(feature?.allowedImports == ["Foundation", "SwiftUI", "Domain"])
        #expect(feature?.forbiddenImports == ["*Feature", "Firebase*"])
    }

    @Test("moduleRule(for:) prefers an exact match over a glob that also matches")
    func exactMatchWinsOverGlob() {
        var config = ArchLintConfig()
        config.modules = [
            ModuleRule(pattern: "*Feature", allowedImports: ["Foundation"]),
            ModuleRule(pattern: "AFeature", forbiddenImports: ["Everything"])
        ]
        let rule = config.moduleRule(for: "AFeature")
        #expect(rule?.pattern == "AFeature")
        #expect(rule?.forbiddenImports == ["Everything"])
    }

    // MARK: - moduleName(relativePath:)

    @Test("moduleName(relativePath:) reads the Sources/<Target>/ segment, Core/UI included")
    func moduleNameFromPath() {
        #expect(RuleEngine.moduleName(relativePath: "Sources/MisCasosFeature/Thing.swift") == "MisCasosFeature")
        #expect(
            RuleEngine.moduleName(relativePath: "Sources/MisCasosFeatureCore/Thing.swift") == "MisCasosFeatureCore"
        )
        #expect(RuleEngine.moduleName(relativePath: "Package.swift") == nil)
    }

    // MARK: - R13 fires

    @Test("R13: AFeature importing BFeature (feature-to-feature) fires with the Domain/AppRoute phrasing")
    func r13FiresForFeatureToFeature() {
        let file = parseSource("Sources/AFeature/AFeatureThing.swift")
        let diags = RuleEngine.run(files: [file], config: multiConfig())
        let r13 = diags.filter { $0.rule == "R13" }
        #expect(r13.count == 1)
        #expect(r13.first?.severity == .error)
        #expect(r13.first?.message.contains("las features se comunican por Domain y por AppRoute") == true)
    }

    @Test("R13: AFeature importing FirebaseAnalytics (an SDK) fires with the Adapter/Kit phrasing")
    func r13FiresForSDKImport() {
        let file = parseSource("Sources/AFeature/AFeatureAnalytics.swift")
        let diags = RuleEngine.run(files: [file], config: multiConfig())
        let r13 = diags.filter { $0.rule == "R13" }
        #expect(r13.count == 1)
        #expect(r13.first?.severity == .error)
        #expect(r13.first?.message.contains("Adapter/Kit") == true)
    }

    @Test("R13: Domain importing only Foundation is clean")
    func r13CleanForDomain() {
        let file = parseSource("Sources/Domain/DomainThing.swift")
        let diags = RuleEngine.run(files: [file], config: multiConfig())
        #expect(!diags.contains { $0.rule == "R13" })
    }

    @Test("R13: --module (moduleOverride) wins over the path-derived module")
    func r13ModuleOverrideWins() {
        var config = multiConfig()
        config.moduleOverride = "Domain"
        // Path says AFeature, override says Domain: BFeature is not among Domain's
        // allowedImports ([Foundation]) either, so this still fires — as Domain, proving the
        // override (not the path) is what decided which rule applied.
        let file = parseSource("Sources/AFeature/AFeatureThing.swift")
        let diags = RuleEngine.run(files: [file], config: config)
        let r13 = diags.filter { $0.rule == "R13" }
        #expect(r13.count == 1)
        #expect(r13.first?.message.hasPrefix("'Domain'") == true)
    }

    @Test("R13: without modules:, nothing fires — full backward compatibility")
    func r13NoOpWithoutModulesConfig() {
        let file = parseSource("Sources/AFeature/AFeatureThing.swift")
        let diags = RuleEngine.run(files: [file], config: ArchLintConfig())
        #expect(diags.isEmpty)
    }

    @Test("R13: import Testing/XCTest is never flagged, even under a restrictive allowedImports")
    func r13IgnoresTestFrameworks() {
        let source = """
            import Testing
            import XCTest

            struct AFeatureSpec {}
            """
        let file = FileParser.parse(
            path: "AFeatureSpec.swift",
            relativePath: "Sources/AFeature/AFeatureSpec.swift",
            source: source
        )
        let diags = RuleEngine.run(files: [file], config: multiConfig())
        #expect(!diags.contains { $0.rule == "R13" })
    }

    // MARK: - R14 fires (Package.swift branch/revision)

    @Test("R14: a dependency pinned to branch: fires as a warning, never an error")
    func r14FiresForBranch() {
        let url = multiFixtureURL("Package.swift")
        let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let diags = RuleEngine.checkR14(packageSwiftSource: source, path: url.path)
        #expect(diags.count == 1)
        #expect(diags.first?.severity == .warning)
        #expect(diags.first?.rule == "R14")
        #expect(diags.first?.message.contains("no es reproducible") == true)
    }

    @Test("R14: a `let revision: String` declaration is not mistaken for a .package(revision:) argument")
    func r14DoesNotFireOnUnrelatedDeclaration() {
        let source = """
            import PackageDescription
            let revision: String = "abc123"
            let branch: String = "main"
            let package = Package(name: "X", dependencies: [
                .package(url: "https://example.com/dep.git", from: "1.0.0")
            ])
            """
        let diags = RuleEngine.checkR14(packageSwiftSource: source, path: "Package.swift")
        #expect(diags.isEmpty)
    }

    @Test("R14: revision: as a call argument also fires")
    func r14FiresForRevision() {
        let source = """
            import PackageDescription
            let package = Package(name: "X", dependencies: [
                .package(url: "https://example.com/dep.git", revision: "abc123")
            ])
            """
        let diags = RuleEngine.checkR14(packageSwiftSource: source, path: "Package.swift")
        #expect(diags.count == 1)
        #expect(diags.first?.severity == .warning)
    }

    // MARK: - resolveModules: local config vs. walking up to a repo-root config vs. override

    @Test("resolveModules walks up from --root to find a parent .archlint.yml's modules:")
    func resolveModulesWalksUpToRepoRoot() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let packageDir = base.appendingPathComponent("Packages/Features")
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let rootConfig = """
            modules:
              Domain:
                allowedImports: [Foundation]
            """
        try rootConfig.write(to: base.appendingPathComponent(".archlint.yml"), atomically: true, encoding: .utf8)

        let modules = ArchLintConfig.resolveModules(currentModules: [], root: packageDir.path, explicitPath: nil)
        #expect(modules.count == 1)
        #expect(modules.first?.pattern == "Domain")
    }

    @Test("resolveModules keeps the local config's own modules: without walking up")
    func resolveModulesKeepsLocalWhenPresent() {
        let local = [ModuleRule(pattern: "Domain", allowedImports: ["Foundation"])]
        let modules = ArchLintConfig.resolveModules(
            currentModules: local,
            root: "/nonexistent-\(UUID().uuidString)",
            explicitPath: nil
        )
        #expect(modules == local)
    }

    @Test("resolveModules: --modules-config overrides everything, even a non-empty local modules:")
    func resolveModulesExplicitPathOverrides() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let explicitPath = base.appendingPathComponent("modules.archlint.yml")
        try "modules.CameraKit.allowedImports: [Foundation, Domain]"
            .write(to: explicitPath, atomically: true, encoding: .utf8)

        let local = [ModuleRule(pattern: "Domain", allowedImports: ["Foundation"])]
        let modules = ArchLintConfig.resolveModules(
            currentModules: local,
            root: "/irrelevant",
            explicitPath: explicitPath.path
        )
        #expect(modules.count == 1)
        #expect(modules.first?.pattern == "CameraKit")
    }
}
