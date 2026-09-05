import Observation

/// Conduce la secuencia entera y decide el veredicto. Es la traducción a código de la QA
/// manual documentada en `ScreenContainerCancellationTests.swift`:
///
///     PUSH B (root -> B) · B .task STARTED
///     PUSH C (B -> C): B queda TAPADA, no eliminada
///     1s después: sigue sin cancelarse
///     POP TO ROOT (elimina B y C) · B .task CANCELLED
///
/// Cada paso espera a un evento observable de `EventBus`, nunca a un `sleep` fijo — ver
/// su doc comment. El único punto donde SÍ hay una espera de duración fija es la
/// comprobación de "no se cancela mientras está tapada": ahí la ausencia de evento
/// durante una ventana acotada ES el resultado correcto, así que no hay forma de
/// sustituirla por una espera a una señal (no hay señal que esperar cuando lo que se
/// verifica es que algo NO ocurre).
@MainActor
@Observable
final class ProbeDriver {
    var path: [Route] = []
    let bus = EventBus()
    let bViewModel: ProbeViewModel

    /// Cuánto se espera a que aparezca un evento antes de declarar fallo.
    private let signalTimeout: Duration = .seconds(5)
    /// Cuánto se espera, tapada, para confirmar que B NO se cancela mientras está cubierta
    /// por C. Deliberadamente corto: solo hace falta demostrar que no cancela de
    /// inmediato al quedar tapada, que es exactamente el bug que este mecanismo existe
    /// para detectar.
    private let coveredWindow: Duration = .milliseconds(500)

    init() {
        bViewModel = ProbeViewModel(screenName: "B", bus: bus)
    }

    /// Ejecuta la secuencia y devuelve el código de salida del proceso: `0` si el
    /// contrato se cumplió exactamente como se espera, `1` en cualquier otro caso (con el
    /// motivo ya escrito en el log de `bus`).
    func run() async -> Int32 {
        bus.log("PUSH B (root -> B)")
        path.append(.b)

        guard
            await bus.wait(
                timeout: signalTimeout,
                matches: { event in
                    if case .taskStarted(screen: "B") = event { return true }
                    return false
                }
            ) != nil
        else {
            bus.log(
                "FALLO: B .task no arrancó en \(signalTimeout) tras el push — el probe está mal cableado, no SwiftUI."
            )
            return 1
        }

        bus.log("PUSH C (B -> C): B queda TAPADA, no eliminada")
        path.append(.c)

        if let regresion = await bus.wait(
            timeout: coveredWindow,
            matches: { event in
                if case .taskEnded(screen: "B", cancelled: true) = event { return true }
                return false
            }
        ) {
            bus.log(
                "FALLO: B se canceló al quedar TAPADA (\(regresion)) — REGRESIÓN: el push adelante "
                    + "está cancelando trabajo de la pantalla anterior."
            )
            return 1
        }
        bus.log("\(coveredWindow) tapada: B sigue sin cancelarse (correcto)")

        bus.log("POP TO ROOT (elimina B y C)")
        path.removeAll()

        guard
            let cancelado = await bus.wait(
                timeout: signalTimeout,
                matches: { event in
                    if case .taskEnded(screen: "B", cancelled: true) = event { return true }
                    return false
                }
            )
        else {
            bus.log("FALLO: B no se canceló en \(signalTimeout) tras el pop — el contrato NO se cumple.")
            return 1
        }
        bus.log("B .task CANCELLED (\(cancelado))")
        return 0
    }
}
