// Paso 3 de la guía «una app en 20 minutos»: rutas + Coordinator. Una pila de
// navegación con una sola capa modal — ver <doc:Navigation> para el resto del contrato.
import AppFoundation
import SwiftUI

enum AppRoute: Hashable {
    case home
    case greeting(name: String)
}

struct RootView: View {
    @State private var coordinator = Coordinator<AppRoute>(root: .home)

    var body: some View {
        CoordinatorView(coordinator: coordinator) { route in
            switch route {
            case .home:
                Text("Home")
            case .greeting(let name):
                Text("Hola, \(name)")
            }
        }
    }
}
