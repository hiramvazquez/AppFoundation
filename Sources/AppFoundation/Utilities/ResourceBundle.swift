import Foundation

/// Localiza el bundle de recursos del paquete (`AppFoundation_AppFoundation.bundle`) sin
/// depender de `Bundle.module`.
///
/// Con `defaultIsolation(MainActor.self)`, los toolchains anteriores a Xcode 26.6 generan
/// el accesor `Bundle.module` aislado al `MainActor`, y este paquete lee sus cadenas desde
/// contextos no aislados (`L10n`, `DefaultErrorPresenter`, `WrappedError`). Este localizador
/// reproduce la búsqueda estándar de SwiftPM y de Xcode (bundle junto al ejecutable, en los
/// recursos del binario que contiene al módulo, en la app principal) y es `nonisolated`
/// en cualquier toolchain.
nonisolated enum ResourceBundle {
    private final class Finder {}

    /// El bundle de recursos del paquete. Se resuelve una vez.
    static let current: Bundle = locate()

    private static let bundleName = "AppFoundation_AppFoundation.bundle"

    private static func locate() -> Bundle {
        let host = Bundle(for: Finder.self)
        var candidates: [URL] = [
            host.bundleURL.deletingLastPathComponent(),  // SwiftPM CLI: `.build/<config>/`
            host.bundleURL,
            Bundle.main.bundleURL
        ]
        if let resources = host.resourceURL { candidates.append(resources) }
        if let resources = Bundle.main.resourceURL { candidates.append(resources) }

        for directory in candidates {
            if let bundle = Bundle(url: directory.appendingPathComponent(bundleName)) {
                return bundle
            }
        }
        // Último recurso: el binario que contiene al módulo. Las cadenas saldrían con su
        // clave literal en vez de traducidas, pero la app no se cae.
        return host
    }
}
