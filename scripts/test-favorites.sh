#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/parc-favorites.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -parse-as-library Sources/ParcCore/*.swift Sources/ParcApp/SidebarItemDrag.swift Sources/ParcApp/FavoriteTileLayout.swift Sources/ParcApp/FavoriteTile.swift Sources/ParcApp/FavoriteTileOverlays.swift tests/Favorites/MoveOwnerStub.swift tests/Support/AppKitObservation.swift tests/Favorites/FavoriteTileTests.swift -o "$check_dir/favorites"
"$check_dir/favorites"

xcrun swiftc -parse-as-library Sources/ParcCore/*.swift Sources/ParcApp/SidebarItemDrag.swift Sources/ParcApp/FavoriteTileLayout.swift Sources/ParcApp/FavoriteTile.swift Sources/ParcApp/FavoriteTileOverlays.swift tests/Favorites/MoveOwnerStub.swift tests/Favorites/FavoritePointerTests.swift -o "$check_dir/pointer"
"$check_dir/pointer"

xcrun swiftc -parse-as-library Sources/ParcCore/*.swift tests/Favorites/FavoriteSplitTests.swift -o "$check_dir/favorite-split-tests"
"$check_dir/favorite-split-tests"

xcrun swiftc -parse-as-library Sources/ParcCore/*.swift tests/Favorites/SavedTabResetEligibilityTests.swift -o "$check_dir/saved-reset-tests"
"$check_dir/saved-reset-tests"

xcrun swiftc -parse-as-library Sources/ParcCore/*.swift tests/Favorites/SavedTabResetTargetsTests.swift -o "$check_dir/reset-targets-tests"
"$check_dir/reset-targets-tests"

xcrun swiftc -parse-as-library Sources/ParcCore/*.swift Sources/ParcApp/FavoriteTileLayout.swift tests/Favorites/FavoriteTileLayoutTests.swift -o "$check_dir/tile-layout"
"$check_dir/tile-layout"

xcrun swiftc -parse-as-library Sources/ParcCore/*.swift Sources/ParcApp/SidebarItemDrag.swift Sources/ParcApp/FavoriteTileLayout.swift Sources/ParcApp/FavoriteTile.swift Sources/ParcApp/FavoriteTileOverlays.swift tests/Favorites/MoveOwnerStub.swift tests/Support/AppKitObservation.swift tests/Favorites/FavoriteTileOverlayTests.swift -o "$check_dir/tile-overlays"
"$check_dir/tile-overlays"
