#if canImport(SwiftUI)
import Testing
@testable import AppFoundation

// MARK: - AF-12/AF-13: native chrome by default, hidden bar is opt-in only

@Suite("ScreenChrome")
struct ScreenChromeTests {
    /// AF-12: `.native` must NEVER report hiding the system navigation bar — that was the
    /// regression (`.toolbar(.hidden, for: .navigationBar)` applied to every route,
    /// breaking swipe-back). This is the pure-logic guarantee that a `.native` screen keeps
    /// the native bar (and, with it, the interactive pop gesture) intact.
    @Test func nativeChromeNeverHidesTheNavigationBar() {
        #expect(!ScreenPresentationLogic.hidesNativeBar(.native))
    }

    /// AF-13: `.custom` is the ONLY way to hide the native bar — an explicit, opt-in
    /// decision per screen, not a package-wide default.
    @Test func customChromeAlwaysHidesTheNavigationBar() {
        #expect(ScreenPresentationLogic.hidesNativeBar(.custom(.hidden)))
        #expect(ScreenPresentationLogic.hidesNativeBar(.custom(.title("Title"))))
        #expect(ScreenPresentationLogic.hidesNativeBar(.custom(.title("Title"), placement: .overlay)))
    }

    /// `NavigationPlacement` is orthogonal to whether the native bar is hidden — both
    /// placements go through `.custom`.
    @Test(arguments: [NavigationPlacement.stack, .overlay])
    func placementDoesNotAffectWhetherTheNativeBarIsHidden(placement: NavigationPlacement) {
        #expect(ScreenPresentationLogic.hidesNativeBar(.custom(.title("Title"), placement: placement)))
    }
}
#endif
