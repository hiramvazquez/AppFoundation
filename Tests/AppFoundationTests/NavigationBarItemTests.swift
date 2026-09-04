#if canImport(SwiftUI)
import SwiftUI
import Testing

@testable import AppFoundation

// MARK: - Public value types of the custom navigation bar (`NavigationBarItem`,
// `NavigationBarConfiguration`, `NavigationBarStyle`, `SearchBarConfiguration`): these are
// plain value types with no SwiftUI rendering involved, so construction, stable identity
// (A10) and default values are verified directly — no snapshot needed.

@Suite("NavigationBarItem")
struct NavigationBarItemTests {
    // MARK: - Factory methods: role, stable id (A10), content

    @Test func backHasStableDefaultIdAndBackRole() {
        let item = NavigationBarItem.back {}
        #expect(item.id == "back")
        #expect(item.role == .back)
        #expect(item.isBackButton)
        guard case .systemIcon(let name, let badge) = item.content else {
            Issue.record("expected .systemIcon content")
            return
        }
        #expect(name == "chevron.left")
        #expect(badge == nil)
    }

    @Test func closeHasStableDefaultIdAndCloseRole() {
        let item = NavigationBarItem.close {}
        #expect(item.id == "close")
        #expect(item.role == .close)
        #expect(!item.isBackButton)
        guard case .systemIcon(let name, _) = item.content else {
            Issue.record("expected .systemIcon content")
            return
        }
        #expect(name == "xmark")
    }

    @Test func backAndCloseAcceptAnExplicitIdOverride() {
        #expect(NavigationBarItem.back(id: "custom-back") {}.id == "custom-back")
        #expect(NavigationBarItem.close(id: "custom-close") {}.id == "custom-close")
    }

    @Test func iconDerivesIdFromSystemName() {
        let item = NavigationBarItem.icon("bell", badge: 3) {}
        #expect(item.id == "system:bell")
        #expect(item.role == .plain)
        guard case .systemIcon(let name, let badge) = item.content else {
            Issue.record("expected .systemIcon content")
            return
        }
        #expect(name == "bell")
        #expect(badge == 3)
    }

    @Test func iconAcceptsAnExplicitIdOverride() {
        let item = NavigationBarItem.icon("bell", id: "notifications") {}
        #expect(item.id == "notifications")
    }

    @Test func customIconDerivesIdFromAssetName() {
        let item = NavigationBarItem.customIcon("brand-logo", badge: 2) {}
        #expect(item.id == "icon:brand-logo")
        guard case .icon(let name, let badge) = item.content else {
            Issue.record("expected .icon content")
            return
        }
        #expect(name == "brand-logo")
        #expect(badge == 2)
    }

    @Test func textDerivesIdFromTheResolvedLocalizedString() {
        // A literal with no matching catalog entry resolves to itself — safe to assert
        // against directly regardless of which language the test runner defaults to.
        let item = NavigationBarItem.text("Unmatched Custom Label XYZ") {}
        #expect(item.id == "text:Unmatched Custom Label XYZ")
        #expect(item.role == .plain)
        guard case .text(let text) = item.content else {
            Issue.record("expected .text content")
            return
        }
        #expect(text == "Unmatched Custom Label XYZ")
    }

    @Test func textAcceptsAnExplicitIdOverride() {
        let item = NavigationBarItem.text("Unmatched Custom Label XYZ", id: "save-button") {}
        #expect(item.id == "save-button")
    }

    @Test func customUsesTheProvidedIdWithNoDerivation() {
        let item = NavigationBarItem.custom(Text("Hi"), id: "avatar") {}
        #expect(item.id == "avatar")
        #expect(item.role == .plain)
    }

    @Test func customDefaultsToACustomId() {
        let item = NavigationBarItem.custom(Text("Hi")) {}
        #expect(item.id == "custom")
    }

    // MARK: - Action wiring

    @Test func itemActionInvokesTheProvidedClosure() {
        var called = false
        let item = NavigationBarItem.icon("gear") { called = true }
        item.action()
        #expect(called)
    }

    // MARK: - Role equality

    @Test func rolesDistinguishAllThreeCases() {
        let roles: [NavigationBarItem.Role] = [.back, .close, .plain]
        for (i, lhs) in roles.enumerated() {
            for (j, rhs) in roles.enumerated() where i != j {
                #expect(lhs != rhs)
            }
        }
    }
}

@Suite("NavigationBarTitle")
struct NavigationBarTitleTests {
    @Test func titleFactoryResolvesToAResolvedTextCase() {
        guard case .text(let text) = NavigationBarTitle.title("Unmatched Custom Title XYZ") else {
            Issue.record("expected .text case")
            return
        }
        #expect(text == "Unmatched Custom Title XYZ")
    }

    @Test func viewFactoryProducesACustomCase() {
        guard case .custom = NavigationBarTitle.view(Text("Logo")) else {
            Issue.record("expected .custom case")
            return
        }
    }
}

@Suite("NavigationBarStyle")
struct NavigationBarStyleTests {
    @Test func defaultStyleHasNoBackgroundAndNoSeparator() {
        let style = NavigationBarStyle.default
        #expect(!style.showSeparator)
        #expect(style.height == 44)
        guard case .solid(let color) = style.background else {
            Issue.record("expected .solid background")
            return
        }
        #expect(color == .clear)
    }

    @Test func solidPresetShowsASeparatorOverAPlatformBackground() {
        let style = NavigationBarStyle.solid
        #expect(style.showSeparator)
        guard case .solid(let color) = style.background else {
            Issue.record("expected .solid background")
            return
        }
        #expect(color == .platformBackground)
    }

