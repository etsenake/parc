#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
export PATH="$repo_root/tests/Support/compilers:$PATH"
mkdir -p "$repo_root/build/tests"
jobs_limit="${PARC_TEST_JOBS:-$(sysctl -n hw.ncpu)}"
steps_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-test-steps.XXXXXX")"
trap 'kill $(jobs -pr) 2>/dev/null || true; rm -rf "$steps_dir"' EXIT
began=$SECONDS
step_count=0
step() {
  while [ "$(jobs -pr | wc -l)" -ge "$jobs_limit" ]; do sleep 0.05; done
  step_count=$((step_count + 1))
  local id
  id=$(printf '%03d' "$step_count")
  printf '%s\n' "$*" | sed "s|$repo_root/||g" > "$steps_dir/$id.name"
  (
    set +e
    started=$SECONDS
    ( set -e; "$@" ) > "$steps_dir/$id.log" 2>&1
    code=$?
    if [ "$code" -eq 0 ]; then result=ok; else result=failed; fi
    echo "$result $((SECONDS - started))" > "$steps_dir/$id.status"
  ) &
}
swift_test() {
  local executable="$repo_root/build/tests/$1"
  shift
  xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" "$@" -o "$executable"
  "$executable"
}
core_sources=(
  "$repo_root/Sources/ParcCore/BrowserStore.swift"
  "$repo_root/Sources/ParcCore/BrowserTabLookup.swift"
  "$repo_root/Sources/ParcCore/SpaceSharing.swift"
  "$repo_root/Sources/ParcCore/SpaceManagement.swift"
  "$repo_root/Sources/ParcCore/BrowserImport.swift"
  "$repo_root/Sources/ParcCore/ArcSidebarImport.swift"
  "$repo_root/Sources/ParcCore/FavoriteSplit.swift"
  "$repo_root/Sources/ParcCore/OriginalSplitDrop.swift"
  "$repo_root/Sources/ParcCore/InterProfileMove.swift"
  "$repo_root/Sources/ParcCore/SidebarSpaceMove.swift" "$repo_root/Sources/ParcCore/SidebarWindowMove.swift"
  "$repo_root/Sources/ParcCore/CommandBarFavoriteAction.swift"
  "$repo_root/Sources/ParcCore/CommandBarFolderMove.swift"
  "$repo_root/Sources/ParcCore/CommandBarFolderAction.swift"
  "$repo_root/Sources/ParcCore/ClosedItems.swift"
  "$repo_root/Sources/ParcCore/PagePlaceholderImages.swift"
  "$repo_root/Sources/ParcCore/SpaceTheme.swift"
  "$repo_root/Sources/ParcCore/OnboardingDraft.swift"
  "$repo_root/Sources/ParcCore/WindowFrame.swift"
  "$repo_root/Sources/ParcCore/SavedWindowFrame.swift"
  "$repo_root/Sources/ParcCore/LinkRouting.swift"
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift"
  "$repo_root/Sources/ParcCore/ProfileRemoval.swift"
  "$repo_root/Sources/ParcCore/SplitPaneControls.swift"
  "$repo_root/Sources/ParcCore/SplitCrossSpaceAdd.swift"
  "$repo_root/Sources/ParcCore/SidebarFolderFromItems.swift"
  "$repo_root/Sources/ParcCore/TabHistoryArchive.swift"
  "$repo_root/Sources/ParcCore/SessionBackups.swift"
  "$repo_root/Sources/ParcCore/NoteFileKind.swift"
  "$repo_root/Sources/ParcCore/NoteFilePaths.swift"
  "$repo_root/Sources/ParcCore/TabNoteVisit.swift"
)
mkdir -p "$repo_root/build/tests/tooltip"
tooltip_sources=()
while IFS= read -r path; do tooltip_sources+=("$path"); done < <(python3 "$repo_root/tests/Tooltip/support.py" "$repo_root/build/tests/tooltip" SpaceTheme.swift)
compile_and_run() {
  local executable="$repo_root/build/tests/$1"
  local test_source="$repo_root/tests/$2.swift"
  shift 2
  xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library "${core_sources[@]}" "$test_source" "$@" -o "$executable"
  "$executable"
}
step compile_and_run favorite-moves FavoriteMoveTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift" \
  "$repo_root/Sources/ParcCore/TabCommandNavigation.swift" \
  "$repo_root/Sources/ParcCore/SidebarKeyboardNavigation.swift" \
  "$repo_root/Sources/ParcCore/RecentTabOrder.swift"
