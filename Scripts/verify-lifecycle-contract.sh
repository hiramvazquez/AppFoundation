#!/usr/bin/env bash
# Scripts/verify-lifecycle-contract.sh — verificación ejecutable de la mitad NO
# automatizable del contrato de `ScreenContainer(cancelsInFlightWorkOnRemoval:)` (AF-11,
# 1.3.0): que SwiftUI cancele el `.task` de una pantalla SOLO cuando la elimina de verdad
# de la jerarquía, y NUNCA cuando simplemente queda tapada por un push. Ver el doc comment
# de `Tests/AppFoundationTests/ScreenContainerCancellationTests.swift` para por qué esto no
# se puede cubrir con `swift test` (headless, sin ventana, sin `NavigationStack` real; y
# `ImageRenderer` no dispara el ciclo de vida de `.task`) y qué se verificaba a mano antes
# de que existiera este script.
#
# Qué hace: construye y ejecuta `LifecycleContractProbeApp`
# (Sources/LifecycleContractProbeApp/ — un target de EJECUTABLE, no un test; `swift test`
# no lo toca para nada), que monta una `NavigationStack` real en una ventana de verdad y
# reproduce exactamente la secuencia de la QA manual:
#
#     PUSH B (root -> B) · B .task STARTED
#     PUSH C (B -> C): B queda TAPADA, no eliminada
#     ventana acotada después: sigue sin cancelarse
#     POP TO ROOT (elimina B y C) · B .task CANCELLED
#
# Cada paso espera a un evento OBSERVABLE con timeout explícito (nunca un `sleep` fijo
# cruzando los dedos) — ver `Sources/LifecycleContractProbeApp/EventBus.swift`. El proceso
# sale con 0 si el contrato se cumplió exactamente como se espera, o con 1 (con el motivo
# ya impreso) en cualquier otro caso, incluido cualquier timeout.
#
# Regresión probada (fuera de este repo, en una copia de /tmp — NUNCA en el árbol de
# trabajo): romper la distinción "cancelación genuina vs. cualquier otro motivo" en
# `ScreenContainer.runRemovalWatchdog()` hace que este script falle con exit 1 y el motivo
# correcto ("B se canceló al quedar TAPADA — REGRESIÓN..."), no con un timeout genérico.
# Ver el informe de la tarea que introdujo este script para la transcripción completa.
#
# CI: honestamente, SOLO verificado en local hasta ahora. Necesita una app con ventana real
# (`NSApplication` + `NSHostingView`, sin bundle `.app`) para que SwiftUI monte de verdad la
# `NavigationStack` — esto requiere un WindowServer activo, no solo un "runner headless".
# Los runners `macos-15` de GitHub Actions SÍ mantienen una sesión de usuario con ventana
# (es precisamente por lo que `xcodebuild test -destination 'platform=iOS Simulator'`, que
# ya corre en el job `test` de este mismo CI, funciona: arrancar un simulador también
# necesita WindowServer/GPU), así que hay buenas razones para esperar que esto funcione
# igual en CI — pero no se ha podido confirmar de verdad ejecutando este job en GitHub
# Actions (esta tarea no incluía hacer push). Por eso el job de CI que invoca este script
# arranca con `continue-on-error: true`: no bloquea el merge mientras se confirma un primer
# run limpio. En cuanto confirmes en el Actions tab que el job pasa (o fallA) por el motivo
# correcto, quita `continue-on-error` del job `lifecycle-contract-probe` en
# `.github/workflows/ci.yml` (los dos: el de este paquete y el del monorepo) para que
# empiece a bloquear de verdad.
#
# Uso: Scripts/verify-lifecycle-contract.sh   (desde cualquier directorio; se autolocaliza)
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PACKAGE_DIR"

log()  { printf '\n\033[1;34m▶ %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m✘ %s\033[0m\n' "$1" >&2; exit 1; }

log "swift build --product LifecycleContractProbeApp"
swift build --product LifecycleContractProbeApp

BIN="$(swift build --show-bin-path)/LifecycleContractProbeApp"
[ -x "$BIN" ] || fail "No se encontró el binario construido en $BIN"

LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

log "Ejecutando la secuencia push -> push -> pop en una ventana real"
# Timeout manual (macOS no trae `timeout` de coreutils por defecto): la secuencia interna
# tiene sus propios timeouts acotados (ver ProbeDriver.swift, máximo ~10.5s en el peor
# caso), así que 30s da margen de sobra para arranque de proceso + la secuencia entera sin
# convertirse en un cuelgue silencioso si algo se queda colgado de verdad.
"$BIN" > "$LOG_FILE" 2>&1 &
PID=$!

DEADLINE=$((SECONDS + 30))
while kill -0 "$PID" 2>/dev/null; do
    if [ "$SECONDS" -ge "$DEADLINE" ]; then
        kill -9 "$PID" 2>/dev/null || true
        cat "$LOG_FILE"
        fail "LifecycleContractProbeApp no terminó en 30s — probable cuelgue real, no un timeout de la secuencia (esos ya se reportarían como FALLO y saldrían solos)."
    fi
    sleep 0.2
done

wait "$PID"
EXIT_CODE=$?

cat "$LOG_FILE"

if [ "$EXIT_CODE" -eq 0 ]; then
    log "OK — SwiftUI solo cancela el .task de la pantalla al eliminarla de la jerarquía, nunca al taparla con un push."
else
    fail "El contrato NO se cumple (o el probe está mal cableado) — ver el motivo en el log de arriba."
fi
