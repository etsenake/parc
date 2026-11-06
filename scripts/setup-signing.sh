#!/bin/bash
# One-time, per Mac: choose the code-signing identity scripts/package-app.sh
# signs with. Without one, builds are ad-hoc signed: the keychain's partition
# list for "Parc Safe Storage" then names each build's cdhash, so macOS asks
# again after every update (and pages stay blank until it's answered), and
# camera/microphone grants reset too. Code signed by an Apple-issued
# certificate carries a Team ID, which the keychain and privacy settings
# remember across builds. A self-signed certificate has no Team ID, so it
# doesn't help.
#
# Any Apple ID works. In Xcode: Settings > Accounts > + > Apple ID, select its
# team (a free "Personal Team" is fine) > Manage Certificates > + > Apple
# Development. Use the same Apple ID on every Mac that builds; each Mac gets
# its own certificate and key from Apple, and nothing private is copied.
#
# Production publication requires Developer ID Application and notarization.
# A paid team can
# instead add Developer ID Application in Manage Certificates; package-app.sh
# then notarizes each build, which needs credentials stored once per Mac with
# `xcrun notarytool store-credentials parc-notary --apple-id <Apple ID> --team-id <team>`.
#
#   scripts/setup-signing.sh             use this Mac's only Apple-issued identity
#   scripts/setup-signing.sh 'IDENTITY'  use that one (as listed by the first form)
#
# It only records the choice in ~/.config/parc/signing-identity; it creates,
# trusts and imports nothing.
set -euo pipefail
keychain="$HOME/Library/Keychains/login.keychain-db"
config="$HOME/.config/parc/signing-identity"
[ $# -le 1 ] || { echo "usage: $0 ['Developer ID Application: Name (TEAM ID)']" >&2; exit 2; }

identities="$(security find-identity -v -p codesigning "$keychain" |
  sed -nE 's/^ *[0-9]+\) [0-9A-F]{40} "((Developer ID Application|Apple Development): .*)"$/\1/p' | sort -u)"
if [ $# -eq 1 ]; then
  name="$1"
  if ! grep -qxF -- "$name" <<<"$identities"; then
    echo "error: \"$name\" isn't a valid Apple-issued code-signing identity in the login keychain." >&2
    if [ -n "$identities" ]; then echo "Valid ones:" >&2; sed 's/^/  /' <<<"$identities" >&2; fi
    exit 1
  fi
elif [ -z "$identities" ]; then
  echo "No Apple Development or Developer ID certificate on this Mac yet. In Xcode:" >&2
  echo "Settings > Accounts > + > Apple ID, select the team > Manage Certificates > + >" >&2
  echo "Apple Development. Then run $0 again." >&2
  exit 1
elif [ "$(wc -l <<<"$identities")" -gt 1 ]; then
  echo "Several identities; rerun with the one to use (the same Apple ID on every Mac):" >&2
  sed "s|^|  $0 '|; s|\$|'|" <<<"$identities" >&2
  exit 1
else
  name="$identities"
fi
team="$(security find-certificate -c "$name" -p "$keychain" | /usr/bin/openssl x509 -noout -subject |
  sed -nE 's#.*/OU=([A-Z0-9]{10})(/.*)?$#\1#p')"
if [ -z "$team" ]; then
  echo "error: \"$name\" has no Apple Team ID" >&2
  exit 1
fi
mkdir -p "$(dirname -- "$config")"
printf '%s\n' "$name" >"$config"
echo "Packaging on this Mac now signs with \"$name\" (team $team)."
echo "The first build signed with it asks once for \"Parc Safe Storage\": choose Always Allow."
