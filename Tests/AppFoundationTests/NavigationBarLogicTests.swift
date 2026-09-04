#if canImport(SwiftUI)
import Testing

@testable import AppFoundation

// MARK: - Pure decisions extracted from `CustomNavigationBar`'s body/@ViewBuilder code
// (`NavigationBarLogic`, in CustomNavigationBar.swift) — same pattern as
// `ScreenPresentationLogic`/`ScreenPresentationLogicTests`.

@Suite("NavigationBarLogic")
struct NavigationBarLogicTests {
    // MARK: - hasBackButton (drives the back button's fade-in animation)

    @Test func noBackButtonWhenLeftItemsIsEmpty() {
        #expect(!NavigationBarLogic.hasBackButton(in: []))
    }

    @Test func noBackButtonWhenLeftItemsHasOnlyPlainItems() {
        let items = [NavigationBarItem.icon("gear") {}, .text("Edit") {}]
        #expect(!NavigationBarLogic.hasBackButton(in: items))
    }

    @Test func hasBackButtonWhenABackItemIsPresent() {
        #expect(NavigationBarLogic.hasBackButton(in: [.back {}]))
    }

    @Test func hasBackButtonEvenWhenTheBackItemIsNotFirst() {
        let items = [NavigationBarItem.icon("gear") {}, .back {}]
        #expect(NavigationBarLogic.hasBackButton(in: items))
    }

    /// `.close` is a distinct role from `.back` — a close button must never trigger the
    /// back button's fade-in animation.
    @Test func closeItemDoesNotCountAsABackButton() {
        #expect(!NavigationBarLogic.hasBackButton(in: [.close {}]))
    }

    // MARK: - shouldShowBadge (positive counts only)

    @Test func badgeShowsForAnyPositiveCount() {
        #expect(NavigationBarLogic.shouldShowBadge(1))
        #expect(NavigationBarLogic.shouldShowBadge(99))
        #expect(NavigationBarLogic.shouldShowBadge(1000))
    }

    @Test func badgeHidesForZero() {
        #expect(!NavigationBarLogic.shouldShowBadge(0))
    }

    @Test func badgeHidesForNegativeCounts() {
        #expect(!NavigationBarLogic.shouldShowBadge(-1))
    }

    // MARK: - badgeText (caps at "99+")

    @Test func badgeTextShowsTheExactCountUnder100() {
        #expect(NavigationBarLogic.badgeText(for: 1) == "1")
        #expect(NavigationBarLogic.badgeText(for: 42) == "42")
        #expect(NavigationBarLogic.badgeText(for: 99) == "99")
    }

    @Test func badgeTextCapsAt99Plus() {
        #expect(NavigationBarLogic.badgeText(for: 100) == "99+")
        #expect(NavigationBarLogic.badgeText(for: 12345) == "99+")
    }

    // MARK: - isEmphasizedIcon (role-based, not icon-name-based — A11)

    @Test func onlyBackRoleIsEmphasized() {
        #expect(NavigationBarLogic.isEmphasizedIcon(for: .back))
        #expect(!NavigationBarLogic.isEmphasizedIcon(for: .close))
        #expect(!NavigationBarLogic.isEmphasizedIcon(for: .plain))
    }

    // MARK: - needsCloseAccessibilityLabel

    @Test func onlyCloseRoleNeedsTheCloseAccessibilityLabel() {
        #expect(NavigationBarLogic.needsCloseAccessibilityLabel(for: .close))
        #expect(!NavigationBarLogic.needsCloseAccessibilityLabel(for: .back))
        #expect(!NavigationBarLogic.needsCloseAccessibilityLabel(for: .plain))
    }

    // MARK: - shouldShowClearButton

    @Test func clearButtonHidesForEmptyText() {
        #expect(!NavigationBarLogic.shouldShowClearButton(text: ""))
    }

    @Test func clearButtonShowsForAnyNonEmptyText() {
        #expect(NavigationBarLogic.shouldShowClearButton(text: "a"))
        #expect(NavigationBarLogic.shouldShowClearButton(text: "search query"))
    }

    // MARK: - shouldShowCancelButton (opt-in AND focused — neither alone is enough)

    @Test func cancelButtonHiddenWhenNotOptedIn() {
        #expect(!NavigationBarLogic.shouldShowCancelButton(showsCancelButton: false, isFocused: true))
    }

    @Test func cancelButtonHiddenWhenNotFocusedEvenIfOptedIn() {
        #expect(!NavigationBarLogic.shouldShowCancelButton(showsCancelButton: true, isFocused: false))
    }

    @Test func cancelButtonHiddenWhenNeitherConditionHolds() {
        #expect(!NavigationBarLogic.shouldShowCancelButton(showsCancelButton: false, isFocused: false))
    }

    @Test func cancelButtonShowsOnlyWhenBothOptedInAndFocused() {
        #expect(NavigationBarLogic.shouldShowCancelButton(showsCancelButton: true, isFocused: true))
    }
}
#endif
