//
//  DeepLink.swift
//  AppFoundation
//
//  Generic deep link system for handling URL-based navigation.
//

import Foundation

/// Protocol for defining deep link types in your app.
///
/// Implement this protocol to define the deep link cases your app supports.
///
/// ## Example
/// ```swift
/// enum AppDeepLink: DeepLinkType {
///     case notifications
///     case profile(userId: String)
///     case game(gameId: String)
/// }
/// ```
public protocol DeepLinkType {
    /// Parse a URL into a deep link case
    static func parse(_ url: URL) -> Self?
}

/// Generic deep link parser that can be extended for any deep link type.
///
/// ## Example
/// ```swift
/// extension DeepLinkParser where T == AppDeepLink {
///     static func parse(_ url: URL) -> AppDeepLink? {
///         let pathComponents = url.pathComponents
///
///         if pathComponents.contains("notifications") {
///             return .notifications
///         }
///
///         if let index = pathComponents.firstIndex(of: "profile"),
///            pathComponents.count > index + 1 {
///             let userId = pathComponents[index + 1]
///             return .profile(userId: userId)
///         }
///
///         return nil
///     }
/// }
/// ```
public struct DeepLinkParser<T: DeepLinkType> {
    /// Parse a URL into a typed deep link
    public static func parse(_ url: URL) -> T? {
        return T.parse(url)
    }
}