step compile_and_run browser-store BrowserStoreTests \
  "$repo_root/Sources/ParcCore/FolderLinks.swift" "$repo_root/tests/Support/FileObservation.swift" \
  "$repo_root/Sources/ParcCore/CommandBarCommandPresentation.swift"
step compile_and_run session-backups SessionBackupTests "$repo_root/Sources/ParcApp/SidebarRescue.swift"
step compile_and_run whats-new-page WhatsNewPageTests
step compile_and_run history-spotlight HistorySpotlightTests "$repo_root/Sources/ParcCore/HistorySpotlight.swift"
step compile_and_run link-routing-store LinkRoutingStoreTests
step bash "$repo_root/scripts/test-link-routing-fallback.sh"
step compile_and_run link-routing-editor LinkRoutingEditorTests

step swift_test settings-pretty-json-persist-skip -parse-as-library \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/tests/SettingsPrettyJSONPersistSkipTests.swift"
step python3 "$repo_root/tests/SettingsPrettyJSONPersistSkip/check.py"
step python3 "$repo_root/tests/PointingHand/check.py"
step python3 "$repo_root/tests/ErrorPages/check.py"

step swift_test native-messaging-hosts -parse-as-library \
  "$repo_root/Sources/ParcCore/NativeMessagingHosts.swift" \
  "$repo_root/tests/NativeMessagingHostsTests.swift"
step bash "$repo_root/scripts/test-shortcut-persist-skip.sh"
step bash "$repo_root/scripts/test-split-link-snapshot.sh"
step bash "$repo_root/scripts/test-fairplay-identity.sh"
step bash "$repo_root/tests/DebuggerWarning/run.sh"
step bash "$repo_root/scripts/test-site-permission-rows.sh"
step compile_and_run automatic-archive-presentation AutoArchivePresentationTests
step compile_and_run automatic-archive-education-view AutoArchiveEducationViewTests \
  "$repo_root/Sources/ParcApp/ThemeRenderer.swift" \
  "$repo_root/Sources/ParcApp/AutoArchiveEducationView.swift" "$repo_root/Sources/ParcApp/PointingHand.swift"
step compile_and_run update-complete-card UpdateCompleteCardTests \
  "$repo_root/Sources/ParcApp/ThemeRenderer.swift" \
  "$repo_root/Sources/ParcApp/UpdateCompleteCard.swift"
step compile_and_run update-ready-card UpdateReadyCardTests \
  "$repo_root/Sources/ParcApp/ThemeRenderer.swift" \
  "$repo_root/Sources/ParcApp/UpdateCompleteCard.swift" "$repo_root/Sources/ParcApp/UpdateReadyCard.swift"
step compile_and_run tab-creation-provenance TabCreationProvenanceTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"
step compile_and_run recent-tab-switcher RecentTabSwitcherTests \
  "$repo_root/Sources/ParcCore/RecentTabOrder.swift"
step compile_and_run same-container-focus SameContainerFocusTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"
step compile_and_run peek-referrer-pool PeekReferrerPoolTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"
step compile_and_run folder-undo-manager FolderUndoManagerTests \
  "$repo_root/Sources/ParcApp/FolderUndoManager.swift"
step compile_and_run folder-document-close FolderDocumentCloseTests \
  "$repo_root/Sources/ParcApp/FolderUndoManager.swift" \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/NoteFileKind.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift"
