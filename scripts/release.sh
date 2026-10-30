#!/bin/bash
# Builds a release DMG of Novra.
#
#   ./scripts/release.sh                 Unsigned DMG for local testing (Gatekeeper will warn).
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="novra-notary" ./scripts/release.sh
#                                        Signed, notarized and stapled DMG, ready to publish.
#
# One-time setup for notarization (needs a paid Apple Developer account):
#   xcrun notarytool store-credentials novra-notary --apple-id you@example.com --team-id TEAMID
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Novra.xcodeproj/project.pbxproj | head -1)
OUT=dist
ARCHIVE=build/Novra.xcarchive
DMG="$OUT/Novra-$VERSION.dmg"
rm -rf "$OUT" "$ARCHIVE" && mkdir -p "$OUT"

echo "› Archiving Novra $VERSION"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  TEAM=$(echo "$DEVELOPER_ID" | sed -n 's/.*(\(.*\))/\1/p')
  xcodebuild archive -project Novra.xcodeproj -scheme Novra -configuration Release -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$TEAM" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" -quiet
else
  echo "  DEVELOPER_ID not set: building an ad-hoc signed app for local testing only."
  xcodebuild archive -project Novra.xcodeproj -scheme Novra -configuration Release -archivePath "$ARCHIVE" \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" -quiet
fi

APP="$ARCHIVE/Products/Applications/Novra.app"
[[ -d "$APP" ]] || { echo "Archive has no app"; exit 1; }

echo "› Creating $DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Novra" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGE"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "› Notarizing (this takes a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  else
    echo "  NOTARY_PROFILE not set: signed but not notarized."
  fi
fi

shasum -a 256 "$DMG"
echo "✓ $DMG"
