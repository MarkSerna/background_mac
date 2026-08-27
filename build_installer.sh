#!/bin/bash
# ==============================================================================
# Script de Compilación y Generación de Instaladores para iPad (.ipa) y Mac (.dmg)
# ==============================================================================

set -e

APP_NAME="BackgroundRemover"
SCHEME="BackgroundRemoverApp"
CONFIGURATION="Release"
OUTPUT_DIR="build/installers"

echo "🔨 Iniciando proceso de empaquetado para $APP_NAME..."

mkdir -p "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# 1. Empaquetado para iPad / iOS (.IPA / Sideloading)
# ------------------------------------------------------------------------------
echo "📱 1. Generando paquete para iPad (.ipa)..."

if command -v xcodebuild &> /dev/null; then
    xcodebuild archive \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "generic/platform=iOS" \
        -archivePath "$OUTPUT_DIR/$APP_NAME-iOS.xcarchive" \
        CODE_SIGNING_ALLOWED=NO

    mkdir -p "$OUTPUT_DIR/Payload"
    cp -r "$OUTPUT_DIR/$APP_NAME-iOS.xcarchive/Products/Applications/$APP_NAME.app" "$OUTPUT_DIR/Payload/"
    cd "$OUTPUT_DIR"
    zip -qr "$APP_NAME.ipa" Payload
    rm -rf Payload
    cd - > /dev/null

    echo "✅ Archivo instalador para iPad generado: $OUTPUT_DIR/$APP_NAME.ipa"
else
    echo "⚠️  xcodebuild no encontrado en este entorno. Usa Xcode en macOS para ejecutar este script."
fi

# ------------------------------------------------------------------------------
# 2. Empaquetado para Mac (.DMG)
# ------------------------------------------------------------------------------
echo "💻 2. Generando instalador para Mac (.dmg)..."

if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "$APP_NAME Installer" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --app-drop-link 450 185 \
        "$OUTPUT_DIR/$APP_NAME.dmg" \
        "$OUTPUT_DIR/$APP_NAME-macOS.xcarchive/Products/Applications/$APP_NAME.app"
    echo "✅ Instalador DMG para Mac generado: $OUTPUT_DIR/$APP_NAME.dmg"
fi

echo "🎉 Proceso de empaquetado finalizado."