step compile_and_run profile-removal ProfileRemovalTests
step compile_and_run profile-removal-controller ProfileRemovalControllerTests \
  "$repo_root/Sources/ParcApp/ProfileRemovalController.swift" \
  "$repo_root/tests/ProfileRemovalTestSupport.swift"

step compile_and_run sidebar-plural-duplicate SidebarPluralDuplicateTests \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/NoteFileKind.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift"
step compile_and_run sidebar-split-copy SidebarSplitCopyTests
step compile_and_run duplicate-undo DuplicateUndoTests \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/NoteFileKind.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcApp/FolderUndoManager.swift" \
  "$repo_root/Sources/ParcApp/DuplicateUndo.swift"

step compile_and_run sidebar-plural-removal SidebarPluralRemovalTests \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/NoteFileKind.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcApp/FolderUndoManager.swift"

step compile_and_run archived-folder-paths ArchivedFolderPathTests
step python3 "$repo_root/tests/FolderDeletion/check.py"

step compile_and_run closed-items ClosedItemsTests \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/NoteFileKind.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"
step compile_and_run split-stacks SplitStacksTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"
step compile_and_run split-stack-layout SplitStackLayoutTests \
  "$repo_root/Sources/ParcCore/SplitStackLayout.swift" \
  "$repo_root/Sources/ParcCore/SplitPaneResize.swift" \
  "$repo_root/Sources/ParcCore/RecentTabOrder.swift"
step compile_and_run split-stack-commands SplitStackCommandsTests
step compile_and_run split-drop-intent SplitDropIntentTests "$repo_root/Sources/ParcCore/SplitDropIntent.swift"
step python3 "$repo_root/tests/SidebarRows/split_stack_commands_check.py"
step bash "$repo_root/scripts/test-close-undo.sh"
step bash "$repo_root/scripts/test-tab-history.sh"
step bash "$repo_root/scripts/test-handoff-activity.sh"
step bash "$repo_root/scripts/test-page-placeholder.sh"
step bash "$repo_root/scripts/test-page-placeholder-images.sh"
step compile_and_run browser-data-export BrowserDataExportTests \
  "$repo_root/Sources/ParcCore/BrowserDataExport.swift"
step compile_and_run command-bar-scope-menu CommandBar/ScopeMenuTests \
  "$repo_root/Sources/ParcApp/CommandBarScopeEditing.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

spinner=$(python3 -B "$repo_root/tests/Support/declarations.py" "$repo_root/build/tests/command-bar-privacy-spinner.swift" ParcButtonSpinner)
step compile_and_run command-bar-privacy CommandBar/SearchPrivacyBannerTests \
  "$repo_root/Sources/ParcApp/CommandBarSearchPrivacyBanner.swift" \
  "$repo_root/Sources/ParcApp/SidebarTablistBackground.swift" \
  "$repo_root/Sources/ParcApp/ParcDialog.swift" "$spinner" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

step compile_and_run command-bar-background CommandBar/BackgroundOpenTests \
  "$repo_root/Sources/ParcApp/CommandBarSubmission.swift" \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"

step compile_and_run command-bar-result-navigation CommandBar/ResultNavigationTests \
  "$repo_root/Sources/ParcApp/CommandResultsTable.swift" \
  "$repo_root/Sources/ParcApp/CommandBarEditState.swift"

step compile_and_run command-bar-row-diff CommandBar/RowDiffTests \
  "$repo_root/Sources/ParcApp/CommandBarRowDiff.swift"
step compile_and_run command-bar-native-hold CommandBar/NativeHoldTests \
  "$repo_root/Sources/ParcApp/CommandBarNativeHold.swift"
step compile_and_run command-bar-ranking CommandBar/RankingTests \
  "$repo_root/Sources/ParcApp/CommandBarRanking.swift" "$repo_root/Sources/ParcApp/CommandBarRowDiff.swift"
