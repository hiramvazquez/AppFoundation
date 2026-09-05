#if canImport(SwiftUI)
import SwiftUI
import Testing

@testable import AppFoundation

// MARK: - Render smoke tests (`ImageRenderer`, no external dependency)
//
// These are deliberately NOT pixel/"golden" snapshot tests — that would be frágil across
// OS/toolchain versions, and the task explicitly rules out adding a snapshot-testing
// dependency. All they assert is that a genuinely complex view (back button + title +
// search field + badge, every screen phase, the coordinator's navigation stack) resolves
// to a non-empty rendered image WITHOUT crashing. That is a real, if narrow, claim: it
// exercises `body`/`@ViewBuilder` code paths that the pure-logic tests elsewhere in this
// package (`NavigationBarLogicTests`, `ScreenPresentationLogicTests`, ...) never touch,
// since those test the DECISIONS, never the rendering itself. The decisions these views
// make are what's actually verified — this file only proves the wiring around them doesn't
// blow up.
@Suite("Render smoke tests (ImageRenderer)")
struct RenderSmokeTests {
    /// Renders `view` off-screen at a fixed, finite size (SwiftUI views using
    /// `.frame(maxWidth: .infinity, ...)` need an explicit `proposedSize` — `ImageRenderer`
    /// can't resolve an infinite frame on its own) and returns the resulting image's pixel
    /// size, or `nil` if rendering produced nothing.
    @MainActor
    private func renderedImageSize(_ view: some View, size: CGSize = CGSize(width: 320, height: 480)) -> CGSize? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        guard let cgImage = renderer.cgImage else { return nil }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    // MARK: - CustomNavigationBar (656 líneas, 0% antes de esta ronda)

    @MainActor
    @Test func customNavigationBarWithBackTitleBadgeAndSearchRendersANonEmptyImage() {
        let bar = CustomNavigationBar(
            configuration: NavigationBarConfiguration(
                title: .text("Games"),
                leftItems: [.back {}],
                rightItems: [.icon("bell", badge: 5) {}, .icon("gear") {}],
                searchBar: SearchBarConfiguration(text: .constant("swift")),
                style: .solid
            )
        )
        let size = renderedImageSize(bar, size: CGSize(width: 380, height: 140))
        #expect((size?.width ?? 0) > 0)
        #expect((size?.height ?? 0) > 0)
    }

    @MainActor
    @Test func customNavigationBarWithFullWidthCustomContentRendersANonEmptyImage() {
        let bar = CustomNavigationBar(
            configuration: .custom(style: .transparent) {
                HStack {
                    Text("Custom")
                    Spacer()
                    Text("Header")
                }
            }
        )
        let size = renderedImageSize(bar, size: CGSize(width: 300, height: 60))
        #expect((size?.width ?? 0) > 0)
        #expect((size?.height ?? 0) > 0)
    }

    @Test func hiddenNavigationBarRendersNothingRatherThanCrashing() async {
        let bar = CustomNavigationBar(configuration: .hidden)
        let size = await MainActor.run { renderedImageSize(bar, size: CGSize(width: 300, height: 60)) }
        // `.hidden` legitimately renders an empty view (`isVisible == false`) — the point
        // here is only that it doesn't crash; a zero-size/nil image is the CORRECT outcome.
        #expect(size != nil)
    }

    // MARK: - ScreenContainer (every phase, native and custom chrome)

    @MainActor
    @Test(
        arguments: [
            ViewPhase.idle, .content, .loading(.fullScreen), .loading(.inline), .loading(.overlay), .empty,
            .error(ScreenError(title: "Network Error", message: "Offline"))
        ]
    )
    func screenContainerRendersANonEmptyImageForEveryPhase(phase: ViewPhase) {
        let container = ScreenContainer(phase: .constant(phase)) {
            Text("Content")
        }
        let size = renderedImageSize(container)
        #expect((size?.width ?? 0) > 0)
        #expect((size?.height ?? 0) > 0)
    }

    /// `cancelsInFlightWorkOnRemoval: false` (the opt-out for work that must survive the
    /// view — see `ScreenContainer`'s doc comment) is a new initializer parameter as of this
    /// change: this only proves it doesn't break rendering. The behavioral claim (the
    /// watchdog never calls `cancelInFlightWork()` when opted out) is
    /// `ScreenContainerCancellationTests.optingOutNeverCallsCancelInFlightWorkEvenWhenCancelled`
    /// — `ImageRenderer` doesn't drive `.task` attach/cancel at all (see that file's doc
    /// comment), so it couldn't verify that even if it rendered twice.
    @MainActor
    @Test func screenContainerOptedOutOfCancelOnRemovalStillRendersANonEmptyImage() {
        let container = ScreenContainer(
            phase: .constant(.content),
            cancelsInFlightWorkOnRemoval: false
        ) {
            Text("Content")
        }
        let size = renderedImageSize(container)
        #expect((size?.width ?? 0) > 0)
        #expect((size?.height ?? 0) > 0)
    }

    @MainActor
    @Test func screenContainerWithCustomChromeRendersANonEmptyImage() {
        let container = ScreenContainer(
            phase: .constant(.content),
            chrome: .custom(.withBack(title: "Detail", backAction: {}))
        ) {
            Text("Content")
        }
        let size = renderedImageSize(container)
        #expect((size?.width ?? 0) > 0)
        #expect((size?.height ?? 0) > 0)
    }

    @MainActor
    @Test func screenContainerWithBannerRendersANonEmptyImage() {
        let container = ScreenContainer(
            phase: .constant(.content),
            banner: .constant(.success("Saved!"))
        ) {
            Text("Content")
        }
        let size = renderedImageSize(container)
        #expect((size?.width ?? 0) > 0)
        #expect((size?.height ?? 0) > 0)
    }

    // MARK: - PhaseView (every phase)

    @MainActor
    @Test(
        arguments: [
            ViewPhase.idle, .content, .loading(.fullScreen), .loading(.inline), .loading(.overlay), .empty,
            .error(ScreenError(title: "Network Error", message: "Offline"))
        ]
    )
    func phaseViewRendersANonEmptyImageForEveryPhase(phase: ViewPhase) {
        let view = PhaseView(phase: .constant(phase)) {
            Text("Content")
        }
        let size = renderedImageSize(view)
        #expect((size?.width ?? 0) > 0)
        #expect((size?.height ?? 0) > 0)
    }

    // MARK: - CoordinatorView (root stack, no modal — a modal is a separate window/sheet
    // that `ImageRenderer` cannot capture regardless of test approach)

    @MainActor
    @Test func coordinatorViewRendersANonEmptyImageForItsRootRoute() {
        let coordinator = Coordinator<Int>(root: 1)
        let view = CoordinatorView(coordinator: coordinator) { route in
            Text("Route \(route)")
        }
        let size = renderedImageSize(view)
        #expect((size?.width ?? 0) > 0)
        #expect((size?.height ?? 0) > 0)
    }

    @MainActor
    @Test func coordinatorViewRendersANonEmptyImageAfterPushingARoute() {
        let coordinator = Coordinator<Int>(root: 1)
        coordinator.push(2)
        let view = CoordinatorView(coordinator: coordinator) { route in
            Text("Route \(route)")
        }
        let size = renderedImageSize(view)
        #expect((size?.width ?? 0) > 0)
        #expect((size?.height ?? 0) > 0)
    }
}
#endif
