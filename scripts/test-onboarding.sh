#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors \
  "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/OnboardingTests.swift" \
  -o "$repo_root/build/tests/onboarding"
"$repo_root/build/tests/onboarding"
python3 "$repo_root/tests/OnboardingReplay/check.py"
bash "$repo_root/scripts/test-onboarding-video.sh"