step bash "$repo_root/scripts/test-command-bar-site-search.sh"
step bash "$repo_root/scripts/test-command-bar-navigation.sh"
step compile_and_run command-bar-title-search CommandBar/TitleSearchTests \
  "$repo_root/Sources/ParcApp/CommandBarTitleSearch.swift" "$repo_root/Sources/ParcApp/CommandBarRanking.swift" \
  "$repo_root/Sources/ParcApp/CommandBarRowDiff.swift" "$repo_root/Sources/ParcCore/CommandBarResultText.swift"
step compile_and_run command-bar-command-ranking CommandBar/CommandRankingTests \
  "$repo_root/Sources/ParcApp/CommandBarRanking.swift" "$repo_root/Sources/ParcApp/CommandBarRowDiff.swift" \
  "$repo_root/Sources/ParcApp/CommandBarCommandCandidate.swift" \
  "$repo_root/Sources/ParcCore/CommandBarTypedCommand.swift" "$repo_root/Sources/ParcCore/CommandBarMenuItemInfo.swift" \
  "$repo_root/Sources/ParcCore/CommandBarCommandPresentation.swift"

step compile_and_run command-bar-pointer CommandBar/PointerSelectionTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultsTable.swift" \
  "$repo_root/Sources/ParcApp/CommandResultRowView.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

step compile_and_run command-bar-appearance CommandBar/AppearanceTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultsTable.swift" \
  "$repo_root/Sources/ParcApp/CommandResultRowView.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" \
  "$repo_root/Sources/ParcApp/PopoverBackgroundView.swift" "${tooltip_sources[@]}"

step compile_and_run command-bar-site-color CommandBar/SiteColorTests \
  "$repo_root/Sources/ParcApp/CommandBarSiteColor.swift" \
  "$repo_root/Sources/ParcApp/CommandBarScopeEditing.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

step compile_and_run command-bar-result-text CommandBar/ResultTextTests \
  "$repo_root/Sources/ParcCore/CommandBarResultText.swift" \
  "$repo_root/Sources/ParcCore/CommandBarCommandPresentation.swift"

step compile_and_run command-bar-result-row CommandBar/ResultRowTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"
step compile_and_run command-bar-field-anchor CommandBar/FieldAnchorTests \
  "$repo_root/Sources/ParcApp/CommandBarFieldAnchor.swift" \
  "$repo_root/Sources/ParcApp/CommandBarCompletionField.swift" \
  "$repo_root/Sources/ParcApp/CommandBarEditState.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"
step compile_and_run command-bar-compact-layout CommandBar/CompactLayoutTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandBarCompactLayout.swift" \
  "$repo_root/Sources/ParcApp/CommandResultsTable.swift" \
  "$repo_root/Sources/ParcApp/SidebarAddressPill.swift" \
  "$repo_root/Sources/ParcApp/SidebarAddressText.swift" \
  "$repo_root/Sources/ParcApp/SidebarChromeLayout.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

step compile_and_run command-bar-folder-copy CommandBar/FolderCopyTests
step compile_and_run command-bar-document-alias CommandBar/DocumentAliasTests \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/NoteFileKind.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift"

step compile_and_run command-bar-folder-move CommandBar/FolderMoveTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

step compile_and_run command-bar-favorites CommandBar/FavoriteActionTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

step compile_and_run command-bar-spaces CommandBar/SpaceActionTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

step compile_and_run command-bar-typed-commands CommandBar/TypedCommandTests \
  "$repo_root/Sources/ParcCore/CommandBarTypedCommand.swift" \
  "$repo_root/Sources/ParcCore/CommandBarMenuItemInfo.swift" \
  "$repo_root/Sources/ParcCore/CommandBarCommandPresentation.swift"
step swift_test command-bar-task-manager -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/TaskManagerCommand.swift" "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" "$repo_root/tests/CommandBar/TaskManagerTests.swift"
step python3 "$repo_root/tests/CommandBar/task_manager_check.py"

step compile_and_run command-bar-reconcile-inputs CommandBar/ReconcileInputsTests \
  "$repo_root/Sources/ParcCore/CommandBarReconcileInputs.swift"

