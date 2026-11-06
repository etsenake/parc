#!/bin/bash
# Packages the app from this clean, pushed checkout and publishes it as a
# private GitHub pre-release, so another Mac can run it without building.
# Either seal a local engine build, or (--from-release) reuse the engine of a
# published standalone package when Engine/ hasn't changed since it was built.
# --local-test packages for this Mac only, against the newest published engine
# even if Engine/ moved on, as long as the app's engine headers didn't (or, with
# PARC_ALLOW_CHANGED_ENGINE_HEADERS=1, their new calls are guarded with
# respondsToSelector:); it is labelled and never published. See
# tests/Packaging/README.md.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
github_repo="etsenake/parc"
keep=3
tag_pattern='^app-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$'
stable_tag_pattern='^v[0-9]+[.][0-9]+[.][0-9]+$'
# An inherited GH_TOKEN may be stale, and gh can fail to read its keyring login
# on its own; pass the keyring token explicitly.
gh_token="$(env -u GH_TOKEN -u GITHUB_TOKEN gh auth token 2>/dev/null || true)"
gh() { GH_TOKEN="$gh_token" GITHUB_TOKEN= command gh "$@"; }

usage() {
  echo "usage: $0 [--stable] <sealed engine-artifacts.json>" >&2
  echo "       $0 [--stable] --from-release [app-<stamp>-<commit> or v<version> tag]" >&2
  echo "       $0 --local-test [app-<stamp>-<commit> tag]" >&2
  exit 2
}
from_release=""
local_test=""
release_tag=""
stable=""
if [ "${1:-}" = --stable ]; then stable=1; shift; fi
case "${1:-}" in
  --from-release|--local-test)
    [ $# -le 2 ] || usage
    from_release=1
    if [ "$1" = --local-test ]; then local_test=1; fi
    release_tag="${2:-}"
    ;;
  ""|-*) usage ;;
  *)
    [ $# -eq 1 ] || usage
    manifest="$(cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")"
    engine="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["engine_dir"])' "$manifest")"
    ;;
esac
if [ -n "$stable" ] && [ -n "$local_test" ]; then usage; fi

cd "$repo_root"
started=$SECONDS
# build.py reads these paths whether or not Git tracks the files.
inputs=(Sources Resources Engine scripts app-version.json)
check_checkout() {
  if [ "$(git rev-parse HEAD)" != "$commit" ] || [ -n "$(git status --porcelain --untracked-files=all -- "${inputs[@]}")" ]; then
    echo "error: the checkout must stay clean at $commit while packaging" >&2
    exit 1
  fi
}
git fetch -q origin
commit="$(git rev-parse HEAD)"
check_checkout
if ! git merge-base --is-ancestor "$commit" origin/main; then
  echo "error: $commit is not on origin/main" >&2
  exit 1
fi
app_version="$(python3 scripts/app_version.py show)"
stable_tag="v$app_version"
if [ -n "$stable" ]; then
  stable_ref="$(git ls-remote --tags origin "refs/tags/$stable_tag")"
  if [ -n "$stable_ref" ]; then
    echo "error: $stable_tag already exists; advance app-version.json before another stable release" >&2
    exit 1
  fi
fi
# build.py copies Resources wholesale, so ignored files there would ship too.
find Resources -name .DS_Store -delete
if [ -n "$(git status --porcelain --ignored=matching --untracked-files=all -- Resources)" ]; then
  echo "error: Resources has ignored files that would be packaged:" >&2
  git status --porcelain --ignored=matching --untracked-files=all -- Resources >&2
  exit 1
fi
overlay="$(python3 -c 'import json; print(json.load(open("Engine/ParcHost/overlay.json"))["version"])')"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
short="${commit:0:8}"
run="$repo_root/build/local-${local_test:+test-}$stamp"
mkdir -p "$repo_root/build"
mkdir "$run"

# An Apple-issued identity's Team ID keeps macOS's Keychain and privacy grants
# across builds; ad-hoc signatures change with every build. scripts/setup-signing.sh
# records the identity once per Mac.
sign_name="${PARC_SIGN_IDENTITY:-}"
if [ -z "$sign_name" ] && [ -s "$HOME/.config/parc/signing-identity" ]; then
  sign_name="$(head -n 1 "$HOME/.config/parc/signing-identity")"
fi
sign_team=""
if [ -z "$local_test" ]; then
  case "$sign_name" in
    'Developer ID Application: '*) ;;
    *)
      echo "error: published app builds require a Developer ID Application identity; run bash scripts/setup-signing.sh first" >&2
      exit 1
      ;;
  esac
