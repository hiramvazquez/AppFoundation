#if canImport(SwiftUI)
import Testing

@testable import AppFoundation

// MARK: - ScreenPresentationLogic.activityContainer — shared between `ScreenContainer` and
// `PhaseView` (extracted so the two views' loading-indicator switches can't silently drift
// out of sync with each other: both now switch on this ONE mapping instead of each
// hardcoding its own copy of "which style gets which container").

@Suite("ScreenPresentationLogic.activityContainer")
struct ActivityContainerLogicTests {
    @Test func fullScreenIsAnOpaqueContainer() {
        #expect(ScreenPresentationLogic.activityContainer(for: .fullScreen) == .opaque)
    }

    @Test func overlayIsADimmedContainer() {
        #expect(ScreenPresentationLogic.activityContainer(for: .overlay) == .dimmed)
    }

    @Test func inlineIsATopAlignedContainer() {
        #expect(ScreenPresentationLogic.activityContainer(for: .inline) == .topAligned)
    }

    /// Every `ActivityStyle` maps to exactly one container — no style is left without a
    /// decision (mirrors the "A2 is dead by construction" guarantee `phaseOverlay` already
    /// has, applied to the container choice instead of the overlay choice).
    @Test(arguments: [ActivityStyle.fullScreen, .inline, .overlay])
    func everyStyleMapsToExactlyOneDistinctContainer(style: ActivityStyle) {
        let container = ScreenPresentationLogic.activityContainer(for: style)
        let others: [ActivityStyle] = [.fullScreen, .inline, .overlay].filter { $0 != style }
        for other in others {
            #expect(ScreenPresentationLogic.activityContainer(for: other) != container)
        }
    }
}
#endif
