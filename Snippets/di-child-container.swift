// Un contenedor hijo por flujo (checkout, sesión, wizard): vive lo que dure el
// flujo, sin scope con clave de cadena que crear/destruir a mano.
import AppFoundation

protocol ProfileRepository {
    func fetchProfile() -> String
}

struct LiveProfileRepository: ProfileRepository {
    func fetchProfile() -> String { "Hiram" }
}

final class CheckoutCart {
    var items: [String] = []
}

@MainActor
func makeCheckoutContainer(parent: Container = .shared) -> Container {
    let checkout = Container(parent: parent)
    // Compartido por toda pantalla del flujo.
    checkout.register(CheckoutCart.self) { _ in CheckoutCart() }
    return checkout
}

Container.shared.register(ProfileRepository.self) { _ in LiveProfileRepository() }
let checkout = makeCheckoutContainer()
let cart: CheckoutCart = checkout.resolve()
let repository: ProfileRepository = checkout.resolve()  // cae al padre
assert(repository.fetchProfile() == "Hiram")
assert(cart.items.isEmpty)
