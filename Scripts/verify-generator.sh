#!/usr/bin/env bash
# Scripts/verify-generator.sh — el test de integración real de PRD-AF-08, tal como lo pide
# el propio PRD: "en un paquete SwiftPM temporal fuera del repo que depende de AppFoundation
# por path:", ejecuta las cuatro variantes de `generate-feature`, comprueba que compilan y
# pasan sus tests, activa `ArchitectureLint` y comprueba que el build pasa limpio, introduce
# una violación de R1/R7/R10 y comprueba que el build FALLA con el diagnóstico esperado, y
# finalmente corre `swift package archlint` sobre los cuatro ejemplos de AF-07 (deben pasar
# limpios: son la referencia).
#
# Uso: Scripts/verify-generator.sh   (desde cualquier directorio; se autolocaliza)
# CI: .github/workflows/ci.yml, job `generator`.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Monorepo: AppFoundation/ y CoreNetworking/ son subdirectorios. Repo publicado (subtree
# split): REPO_ROOT ES AppFoundation y CoreNetworking se toma de su repositorio.
if [ -d "$REPO_ROOT/AppFoundation" ] && [ -d "$REPO_ROOT/CoreNetworking" ]; then
    APPFOUNDATION_DIR="$REPO_ROOT/AppFoundation"
    CORENETWORKING_DEP=".package(path: \"$REPO_ROOT/CoreNetworking\")"
else
    APPFOUNDATION_DIR="$REPO_ROOT"
    CORENETWORKING_DEP="${CORENETWORKING_DEP:-.package(url: \"https://github.com/hiramvazquez/CoreNetworking.git\", branch: \"main\")}"
fi
WORK_DIR="$(mktemp -d /tmp/spm-pro-af08-verify.XXXXXX)"
DEMO_DIR="$WORK_DIR/DemoApp"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

log() { printf '\n\033[1;34m▶ %s\033[0m\n' "$1"; }
fail() {
    printf '\n\033[1;31m✘ %s\033[0m\n' "$1" >&2
    exit 1
}

log "Paquete temporal en $DEMO_DIR"
mkdir -p "$DEMO_DIR/Sources/DemoApp" "$DEMO_DIR/Tests/DemoAppTests"

cat > "$DEMO_DIR/Package.swift" <<EOF
// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "DemoApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DemoApp", targets: ["DemoApp"])],
    dependencies: [
        .package(path: "$APPFOUNDATION_DIR"),
        $CORENETWORKING_DEP
    ],
    targets: [
        .target(
            name: "DemoApp",
            dependencies: [
                .product(name: "AppFoundation", package: "AppFoundation"),
                .product(name: "CoreNetworking", package: "CoreNetworking")
            ],
            path: "Sources/DemoApp",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DemoAppTests",
            dependencies: [
                "DemoApp",
                .product(name: "AppFoundationTestSupport", package: "AppFoundation"),
                .product(name: "CoreNetworkingTestSupport", package: "CoreNetworking")
            ],
            path: "Tests/DemoAppTests",
            swiftSettings: swiftSettings
        )
    ]
)
EOF

cat > "$DEMO_DIR/Sources/DemoApp/DemoApp.swift" <<'EOF'
public struct DemoApp {
    public init() {}
}
EOF

cat > "$DEMO_DIR/Tests/DemoAppTests/PlaceholderTests.swift" <<'EOF'
import Testing

@Suite("Placeholder")
struct PlaceholderTests {
    @Test("1 + 1 == 2")
    func arithmeticWorks() {
        #expect(1 + 1 == 2)
    }
}
EOF

log "generate-feature Login --api / Notes --local / Catalog --api --local / Counter"
swift package --package-path "$DEMO_DIR" --allow-writing-to-package-directory generate-feature Login --api
swift package --package-path "$DEMO_DIR" --allow-writing-to-package-directory generate-feature Notes --local
swift package --package-path "$DEMO_DIR" --allow-writing-to-package-directory generate-feature Catalog --api --local
swift package --package-path "$DEMO_DIR" --allow-writing-to-package-directory generate-feature Counter

