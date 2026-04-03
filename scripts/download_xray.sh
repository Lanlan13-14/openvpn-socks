#!/usr/bin/env bash
set -e

# 默认目录
BASE_DIR="$(pwd)/../xray"
TAG=${1:-latest}

# 取最新版本（如果用 “latest” 则自动获取最新 release tag）
if [ "$TAG" == "latest" ]; then
    TAG=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name":' | head -n1 | cut -d '"' -f4)
fi

echo "🧾 Xray version: $TAG"
mkdir -p "$BASE_DIR"/{linux,windows,macos,android}

download_and_unzip() {
    local url=$1
    local dest=$2

    echo "📥 下载: $url"
    curl -L "$url" -o /tmp/xray_tmp.zip

    echo "📦 解压到: $dest"
    unzip -o /tmp/xray_tmp.zip -d "$dest"
    chmod +x "$dest"/xray* || true
    rm -f /tmp/xray_tmp.zip
}

# 1) Linux 64
download_and_unzip \
  "https://github.com/XTLS/Xray-core/releases/download/${TAG}/Xray-linux-64.zip" \
  "$BASE_DIR/linux"

# 2) Windows 64
download_and_unzip \
  "https://github.com/XTLS/Xray-core/releases/download/${TAG}/Xray-windows-64.zip" \
  "$BASE_DIR/windows"

# 3) macOS ARM64
download_and_unzip \
  "https://github.com/XTLS/Xray-core/releases/download/${TAG}/Xray-macos-arm64-v8a.zip" \
  "$BASE_DIR/macos"

# 4) Android AMD64
download_and_unzip \
  "https://github.com/XTLS/Xray-core/releases/download/${TAG}/Xray-android-amd64.zip" \
  "$BASE_DIR/android/amd64"

# 5) Android ARM64
download_and_unzip \
  "https://github.com/XTLS/Xray-core/releases/download/${TAG}/Xray-android-arm64-v8a.zip" \
  "$BASE_DIR/android/arm64"

echo "✅ Xray 下载完成: $BASE_DIR"