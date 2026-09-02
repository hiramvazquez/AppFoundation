//
//  NavigationBarItem.swift
//  AppFoundation
//
//  Custom navigation bar item models for iOS 26+ compatibility.
//

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Navigation Bar Item

/// Represents an item in the custom navigation bar.
///
/// Use this to define buttons for the left and right sides of the navigation bar.
///
/// ## Identity (A10)
///
/// Items have a STABLE identity derived from their role and content (`"back"`,
/// `"system:bell"`, `"text:Save"`, ...) so `ForEach` diffing and animations survive
/// re-renders — a `UUID()` per render made every item "new" every time. If one bar
/// hosts two items that would derive the same id, disambiguate with the `id:` parameter.
///
/// ## Example
/// ```swift
/// NavigationBarItem.back { coordinator.pop() }
/// NavigationBarItem.close { coordinator.dismiss() }
/// NavigationBarItem.icon("bell", badge: 3) { showNotifications() }
/// NavigationBarItem.text("Save") { saveDocument() }
/// ```
public struct NavigationBarItem: Identifiable {
    /// Semantic role of the item (A11): behavior/styling keys off this, never off
    /// matching an icon name like `"chevron.left"`.
    public nonisolated enum Role: Equatable, Sendable {
        /// Navigates back in the current stack (animated chevron treatment).
        case back
        /// Dismisses the current modal context.
        case close
        /// A regular action item.
        case plain
    }

    /// Stable identity (A10) — derived from role/content, or explicitly provided.
    public let id: String

    /// The semantic role of this item.
    public let role: Role

    let content: NavigationBarItemContent
    let action: Action

    /// Returns true if this item is a back button.
    public var isBackButton: Bool { role == .back }

    /// The visual content of the navigation bar item.
    public enum NavigationBarItemContent {
        case icon(String, badge: Int?)
        case systemIcon(String, badge: Int?)
        case text(String)
        /// A caller-supplied view. Stored type-erased (`ErasedView`, see that file):
        /// items of different concrete view types must live side by side in the same
        /// `[NavigationBarItem]` array, which `some View` cannot express (AF-15).
        case view(ErasedView)
    }

    // MARK: - Factory Methods

    /// Creates a back button with chevron icon.
    public static func back(id: String = "back", action: @escaping Action) -> NavigationBarItem {
        NavigationBarItem(id: id, role: .back, content: .systemIcon("chevron.left", badge: nil), action: action)
    }

    /// Creates a close button with X icon.
    public static func close(id: String = "close", action: @escaping Action) -> NavigationBarItem {
        NavigationBarItem(id: id, role: .close, content: .systemIcon("xmark", badge: nil), action: action)
    }

    /// Creates a button with a system SF Symbol.
    public static func icon(_ systemName: String, badge: Int? = nil, id: String? = nil, action: @escaping Action) -> NavigationBarItem {
        NavigationBarItem(id: id ?? "system:\(systemName)", role: .plain, content: .systemIcon(systemName, badge: badge), action: action)
    }

    /// Creates a button with a custom image from assets.
    public static func customIcon(_ imageName: String, badge: Int? = nil, id: String? = nil, action: @escaping Action) -> NavigationBarItem {
        NavigationBarItem(id: id ?? "icon:\(imageName)", role: .plain, content: .icon(imageName, badge: badge), action: action)
    }

    /// Creates a text button (localized resource; literals localize through the app's catalog).
    public static func text(_ text: LocalizedStringResource, id: String? = nil, action: @escaping Action) -> NavigationBarItem {
        let resolved = String(localized: text)
        return NavigationBarItem(id: id ?? "text:\(resolved)", role: .plain, content: .text(resolved), action: action)
    }

    /// Creates a button with a custom view.
    ///
    /// Custom views cannot derive a content-based id — pass `id:` when a bar hosts
    /// more than one custom item.
    public static func custom<V: View>(_ view: V, id: String = "custom", action: @escaping Action) -> NavigationBarItem {
        NavigationBarItem(id: id, role: .plain, content: .view(ErasedView(view)), action: action)
    }
}

// MARK: - Navigation Bar Title

/// Represents the title content of the navigation bar.
public enum NavigationBarTitle {
    /// No title.
    case none

    /// Simple text title.
    case text(String)

    /// Custom view as title (for logos, search bars, etc.). Stored type-erased
    /// (`ErasedView`): see that file for why (AF-15).
    case custom(ErasedView)

    // MARK: - Factory Methods

    /// Creates a text title (localized resource). For runtime, already-localized
    /// strings use the `.text(_:)` case directly.
    public static func title(_ text: LocalizedStringResource) -> NavigationBarTitle {
        .text(String(localized: text))
    }

