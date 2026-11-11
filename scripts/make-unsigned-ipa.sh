#!/usr/bin/env bash
# Package an unsigned iOS device build into an .ipa that AltStore / AltServer
# can re-sign with the user's own Apple ID.
#
#   usage: make-unsigned-ipa.sh <path/to/MNGCloud.app> <output.ipa>
#
# The bundle keeps the standard layout:
#
#   Payload/MNGCloud.app/...
#
# No signature, no provisioning profile and no team id are added here: the
# runner only compiles and packs, AltStore signs on the user's machine.
set -euo pipefail

APP_PATH="${1:-}"
OUTPUT="${2:-}"

if [ -z "$APP_PATH" ] || [ -z "$OUTPUT" ]; then
  echo "usage: $0 <path/to/App.app> <output.ipa>" >&2
  exit 2
fi
if [ ! -d "$APP_PATH" ]; then
  echo "error: '$APP_PATH' is not a directory" >&2
  exit 2
fi

APP_BUNDLE="$(basename "$APP_PATH")"
APP_NAME="${APP_BUNDLE%.app}"
# macOS ships PlistBuddy here; the override keeps the script testable.
PLIST_BUDDY="${PLIST_BUDDY:-/usr/libexec/PlistBuddy}"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT")" 2>/dev/null && pwd || echo "$(dirname "$OUTPUT")")"
mkdir -p "$OUTPUT_DIR"
OUTPUT="$OUTPUT_DIR/$(basename "$OUTPUT")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/Payload"
cp -R "$APP_PATH" "$STAGE/Payload/$APP_BUNDLE"

APP="$STAGE/Payload/$APP_BUNDLE"
PLIST="$APP/Info.plist"

read_plist() {
  "$PLIST_BUDDY" -c "Print :$1" "$PLIST" 2>/dev/null || echo ""
}

BUNDLE_ID="$(read_plist CFBundleIdentifier)"
EXECUTABLE="$(read_plist CFBundleExecutable)"
DISPLAY_NAME="$(read_plist CFBundleDisplayName)"
VERSION="$(read_plist CFBundleShortVersionString)"
BUILD="$(read_plist CFBundleVersion)"
MIN_OS="$(read_plist MinimumOSVersion)"

echo "== IPA report =="
echo "Bundle id:       $BUNDLE_ID"
echo "Display name:    $DISPLAY_NAME"
echo "Version:         $VERSION ($BUILD)"
echo "Minimum iOS:     $MIN_OS"
echo "Executable:      $EXECUTABLE"

if [ -z "$BUNDLE_ID" ] || [ -z "$EXECUTABLE" ]; then
  echo "error: Info.plist is missing CFBundleIdentifier or CFBundleExecutable" >&2
  exit 1
fi
if [ ! -f "$APP/$EXECUTABLE" ]; then
  echo "error: the executable '$EXECUTABLE' is missing from the bundle" >&2
  exit 1
fi
if [ ! -f "$PLIST" ]; then
  echo "error: Info.plist is missing from the bundle" >&2
  exit 1
fi

echo "Architectures:   $(lipo -archs "$APP/$EXECUTABLE" 2>/dev/null || echo unknown)"
echo "Binary:          $(file -b "$APP/$EXECUTABLE")"

if codesign -dv "$APP" >/dev/null 2>&1; then
  echo "Signature:       present (unexpected on the AltStore path)"
else
  echo "Signature:       none (AltStore signs it with the personal Apple ID)"
fi

frameworks=()
while IFS= read -r fw; do frameworks+=("$fw"); done \
  < <(find "$APP/Frameworks" -maxdepth 1 -name '*.framework' 2>/dev/null | sort)
if [ ${#frameworks[@]} -gt 0 ]; then
  echo "Frameworks:      ${#frameworks[@]}"
  for fw in "${frameworks[@]}"; do
    echo "  - $(basename "$fw")"
    if [ ! -f "$fw/Info.plist" ]; then
      echo "error: $(basename "$fw") has no Info.plist" >&2
      exit 1
    fi
  done
else
  echo "Frameworks:      none (Swift package libraries are linked statically)"
fi

extensions=()
while IFS= read -r ext; do extensions+=("$ext"); done \
  < <(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' 2>/dev/null | sort)
if [ ${#extensions[@]} -gt 0 ]; then
  echo "App extensions:  ${#extensions[@]} (AltStore re-signs them together)"
  for ext in "${extensions[@]}"; do echo "  - $(basename "$ext")"; done
else
  echo "App extensions:  none"
fi

watches=()
while IFS= read -r watch; do watches+=("$watch"); done \
  < <(find "$APP/Watch" -maxdepth 1 -name '*.app' 2>/dev/null | sort)
if [ ${#watches[@]} -gt 0 ]; then
  echo "Watch apps:      ${#watches[@]} (AltStore Classic cannot install them)"
  for watch in "${watches[@]}"; do echo "  - $(basename "$watch")"; done
else
  echo "Watch apps:      none"
fi

echo "Resources:       $(find "$APP" -maxdepth 1 \( -name '*.car' -o -name '*.bundle' \) 2>/dev/null | wc -l | tr -d ' ')"

rm -f "$OUTPUT"
( cd "$STAGE" && zip -qry "$OUTPUT" Payload )

echo "Packaged:        $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
echo "Payload layout:"
( cd "$STAGE" && find Payload -maxdepth 2 | sort | sed 's/^/  /' )
