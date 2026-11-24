#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="GearChanger"
APP_BUNDLE="${ROOT_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

echo "==> Building GearChangerMenuBar (release)..."
cd "${ROOT_DIR}"
swift build -c release --product GearChangerMenuBar

BIN_PATH="$(swift build -c release --show-bin-path)/GearChangerMenuBar"

echo "==> Creating ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>es</string>
    <key>CFBundleExecutable</key>
    <string>GearChanger</string>
    <key>CFBundleIdentifier</key>
    <string>com.gearchanger.menubar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>GearChanger</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>GearChanger necesita acceso a Bluetooth para conectarse a tu mando ThinkRider VS200 y leer los cambios de marcha.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>GearChanger necesita acceso a la red local para anunciar el servicio OpenBikeControl y conectarse con MyWhoosh.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_openbikecontrol._tcp</string>
    </array>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing ${APP_BUNDLE}..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Done! App ready at: ${APP_BUNDLE}"
echo "    Launch with: open \"${APP_BUNDLE}\""
