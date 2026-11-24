#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="GearChanger"
APP_BUNDLE="${ROOT_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building GearChangerMenuBar (release)..."
cd "${ROOT_DIR}"
swift build -c release --product GearChangerMenuBar

BIN_PATH="$(swift build -c release --show-bin-path)/GearChangerMenuBar"

echo "==> Creating ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cp -R "${ROOT_DIR}/Sources/GearChangerMenuBar/Resources/en.lproj" "${RESOURCES_DIR}/"
cp -R "${ROOT_DIR}/Sources/GearChangerMenuBar/Resources/es.lproj" "${RESOURCES_DIR}/"

sed \
    -e "s|\$(EXECUTABLE_NAME)|${APP_NAME}|g" \
    -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|com.gearchanger.menubar|g" \
    -e "s|\$(PRODUCT_NAME)|${APP_NAME}|g" \
    "${ROOT_DIR}/App/Info.plist" > "${CONTENTS_DIR}/Info.plist"

echo "==> Ad-hoc signing ${APP_BUNDLE}..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Done! App ready at: ${APP_BUNDLE}"
echo "    Launch with: open \"${APP_BUNDLE}\""