fi
sign_identity=""
if [ -n "$sign_name" ]; then
  sign_identity="$(security find-identity -v -p codesigning 2>/dev/null |
    awk -v name="\"$sign_name\"" '{ hash = $2; $1 = ""; $2 = ""; sub(/^  /, ""); if ($0 == name) { print hash; exit } }')"
  if [ -z "$sign_identity" ]; then
    echo "error: \"$sign_name\" isn't a valid code-signing identity here; rerun bash scripts/setup-signing.sh" >&2
    exit 1
  fi
  signed_with="$sign_name"
  if [ -z "$local_test" ]; then
    sign_team="$(security find-certificate -c "$sign_name" -p |
      /usr/bin/openssl x509 -noout -subject |
      sed -nE 's#.*/OU=([A-Z0-9]{10})(/.*)?$#\1#p')"
    if [ -z "$sign_team" ]; then
      echo "error: published app builds require an Apple Team ID; rerun bash scripts/setup-signing.sh" >&2
      exit 1
    fi
  fi
else
  sign_identity="-"
  signed_with="ad-hoc"
  echo "note: signing ad-hoc, so macOS asks for Parc Safe Storage again; see bash scripts/setup-signing.sh" >&2
fi
# Production publication requires Apple's Developer ID and notarization checks.
# Validate the stored credentials before compiling.
notary_profile=""
if [ -z "$local_test" ] && [[ "$sign_name" == 'Developer ID Application: '* ]]; then
  notary_profile="${PARC_NOTARY_PROFILE:-parc-notary}"
  if ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
    echo "error: Developer ID builds are notarized before publishing; store this Mac's credentials once with" >&2
    echo "  xcrun notarytool store-credentials $notary_profile --apple-id <Apple ID> --team-id $sign_team" >&2
    exit 1
  fi
fi

