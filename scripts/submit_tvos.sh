#!/usr/bin/env bash
#
# Build, sign, export, and upload the Crown Breaker tvOS app to App Store
# Connect. Run from the project root:  ./scripts/submit_tvos.sh
#
# ── One-time prerequisites ────────────────────────────────────────────────
#  1. Xcode signed in to the Apple Developer account for team 866PPL96Z4
#     (Xcode ▸ Settings ▸ Accounts). Automatic signing needs it to mint the
#     Apple Distribution cert + App Store provisioning profile.
#  2. An app record at appstoreconnect.apple.com for bundle id
#     com.flutter-watchos.crownbreaker (platform: tvOS).
#  3. An App Store Connect API key (Users and Access ▸ Integrations ▸
#     App Store Connect API ▸ generate). Download the AuthKey_XXXX.p8 ONCE and
#     drop it in ~/.appstoreconnect/private_keys/ (altool auto-discovers it).
#  4. Export these before running — no secrets are stored in this repo:
#       export ASC_KEY_ID=XXXXXXXXXX
#       export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# The script never handles your password/credentials directly; altool reads
# the API key you provisioned above.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

FLUTTER=/Users/aliustaoglu/Developer/sdk/flutter-tvos/bin/flutter-tvos
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/tvos_dist"
WORKSPACE="$ROOT/tvos/Runner.xcworkspace"
ARCHIVE="$OUT/Runner.xcarchive"

cd "$ROOT"

echo "==> 1/4  Building Flutter tvOS release assets (AOT App.framework)"
"$FLUTTER" build tvos --release

echo "==> 2/4  Archiving with distribution signing"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme Runner \
  -configuration Release \
  -sdk appletvos \
  -destination 'generic/platform=tvOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

echo "==> 3/4  Exporting App Store .ipa"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/tvos/ExportOptions.plist" \
  -exportPath "$OUT/ipa" \
  -allowProvisioningUpdates

echo "==> 4/4  Uploading to App Store Connect"
: "${ASC_KEY_ID:?export ASC_KEY_ID first}"
: "${ASC_ISSUER_ID:?export ASC_ISSUER_ID first}"
xcrun altool --upload-app \
  --type tvos \
  --file "$OUT"/ipa/*.ipa \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo
echo "✅ Uploaded. It appears in App Store Connect ▸ TestFlight after Apple"
echo "   finishes processing (a few minutes). Then submit for review from the"
echo "   app's Distribution page."
