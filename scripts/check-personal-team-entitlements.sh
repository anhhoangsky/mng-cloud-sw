#!/usr/bin/env bash
# Report the capabilities the app asks for and fail when one of them needs a
# paid Apple Developer Program membership.
#
#   usage: check-personal-team-entitlements.sh [source-dir]
#
# A free "Personal Team" cannot grant these entitlements, so an AltStore build
# would fail at install time. The script never removes them: it reports and
# fails so the decision stays with the developer.
set -euo pipefail

SOURCE_DIR="${1:-App}"

# Entitlements that a free Personal Team cannot provision.
UNSUPPORTED_ENTITLEMENTS=(
  "aps-environment"
  "com.apple.developer.associated-domains"
  "com.apple.developer.icloud-container-identifiers"
  "com.apple.developer.icloud-services"
  "com.apple.developer.ubiquity-container-identifiers"
  "com.apple.security.application-groups"
  "keychain-access-groups"
)

# Capability-gated frameworks; using them at runtime needs a matching
# entitlement even when no .entitlements file exists.
CAPABILITY_APIS=(
  "UNUserNotificationCenter"
  "CKContainer"
  "CloudKit"
  "containerURL(forSecurityApplicationGroupIdentifier"
  "UserDefaults(suiteName:"
  "kSecAttrAccessGroup"
)

echo "== Personal Team capability report =="
echo "Source folder: $SOURCE_DIR"
echo

failures=0

entitlement_files=()
while IFS= read -r file; do
  entitlement_files+=("$file")
done < <(find "$SOURCE_DIR" -name '*.entitlements' -not -path '*/build/*' 2>/dev/null | sort)

if [ ${#entitlement_files[@]} -eq 0 ]; then
  echo "Entitlements files: none"
else
  echo "Entitlements files: ${#entitlement_files[@]}"
  for file in "${entitlement_files[@]}"; do
    echo "  - $file"
    for key in "${UNSUPPORTED_ENTITLEMENTS[@]}"; do
      if grep -q "$key" "$file"; then
        echo "    UNSUPPORTED by a free Personal Team: $key"
        failures=1
      fi
    done
  done
fi

echo
api_hits=0
for api in "${CAPABILITY_APIS[@]}"; do
  hits="$(grep -rn --include='*.swift' -F "$api" "$SOURCE_DIR" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "Uses $api:"
    echo "$hits" | sed 's/^/    /'
    api_hits=1
  fi
done
if [ "$api_hits" -eq 0 ]; then
  echo "Capability-gated APIs: none used"
fi

echo
if [ -f project.yml ]; then
  background_modes="$(grep -A4 'UIBackgroundModes' project.yml 2>/dev/null || true)"
  if [ -n "$background_modes" ]; then
    echo "UIBackgroundModes declared:"
    echo "$background_modes" | sed 's/^/    /'
  else
    echo "UIBackgroundModes: none"
  fi
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "RESULT: the app requests entitlements that a free Personal Team cannot"
  echo "        grant. Remove the capability from the app (it is a functional"
  echo "        change) or build with a paid team. Nothing was stripped here."
  exit 1
fi

echo "RESULT: the app requests no capability, so AltStore can re-sign it with"
echo "        a free Personal Team."