step compile_and_run command-bar-open-results-skip CommandBar/OpenResultsSkipTests \
  "$repo_root/Sources/ParcCore/CommandBarOpenResultsSkip.swift"

step compile_and_run command-bar-history-scan-skip CommandBar/HistoryScanSkipTests \
  "$repo_root/Sources/ParcCore/CommandBarHistoryScanSkip.swift"

step compile_and_run find-reconcile-skip KeyboardNavigation/FindReconcileSkipTests \
  "$repo_root/Sources/ParcCore/FindReconcileSkip.swift"

step compile_and_run shortcut-tooltip-discovery-skip ShortcutTooltipDiscoverySkipTests \
  "$repo_root/Sources/ParcCore/ShortcutTooltipDiscoverySkip.swift"
step python3 "$repo_root/tests/ShortcutTooltipDiscoverySkip/check.py"

step compile_and_run peek-presentation-skip PeekPresentationSkipTests \
  "$repo_root/Sources/ParcCore/PeekPresentationSkip.swift"
step python3 "$repo_root/tests/PeekPresentationSkip/check.py"
step python3 "$repo_root/tests/PeekWindowHost/check.py"
step python3 "$repo_root/tests/ArchivePreviewHost/check.py"

step compile_and_run split-layout-flush-skip SplitLayoutFlushSkipTests \
  "$repo_root/Sources/ParcCore/SplitLayoutFlushSkip.swift"
step python3 "$repo_root/tests/SplitLayoutFlushSkip/check.py"
step compile_and_run page-switch-hold PageSwitchHoldTests \
  "$repo_root/Sources/ParcApp/PageSwitchHold.swift"
step compile_and_run sidebar-outline-layout-flush-skip SidebarOutlineLayoutFlushSkipTests \
  "$repo_root/Sources/ParcCore/SidebarOutlineLayoutFlushSkip.swift"
step python3 "$repo_root/tests/SidebarOutlineLayoutFlushSkip/check.py"
step compile_and_run sidebar-outline-configure-skip SidebarOutlineConfigureSkipTests \
  "$repo_root/Sources/ParcCore/SidebarOutlineConfigureSkip.swift"
step python3 "$repo_root/tests/SidebarOutlineConfigureSkip/check.py"
step python3 "$repo_root/tests/SidebarSpaceSwipe/check.py"
step python3 "$repo_root/tests/SidebarHeaderGlyphs/check.py"
step python3 "$repo_root/tests/ExtensionPopupPlacement/check.py"
step python3 "$repo_root/tests/ExtensionPopupActivity/check.py"
step python3 "$repo_root/tests/SidebarPreviewHeader/check.py"
step python3 "$repo_root/tests/SidebarDocumentPreview/check.py"
step python3 "$repo_root/tests/IncognitoWindowTheme/check.py"
step python3 "$repo_root/tests/EmptyWindow/check.py"
step python3 "$repo_root/tests/StartPage/check.py"
step python3 "$repo_root/tests/StartPageMark/check.py"
step python3 "$repo_root/tests/CommandBar/resident_check.py"
step compile_and_run mini-player-layout-flush-skip MiniPlayerLayoutFlushSkipTests
step python3 "$repo_root/tests/MiniPlayerLayoutFlushSkip/check.py"
step compile_and_run pane-content-hosted-layout-flush PaneContentHostedLayoutFlushTests
step python3 "$repo_root/tests/PaneContentHostedLayoutFlush/check.py"

step python3 "$repo_root/tests/CaptureLensTimerIdle/check.py"

step bash "$repo_root/scripts/test-shortcut-smiley-timer-idle.sh"

step bash "$repo_root/scripts/test-theme-appearance-timer-idle.sh"

step compile_and_run layout-chrome-geometry-skip LayoutChromeGeometrySkipTests \
  "$repo_root/Sources/ParcApp/SidebarMotionController.swift"
