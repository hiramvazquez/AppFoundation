import AppFoundation

/// El `ScreenViewModel` mínimo que necesita este probe: un `BaseViewModel` real (no un
/// doble de test) para ejercitar el mecanismo COMPLETO — `ScreenContainer` +
/// `performLoad` + `cancelInFlightWork()` — tal y como lo usaría una pantalla real, no
/// solo la mitad que `ScreenContainerCancellationTests` ya cubre llamando al watchdog
/// directamente.
///
/// `.load` arranca un `performLoad` que se queda dormido "para siempre" (100 años):
/// nunca termina por sí solo, así que la única forma de que emita `taskEnded` es que
/// alguien cancele `inFlightLoad` — exactamente lo que `ScreenContainer` hace al
/// eliminar la vista de la jerarquía.
@MainActor
final class ProbeViewModel: BaseViewModel, ActionHandling {
    enum Action: Sendable {
        case load
    }

    let screenName: String
    let bus: EventBus

    init(screenName: String, bus: EventBus) {
        self.screenName = screenName
        self.bus = bus
        super.init()
    }

    deinit {}

    func handle(_ action: Action) {
        switch action {
        case .load:
            performLoad { vm in
                vm.bus.emit(.taskStarted(screen: vm.screenName))
                do {
                    try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
                } catch {
                    vm.bus.emit(.taskEnded(screen: vm.screenName, cancelled: Task.isCancelled))
                    throw error
                }
            }
        }
    }
}
