#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
out="$repo_root/build/tests/native-certificate-viewer"
mkdir -p "$out"
/usr/bin/openssl x509 -in "$repo_root/tests/NativeCertificateViewer/fixture.pem" -outform DER -out "$out/fixture.der"
xcrun clang++ -std=c++20 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
  -I "$repo_root/Engine/ParcNative" \
  "$repo_root/Engine/ParcNative/certificate_viewer_presenter.mm" \
  "$repo_root/tests/NativeCertificateViewer/presenter_tests.mm" \
  -framework AppKit -framework Security -framework SecurityInterface \
  -o "$out/presenter_tests"
"$out/presenter_tests" "$out/fixture.der"
