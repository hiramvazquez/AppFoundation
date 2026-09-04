#!/usr/bin/env bash
# Scripts/verify-multi.sh — el test de integración real de PRD-AF-10: en un directorio
# temporal, arranca una app modular de tres niveles con `Scripts/bootstrap-multi.sh`
# (manifiesto mínimo + `archinit --multi`), genera dos features con `generate-feature`,
# compila y testea ambos paquetes, comprueba `archlint` limpio, e introduce un `import`
# entre features para comprobar que el build FALLA con `[ArchLint.R13]`. Si `xcodegen`
# está en el PATH, genera también el proyecto y compila la app para iOS Simulator.
#
# Uso: Scripts/verify-multi.sh          (desde cualquier directorio; se autolocaliza)
#      VERIFY_MULTI_FIREBASE=1 …        añade `--adapter Firebase` (resuelve y compila el SDK: lento)
# CI: .github/workflows/ci.yml, job `multi`.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -d "$REPO_ROOT/AppFoundation" ] && [ -d "$REPO_ROOT/CoreNetworking" ]; then
    APPFOUNDATION_DIR="$REPO_ROOT/AppFoundation"
    CORENETWORKING_DEP=".package(path: \"$REPO_ROOT/CoreNetworking\")"
else
    APPFOUNDATION_DIR="$REPO_ROOT"
    CORENETWORKING_DEP="${CORENETWORKING_DEP:-.package(url: \"https://github.com/hiramvazquez/CoreNetworking.git\", from: \"1.0.0\")}"
fi

WORK_DIR="$(mktemp -d /tmp/spm-pro-af10-verify.XXXXXX)"
APP_DIR="$WORK_DIR/DemoMulti"
trap 'rm -rf "$WORK_DIR"' EXIT

log()  { printf '\033[1;34m▶ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✘ %s\033[0m\n' "$*"; exit 1; }

# Los manifiestos generados apuntan a AppFoundation por URL y tag (lo correcto para un
# consumidor); aquí se verifica el kit SIN publicar, así que se sustituyen por `path:`.
use_local_kits() {
    local manifest="$1"
    python3 - "$manifest" "$APPFOUNDATION_DIR" "$CORENETWORKING_DEP" <<'PY'
import re, sys
path, af, cn = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
s = re.sub(r'\.package\(url: "https://github\.com/hiramvazquez/AppFoundation\.git", from: "[^"]+"\)', f'.package(path: "{af}")', s)
s = re.sub(r'\.package\(url: "https://github\.com/hiramvazquez/CoreNetworking\.git", from: "[^"]+"\)', cn, s)
open(path, "w").write(s)
PY
}

log "Arranque: bootstrap-multi.sh DemoMulti --capability Camera --adapter Analytics ${VERIFY_MULTI_FIREBASE:+--adapter Firebase}"
mkdir -p "$APP_DIR" && cd "$APP_DIR" && git init -q
APPFOUNDATION_PATH="$APPFOUNDATION_DIR" bash "$APPFOUNDATION_DIR/Scripts/bootstrap-multi.sh" DemoMulti \
    --capability Camera --adapter Analytics ${VERIFY_MULTI_FIREBASE:+--adapter Firebase} > "$WORK_DIR/archinit.log" 2>&1 \
    || { cat "$WORK_DIR/archinit.log"; fail "archinit --multi falló"; }
for f in App/AppModule.swift App/AppRoute.swift Packages/Platform/Package.swift Packages/Features/Package.swift Packages/Features/.archinit-multi .archlint.yml project.yml; do
    [ -e "$APP_DIR/$f" ] || fail "archinit --multi no generó $f"
done
grep -q "archinit:features-begin" Packages/Features/Package.swift || fail "faltan los markers en Packages/Features/Package.swift"
grep -q "modules:" .archlint.yml || fail "falta la sección modules: en .archlint.yml"
use_local_kits Packages/Features/Package.swift
use_local_kits Packages/Platform/Package.swift

log "Packages/Platform: swift build + swift test + archlint"
swift build --package-path Packages/Platform > "$WORK_DIR/platform-build.log" 2>&1 || { tail -20 "$WORK_DIR/platform-build.log"; fail "Platform no compila"; }
swift test --package-path Packages/Platform > "$WORK_DIR/platform-test.log" 2>&1 || { tail -20 "$WORK_DIR/platform-test.log"; fail "Platform: tests en rojo"; }
swift package --package-path Packages/Platform archlint > "$WORK_DIR/platform-archlint.log" 2>&1 || { cat "$WORK_DIR/platform-archlint.log"; fail "Platform: archlint con errores"; }
grep -q "archlint: 0 errors" "$WORK_DIR/platform-archlint.log" || fail "Platform: no se vio 'archlint: 0 errors'"

