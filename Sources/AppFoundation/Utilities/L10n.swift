import Foundation

/// Internal accessors for the package's localized default strings (A13).
///
/// Every user-visible default string the package ships lives in
/// `Resources/Localizable.xcstrings` (EN + ES) and is read through here or through
/// `Text(_, bundle: .module)` at the point of use.
nonisolated enum L10n {
    /// The package's resource bundle (exposed for tests via @testable).
    static var bundle: Bundle { .module }

    /// "Error" — default error title.
    static var error: String { String(localized: "Error", bundle: .module) }

    /// "OK" — default dismiss button title.
    static var ok: String { String(localized: "OK", bundle: .module) }

    /// "Search" — default search placeholder.
    static var search: String { String(localized: "Search", bundle: .module) }

    /// "Something went wrong. Please try again." — generic fallback message for errors
    /// that `DefaultErrorPresenter` can't otherwise present (not `AppErrorConvertible`,
    /// not `LocalizedError`). Never the raw `localizedDescription` of a foreign error.
    static var genericErrorMessage: String {
        String(localized: "Something went wrong. Please try again.", bundle: .module)
    }
}
