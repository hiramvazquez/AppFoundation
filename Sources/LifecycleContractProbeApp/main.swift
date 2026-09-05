import AppKit
import SwiftUI

// MARK: - LifecycleContractProbeApp
//
// Convierte en verificación ejecutable la mitad NO automatizada del contrato de
// `ScreenContainer(cancelsInFlightWorkOnRemoval:)` (AF-11, 1.3.0): que SwiftUI cancele el
// `.task` de una pantalla SOLO cuando la elimina de verdad de la jerarquía, y NUNCA
// cuando simplemente queda tapada por un push. Ver `ProbeDriver` para la secuencia y
// `Scripts/verify-lifecycle-contract.sh` para cómo se invoca y por qué solo corre en
// local (no en CI) — no toca `swift test` ni `swift build --build-tests` para nada más
// que compilar este target: no se ejecuta desde ningún test ni desde ningún job de CI.
//
// Necesita una app real con ventana (`ScreenContainer` monta su `.task` sobre una vista
// SwiftUI de verdad; `ImageRenderer` no dispara ese ciclo de vida — ver el doc comment de
// `ScreenContainerCancellationTests.swift`), así que arranca `NSApplication` a mano en
// vez de depender de un bundle `.app` con `Info.plist`.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let driver = ProbeDriver()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LifecycleContractProbe"
        window.contentView = NSHostingView(rootView: RootView(driver: driver))
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            let exitCode = await driver.run()
            if exitCode == 0 {
                driver.bus.log("RESULTADO: OK — SwiftUI solo cancela el .task al eliminar la vista, nunca al taparla.")
            } else {
                driver.bus.log("RESULTADO: FALLO — ver el motivo arriba.")
            }
            exit(exitCode)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
