import AppFoundation
import SwiftUI

/// Las dos pantallas que la secuencia push → push → pop necesita. `b` es la que se
/// instrumenta con `ProbeViewModel`; `c` solo existe para tapar `b` sin eliminarla.
enum Route: Hashable {
    case b
    case c
}

/// Jerarquía real de `NavigationStack` — no una vista aislada — porque lo que se
/// verifica es precisamente cómo SwiftUI trata la identidad de `b` cuando queda
/// TAPADA por `c` frente a cuando `path.removeAll()` la elimina de verdad.
struct RootView: View {
    @Bindable var driver: ProbeDriver

    var body: some View {
        NavigationStack(path: $driver.path) {
            Text("root")
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .b:
                        ScreenContainer(driver.bViewModel) { send in
                            Color.clear.task { send(.load) }
                        }
                    case .c:
                        Text("c")
                    }
                }
        }
        .frame(width: 400, height: 300)
    }
}
