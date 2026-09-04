#!/usr/bin/env bash
# Scripts/bootstrap-multi.sh — arranque en un comando de una app modular de tres niveles
# (PRD-AF-10). Un command plugin solo corre sobre un paquete que dependa de AppFoundation,
# así que este script crea el manifiesto mínimo de `Packages/Features` y llama a
# `archinit --multi`, que reescribe ese manifiesto y genera todo lo demás.
#
# Uso (desde la raíz del repo, vacío o recién creado):
#   Scripts/bootstrap-multi.sh <Name> [--capability Camera]… [--adapter Firebase]… [--bundle-id …] [--no-xcodegen] [--dry-run]
#
# Variables:
#   APPFOUNDATION_VERSION  tag mínimo de AppFoundation (por defecto 1.2.0)
#   APPFOUNDATION_PATH     ruta local a AppFoundation en vez de la URL (desarrollo del kit)
set -euo pipefail

NAME="${1:-}"
if [ -z "$NAME" ]; then
    echo "Uso: $0 <Name> [opciones de archinit --multi]" >&2
    exit 64
fi
shift

ROOT="$(pwd)"
FEATURES="$ROOT/Packages/Features"
VERSION="${APPFOUNDATION_VERSION:-1.2.0}"

if [ -f "$FEATURES/Package.swift" ] && grep -q "archinit:features-begin" "$FEATURES/Package.swift"; then
    echo "Packages/Features ya está inicializado (markers presentes); ejecutando solo archinit --multi." >&2
else
    mkdir -p "$FEATURES"
    if [ -n "${APPFOUNDATION_PATH:-}" ]; then
        DEP=".package(path: \"$APPFOUNDATION_PATH\")"
    else
        DEP=".package(url: \"https://github.com/hiramvazquez/AppFoundation.git\", from: \"$VERSION\")"
    fi
    cat > "$FEATURES/Package.swift" <<MANIFEST
// swift-tools-version: 6.2
// Manifiesto mínimo: archinit --multi lo reescribe con la forma final.
import PackageDescription

let package = Package(
    name: "Features",
    dependencies: [
        $DEP
    ]
)
MANIFEST
fi

cd "$FEATURES"
swift package --allow-writing-to-package-directory archinit --multi --root "$ROOT" --name "$NAME" "$@"
