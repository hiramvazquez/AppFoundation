import Foundation

/// Registro de eventos de ciclo de vida, con espera determinista por timeout.
///
/// Existe para convertir la verificación manual descrita en
/// `ScreenContainerCancellationTests.swift` (montar una app SwiftUI de usar y tirar,
/// mirar un log a ojo) en algo que un proceso pueda comprobar solo: cada paso de la
/// secuencia push → push → pop espera a un evento OBSERVABLE (nunca a un `sleep` fijo
/// cruzando los dedos), y el timeout de esa espera es un FALLO explícito, no un cuelgue.
@MainActor
final class EventBus {
    /// Los únicos eventos que le interesan a esta verificación: cuándo arranca el
    /// trabajo en vuelo de una pantalla y cuándo termina (y si terminó por cancelación).
    enum Event: Sendable, Equatable, CustomStringConvertible {
        case taskStarted(screen: String)
        case taskEnded(screen: String, cancelled: Bool)

        var description: String {
            switch self {
            case .taskStarted(let screen):
                return "\(screen) .task STARTED"
            case .taskEnded(let screen, let cancelled):
                return "\(screen) .task ENDED (cancelled: \(cancelled))"
            }
        }
    }

    private(set) var history: [Event] = []

    /// Escribe una línea con marca de tiempo en stdout — el mismo log que se inspeccionaba
    /// a mano en la QA manual, ahora también consumido por `wait(timeout:matches:)`.
    func log(_ message: String) {
        print("[\(Self.timestamp())] \(message)")
    }

    func emit(_ event: Event) {
        log(event.description)
        history.append(event)
    }

    /// Espera a que ocurra un evento que cumpla `predicate`, comprobando cada 5 ms hasta
    /// `timeout`. Si el evento ya ocurrió, devuelve al instante. Si `timeout` se cumple sin
    /// que el evento aparezca, devuelve `nil` — eso es lo que el llamador debe tratar como
    /// fallo, nunca como "asumir que pasó".
    func wait(timeout: Duration, matches predicate: (Event) -> Bool) async -> Event? {
        let deadline = ContinuousClock.now + timeout
        while true {
            if let found = history.first(where: predicate) {
                return found
            }
            if ContinuousClock.now >= deadline {
                return nil
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
