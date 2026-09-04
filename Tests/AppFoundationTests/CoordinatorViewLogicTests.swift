#if canImport(SwiftUI)
import Testing

@testable import AppFoundation

// MARK: - Pure decisions extracted from `CoordinatorView`'s modal `Binding` closures
// (`CoordinatorViewLogic`, in CoordinatorView.swift) — same pattern as
// `ScreenPresentationLogic`/`ScreenPresentationLogicTests`. Verified directly against
// `PresentationStyle` values instead of constructing a live `Coordinator` + SwiftUI
// hierarchy, which `CoordinatorTests` already exercises for the state machine itself.

@Suite("CoordinatorViewLogic")
struct CoordinatorViewLogicTests {
    // MARK: - isPresented (the `get` half — style-specific, not "any modal exists")

    // NOTE: results are compared with `== <bool>` rather than passed bare (or with a
    // leading `!`) to `#expect` — passing a non-optional case literal (`.sheet`) where a
    // static function expects `PresentationStyle?` otherwise trips an unrelated
    // swift-testing macro expansion quirk ("result of call to ... is unused") when the
    // call is auto-captured for argument reporting.

    @Test func notPresentedWhenNoModalIsActive() {
        #expect(CoordinatorViewLogic.isPresented(currentModalStyle: nil, for: .sheet) == false)
        #expect(CoordinatorViewLogic.isPresented(currentModalStyle: nil, for: .fullScreenCover) == false)
    }

    @Test func presentedOnlyForTheMatchingStyle() {
        #expect(CoordinatorViewLogic.isPresented(currentModalStyle: .sheet, for: .sheet) == true)
        #expect(CoordinatorViewLogic.isPresented(currentModalStyle: .sheet, for: .fullScreenCover) == false)
    }

    /// The sheet binding must NOT also report "presented" while a full screen cover is
    /// active (and vice versa) — SwiftUI would try to present both modifiers at once.
    @Test func differentStylesNeverBothReportPresentedForTheSameActiveModal() {
        for active in [PresentationStyle.sheet, .fullScreenCover] {
            let reportedPresented = [PresentationStyle.sheet, .fullScreenCover]
                .filter { CoordinatorViewLogic.isPresented(currentModalStyle: active, for: $0) }
            #expect(reportedPresented == [active])
        }
    }

    // MARK: - shouldDismiss (the `set` half — only for the modal actually being turned off)

    // NOTE: `shouldDismiss`'s result is compared with `== <bool>` rather than passed bare
    // (or with a leading `!`) to `#expect` — the three-argument static call otherwise trips
    // an unrelated swift-testing macro expansion quirk ("result of call to ... is unused").

    @Test func settingPresentedToTrueNeverDismisses() {
        #expect(
            CoordinatorViewLogic.shouldDismiss(settingPresentedTo: true, currentModalStyle: .sheet, for: .sheet)
                == false
        )
        #expect(
            CoordinatorViewLogic.shouldDismiss(settingPresentedTo: true, currentModalStyle: nil, for: .sheet) == false
        )
    }

    @Test func settingPresentedToFalseDismissesWhenThatStyleIsTheActiveModal() {
        #expect(
            CoordinatorViewLogic.shouldDismiss(settingPresentedTo: false, currentModalStyle: .sheet, for: .sheet)
                == true
        )
        #expect(
            CoordinatorViewLogic.shouldDismiss(
                settingPresentedTo: false,
                currentModalStyle: .fullScreenCover,
                for: .fullScreenCover
            ) == true
        )
    }

    /// A7 / the actual bug this exists to prevent: a `.sheet` binding turning itself off
    /// must NOT dismiss a `.fullScreenCover` that has since replaced it (and vice versa) —
    /// only the binding for the style that is CURRENTLY active is allowed to dismiss.
    @Test func stalePresentedBindingDoesNotDismissADifferentActiveModal() {
        #expect(
            CoordinatorViewLogic.shouldDismiss(
                settingPresentedTo: false,
                currentModalStyle: .fullScreenCover,
                for: .sheet
            ) == false
        )
        #expect(
            CoordinatorViewLogic.shouldDismiss(
                settingPresentedTo: false,
                currentModalStyle: .sheet,
                for: .fullScreenCover
            ) == false
        )
    }

    @Test func settingPresentedToFalseWithNoActiveModalDoesNothing() {
        #expect(
            CoordinatorViewLogic.shouldDismiss(settingPresentedTo: false, currentModalStyle: nil, for: .sheet)
                == false
        )
    }
}
#endif
