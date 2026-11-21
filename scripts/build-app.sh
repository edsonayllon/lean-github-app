#!/bin/bash
# Builds "Repo Select.app" into build/. Pass --install to also copy it to /Applications. Pass --release to
# build it for Apple silicon and Intel, sign it for distribution and make a notarised build/RepoSelect.dmg
# (needs a Developer ID Application certificate and a notarytool profile, see README).
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-}"
case "$MODE" in
  "" | --install | --release) ;;
  *) echo "usage: $0 [--install | --release]" >&2; exit 2 ;;
esac

# The keychain profile saved with `xcrun notarytool store-credentials`.
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"
if [ "$MODE" = "--release" ]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
  if [ -z "$IDENTITY" ]; then
    echo "No Developer ID Application certificate in the keychain. Create one first (see README)." >&2
    exit 1
  fi
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "No notarytool profile named \"$NOTARY_PROFILE\". Save one first (see README)." >&2
    exit 1
  fi
  # People download this one, so it runs on Intel Macs as well.
  BUILD_FLAGS=(-c release --arch arm64 --arch x86_64)
else
  # A stable signing identity keeps macOS from asking for folder access again after every rebuild.
  IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
  BUILD_FLAGS=(-c release)
fi

APP_NAME="Repo Select"
BUNDLE_ID="com.reposelect.app"
# The version is the one being released (scripts/release.sh passes it), or else the last release's tag.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-1.0.0}"
APP="build/$APP_NAME.app"

swift build "${BUILD_FLAGS[@]}"
BIN="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/RepoSelect"

# The icon is drawn by a script and kept in the repo; redraw it only if it's missing.
if [ ! -f Resources/AppIcon.icns ]; then
  TMP="$(mktemp -d)"
  swift scripts/make-icon.swift "$TMP/icon.png"
  mkdir "$TMP/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RepoSelect"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>RepoSelect</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDocumentsFolderUsageDescription</key><string>Repo Select lists and manages the repositories in your GitHub folder.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Repo Select needs access to add a repository stored on your Desktop.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Repo Select needs access to add a repository stored in Downloads.</string>
</dict>
</plist>
PLIST

# Every build runs under the hardened runtime that notarisation requires, so a local build behaves like the
# one people download. Only a release needs the secure timestamp, which asks Apple's server.
SIGN_FLAGS=(--force --options runtime)
[ "$MODE" = "--release" ] && SIGN_FLAGS+=(--timestamp)
codesign "${SIGN_FLAGS[@]}" --sign "${IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP $VERSION (signed with: ${IDENTITY:-ad-hoc})"

if [ "$MODE" = "--release" ]; then
  DMG="build/RepoSelect.dmg"
  STAGE="$(mktemp -d)"
  MOUNT="$(mktemp -d)"
  trap 'hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true; rm -rf "$STAGE"' EXIT
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"

  # --timeout keeps a stuck submission from waiting forever; Apple usually answers in a few minutes.
  echo "Notarising $DMG..."
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 20m \
    > build/notarytool.log 2>&1 || true
  if ! grep -q "status: Accepted" build/notarytool.log; then
    cat build/notarytool.log >&2
    echo "Notarisation failed. For the reasons: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE" >&2
    exit 1
  fi
  xcrun stapler staple -q "$DMG"

  # Check it the way Gatekeeper will on someone else's Mac: the disk image, then the app inside it.
  xcrun stapler validate -q "$DMG"
  spctl -a -t open --context context:primary-signature "$DMG"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
  spctl -a -t exec "$MOUNT/$APP_NAME.app"
  echo "Notarised $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
  exit 0
fi

if [ "$MODE" = "--install" ]; then
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "Installed /Applications/$APP_NAME.app"
fi
