#!/usr/bin/env bash
#
# Build, sign, export, and upload the Crown Breaker watchOS app to App Store
# Connect. Run from the project root:  ./scripts/submit_watchos.sh
#
# ── One-time prerequisites ────────────────────────────────────────────────
#  1. Xcode signed in to the Apple Developer account for team 866PPL96Z4
#     (Xcode ▸ Settings ▸ Accounts). Automatic signing mints the Apple
#     Distribution cert and BOTH App Store profiles it needs — one for the
#     container (com.flutter-watchos.crownbreaker) and one for the watch app
#     (…​.watchkitapp).
#  2. An app record at appstoreconnect.apple.com for bundle id
#     com.flutter-watchos.crownbreaker. Platform is **iOS**, not watchOS: a
#     watch-only app ships inside a code-less iOS container, so App Store
#     Connect files it under iOS.
#  3. An App Store Connect API key in ~/.appstoreconnect/private_keys/ and:
#       export ASC_KEY_ID=XXXXXXXXXX
#       export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# ── Two things that will silently produce a bad build ─────────────────────
#  * The engine. flutter-watchos prefers a local engine_artifacts/ over the
#    version pinned in bin/internal/engine.version, and it does not warn when
#    the two disagree. A stale hand-built tree there links an old engine into
#    a *release* build with no error. WATCHOS_ENGINE_ARTIFACTS below pins it
#    explicitly; keep it pointed at the directory matching engine.version.
#  * The scheme. Archive `crown_breaker` (the container), not `Runner` (the
#    bare watch app). A bare watch target archives as a "Generic Xcode
#    Archive" with no App Store distribution option.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

MONOREPO=/Users/aliustaoglu/Developer/playground/flutter_watchos_monorepo
FLUTTER="$MONOREPO/flutter-watchos/bin/flutter-watchos"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/watchos_dist"
PROJECT="$ROOT/watchos/Runner.xcodeproj"
ARCHIVE="$OUT/Runner.xcarchive"

# Must match flutter-watchos/bin/internal/engine.version.
export WATCHOS_ENGINE_ARTIFACTS="$MONOREPO/artifacts/v0.1.7"

cd "$ROOT"

PINNED="$(cat "$MONOREPO/flutter-watchos/bin/internal/engine.version")"
echo "==> 0/5  Engine pin is $PINNED; using $WATCHOS_ENGINE_ARTIFACTS"
[ -d "$WATCHOS_ENGINE_ARTIFACTS" ] || {
  echo "!! $WATCHOS_ENGINE_ARTIFACTS does not exist — fix before shipping." >&2
  exit 1
}

echo "==> 1/5  Building Flutter watchOS release assets (AOT)"
"$FLUTTER" build watchos --release

echo "==> 2/5  Checking the watch executable is fat"
# The App Store requires an arm64_32 slice while WATCHOS_DEPLOYMENT_TARGET is
# below 27.0. The engine is arm64-only, so the template supplies a stub
# arm64_32 that shows a "needs Series 9 or later" screen on older hardware.
SLICES="$(lipo -info "$ROOT/build/watchos/Release-watchos/Runner.app/Runner")"
echo "    $SLICES"
case "$SLICES" in
  *arm64_32*) ;;
  *) echo "!! no arm64_32 slice — the App Store will reject this." >&2; exit 1 ;;
esac

echo "==> 3/5  Archiving the container with distribution signing"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild \
  -project "$PROJECT" \
  -scheme crown_breaker \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

echo "==> 4/5  Exporting App Store .ipa"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/watchos/ExportOptions.plist" \
  -exportPath "$OUT/ipa" \
  -allowProvisioningUpdates

echo "==> 5/5  Uploading to App Store Connect"
: "${ASC_KEY_ID:?export ASC_KEY_ID first}"
: "${ASC_ISSUER_ID:?export ASC_ISSUER_ID first}"
xcrun altool --upload-app \
  --type ios \
  --file "$OUT"/ipa/*.ipa \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo
echo "✅ Uploaded. It appears in App Store Connect ▸ TestFlight after Apple"
echo "   finishes processing (a few minutes). Then submit for review from the"
echo "   app's Distribution page."