    @Test func transparentPresetUsesWhiteForegroundOverAClearBackground() {
        let style = NavigationBarStyle.transparent
        #expect(style.titleColor == .white)
        #expect(style.tintColor == .white)
        guard case .solid(let color) = style.background else {
            Issue.record("expected .solid background")
            return
        }
        #expect(color == .clear)
    }

    @Test func blurPresetShowsASeparatorOverAMaterialBackground() {
        let style = NavigationBarStyle.blur
        #expect(style.showSeparator)
        guard case .blur = style.background else {
            Issue.record("expected .blur background")
            return
        }
    }

    @Test func customStyleHonorsEveryParameter() {
        let style = NavigationBarStyle(
            background: .solid(.red),
            titleColor: .yellow,
            tintColor: .green,
            showSeparator: true,
            height: 60
        )
        #expect(style.titleColor == .yellow)
        #expect(style.tintColor == .green)
        #expect(style.showSeparator)
        #expect(style.height == 60)
    }
}

@Suite("SearchBarConfiguration")
struct SearchBarConfigurationTests {
    @Test func defaultsToTheLocalizedSearchPlaceholderAndACancelButton() {
        let config = SearchBarConfiguration(text: .constant(""))
        #expect(["Search", "Buscar"].contains(config.placeholder))
        #expect(config.showsCancelButton)
        #expect(config.onSubmit == nil)
        #expect(config.onCancel == nil)
    }

    @Test func explicitPlaceholderOverridesTheLocalizedDefault() {
        let config = SearchBarConfiguration(text: .constant(""), placeholder: "Unmatched Placeholder XYZ")
        #expect(config.placeholder == "Unmatched Placeholder XYZ")
    }

    @Test func cancelButtonCanBeOptedOut() {
        let config = SearchBarConfiguration(text: .constant(""), showsCancelButton: false)
        #expect(!config.showsCancelButton)
    }

    @Test func submitAndCancelClosuresAreWiredThrough() {
        var submitted = false
        var cancelled = false
        let config = SearchBarConfiguration(
            text: .constant(""),
            onSubmit: { submitted = true },
            onCancel: { cancelled = true }
        )
        config.onSubmit?()
        config.onCancel?()
        #expect(submitted)
        #expect(cancelled)
    }
}

@Suite("NavigationBarConfiguration")
struct NavigationBarConfigurationTests {
    @Test func defaultConfigurationIsVisibleWithNoItemsAndNoTitle() {
        let config = NavigationBarConfiguration()
        #expect(config.isVisible)
        #expect(config.leftItems.isEmpty)
        #expect(config.rightItems.isEmpty)
        #expect(config.searchBar == nil)
        #expect(config.accessoryView == nil)
        #expect(config.customContent == nil)
        guard case .none = config.title else {
            Issue.record("expected .none title")
            return
        }
    }

    @Test func hiddenConfigurationIsNotVisible() {
        #expect(!NavigationBarConfiguration.hidden.isVisible)
    }

    @Test func titleConvenienceSetsOnlyTheTitle() {
        let config = NavigationBarConfiguration.title("Unmatched Title XYZ")
        guard case .text(let text) = config.title else {
            Issue.record("expected .text title")
            return
        }
        #expect(text == "Unmatched Title XYZ")
        #expect(config.leftItems.isEmpty)
        #expect(config.rightItems.isEmpty)
    }

    @Test func withBackAddsExactlyOneBackItemOnTheLeft() {
        let config = NavigationBarConfiguration.withBack(title: "Details") {}
        #expect(config.leftItems.count == 1)
        #expect(config.leftItems[0].role == .back)
        #expect(config.rightItems.isEmpty)
    }

    @Test func withBackWithoutATitleHasNoTitle() {
        let config = NavigationBarConfiguration.withBack {}
        guard case .none = config.title else {
            Issue.record("expected .none title")
            return
        }
    }

    @Test func withCloseAddsExactlyOneCloseItemOnTheRight() {
        let config = NavigationBarConfiguration.withClose(title: "Filters") {}
        #expect(config.rightItems.count == 1)
        #expect(config.rightItems[0].role == .close)
        #expect(config.leftItems.isEmpty)
    }

    @Test func customConfigurationStoresTheContentAndHasNoOtherChrome() {
        let config = NavigationBarConfiguration.custom { Text("Full width") }
        #expect(config.customContent != nil)
        #expect(config.leftItems.isEmpty)
        #expect(config.rightItems.isEmpty)
        #expect(config.isVisible)
    }

    @Test func withBackAndAccessoryCombinesABackButtonWithAnAccessoryView() {
        let config = NavigationBarConfiguration.withBackAndAccessory(
            title: "Select",
            backAction: {},
            accessory: { Text("Accessory") }
        )
        #expect(config.leftItems.count == 1)
        #expect(config.leftItems[0].role == .back)
        #expect(config.accessoryView != nil)
        #expect(config.searchBar == nil)
    }

    @Test func withSearchSetsTitleAndSearchBarWithNoLeftItems() {
        let config = NavigationBarConfiguration.withSearch(title: "Games", searchText: .constant(""))
        guard case .text(let text) = config.title else {
            Issue.record("expected .text title")
            return
        }
        #expect(text == "Games")
        #expect(config.searchBar != nil)
        #expect(config.leftItems.isEmpty)
    }

    @Test func withBackAndSearchCombinesABackButtonWithASearchBar() {
        let config = NavigationBarConfiguration.withBackAndSearch(
            title: "Games",
            searchText: .constant(""),
            backAction: {}
        )
        #expect(config.leftItems.count == 1)
        #expect(config.leftItems[0].role == .back)
        #expect(config.searchBar != nil)
    }

    @Test func withSearchDefaultsToTheSolidStyle() {
        let config = NavigationBarConfiguration.withSearch(title: "Games", searchText: .constant(""))
        #expect(config.style.showSeparator)
    }
}
#endif
