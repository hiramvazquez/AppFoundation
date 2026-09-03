import Foundation
import Testing

@testable import AppFoundation

// MARK: - PRD-X-05 A3 / A7: la View retiene su ViewModel; nada se pierde en silencio

/// ViewModel de prueba: deja constancia en `recorder` de cada vez que su `work` corre de
/// verdad. Si el VM muere antes de que el `work` arranque, no hay evento — exactamente el
/// síntoma que AppStarter vio en pantalla (vacía, sin spinner ni error).
@MainActor
private final class OwnershipProbeViewModel: BaseViewModel, ActionHandling {
    enum Action: Sendable {
        case load
        case refresh
    }

    let recorder: Recorder

    init(recorder: Recorder) {
        self.recorder = recorder
        super.init()
    }

    func handle(_ action: Action) {
        switch action {
        case .load:
            performLoad { vm in vm.recorder.record("load-work") }
        case .refresh:
            performActivity { vm in vm.recorder.record("refresh-work") }
        }
    }
}

/// Reproduce, sin SwiftUI, el fallo del patrón `let viewModel` en una View (A3): SwiftUI
/// reejecuta el builder de destino durante el push y sustituye la instancia que recibió
/// `.load`. Aquí «sustituir» es soltar la última referencia fuerte — el `sender` (débil)
/// y el `Task` de `performLoad` (débil) son lo único que queda, como en la app real.
///
/// `.serialized`: `AppFoundationDiagnostics.droppedActionHandler` es un hook global; dos
/// tests de esta suite no pueden instalarlo a la vez.
@Suite("View ↔ ViewModel — propiedad con @State (PRD-X-05 A3/A7)", .serialized)
struct ViewModelOwnershipTests {
    /// Instala el hook de diagnóstico y devuelve el recorder que recibe cada mensaje.
    @MainActor
    private func installDropHandler() -> Recorder {
        let reports = Recorder()
        AppFoundationDiagnostics.droppedActionHandler = { reports.record($0) }
        return reports
    }

    private func drops(in reports: Recorder) -> [String] {
        // Otros tests (en paralelo, fuera de esta suite) pueden soltar VMs propios; solo
        // cuentan los mensajes sobre el VM de esta suite.
        reports.events.filter { $0.contains("OwnershipProbeViewModel") }
    }

    // MARK: - Caso negativo: el patrón `let` — la acción se pierde, pero ya no en silencio

    /// Un `sender` obtenido de una instancia que después muere: `send(.load)` no ejecuta
    /// nada (ni `work`, ni error, ni crash) y, tras A7, el descarte queda registrado con
    /// la acción, el tipo del VM y la pista de `@State`.
    @Test func actionSentToADeallocatedViewModelIsDroppedAndReported() {
        let reports = installDropHandler()
        defer { AppFoundationDiagnostics.droppedActionHandler = nil }
        let work = Recorder()

        weak var weakVM: OwnershipProbeViewModel?
        var sender: ActionSender<OwnershipProbeViewModel.Action>?
        _ = {
            let viewModel = OwnershipProbeViewModel(recorder: work)
            weakVM = viewModel
            sender = viewModel.sender
        }()
        #expect(weakVM == nil)  // «la instancia A muere»

        sender?(.load)

        #expect(work.events.isEmpty)  // nada corrió, ningún error: la pantalla se quedaría vacía
        #if DEBUG
        let dropped = drops(in: reports)
        #expect(dropped.count == 1)
        #expect(dropped.first?.hasPrefix("Action load dropped: its ViewModel (OwnershipProbeViewModel)") == true)
        #expect(dropped.first?.contains("retain the ViewModel with @State in the View") == true)
        #else
        #expect(reports.events.isEmpty)
        #endif
    }

    /// La otra mitad del mismo fallo: el VM recibió `.load` (el `Task` ya existe) y muere
    /// ANTES de que el `Task` llegue a correr — `deinit` lo cancela y el `work` nunca
    /// arranca. Tras A7, `performLoad` deja constancia del salto.
    @Test func performLoadWorkSkippedAfterDeallocationIsReported() async {
        let reports = installDropHandler()
        defer { AppFoundationDiagnostics.droppedActionHandler = nil }
        let work = Recorder()

        var viewModel: OwnershipProbeViewModel? = OwnershipProbeViewModel(recorder: work)
        weak let weakVM = viewModel
        viewModel?.handle(.load)
        let task = viewModel?.inFlightLoad
        #expect(task != nil)

        // Sin punto de suspensión desde `handle(.load)`: el `Task` aún no ha corrido.
        viewModel = nil
        #expect(weakVM == nil)

        await task?.value

        #expect(work.events.isEmpty)
        #if DEBUG
        #expect(
            drops(in: reports) == ["performLoad work skipped: OwnershipProbeViewModel was deallocated before it ran"]
        )
        #else
        #expect(reports.events.isEmpty)
        #endif
    }

    /// Mismo contrato para `performActivity`.
    @Test func performActivityWorkSkippedAfterDeallocationIsReported() async {
        let reports = installDropHandler()
        defer { AppFoundationDiagnostics.droppedActionHandler = nil }
        let work = Recorder()

        var viewModel: OwnershipProbeViewModel? = OwnershipProbeViewModel(recorder: work)
        weak let weakVM = viewModel
        viewModel?.handle(.refresh)
        let task = viewModel?.inFlightActivity
        #expect(task != nil)

        viewModel = nil
        #expect(weakVM == nil)

        await task?.value

        #expect(work.events.isEmpty)
        #if DEBUG
        #expect(
            drops(in: reports) == [
                "performActivity work skipped: OwnershipProbeViewModel was deallocated before it ran"
            ]
        )
        #else
        #expect(reports.events.isEmpty)
        #endif
    }

    // MARK: - Caso positivo: la instancia viva (lo que `@State` garantiza)

    /// Con la instancia retenida (lo que `@State` hace en la View), el mismo `sender` y la
    /// misma acción ejecutan el `work`, la fase llega a `.content` y no hay ningún descarte
    /// que registrar.
    @Test func actionSentToALiveViewModelRunsItsWorkWithoutAnyReport() async {
        let reports = installDropHandler()
        defer { AppFoundationDiagnostics.droppedActionHandler = nil }
        let work = Recorder()

        let viewModel = OwnershipProbeViewModel(recorder: work)
        let sender = viewModel.sender

        sender(.load)
        await viewModel.inFlightLoad?.value

        #expect(work.events == ["load-work"])
        #expect(viewModel.isContent)
        #expect(drops(in: reports).isEmpty)

        sender(.refresh)
        await viewModel.inFlightActivity?.value

        #expect(work.events == ["load-work", "refresh-work"])
        #expect(viewModel.activity == .none)
        #expect(drops(in: reports).isEmpty)
    }
}
