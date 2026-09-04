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
    CORENETWORKING_DEP="${CORENETWORKING_DEP:-.package(url: \"https://github.com/hiramvazquez/CoreNetworking.git\", from: \"1.0.0\")}"
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

log "A4 (PRD-X-05): generate-feature Products --api / Detail --api --service-from Products"
swift package --package-path "$DEMO_DIR" --allow-writing-to-package-directory generate-feature Products --api
swift package --package-path "$DEMO_DIR" --allow-writing-to-package-directory generate-feature Detail --api --service-from Products

DETAIL_LOGIC="$DEMO_DIR/Sources/DemoApp/Features/Detail/DetailLogic.swift"
grep -q "any ProductsServicing" "$DETAIL_LOGIC" || fail "DetailLogic no depende de 'any ProductsServicing' (--service-from no se aplicó)"
grep -q "protocol DetailServicing" "$DETAIL_LOGIC" && fail "DetailLogic declaró un DetailServicing propio — --service-from debía reutilizar ProductsServicing, no generar uno nuevo"
[ -f "$DEMO_DIR/Sources/DemoApp/Features/Detail/Services/DetailService.swift" ] && fail "--service-from no debía generar Detail/Services/DetailService.swift"
[ -f "$DEMO_DIR/Tests/DemoAppTests/Features/Detail/Mocks/DetailServiceMock.swift" ] && fail "--service-from no debía generar DetailServiceMock.swift"
grep -q "ProductsServiceMock" "$DEMO_DIR/Tests/DemoAppTests/Features/Detail/DetailLogicTests.swift" \
    || fail "DetailLogicTests no reutiliza ProductsServiceMock"

log "swift build (sin ArchitectureLint todavía)"
swift build --package-path "$DEMO_DIR" || fail "swift build falló sobre el código generado"

log "swift test"
swift test --package-path "$DEMO_DIR" || fail "swift test falló sobre el código generado"

# PRD-AF-09: el código generado debe pasar la configuración curada de SwiftLint sin avisos.
# Solo si `swiftlint` está en el PATH (el plugin lo descarga en los consumidores; aquí no).
SWIFTLINT_CONFIG="$REPO_ROOT/Templates/swiftlint.yml"
if command -v swiftlint > /dev/null 2>&1; then
    log "swiftlint --strict sobre el código generado (Templates/swiftlint.yml)"
    # Solo Sources/ y Tests/: los `excluded` del .yml son relativos al fichero de configuración,
    # no al directorio lintado, así que con --config desde otro sitio no excluirían .build/.
    swiftlint lint --strict --quiet --config "$SWIFTLINT_CONFIG" "$DEMO_DIR/Sources" "$DEMO_DIR/Tests" \
        || fail "El código generado no pasa swiftlint --strict con la configuración curada"
else
    log "AVISO: swiftlint no está en el PATH — se omite la comprobación de calidad del código generado"
fi

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
    if command -v swiftlint > /dev/null 2>&1; then
        swiftlint lint --strict --quiet --config "$SWIFTLINT_CONFIG" "$example_dir/Sources" "$example_dir/Tests" \
            || fail "Examples/$example no pasa swiftlint --strict con Templates/swiftlint.yml"
        log "Examples/$example: swiftlint --strict limpio"
    fi
done

########################################################################################
# PRD-AF-10 (entregable 2): "modo multi" — generate-feature registra el target/producto
# entre los markers de un Package.swift de tipo `Features` (archinit --multi, agente A) y
# hace las inserciones best-effort en ../../App/{AppModule,AppRoute}.swift. `archinit
# --multi` en sí no está construido todavía (otro entregable de PRD-AF-10): esta sección
# monta a mano la estructura mínima del contrato documentado — `.archinit-multi`, los
# markers de Package.swift, un `Platform` con el producto `Domain` vacío, y
# `App/{AppModule,AppRoute}.swift` con sus markers — exactamente como se espera que
# `archinit --multi` los deje.
########################################################################################

log "Modo multi: montando la estructura mínima del contrato (.archinit-multi + markers)"

MULTI_ROOT="$WORK_DIR/MultiApp"
FEATURES_DIR="$MULTI_ROOT/Packages/Features"
PLATFORM_DIR="$MULTI_ROOT/Packages/Platform"
APP_DIR="$MULTI_ROOT/App"