    /// Creates a custom view title.
    public static func view<V: View>(_ view: V) -> NavigationBarTitle {
        .custom(ErasedView(view))
    }
}

// MARK: - Navigation Bar Style

/// Visual style for the custom navigation bar.
public struct NavigationBarStyle: Sendable {
    /// Background color or material.
    public let background: NavigationBarBackground

    /// Title text color.
    public let titleColor: Color

    /// Icon/button tint color.
    public let tintColor: Color

    /// Whether to show a bottom separator line.
    public let showSeparator: Bool

    /// Height of the navigation bar (excluding safe area).
    public let height: CGFloat

    public init(
        background: NavigationBarBackground = .solid(.clear),
        titleColor: Color = .primary,
        tintColor: Color = .accentColor,
        showSeparator: Bool = false,
        height: CGFloat = 44
    ) {
        self.background = background
        self.titleColor = titleColor
        self.tintColor = tintColor
        self.showSeparator = showSeparator
        self.height = height
    }

    // MARK: - Presets

    /// Default style with no background.
    public static let `default` = NavigationBarStyle()

    /// Solid white background with separator.
    public static let solid = NavigationBarStyle(
        background: .solid(.platformBackground),
        showSeparator: true
    )

    /// Transparent background.
    public static let transparent = NavigationBarStyle(
        background: .solid(.clear),
        titleColor: .white,
        tintColor: .white
    )

    /// Blur/material background.
    public static let blur = NavigationBarStyle(
        background: .blur(.regular),
        showSeparator: true
    )
}

/// Background type for the navigation bar.
public enum NavigationBarBackground: Sendable {
    /// Solid color background.
    case solid(Color)

    /// Blur/material background.
    case blur(Material)

    /// Gradient background.
    case gradient(LinearGradient)
}

// MARK: - Navigation Bar Configuration

/// Configuration for the search bar in the navigation.
public struct SearchBarConfiguration {
    /// Binding to the search text.
    let text: Binding<String>

    /// Placeholder text when empty.
    let placeholder: String

    /// Whether to show a cancel button when focused.
    let showsCancelButton: Bool

    /// Action called when search is submitted (keyboard return).
    let onSubmit: Action?

    /// Action called when cancel is tapped.
    let onCancel: Action?

    /// Creates a search bar configuration.
    ///
    /// - Parameters:
    ///   - text: Binding to the search text.
    ///   - placeholder: Placeholder text. Defaults to the localized "Search" (A13).
    ///   - showsCancelButton: Show cancel button when focused. Defaults to true.
    ///   - onSubmit: Called when user taps return on keyboard.
    ///   - onCancel: Called when user taps cancel button.
    public init(
        text: Binding<String>,
        placeholder: LocalizedStringResource? = nil,
        showsCancelButton: Bool = true,
        onSubmit: Action? = nil,
        onCancel: Action? = nil
    ) {
        self.text = text
        self.placeholder = placeholder.map { String(localized: $0) } ?? L10n.search
        self.showsCancelButton = showsCancelButton
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }
}

/// Complete configuration for a screen's navigation bar.
///
/// ## Example - With Search Bar
/// ```swift
/// NavigationBarConfiguration(
///     title: .text("Games"),
///     searchBar: SearchBarConfiguration(
///         text: $searchText,
///         placeholder: "Search games..."
///     ),
///     style: .solid
/// )
/// ```
public struct NavigationBarConfiguration {
    /// Title content.
    public let title: NavigationBarTitle

    /// Left side items (usually back/close).
    public let leftItems: [NavigationBarItem]

    /// Right side items (actions).
    public let rightItems: [NavigationBarItem]

    /// Optional search bar configuration.
    public let searchBar: SearchBarConfiguration?

    /// Optional custom view rendered below the navigation bar (same slot as searchBar).
    /// Takes priority over `searchBar` when both are set. Stored type-erased
    /// (`ErasedView`): see that file for why (AF-15).
    public let accessoryView: ErasedView?

    /// Visual style.
    public let style: NavigationBarStyle

    /// Whether the navigation bar is visible.
    public let isVisible: Bool

    /// Full-width custom content that replaces the entire left/title/right layout.
    /// Stored type-erased (`ErasedView`): see that file for why (AF-15).
    public let customContent: ErasedView?

    public init(
        title: NavigationBarTitle = .none,
        leftItems: [NavigationBarItem] = [],
        rightItems: [NavigationBarItem] = [],
        searchBar: SearchBarConfiguration? = nil,
        style: NavigationBarStyle = .default,
        isVisible: Bool = true
    ) {
        self.title = title
        self.leftItems = leftItems
        self.rightItems = rightItems
        self.searchBar = searchBar
        self.accessoryView = nil
        self.style = style
        self.isVisible = isVisible
        self.customContent = nil
    }