log "generate-feature Contratos --api · MisCasos --api --local"
(cd Packages/Features && swift package --allow-writing-to-package-directory generate-feature Contratos --api > "$WORK_DIR/gen-contratos.log" 2>&1) || { cat "$WORK_DIR/gen-contratos.log"; fail "generate-feature Contratos falló"; }
(cd Packages/Features && swift package --allow-writing-to-package-directory generate-feature MisCasos --api --local > "$WORK_DIR/gen-miscasos.log" 2>&1) || { cat "$WORK_DIR/gen-miscasos.log"; fail "generate-feature MisCasos falló"; }
grep -q 'name: "ContratosFeature"' Packages/Features/Package.swift || fail "ContratosFeature no se dio de alta en el manifiesto"
grep -q 'name: "MisCasosFeature"' Packages/Features/Package.swift || fail "MisCasosFeature no se dio de alta en el manifiesto"
grep -q "ContratosModule(baseURL: AppModule.apiBaseURL)," App/AppModule.swift || fail "ContratosModule(baseURL:) no se añadió a App/AppModule.swift"
grep -q "try MisCasosModule(baseURL: AppModule.apiBaseURL)," App/AppModule.swift || fail "try MisCasosModule(baseURL:) no se añadió a App/AppModule.swift"
grep -q "import ContratosFeature" App/AppModule.swift || fail "import ContratosFeature no se añadió a App/AppModule.swift"
grep -q "case .contratos: ContratosView" App/RootView.swift || fail "el destino de Contratos no se añadió a App/RootView.swift"
grep -q "product: ContratosFeature" project.yml || fail "el producto ContratosFeature no se añadió a project.yml"
grep -q "case contratos" App/AppRoute.swift || fail "case contratos no se añadió a App/AppRoute.swift"

log "Packages/Features: swift build + swift test + archlint (limpio)"
swift build --package-path Packages/Features > "$WORK_DIR/features-build.log" 2>&1 || { tail -30 "$WORK_DIR/features-build.log"; fail "Features no compila"; }
swift test --package-path Packages/Features > "$WORK_DIR/features-test.log" 2>&1 || { tail -30 "$WORK_DIR/features-test.log"; fail "Features: tests en rojo"; }
swift package --package-path Packages/Features archlint > "$WORK_DIR/features-archlint.log" 2>&1 || { cat "$WORK_DIR/features-archlint.log"; fail "Features: archlint con errores"; }
grep -q "archlint: 0 errors" "$WORK_DIR/features-archlint.log" || fail "Features: no se vio 'archlint: 0 errors'"

log "Prueba negativa: import ContratosFeature dentro de MisCasos (debe FALLAR con [ArchLint.R13])"
TARGET_FILE="$(ls Packages/Features/Sources/MisCasosFeature/*Logic.swift | head -1)"
cp "$TARGET_FILE" "$WORK_DIR/logic.bak"
{ echo "import ContratosFeature"; cat "$WORK_DIR/logic.bak"; } > "$TARGET_FILE"
if swift build --package-path Packages/Features > "$WORK_DIR/features-r13.log" 2>&1; then
    fail "El build debió fallar con un import entre features"
fi
grep -q "ArchLint.R13" "$WORK_DIR/features-r13.log" || { tail -20 "$WORK_DIR/features-r13.log"; fail "El build falló, pero no por R13"; }
cp "$WORK_DIR/logic.bak" "$TARGET_FILE"
swift build --package-path Packages/Features > "$WORK_DIR/features-restored.log" 2>&1 || fail "Tras revertir, Features no compila"
log "R13 bloqueó el import entre features y el build se recupera al revertir"

if command -v xcodegen > /dev/null 2>&1; then
    log "xcodegen + xcodebuild build (iOS Simulator)"
    (cd "$APP_DIR" && bash Scripts/bootstrap.sh > "$WORK_DIR/xcodegen.log" 2>&1) || { tail -20 "$WORK_DIR/xcodegen.log"; fail "bootstrap.sh (xcodegen) falló"; }
    xcodebuild build -project "$APP_DIR/DemoMulti.xcodeproj" -scheme DemoMulti -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation -quiet > "$WORK_DIR/xcodebuild.log" 2>&1 \
        || { grep -E "error:" "$WORK_DIR/xcodebuild.log" | head -10; fail "xcodebuild build de la app falló"; }
    log "xcodebuild build de la app en verde"
else
    log "AVISO: xcodegen no está en el PATH — se omite el build de la app"
fi

log "Todo verde: archinit --multi + generate-feature (2 features, alta automática) + build/test de Platform y Features + archlint + R13 bloquea el import entre features${VERIFY_MULTI_FIREBASE:+ + Firebase}"
