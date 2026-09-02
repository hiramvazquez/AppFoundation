// Paso 2 de la guía «una app en 20 minutos»: registrar dependencias en el
// composition root. `Container` es `@MainActor`; se registra una vez, al arrancar.
import AppFoundation

protocol GreetingServicing {
    func greeting(for name: String) -> String
}

struct GreetingService: GreetingServicing {
    func greeting(for name: String) -> String { "Hola, \(name)" }
}

struct GreetingModule: DependencyModule {
    func register(in container: Container) {
        container.register(GreetingServicing.self) { _ in GreetingService() }
    }
}

Container.shared.register(modules: [GreetingModule()])
let service: GreetingServicing = Container.shared.resolve()
print(service.greeting(for: "Hiram"))