    // MARK: - Convenience Initializers

    /// Creates a configuration with just a title.
    public static func title(_ text: LocalizedStringResource, style: NavigationBarStyle = .default) -> NavigationBarConfiguration {
        NavigationBarConfiguration(title: .title(text), style: style)
    }

    /// Creates a configuration with title and back button.
    public static func withBack(
        title: LocalizedStringResource? = nil,
        style: NavigationBarStyle = .default,
        backAction: @escaping Action
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            title: title.map { .title($0) } ?? .none,
            leftItems: [.back(action: backAction)],
            style: style
        )
    }

    /// Creates a configuration with title and close button.
    public static func withClose(
        title: LocalizedStringResource,
        style: NavigationBarStyle = .default,
        closeAction: @escaping Action
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            title: .title(title),
            rightItems: [.close(action: closeAction)],
            style: style
        )
    }

    /// Creates a configuration with a full-width custom view that replaces
    /// the entire left/title/right layout.
    ///
    /// Use this when you need complete control over the navigation bar content
    /// (e.g. a header with avatar, greeting text, and action buttons).
    ///
    /// ```swift
    /// NavigationBarConfiguration.custom(style: .solid) {
    ///     HStack {
    ///         Avatar()
    ///         Text("Hello")
    ///         Spacer()
    ///         Button("Action") { }
    ///     }
    /// }
    /// ```
    public static func custom<Content: View>(
        style: NavigationBarStyle = .default,
        @ViewBuilder content: () -> Content
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            customContent: ErasedView(content()),
            style: style
        )
    }

    /// Internal init for custom content configurations.
    private init(customContent: ErasedView, accessoryView: ErasedView? = nil, style: NavigationBarStyle) {
        self.title = .none
        self.leftItems = []
        self.rightItems = []
        self.searchBar = nil
        self.accessoryView = accessoryView
        self.style = style
        self.isVisible = true
        self.customContent = customContent
    }

    /// Creates a configuration with back button, title, and a custom accessory view
    /// below the navigation bar (e.g. a search bar with extra controls).
    ///
    /// ```swift
    /// NavigationBarConfiguration.withBackAndAccessory(
    ///     title: "Select Partner",
    ///     style: .solid,
    ///     backAction: { coordinator.pop() }
    /// ) {
    ///     PlayerSearchBar(text: $searchText, onFilter: { })
    /// }
    /// ```
    public static func withBackAndAccessory<Accessory: View>(
        title: LocalizedStringResource? = nil,
        style: NavigationBarStyle = .default,
        backAction: @escaping Action,
        @ViewBuilder accessory: () -> Accessory
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            title: title.map { .title($0) } ?? .none,
            leftItems: [.back(action: backAction)],
            style: style,
            accessoryView: accessory
        )
    }

    /// Full init with accessory view support.
    public init<Accessory: View>(
        title: NavigationBarTitle = .none,
        leftItems: [NavigationBarItem] = [],
        rightItems: [NavigationBarItem] = [],
        style: NavigationBarStyle = .default,
        @ViewBuilder accessoryView: () -> Accessory
    ) {
        self.title = title
        self.leftItems = leftItems
        self.rightItems = rightItems
        self.searchBar = nil
        self.accessoryView = ErasedView(accessoryView())
        self.style = style
        self.isVisible = true
        self.customContent = nil
    }

    /// No navigation bar.
    public static let hidden = NavigationBarConfiguration(isVisible: false)

    // MARK: - Search Bar Convenience Initializers

    /// Creates a configuration with title and search bar.
    public static func withSearch(
        title: LocalizedStringResource,
        searchText: Binding<String>,
        searchPlaceholder: LocalizedStringResource? = nil,
        style: NavigationBarStyle = .solid,
        onSubmit: Action? = nil
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            title: .title(title),
            searchBar: SearchBarConfiguration(
                text: searchText,
                placeholder: searchPlaceholder,
                onSubmit: onSubmit
            ),
            style: style
        )
    }

    /// Creates a configuration with back button, title, and search bar.
    public static func withBackAndSearch(
        title: LocalizedStringResource,
        searchText: Binding<String>,
        searchPlaceholder: LocalizedStringResource? = nil,
        style: NavigationBarStyle = .solid,
        backAction: @escaping Action,
        onSubmit: Action? = nil
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            title: .title(title),
            leftItems: [.back(action: backAction)],
            searchBar: SearchBarConfiguration(
                text: searchText,
                placeholder: searchPlaceholder,
                onSubmit: onSubmit
            ),
            style: style
        )
    }
}

#endif
