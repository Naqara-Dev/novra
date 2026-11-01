#!/bin/bash
# Builds a release DMG of Novra.
#
#   ./scripts/release.sh                 DMG signed with the "Naqara Dev Code Signing" certificate in your
#                                        keychain when it's there (ad-hoc otherwise). Gatekeeper still warns
#                                        on first install, but macOS keeps Novra's permissions across updates.
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="novra-notary" ./scripts/release.sh
#                                        Signed, notarized and stapled DMG, ready to publish.
#
# One-time setup for notarization (needs a paid Apple Developer account):
#   xcrun notarytool store-credentials novra-notary --apple-id you@example.com --team-id TEAMID
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Novra.xcodeproj/project.pbxproj | head -1)
OUT=${OUT:-dist}
SELF_SIGNED="Naqara Dev Code Signing"
BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/p' Novra.xcodeproj/project.pbxproj | head -1)
ARCHIVE=build/Novra.xcarchive
PACKAGES=build/SourcePackages
SPARKLE_BIN=$PACKAGES/artifacts/sparkle/Sparkle/bin
DMG="$OUT/Novra-$VERSION.dmg"
rm -rf "$OUT" "$ARCHIVE" && mkdir -p "$OUT"

echo "› Archiving Novra $VERSION"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  TEAM=$(echo "$DEVELOPER_ID" | sed -n 's/.*(\(.*\))/\1/p')
  xcodebuild archive -project Novra.xcodeproj -scheme Novra -configuration Release -archivePath "$ARCHIVE" \
    -clonedSourcePackagesDirPath "$PACKAGES" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$TEAM" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" -quiet
else
  echo "  DEVELOPER_ID not set: building ad-hoc, then signing with \"$SELF_SIGNED\" if it's in the keychain."
  xcodebuild archive -project Novra.xcodeproj -scheme Novra -configuration Release -archivePath "$ARCHIVE" \
    -clonedSourcePackagesDirPath "$PACKAGES" CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" -quiet
fi

APP="$ARCHIVE/Products/Applications/Novra.app"
[[ -d "$APP" ]] || { echo "Archive has no app"; exit 1; }

# An ad-hoc signature changes with every build, so macOS treats each update as a new app and drops its
# Full Disk Access. A certificate that stays the same keeps the grant.
if [[ -z "${DEVELOPER_ID:-}" ]] && security find-certificate -c "$SELF_SIGNED" >/dev/null 2>&1; then
  echo "› Signing with \"$SELF_SIGNED\""
  sign() { codesign --force --sign "$SELF_SIGNED" --timestamp=none --options runtime --preserve-metadata=identifier,entitlements "$1"; }
  # Nested code first (Sparkle's helpers, then its framework), the app last.
  find "$APP/Contents" -depth \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" -o -name "*.dylib" \
    -o \( -name Autoupdate -type f \) \) -print0 |
    while IFS= read -r -d '' code; do sign "$code"; done
  # Library validation only accepts frameworks from Apple or the app's own Apple team, and a self-signed
  # certificate has no team, so Novra couldn't load Sparkle. Developer ID builds keep validation on.
  ENTITLEMENTS=$(mktemp)
  codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS"
  codesign --force --sign "$SELF_SIGNED" --timestamp=none --options runtime --preserve-metadata=identifier \
    --entitlements "$ENTITLEMENTS" "$APP"
  rm -f "$ENTITLEMENTS"
  codesign --verify --strict "$APP"
fi

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

# The feed Sparkle reads, signed with the EdDSA key in your keychain (made once with
# $SPARKLE_BIN/generate_keys --account naqara-novra). Upload it to the release next to the DMG.
echo "› Writing appcast.xml"
SIGNATURE=$("$SPARKLE_BIN/sign_update" --account naqara-novra "$DMG")
cat > "$OUT/appcast.xml" <<FEED
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Novra</title>
    <item>
      <title>Novra $VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <enclosure url="https://github.com/Naqara-Dev/novra/releases/download/v$VERSION/Novra-$VERSION.dmg" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
FEED

shasum -a 256 "$DMG"
echo "✓ $DMG"
echo "✓ $OUT/appcast.xml"