if [ -n "$from_release" ]; then
  if [ -z "$release_tag" ]; then
    # A local test takes the newest engine; a published build needs HEAD's overlay.
    wanted="engine overlay $overlay)"
    if [ -n "$local_test" ]; then wanted="engine overlay "; fi
    release_tag="$(gh release list -R "$github_repo" --limit 200 --json tagName,name,createdAt,isDraft,isPrerelease \
      --jq "[.[] | select((((.tagName | test(\"$tag_pattern\")) and .isPrerelease) or ((.tagName | test(\"$stable_tag_pattern\")) and (.isPrerelease | not))) and (.isDraft | not) and (.name | contains(\"$wanted\")))] | sort_by(.createdAt) | reverse | .[0].tagName // empty" </dev/null)"
    if [ -z "$release_tag" ] && [ -n "$local_test" ]; then
      echo "error: no published app package to take an engine from" >&2
      exit 1
    elif [ -z "$release_tag" ]; then
      echo "error: no published app package has engine overlay $overlay; build the engine instead" >&2
      exit 1
    fi
  elif ! [[ "$release_tag" =~ $tag_pattern ]] && ! [[ "$release_tag" =~ $stable_tag_pattern ]]; then
    echo "error: $release_tag is not an app package tag" >&2
    exit 1
  fi
  release_json="$(gh release view "$release_tag" -R "$github_repo" --json targetCommitish,assets </dev/null)"
  release_commit="$(jq -r .targetCommitish <<<"$release_json")"
  asset="$(jq -r '[.assets[] | select(.name | endswith(".zip"))] | if length == 1 then .[0].name else empty end' <<<"$release_json")"
  digest="$(jq -r --arg name "$asset" '.assets[] | select(.name == $name) | .digest // empty' <<<"$release_json")"
  if ! [[ "$release_commit" =~ ^[0-9a-f]{40}$ ]] || [ -z "$asset" ] || ! [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "error: $release_tag lacks a commit, a single zip or its digest" >&2
    exit 1
  fi
  if ! git cat-file -e "$release_commit^{commit}" 2>/dev/null; then
    echo "error: $release_tag was built from $release_commit, which this checkout doesn't have" >&2
    exit 1
  fi
  if [ -n "$local_test" ]; then
    if ! git diff --quiet "$release_commit" "$commit" -- Engine/source-lock.json; then
      echo "error: the source lock changed since $release_tag; a local test needs the same CEF" >&2
      exit 1
    fi
  elif ! git diff --quiet "$release_commit" "$commit" -- Engine; then
    echo "error: Engine/ changed since $release_tag ($release_commit); build the engine instead" >&2
    exit 1
  fi
  # The pinned CEF/Chromium inputs come from an engine workspace's Git objects.
  workspace="${PARC_ENGINE_WORKSPACE:-}"
  if [ -z "$workspace" ]; then
    main_root="$(dirname -- "$(git rev-parse --path-format=absolute --git-common-dir)")"
    for candidate in "$main_root/work/engine" "$HOME/Documents/Codex/2026-10-23/re/work/engine-source"; do
      if [ -d "$candidate/chromium/src/cef" ]; then workspace="$candidate"; break; fi
    done
  fi
  if [ -z "$workspace" ]; then
    echo "error: no engine workspace found; set PARC_ENGINE_WORKSPACE" >&2
    exit 1
  fi
  cache="$repo_root/build/release-cache/$release_tag"
  zip="$cache/$asset"
  if [ ! -f "$zip" ] || [ "sha256:$(shasum -a 256 "$zip" | cut -d' ' -f1)" != "$digest" ]; then
    # Keep only the engine package in use.
    rm -rf -- "$repo_root/build/release-cache"
    mkdir -p "$cache"
    gh release download "$release_tag" -R "$github_repo" -p "$asset" -D "$cache" </dev/null
  fi
  if [ "sha256:$(shasum -a 256 "$zip" | cut -d' ' -f1)" != "$digest" ]; then
    echo "error: $asset does not match its published digest" >&2
    exit 1
  fi
  trap 'rm -rf -- "$run/engine-release"' EXIT
  ditto -x -k "$zip" "$run/engine-release"
  echo "reusing the engine of $release_tag ($release_commit)"
  build_args=(release-build --release-package "$run/engine-release/development" --release-tag "$release_tag"
    --release-commit "$release_commit" --engine-workspace "$workspace" ${local_test:+--local-test})
  if [ -n "$local_test" ] && [ "${PARC_ALLOW_CHANGED_ENGINE_HEADERS:-}" = 1 ]; then
    build_args+=(--allow-changed-headers)
  fi
  description="Standalone package built from $commit on engine overlay $overlay, reusing the engine of $release_tag; signed $signed_with."
else
  cp "$manifest" "$run/engine-artifacts.json"
  build_args=(build --engine-dir "$engine" --manifest "$run/engine-artifacts.json")
  description="Package built from $commit on engine overlay $overlay; signed $signed_with."
fi

# build.py writes its own package.log in the run directory.
purpose=distribution
if [ -n "$local_test" ]; then purpose=development; fi
if ! python3 scripts/build.py "${build_args[@]}" --output "$run/development" --configuration release --purpose "$purpose" \
  --sign-identity "$sign_identity" >"$run/package-output.log" 2>&1; then
  echo "error: packaging failed; see $run/package.log and $run/package-output.log" >&2
  exit 1
fi
check_checkout
if [ -z "$local_test" ]; then
  python3 - "$run/development/package-report.json" "$sign_team" <<'PY'
import json
import sys

with open(sys.argv[1]) as stream:
    report = json.load(stream)
if report.get("signing_team") != sys.argv[2] or report.get("signing_identity") in (None, "", "-"):
    raise SystemExit("error: package signing identity/Team ID differs from the selected Apple identity; refusing publication")
PY
fi
if [ -n "$notary_profile" ]; then
  python3 scripts/notarize-app.py "$run/development" --profile "$notary_profile" --team "$sign_team"
  python3 - "$run/development/package-report.json" "$sign_team" <<'PY'
import json
import sys

with open(sys.argv[1]) as stream:
    report = json.load(stream)
notary = report.get("notarization", {})
if (report.get("notarized") is not True or notary.get("status") != "Accepted"
        or notary.get("team") != sys.argv[2] or notary.get("stapled") is not True
        or notary.get("gatekeeper_verified") is not True):
    raise SystemExit("error: missing verified Apple notarization; refusing publication")
PY
  check_checkout
  description="$description Notarized by Apple with a stapled ticket."
fi
echo "packaged $run/development/Parc.app"
if [ -n "$local_test" ]; then
  echo "LOCAL TEST BUILD, not published: app $short on the engine of $release_tag, in $(( (SECONDS - started) / 60 ))m$(( (SECONDS - started) % 60 ))s"
  exit 0
fi

tag="app-$stamp-$short"
archive="$run/Parc-$stamp-$short.zip"
release_options=(--prerelease)
title="Parc app $stamp ($short, engine overlay $overlay)"
if [ -n "$stable" ]; then
  tag="$stable_tag"
  archive="$run/Parc-$app_version-arm64.zip"
  release_options=(--prerelease --latest=false)
  title="Parc $app_version candidate (engine overlay $overlay)"
fi
trap 'rm -rf -- "$archive" "$run/engine-release"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$run/development" "$archive"
assets=("$archive")
if [ -n "$stable" ]; then
  dmg="$run/Parc-$app_version-arm64.dmg"
  python3 scripts/package-dmg.py "$run/development" --output "$dmg" \
    --sign-identity "$sign_identity" --profile "$notary_profile" --team "$sign_team"
  check_checkout
  assets+=("$dmg")
fi
gh release create "$tag" "${assets[@]}" -R "$github_repo" "${release_options[@]}" --target "$commit" \
  --title "$title" \
  --notes "$description Install: tests/Packaging/README.md, \"Publishing app builds\"."
echo "published $tag in $(( (SECONDS - started) / 60 ))m$(( (SECONDS - started) % 60 ))s"

gh release list -R "$github_repo" --limit 200 --json tagName,createdAt,isDraft,isPrerelease \
  --jq "[.[] | select((.tagName | test(\"$tag_pattern\")) and .isPrerelease and (.isDraft | not))] | sort_by(.createdAt) | reverse | .[$keep:] | .[].tagName" </dev/null |
  while IFS= read -r old; do
    gh release delete "$old" -R "$github_repo" --yes --cleanup-tag </dev/null || echo "warning: could not delete $old" >&2
  done || echo "warning: pruning old app releases failed" >&2