mkdir -p "$FEATURES_DIR/Sources" "$FEATURES_DIR/Tests" "$PLATFORM_DIR/Sources/Domain" "$APP_DIR"
touch "$FEATURES_DIR/.archinit-multi"

cat > "$PLATFORM_DIR/Package.swift" <<'EOF'
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Platform",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"])
    ],
    targets: [
        .target(name: "Domain", path: "Sources/Domain")
    ]
)
EOF

cat > "$PLATFORM_DIR/Sources/Domain/Domain.swift" <<'EOF'
// Modelos y protocolos compartidos entre features — solo Foundation (PRD-AF-10). Vacío a
// propósito: este fixture solo comprueba que generate-feature enlaza contra el producto
// Domain, no que lo use.
public enum Domain {}
EOF

cat > "$FEATURES_DIR/Package.swift" <<EOF
// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "Features",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // archinit:products-begin
        // archinit:products-end
    ],
    dependencies: [
        .package(path: "$APPFOUNDATION_DIR"),
        $CORENETWORKING_DEP,
        .package(path: "$PLATFORM_DIR")
    ],
    targets: [
        // archinit:features-begin
        // archinit:features-end
    ]
)
EOF

cat > "$APP_DIR/AppModule.swift" <<'EOF'
import AppFoundation

/// Composition root — generado a mano por este fixture con la forma que archinit --multi
/// deja (PRD-AF-10, entregable 4): generate-feature solo toca la línea del marker.
enum AppModule {
    static func register(in container: Container) {
        container.register(modules: [
            AppFoundationModule(),
            // archinit:modules
        ])
    }
}
EOF

cat > "$APP_DIR/AppRoute.swift" <<'EOF'
/// Cada pantalla navegable de la app — generado a mano por este fixture con la forma que
/// archinit --multi deja (PRD-AF-10, entregable 4): generate-feature solo añade el `case`.
enum AppRoute: Hashable {
    case home
    // archinit:routes
}
EOF

log "Modo multi: generate-feature Contratos --api / MisCasos --api --local --module"
swift package --package-path "$FEATURES_DIR" --allow-writing-to-package-directory generate-feature Contratos --api
swift package --package-path "$FEATURES_DIR" --allow-writing-to-package-directory generate-feature MisCasos --api --local --module

MULTI_MANIFEST="$FEATURES_DIR/Package.swift"

log "Modo multi: el target/producto de Contratos y MisCasos quedaron entre los markers"
grep -q 'name: "ContratosFeature"' "$MULTI_MANIFEST" || fail "ContratosFeature no se registró entre los markers de targets"
grep -q 'name: "ContratosFeatureTests"' "$MULTI_MANIFEST" || fail "ContratosFeatureTests no se registró entre los markers de targets"
grep -q 'name: "MisCasosFeatureCore"' "$MULTI_MANIFEST" || fail "MisCasosFeatureCore no se registró (--module) entre los markers de targets"
grep -q 'name: "MisCasosFeatureUI"' "$MULTI_MANIFEST" || fail "MisCasosFeatureUI no se registró (--module) entre los markers de targets"
grep -q 'name: "MisCasosFeatureTests"' "$MULTI_MANIFEST" || fail "MisCasosFeatureTests no se registró entre los markers de targets"
grep -q '.library(name: "ContratosFeature", targets: \["ContratosFeature"\])' "$MULTI_MANIFEST" \
    || fail "El producto ContratosFeature no se registró entre los markers de products"
grep -q '.library(name: "MisCasosFeature", targets: \["MisCasosFeatureCore", "MisCasosFeatureUI"\])' "$MULTI_MANIFEST" \
    || fail "El producto MisCasosFeature (Core+UI) no se registró entre los markers de products"

log "Modo multi: regenerar el mismo feature falla claro y no toca nada (target ya existe)"
cp "$MULTI_MANIFEST" "$WORK_DIR/Package.swift.before-duplicate"
if swift package --package-path "$FEATURES_DIR" --allow-writing-to-package-directory generate-feature Contratos --api \
    > "$WORK_DIR/duplicate.log" 2>&1; then
    cat "$WORK_DIR/duplicate.log"
    fail "generate-feature Contratos --api debería haber fallado (ya está registrado) y no falló"