step python3 "$repo_root/tests/LayoutChromeGeometrySkip/check.py"
step python3 "$repo_root/tests/LayoutChromePageHostSkip/check.py"

step python3 "$repo_root/tests/DocumentsLibraryCatalogSkip/check.py"

step compile_and_run sidebar-new-space SidebarNewSpaceTests
step compile_and_run new-space-window-choice NewSpaceWindowChoiceTests \
  "$repo_root/Sources/ParcCore/NewSpaceWindowChoice.swift"
step python3 "$repo_root/tests/PopupTabHandoff/check.py"
step bash "$repo_root/scripts/test-shortcut-essentials.sh"
step compile_and_run new-space-blocker-wait NewSpaceBlockerWaitTests \
  "$repo_root/Sources/ParcCore/NewSpaceBlockerWait.swift"
step compile_and_run sidebar-space-moves SidebarSpaceMoveTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"

step compile_and_run command-bar-folders CommandBar/FolderActionTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

step compile_and_run download-library-selection DownloadLibrary/SelectionTests \
  "$repo_root/Sources/ParcApp/DownloadLibrarySelection.swift" \
  "$repo_root/Sources/ParcApp/DownloadLibraryTable.swift"
step swift_test external-media-library -parse-as-library -warnings-as-errors \
  "$repo_root/Sources/ParcApp/ExternalMediaLibrary.swift" \
  "$repo_root/Sources/ParcApp/MediaLibraryContext.swift" \
  "$repo_root/tests/ExternalMediaLibraryTests.swift"
step swift_test media-library-grid -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/MediaLibraryContext.swift" "$repo_root/tests/MediaLibraryGridTests.swift"
step python3 "$repo_root/tests/CaptureLibraryCatalogSkip/check.py"
step python3 "$repo_root/tests/DownloadLibrary/check-view.py"
step python3 "$repo_root/tests/NavigationLoading/check.py"
step python3 "$repo_root/tests/EaselIdleSleep/check.py"
step python3 "$repo_root/tests/DownloadLocation/check-picker.py"
step python3 "$repo_root/tests/MenuImages/check.py"
step bash "$repo_root/scripts/test-parc-dialog.sh"
step bash "$repo_root/scripts/test-page-tool-appearance.sh"
step python3 "$repo_root/tests/PopupChrome/check.py"

step compile_and_run sidebar-window-move SidebarWindowMoveTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift" \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/NoteFileKind.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift"

step swift_test dock-reopen -warnings-as-errors -parse-as-library "$repo_root/Sources/ParcCore/DockReopen.swift" \
  "$repo_root/tests/DockReopenTests.swift"
step swift_test tab-peek -warnings-as-errors -parse-as-library "$repo_root/Sources/ParcCore/TabPeek.swift" \
  "$repo_root/tests/TabPeekTests.swift"

wait
shopt -s nullglob
failed=0
passed=0
for status in "$steps_dir"/*.status; do
  id="${status%.status}"
  read -r result seconds < "$status"
  if [ "$result" = ok ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf '%s\nFAILED after %ss: %s\n%s\n' "$(printf '=%.0s' {1..70})" "$seconds" "$(cat "$id.name")" "$(printf -- '-%.0s' {1..70})"
    cat "$id.log"
  fi
done
missing=$((step_count - passed - failed))
if [ -n "${PARC_TEST_DURATIONS:-}" ]; then
  echo "Slowest steps"
  for status in "$steps_dir"/*.status; do
    read -r result seconds < "$status"
    printf '%5ss  %s\n' "$seconds" "$(cat "${status%.status}.name" | cut -c1-110)"
  done | sort -rn | head -n "$PARC_TEST_DURATIONS"
fi
summary="Ran $step_count steps in $((SECONDS - began))s with $jobs_limit jobs: $passed passed, $failed failed"
[ "$missing" -eq 0 ] || summary="$summary, $missing without a result"
echo "$summary"
[ "$failed" -eq 0 ] && [ "$missing" -eq 0 ]
