#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: package_dmg.sh VERSION [APP_BUNDLE]}"
APP_BUNDLE="${2:-apps/flutter_app/build/macos/Build/Products/Release/driveflow.app}"
OUT_DIR="${3:-build/release}"
APP_NAME="DriveFlow"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi
mkdir -p "$OUT_DIR"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP_BUNDLE" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT_DIR/DriveFlow-macOS-v${VERSION}.dmg"
