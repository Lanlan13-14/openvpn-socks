#!/usr/bin/env bash
set -e

XRAY_DIR=${XRAY_DIR:-xray}
mkdir -p "$XRAY_DIR"

PLATFORMS=("linux" "windows" "macos" "android")
for plat in "${PLATFORMS[@]}"; do
    case "$plat" in
        linux)
            URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
            ;;
        windows)
            URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip"
            ;;
        macos)
            URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-macos-64.zip"
            ;;
        android)
            URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-android-64.zip"
            ;;
    esac

    ZIP_FILE="$XRAY_DIR/xray-${plat}.zip"
    BIN_FILE="$XRAY_DIR/$plat/xray"

    mkdir -p "$XRAY_DIR/$plat"
    echo "Downloading $plat xray..."
    curl -L "$URL" -o "$ZIP_FILE"
    unzip -o "$ZIP_FILE" -d "$XRAY_DIR/$plat"
    rm -f "$ZIP_FILE"
    chmod +x "$BIN_FILE" 2>/dev/null || true
done