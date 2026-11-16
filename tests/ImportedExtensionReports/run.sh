#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-imported-extension-reports.XXXXXX")"
trap 'rm -rf "$output"' EXIT
flags=(-arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -fblocks -DOS_MAC=1
       -I "$root/Engine/ParcNative" -I "$root/Sources/ParcEngine")
xcrun clang "${flags[@]}" -Wall -Wextra -Werror -Wno-unused-parameter \
  -c "$root/Sources/ParcEngine/ParcEngine.m" -o "$output/ParcEngine.o"
if nm -u "$output/ParcEngine.o" | grep -q 'PCNativeImportExtensionFailure'; then
  echo "error: the app facade links against the engine's extension failure class" >&2
  exit 1
fi
if grep -rnE 'PCNativeImportExtensionFailure|installImportedExtensions|extensionRestriction\(for' \
     "$root/Sources/ParcApp" "$root/Sources/ParcCore"; then
  echo "error: Swift reaches past the facade to the engine's extension failure report" >&2
  exit 1
fi
xcrun clang "${flags[@]}" -Wall -Werror -Wno-incomplete-implementation -Wno-objc-property-implementation \
  -Wno-objc-protocol-property-synthesis -Wno-protocol -Wno-objc-root-class \
  -c "$root/tests/ImportedExtensionReports/Tests.m" -o "$output/Tests.o"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -framework AppKit \
  "$output/ParcEngine.o" "$output/Tests.o" -o "$output/check"
"$output/check"
