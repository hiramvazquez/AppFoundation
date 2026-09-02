import Testing

@testable import GenerateFeatureSupport

@Suite("TemplateEngine")
struct TemplateEngineTests {
    @Test("Substitutes a simple variable")
    func substitutesVariable() {
        let result = TemplateEngine.render("Hello {{Name}}!", substitutions: ["Name": "Login"], flags: [:])
        #expect(result == "Hello Login!")
    }

    @Test("A missing variable renders as empty")
    func missingVariableRendersEmpty() {
        let result = TemplateEngine.render("[{{Missing}}]", substitutions: [:], flags: [:])
        #expect(result == "[]")
    }

    @Test("A true section renders its content")
    func trueSectionRenders() {
        let result = TemplateEngine.render("{{#api}}api{{/api}}", substitutions: [:], flags: ["api": true])
        #expect(result == "api")
    }

    @Test("A false section renders nothing")
    func falseSectionRendersNothing() {
        let result = TemplateEngine.render("{{#api}}api{{/api}}", substitutions: [:], flags: ["api": false])
        #expect(result.isEmpty)
    }

    @Test("A missing flag behaves like false")
    func missingFlagIsFalse() {
        let result = TemplateEngine.render("{{#api}}api{{/api}}", substitutions: [:], flags: [:])
        #expect(result.isEmpty)
    }

    @Test("Inverted section renders when the flag is false")
    func invertedSectionRendersWhenFalse() {
        let result = TemplateEngine.render("{{^api}}no-api{{/api}}", substitutions: [:], flags: ["api": false])
        #expect(result == "no-api")
    }

    @Test("Inverted section renders nothing when the flag is true")
    func invertedSectionRendersNothingWhenTrue() {
        let result = TemplateEngine.render("{{^api}}no-api{{/api}}", substitutions: [:], flags: ["api": true])
        #expect(result.isEmpty)
    }

    @Test("Sections nest correctly")
    func sectionsNest() {
        let template = "{{#outer}}before-{{#inner}}inner{{/inner}}-after{{/outer}}"
        let bothOn = TemplateEngine.render(template, substitutions: [:], flags: ["outer": true, "inner": true])
        #expect(bothOn == "before-inner-after")

        let innerOff = TemplateEngine.render(template, substitutions: [:], flags: ["outer": true, "inner": false])
        #expect(innerOff == "before--after")

        let outerOff = TemplateEngine.render(template, substitutions: [:], flags: ["outer": false, "inner": true])
        #expect(outerOff.isEmpty)
    }

    @Test("Same-named sections at different nesting levels each match their own close tag")
    func sameNamedNestedSectionsResolveIndependently() {
        let template = "{{#x}}outer-{{^x}}should-not-render{{/x}}{{/x}}"
        let result = TemplateEngine.render(template, substitutions: [:], flags: ["x": true])
        #expect(result == "outer-")
    }

    @Test("Renders a realistic Logic.swift.txt-shaped fragment for the API-only variant")
    func rendersApiOnlyFragment() {
        let template = """
            {{#both}}
            func cached() async -> [Item] { [] }
            {{/both}}
            {{^both}}
            {{#api}}
            func load() async throws -> [Item] { try await service.fetchItems() }
            {{/api}}
            {{#local}}
            func load() async throws -> [Item] { try await store.fetchAll() }
            {{/local}}
            {{/both}}
            """
        let result = TemplateEngine.render(
            template,
            substitutions: [:],
            flags: ["api": true, "local": false, "both": false]
        )
        #expect(result.contains("service.fetchItems()"))
        #expect(!result.contains("store.fetchAll()"))
        #expect(!result.contains("cached()"))
    }
}
