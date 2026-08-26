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
/// ## Example
/// ```swift
/// NavigationBarItem.back { coordinator.pop() }
/// NavigationBarItem.close { coordinator.dismissModal() }
/// NavigationBarItem.icon("bell", badge: 3) { showNotifications() }
/// NavigationBarItem.text("Save") { saveDocument() }
/// ```
public struct NavigationBarItem: Identifiable {
    public let id = UUID()
    let content: NavigationBarItemContent
    let action: () -> Void

    /// Returns true if this item is a back button (chevron.left icon).
    public var isBackButton: Bool {
        if case .systemIcon(let name, _) = content {
            return name == "chevron.left"
        }
        return false
    }

    /// The visual content of the navigation bar item.
    public enum NavigationBarItemContent {
        case icon(String, badge: Int?)
        case systemIcon(String, badge: Int?)
        case text(String)
        case view(AnyView)
    }

    // MARK: - Factory Methods

    /// Creates a back button with chevron icon.
    public static func back(action: @escaping () -> Void) -> NavigationBarItem {
        NavigationBarItem(content: .systemIcon("chevron.left", badge: nil), action: action)
    }

    /// Creates a close button with X icon.
    public static func close(action: @escaping () -> Void) -> NavigationBarItem {
        NavigationBarItem(content: .systemIcon("xmark", badge: nil), action: action)
    }

    /// Creates a button with a system SF Symbol.
    public static func icon(_ systemName: String, badge: Int? = nil, action: @escaping () -> Void) -> NavigationBarItem {
        NavigationBarItem(content: .systemIcon(systemName, badge: badge), action: action)
    }

    /// Creates a button with a custom image from assets.
    public static func customIcon(_ imageName: String, badge: Int? = nil, action: @escaping () -> Void) -> NavigationBarItem {
        NavigationBarItem(content: .icon(imageName, badge: badge), action: action)
    }

    /// Creates a text button.
    public static func text(_ text: String, action: @escaping () -> Void) -> NavigationBarItem {
        NavigationBarItem(content: .text(text), action: action)
    }

    /// Creates a button with a custom view.
    public static func custom<V: View>(_ view: V, action: @escaping () -> Void) -> NavigationBarItem {
        NavigationBarItem(content: .view(AnyView(view)), action: action)
    }
}

// MARK: - Navigation Bar Title

/// Represents the title content of the navigation bar.
public enum NavigationBarTitle {
    /// No title.
    case none

    /// Simple text title.
    case text(String)

    /// Large title that can collapse on scroll (future feature).
    case largeText(String)

    /// Custom view as title (for logos, search bars, etc.).
    case custom(AnyView)

    // MARK: - Factory Methods

    /// Creates a text title.
    public static func title(_ text: String) -> NavigationBarTitle {
        .text(text)
    }

    /// Creates a custom view title.
    public static func view<V: View>(_ view: V) -> NavigationBarTitle {
        .custom(AnyView(view))
    }
}

// MARK: - Navigation Bar Style

/// Visual style for the custom navigation bar.
public struct NavigationBarStyle {
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
public enum NavigationBarBackground {
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
    let onSubmit: (() -> Void)?

    /// Action called when cancel is tapped.
    let onCancel: (() -> Void)?

    /// Creates a search bar configuration.
    ///
    /// - Parameters:
    ///   - text: Binding to the search text.
    ///   - placeholder: Placeholder text. Defaults to "Search".
    ///   - showsCancelButton: Show cancel button when focused. Defaults to true.
    ///   - onSubmit: Called when user taps return on keyboard.
    ///   - onCancel: Called when user taps cancel button.
    public init(
        text: Binding<String>,
        placeholder: String = "Search",
        showsCancelButton: Bool = true,
        onSubmit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.text = text
        self.placeholder = placeholder
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
    /// Takes priority over `searchBar` when both are set.
    public let accessoryView: AnyView?

    /// Visual style.
    public let style: NavigationBarStyle

    /// Whether the navigation bar is visible.
    public let isVisible: Bool

    /// Full-width custom content that replaces the entire left/title/right layout.
    public let customContent: AnyView?

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
    public static func title(_ text: String, style: NavigationBarStyle = .default) -> NavigationBarConfiguration {
        NavigationBarConfiguration(title: .text(text), style: style)
    }

    /// Creates a configuration with title and back button.
    public static func withBack(
        title: String = "",
        style: NavigationBarStyle = .default,
        backAction: @escaping () -> Void
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            title: .text(title),
            leftItems: [.back(action: backAction)],
            style: style
        )
    }

    /// Creates a configuration with title and close button.
    public static func withClose(
        title: String,
        style: NavigationBarStyle = .default,
        closeAction: @escaping () -> Void
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            title: .text(title),
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
    /// NavigationBarConfiguration.custom(style: .dark) {
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
            customContent: AnyView(content()),
            style: style
        )
    }

    /// Internal init for custom content configurations.
    private init(customContent: AnyView, accessoryView: AnyView? = nil, style: NavigationBarStyle) {
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
    ///     style: .dark,
    ///     backAction: { coordinator.pop() }
    /// ) {
    ///     PlayerSearchBar(text: $searchText, onFilter: { })
    /// }
    /// ```
    public static func withBackAndAccessory<Accessory: View>(
        title: String = "",
        style: NavigationBarStyle = .default,
        backAction: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            title: .text(title),
            leftItems: [.back(action: backAction)],
            accessoryView: AnyView(accessory()),
            style: style
        )
    }

    /// Full init with accessory view support.
    public init(
        title: NavigationBarTitle = .none,
        leftItems: [NavigationBarItem] = [],
        rightItems: [NavigationBarItem] = [],
        accessoryView: AnyView,
        style: NavigationBarStyle = .default
    ) {
        self.title = title
        self.leftItems = leftItems
        self.rightItems = rightItems
        self.searchBar = nil
        self.accessoryView = accessoryView
        self.style = style
        self.isVisible = true
        self.customContent = nil
    }

    /// No navigation bar.
    public static let hidden = NavigationBarConfiguration(isVisible: false)

    // MARK: - Search Bar Convenience Initializers

    /// Creates a configuration with title and search bar.
    public static func withSearch(
        title: String,
        searchText: Binding<String>,
        searchPlaceholder: String = "Search",
        style: NavigationBarStyle = .solid,
        onSubmit: (() -> Void)? = nil
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            title: .text(title),
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
        title: String,
        searchText: Binding<String>,
        searchPlaceholder: String = "Search",
        style: NavigationBarStyle = .solid,
        backAction: @escaping () -> Void,
        onSubmit: (() -> Void)? = nil
    ) -> NavigationBarConfiguration {
        NavigationBarConfiguration(
            title: .text(title),
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
