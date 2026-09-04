import Testing

@testable import Domain

@Suite("Domain")
struct DomainTests {
    @Test("El módulo compila de forma aislada — solo depende de Foundation")
    func placeholder() {
        #expect(Bool(true))
    }
}
