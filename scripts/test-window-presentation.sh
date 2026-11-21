#!/bin/bash
set -euo pipefail

if (( $# > 2 )); then
  echo "Usage: $0 [source-root [support-root]]" >&2
  exit 2
fi
script_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source_root="${1:-$script_root}"
support_root="${2:-$source_root}"
build_root="${PARC_TEST_BUILD_DIR:-$source_root/build/tests}"

source_path() {
  local relative="$1"
  if [[ -f "$source_root/$relative" ]]; then
    printf '%s\n' "$source_root/$relative"
  elif [[ -f "$support_root/$relative" ]]; then
    printf '%s\n' "$support_root/$relative"
  else
    echo "Missing test source: $relative" >&2
    return 1
  fi
}

store_source="$(source_path Sources/ParcCore/BrowserStore.swift)"
tab_lookup_source="$(source_path Sources/ParcCore/BrowserTabLookup.swift)"
space_sharing_source="$(source_path Sources/ParcCore/SpaceSharing.swift)"
window_frame_source="$(source_path Sources/ParcCore/WindowFrame.swift)"
saved_window_frame_source="$(source_path Sources/ParcCore/SavedWindowFrame.swift)"
space_management_source="$(source_path Sources/ParcCore/SpaceManagement.swift)"
import_source="$(source_path Sources/ParcCore/BrowserImport.swift)"
arc_sidebar_import_source="$(source_path Sources/ParcCore/ArcSidebarImport.swift)"
favorite_split_source="$(source_path Sources/ParcCore/FavoriteSplit.swift)"
original_split_source="$(source_path Sources/ParcCore/OriginalSplitDrop.swift)"
inter_profile_source="$(source_path Sources/ParcCore/InterProfileMove.swift)"
space_move_source="$(source_path Sources/ParcCore/SidebarSpaceMove.swift)"
window_move_source="$(source_path Sources/ParcCore/SidebarWindowMove.swift)"
closed_items_source="$(source_path Sources/ParcCore/ClosedItems.swift)"
placeholder_images_source="$(source_path Sources/ParcCore/PagePlaceholderImages.swift)"
favorite_action_source="$(source_path Sources/ParcCore/CommandBarFavoriteAction.swift)"
folder_move_source="$(source_path Sources/ParcCore/CommandBarFolderMove.swift)"
folder_action_source="$(source_path Sources/ParcCore/CommandBarFolderAction.swift)"
theme_source="$(source_path Sources/ParcCore/SpaceTheme.swift)"
onboarding_source="$(source_path Sources/ParcCore/OnboardingDraft.swift)"
routing_source="$(source_path Sources/ParcCore/LinkRouting.swift)"
pretty_json_source="$(source_path Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift)"
removal_source="$(source_path Sources/ParcCore/ProfileRemoval.swift)"
split_controls_source="$(source_path Sources/ParcCore/SplitPaneControls.swift)"
split_cross_space_source="$(source_path Sources/ParcCore/SplitCrossSpaceAdd.swift)"
folder_creation_source="$(source_path Sources/ParcCore/SidebarFolderFromItems.swift)"
tab_history_source="$(source_path Sources/ParcCore/TabHistoryArchive.swift)"
session_backups_source="$(source_path Sources/ParcCore/SessionBackups.swift)"
note_source="$(source_path Sources/ParcCore/NoteFileKind.swift)"
note_paths_source="$(source_path Sources/ParcCore/NoteFilePaths.swift)"
note_visit_source="$(source_path Sources/ParcCore/TabNoteVisit.swift)"
easel_source="$(source_path Sources/ParcCore/EaselStore.swift)"
easel_text_source="$(source_path Sources/ParcCore/EaselRichText.swift)"
easel_table_source="$(source_path Sources/ParcCore/EaselTable.swift)"
presentation_source="$(source_path Sources/ParcCore/WindowPresentation.swift)"
restoration_launch_source="$(source_path Sources/ParcCore/WindowRestorationLaunch.swift)"
test_source="$(source_path tests/WindowPresentationTests.swift)"
failure_source="$(source_path tests/Support/TestFailure.swift)"
mkdir -p -- "$build_root"
xcrun swiftc "$failure_source" -warnings-as-errors -whole-module-optimization -parse-as-library \
  "$saved_window_frame_source" \
  "$store_source" "$tab_lookup_source" "$space_sharing_source" "$window_frame_source" "$space_management_source" "$import_source" "$arc_sidebar_import_source" "$favorite_split_source" "$original_split_source" "$inter_profile_source" "$space_move_source" "$window_move_source" "$closed_items_source" "$placeholder_images_source" "$favorite_action_source" "$folder_move_source" "$folder_action_source" "$theme_source" "$onboarding_source" "$routing_source" "$pretty_json_source" "$removal_source" "$split_controls_source" "$split_cross_space_source" "$folder_creation_source" "$tab_history_source" "$session_backups_source" "$note_source" "$note_paths_source" "$note_visit_source" "$easel_source" "$easel_text_source" "$easel_table_source" "$presentation_source" "$restoration_launch_source" "$test_source" \
  -o "$build_root/window-presentation"
exec "$build_root/window-presentation"
