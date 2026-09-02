import Foundation
import Testing

@testable import AppFoundation

/// `load`/`activity` (estructurados) deben dejar la pantalla en `.loading` mientras corre
/// el trabajo, exactamente igual que `performLoad`/`performActivity`. Regresión del doble
/// check posterior a X-02: las variantes estructuradas saltaban ese paso.
@Suite("LoadableViewModel — variantes estructuradas")
struct StructuredLoadTests {
    final class ProbeViewModel: BaseViewModel {
        var phaseWhileWorking: ViewPhase = .idle
        var activityWhileWorking: ActivityState = .none
    }

    @Test func loadShowsLoadingWhileWorkRunsAndContentAfter() async {
        let vm = ProbeViewModel()
        await vm.load(style: .inline) { vm in vm.phaseWhileWorking = vm.phase }
        #expect(vm.phaseWhileWorking == .loading(.inline))
        #expect(vm.phase == .content)
    }

    @Test func loadFailureEndsInErrorPhase() async {
        struct Boom: Error {}
        let vm = ProbeViewModel()
        await vm.load { _ in throw Boom() }
        #expect(vm.hasError)
    }

    @Test func activityShowsIndicatorWhileWorkRunsAndStopsAfter() async {
        let vm = ProbeViewModel()
        await vm.activity(style: .inline) { vm in vm.activityWhileWorking = vm.activity }
        #expect(vm.activityWhileWorking == .loading(.inline))
        #expect(vm.activity == .none)
    }
}