log "swift build (sin ArchitectureLint todavía)"
swift build --package-path "$DEMO_DIR" || fail "swift build falló sobre el código generado"

log "swift test"
swift test --package-path "$DEMO_DIR" || fail "swift test falló sobre el código generado"

log "Activando el plugin ArchitectureLint en el target DemoApp"
python3 - "$DEMO_DIR/Package.swift" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()
marker = 'path: "Sources/DemoApp",\n            swiftSettings: swiftSettings\n        ),'
replacement = (
    'path: "Sources/DemoApp",\n'
    '            swiftSettings: swiftSettings,\n'
    '            plugins: [.plugin(name: "ArchitectureLint", package: "AppFoundation")]\n'
    '        ),'
)
if marker not in text:
    sys.exit("No se encontró el target DemoApp en Package.swift para añadir el plugin")
open(path, "w").write(text.replace(marker, replacement, 1))
PYEOF

log "swift build con ArchitectureLint activo (debe pasar limpio)"
rm -rf "$DEMO_DIR/.build"
if ! swift build --package-path "$DEMO_DIR" > "$WORK_DIR/build-clean.log" 2>&1; then
    cat "$WORK_DIR/build-clean.log"
    fail "El build con ArchitectureLint activo debería pasar limpio y no lo hizo"
fi
grep -q "archlint: 0 errors" "$WORK_DIR/build-clean.log" || fail "No se vio 'archlint: 0 errors' en el build limpio"

VM_FILE="$DEMO_DIR/Sources/DemoApp/Features/Login/LoginViewModel.swift"
cp "$VM_FILE" "$WORK_DIR/LoginViewModel.swift.orig"

log "Introduciendo una violación de R1 (import CoreNetworking + APIService en LoginViewModel)"
python3 - "$VM_FILE" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("import AppFoundation\n", "import AppFoundation\nimport CoreNetworking\n", 1)
text = text.replace(
    "public private(set) var items: [LoginItem] = []",
    "public private(set) var items: [LoginItem] = []\n    private let api: APIService?",
    1
)
open(path, "w").write(text)
PYEOF

log "swift build (debe FALLAR con [ArchLint.R1])"
if swift build --package-path "$DEMO_DIR" > "$WORK_DIR/build-r1.log" 2>&1; then
    cat "$WORK_DIR/build-r1.log"
    fail "El build debería haber fallado por la violación de R1 y no falló"
fi
grep -q '\[ArchLint\.R1\]' "$WORK_DIR/build-r1.log" || {
    cat "$WORK_DIR/build-r1.log"
    fail "El build falló pero no se vio un diagnóstico [ArchLint.R1]"
}
log "Confirmado: el build falla con [ArchLint.R1]"

cp "$WORK_DIR/LoginViewModel.swift.orig" "$VM_FILE"

log "Restaurado LoginViewModel.swift — comprobando que el build vuelve a pasar limpio"
if ! swift build --package-path "$DEMO_DIR" > "$WORK_DIR/build-restored.log" 2>&1; then
    cat "$WORK_DIR/build-restored.log"
    fail "El build debería volver a pasar tras revertir la violación"
fi

log "swift package archlint sobre los cuatro ejemplos de AF-07 (deben pasar limpios)"
for example in LoginApp NotesApp CatalogApp CounterApp; do
    example_dir="$APPFOUNDATION_DIR/Examples/$example"
    if ! swift package --package-path "$example_dir" archlint > "$WORK_DIR/archlint-$example.log" 2>&1; then
        cat "$WORK_DIR/archlint-$example.log"
        fail "swift package archlint falló sobre Examples/$example (debería pasar limpio: es la referencia)"
    fi
    grep -q "archlint: 0 errors" "$WORK_DIR/archlint-$example.log" || {
        cat "$WORK_DIR/archlint-$example.log"
        fail "Examples/$example no reportó 'archlint: 0 errors'"
    }
    log "Examples/$example: archlint limpio"
done

log "Todo verde: generate-feature (4 variantes) + ArchitectureLint (pasa limpio, falla con R1, se recupera) + archlint sobre los 4 ejemplos de AF-07."
