import Foundation
import Testing

@testable import AppFoundation

// MARK: - Espías de colaboradores

/// Espía de `ErrorPresenting`. `screenError(for:...)` no es `async` — un `SpyRecorder`
/// (actor) no serviría aquí, porque no se puede `await` desde una función síncrona — así
/// que graba con un candado explícito, igual que `Recorder` en `TestSupport.swift`.
/// `nonisolated` a propósito (R16 solo exige `deinit` explícito en clases NO
/// `nonisolated`), pero se lo damos igualmente por higiene, como pide la tarea.
nonisolated final class ErrorPresenterSpy: ErrorPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []

    /// Descripción de cada error con el que se consultó, en orden.
    var events: [String] { lock.withLock { _events } }
    var callCount: Int { events.count }

    func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError {
        lock.withLock { _events.append(String(describing: error)) }
        return ScreenError(title: "spy-presented", message: "spy", retry: retry)
    }

    deinit {}
}

/// Espía de `CancellationRecognizing`: registra cada consulta y deja que el test decida,
/// por closure, qué errores reconoce como cancelación.
nonisolated final class CancellationRecognizerSpy: CancellationRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    private let recognizes: @Sendable (any Error) -> Bool

    init(recognizes: @escaping @Sendable (any Error) -> Bool) {
        self.recognizes = recognizes
    }

    var events: [String] { lock.withLock { _events } }
    var callCount: Int { events.count }

    func isCancellation(_ error: any Error) -> Bool {
        lock.withLock { _events.append(String(describing: error)) }
        return recognizes(error)
    }

    deinit {}
}

// MARK: - Contrato: CancellationRecognizing se consulta ANTES que ErrorPresenting

/// `ErrorPresenting.screenError(for:...)` documenta sobre su parámetro `error`: "Never a
/// cancellation — `BaseViewModel` filters those out through `CancellationRecognizing`
/// before calling the presenter." Estos tests fijan ese orden con espías inyectados por
/// `init` (nunca mutando los `static var`, DC-AF-3): si alguien invirtiera las dos
/// comprobaciones, cada cancelación pasaría a mostrarse como error de pantalla y ningún
/// otro test de la suite lo notaría.
@Suite("BaseViewModel — CancellationRecognizing antes que ErrorPresenting")
struct BaseViewModelRecognizerBeforePresenterTests {
    // MARK: performLoad

    @Test("performLoad: un error reconocido como cancelación no llega nunca al presenter")
    func performLoadCancellationNeverReachesPresenter() async {
        let presenter = ErrorPresenterSpy()
        let recognizer = CancellationRecognizerSpy(recognizes: { _ in true })
        let vm = BaseViewModel(errorPresenter: presenter, cancellationRecognizer: recognizer)

        let task = vm.performLoad { _ in throw TestError("network-cancelled") }
        await task.value

        #expect(
            presenter.callCount == 0,
            """
            El recognizer reconoció el error como cancelación; el presenter NO debía consultarse. \
            recognizer.events=\(recognizer.events), presenter.events=\(presenter.events)
            """
        )
        #expect(recognizer.callCount == 1)
        #expect(!vm.hasError)
    }

    @Test("performLoad: un error NO reconocido como cancelación llega al presenter exactamente una vez")
    func performLoadNonCancellationReachesPresenterOnce() async {
        let presenter = ErrorPresenterSpy()
        let recognizer = CancellationRecognizerSpy(recognizes: { _ in false })
        let vm = BaseViewModel(errorPresenter: presenter, cancellationRecognizer: recognizer)

        let task = vm.performLoad { _ in throw TestError("real-failure") }
        await task.value

        #expect(
            presenter.callCount == 1,
            """
            Un fallo real debe consultar el presenter exactamente una vez; se consultó \
            \(presenter.callCount) veces. events=\(presenter.events)
            """
        )
        #expect(recognizer.callCount == 1)
        #expect(vm.hasError)
    }

    // MARK: performActivity (handleActivityError también consulta el presenter)

    @Test("performActivity: un error reconocido como cancelación no llega nunca al presenter")
    func performActivityCancellationNeverReachesPresenter() async {
        let presenter = ErrorPresenterSpy()
        let recognizer = CancellationRecognizerSpy(recognizes: { _ in true })
        let vm = BaseViewModel(errorPresenter: presenter, cancellationRecognizer: recognizer)

        let task = vm.performActivity { _ in throw TestError("network-cancelled") }
        await task.value

        #expect(
            presenter.callCount == 0,
            """
            El recognizer reconoció el error de la actividad como cancelación; el presenter NO \
            debía consultarse (ni siquiera vía handleActivityError). \
            recognizer.events=\(recognizer.events), presenter.events=\(presenter.events)
            """
        )
        #expect(recognizer.callCount == 1)
        #expect(vm.banner == nil)
    }

    @Test("performActivity: un error NO reconocido llega al presenter exactamente una vez vía handleActivityError")
    func performActivityNonCancellationReachesPresenterOnce() async {
        let presenter = ErrorPresenterSpy()
        let recognizer = CancellationRecognizerSpy(recognizes: { _ in false })
        let vm = BaseViewModel(errorPresenter: presenter, cancellationRecognizer: recognizer)

        let task = vm.performActivity { _ in throw TestError("real-failure") }
        await task.value

        #expect(
            presenter.callCount == 1,
            """
            Un fallo real de actividad debe consultar el presenter exactamente una vez (a través de \
            handleActivityError); se consultó \(presenter.callCount) veces. events=\(presenter.events)
            """
        )
        #expect(recognizer.callCount == 1)
    }
}
