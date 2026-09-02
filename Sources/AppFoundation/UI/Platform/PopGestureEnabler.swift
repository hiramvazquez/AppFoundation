#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import UIKit

/// Re-enables the interactive pop gesture (edge swipe-back) that `UINavigationController`
/// disables whenever its navigation bar is hidden — exactly what `ScreenChrome.custom`
/// does via `.toolbar(.hidden, for: .navigationBar)` (AF-12/AF-13). Without this, every
/// screen using the custom bar would lose swipe-back, a basic and expected iOS gesture.
///
/// This is a documented community workaround (reliable since iOS 16): drop a size-zero
/// `UIViewController` into the hierarchy purely to reach `self.navigationController` from
/// `viewDidAppear`, then grab `interactivePopGestureRecognizer` and hand it a `nil`
/// delegate (dropping the system's "no gesture while the bar is hidden" rule) while making
/// sure it stays `isEnabled`. There is no supported SwiftUI-only way to do this — the
/// recognizer lives on `UINavigationController`, which SwiftUI's `NavigationStack` does
/// not expose.
///
/// `ScreenContainer` installs this automatically for `chrome: .custom(...)`; screens using
/// `chrome: .native` never need it, since the native bar never disables the gesture.
struct PopGestureEnabler: UIViewControllerRepresentable {
    final class ViewController: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }

    func makeUIViewController(context: Context) -> ViewController {
        ViewController()
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
        // No dynamic configuration: the workaround only needs to run once per appearance.
    }
}

#endif
