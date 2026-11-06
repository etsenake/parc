#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
check_bundle="$repo_root/build/tests/ScriptingChecks.app/Contents"
mkdir -p "$check_bundle/MacOS" "$check_bundle/Resources"
cp "$repo_root/Resources/Parc.sdef" "$check_bundle/Resources/Parc.sdef"
cat > "$check_bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ScriptingChecks</string>
<key>CFBundleIdentifier</key><string>test.parc.scripting.components</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSAppleScriptEnabled</key><true/>
<key>OSAScriptingDefinition</key><string>Parc.sdef</string>
</dict></plist>
PLIST
# This process contains only the scripting wrappers and fake model owners.
# No browser, Apple Event, osascript or user-profile operation is performed.
xcrun swiftc -parse-as-library \
  "$repo_root/Sources/ParcApp/BrowserScripting.swift" \
  "$repo_root/tests/Scripting/main.swift" \
  -o "$check_bundle/MacOS/ScriptingChecks"
"$check_bundle/MacOS/ScriptingChecks"