fi
grep -q "ya está registrado" "$WORK_DIR/duplicate.log" || {
    cat "$WORK_DIR/duplicate.log"
    fail "El error de 'ya existe' no fue claro"
}
diff -q "$WORK_DIR/Package.swift.before-duplicate" "$MULTI_MANIFEST" > /dev/null \
    || fail "generate-feature tocó Package.swift aunque el target ya existía — debía dejarlo intacto"
[ -f "$FEATURES_DIR/Sources/ContratosFeature/ContratosView.swift" ] \
    || fail "el intento duplicado no debería haber borrado los ficheros de la primera generación"
log "Confirmado: sin markers/target duplicado, generate-feature no toca nada"

log "Modo multi: App/AppModule.swift y App/AppRoute.swift recibieron las inserciones"
grep -q "ContratosModule()," "$APP_DIR/AppModule.swift" || fail "ContratosModule() no se insertó en App/AppModule.swift"
grep -q "MisCasosModule()," "$APP_DIR/AppModule.swift" || fail "MisCasosModule() no se insertó en App/AppModule.swift"
grep -q "case contratos" "$APP_DIR/AppRoute.swift" || fail "'case contratos' no se insertó en App/AppRoute.swift"
grep -q "case misCasos" "$APP_DIR/AppRoute.swift" || fail "'case misCasos' no se insertó en App/AppRoute.swift"

log "Modo multi: swift build del paquete Features (Contratos + MisCasosCore/UI, ArchitectureLint incluido)"
swift build --package-path "$FEATURES_DIR" || fail "swift build falló sobre el paquete Features en modo multi"

log "Modo multi: swift test del paquete Features"
swift test --package-path "$FEATURES_DIR" || fail "swift test falló sobre el paquete Features en modo multi"

log "Modo multi: swift package archlint sobre Features (debe pasar limpio)"
if ! swift package --package-path "$FEATURES_DIR" archlint > "$WORK_DIR/archlint-multi.log" 2>&1; then
    cat "$WORK_DIR/archlint-multi.log"
    fail "swift package archlint falló sobre el paquete Features en modo multi"
fi
grep -q "archlint: 0 errors" "$WORK_DIR/archlint-multi.log" || {
    cat "$WORK_DIR/archlint-multi.log"
    fail "El paquete Features en modo multi no reportó 'archlint: 0 errors'"
}

if command -v swiftlint > /dev/null 2>&1; then
    log "Modo multi: swiftlint --strict sobre el código generado (Templates/swiftlint.yml)"
    swiftlint lint --strict --quiet --config "$SWIFTLINT_CONFIG" "$FEATURES_DIR/Sources" "$FEATURES_DIR/Tests" \
        || fail "El código generado en modo multi no pasa swiftlint --strict con la configuración curada"
else
    log "AVISO: swiftlint no está en el PATH — se omite la comprobación de calidad del código generado en modo multi"
fi

log "Modo multi: --no-register no toca Package.swift ni App/"
cp "$MULTI_MANIFEST" "$WORK_DIR/Package.swift.before-no-register"
cp "$APP_DIR/AppModule.swift" "$WORK_DIR/AppModule.swift.before-no-register"
cp "$APP_DIR/AppRoute.swift" "$WORK_DIR/AppRoute.swift.before-no-register"
swift package --package-path "$FEATURES_DIR" --allow-writing-to-package-directory generate-feature Standalone --no-register
diff -q "$WORK_DIR/Package.swift.before-no-register" "$MULTI_MANIFEST" > /dev/null \
    || fail "--no-register no debía tocar Package.swift"
diff -q "$WORK_DIR/AppModule.swift.before-no-register" "$APP_DIR/AppModule.swift" > /dev/null \
    || fail "--no-register no debía tocar App/AppModule.swift"
diff -q "$WORK_DIR/AppRoute.swift.before-no-register" "$APP_DIR/AppRoute.swift" > /dev/null \
    || fail "--no-register no debía tocar App/AppRoute.swift"
[ -f "$FEATURES_DIR/Sources/StandaloneFeature/StandaloneView.swift" ] \
    || fail "--no-register debía seguir generando los ficheros del feature, solo sin registrar nada"
log "Confirmado: --no-register genera ficheros sin editar Package.swift ni App/"

log "Todo verde: generate-feature (4 variantes) + modo multi (targets/producto registrados, duplicado rechazado sin tocar nada, App/AppModule+AppRoute, --no-register) + ArchitectureLint (pasa limpio, falla con R1, se recupera) + archlint sobre los 4 ejemplos de AF-07 y sobre Features en modo multi."
