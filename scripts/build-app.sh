#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="GearChanger"
APP_VERSION="${APP_VERSION:-1.0.0}"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-macOS-universal.zip"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building GearChangerMenuBar (release, universal arm64 + x86_64)..."
cd "${ROOT_DIR}"
swift build -c release --arch arm64 --arch x86_64 --product GearChangerMenuBar

BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/GearChangerMenuBar"

echo "==> Creating ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}" "${ZIP_PATH}"
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

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"

echo "==> Ad-hoc signing ${APP_BUNDLE}..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Verifying architectures..."
lipo -info "${MACOS_DIR}/${APP_NAME}"

echo "==> Packaging release archive ${ZIP_PATH}..."
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "==> Done!"
echo "    App: ${APP_BUNDLE}"
echo "    Zip: ${ZIP_PATH}"
echo "    Launch with: open \"${APP_BUNDLE}\""
