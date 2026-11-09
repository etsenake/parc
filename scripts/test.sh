#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
core_sources=(
  "$repo_root/Sources/ParcCore/BrowserStore.swift"
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
  "$repo_root/Sources/ParcCore/SpaceTheme.swift"
  "$repo_root/Sources/ParcCore/OnboardingDraft.swift"
  "$repo_root/Sources/ParcCore/LinkRouting.swift"
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift"
  "$repo_root/Sources/ParcCore/ProfileRemoval.swift"
  "$repo_root/Sources/ParcCore/SplitPaneControls.swift"
  "$repo_root/Sources/ParcCore/SplitCrossSpaceAdd.swift"
  "$repo_root/Sources/ParcCore/SidebarFolderFromItems.swift"
  "$repo_root/Sources/ParcCore/TabHistoryArchive.swift"
)
#
mkdir -p "$repo_root/build/tests/tooltip"
tooltip_sources=()
while IFS= read -r path; do tooltip_sources+=("$path"); done < <(python3 "$repo_root/tests/Tooltip/support.py" "$repo_root/build/tests/tooltip" SpaceTheme.swift)
compile_and_run() {
  local executable="$repo_root/build/tests/$1"
  local test_source="$repo_root/tests/$2.swift"
  shift 2
  xcrun swiftc -parse-as-library "${core_sources[@]}" "$test_source" "$@" -o "$executable"
  "$executable"
}
compile_and_run favorite-moves FavoriteMoveTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift" \
  "$repo_root/Sources/ParcCore/TabCommandNavigation.swift" \
  "$repo_root/Sources/ParcCore/SidebarKeyboardNavigation.swift" \
  "$repo_root/Sources/ParcCore/RecentTabOrder.swift"
compile_and_run browser-store BrowserStoreTests \
  "$repo_root/Sources/ParcCore/FolderLinks.swift" "$repo_root/tests/Support/FileObservation.swift"
compile_and_run whats-new-page WhatsNewPageTests
# Temporary data only: verifies that blocked edits preserve an unreadable file.
# Also locks identical pretty-JSON recommit skip for link-routing prefs.
compile_and_run link-routing-store LinkRoutingStoreTests
# Pure ordered-window and unavailable-Space fallback policy; no browser execution.
bash "$repo_root/scripts/test-link-routing-fallback.sh"
compile_and_run link-routing-editor LinkRoutingEditorTests

# Settings pretty JSON identical-byte persist skip (shortcuts + link-routing).
# Helper is already in core_sources; keep this compile helper-only via a direct
# swiftc so BrowserStore and friends are not pulled in for a predicate check.
mkdir -p "$repo_root/build/tests"
xcrun swiftc -parse-as-library \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/tests/SettingsPrettyJSONPersistSkipTests.swift" \
  -o "$repo_root/build/tests/settings-pretty-json-persist-skip"
"$repo_root/build/tests/settings-pretty-json-persist-skip"
python3 "$repo_root/tests/SettingsPrettyJSONPersistSkip/check.py"

# Other browsers' native messaging manifests linked into the engine folder
# (temporary directories only).
xcrun swiftc -parse-as-library \
  "$repo_root/Sources/ParcCore/NativeMessagingHosts.swift" \
  "$repo_root/tests/NativeMessagingHostsTests.swift" \
  -o "$repo_root/build/tests/native-messaging-hosts"
"$repo_root/build/tests/native-messaging-hosts"
bash "$repo_root/scripts/test-shortcut-persist-skip.sh"
# Pure stale-owner/selection checks for original split-link presentation.
bash "$repo_root/scripts/test-split-link-snapshot.sh"
bash "$repo_root/scripts/test-split-link-policy.sh"
# Pure DidFinishNavigation shell-notify filters; no browser execution.
bash "$repo_root/scripts/test-page-shell-notify.sh"
# Pure top-band sampling, band geometry and frame-sample delivery rules.
bash "$repo_root/scripts/test-top-band-color.sh"
# Pure pane compositor hand-off and sweep rules; no browser execution.
bash "$repo_root/scripts/test-pane-compositor-policy.sh"
# Pure FairPlay identity site, navigation and Widevine rules; no browser execution.
bash "$repo_root/scripts/test-fairplay-identity.sh"
# Page host containment and the pane compositor view in real offscreen AppKit,
# and the two other suites that build the page host on its own.
bash "$repo_root/tests/NativePageHost/run.sh"
bash "$repo_root/tests/NativeFocusManager/run.sh"
bash "$repo_root/tests/NativeExtensionPopup/run.sh"
# Pure media Publish notify filters; no browser execution.
bash "$repo_root/scripts/test-media-notify.sh"
# Inert NSTextView checks Return while marked-text input is active.
compile_and_run link-routing-text LinkRoutingTextEditingTests \
  "$repo_root/Sources/ParcApp/LinkRoutingTextEditing.swift"
compile_and_run automatic-archive-presentation AutoArchivePresentationTests
compile_and_run automatic-archive-education-view AutoArchiveEducationViewTests \
  "$repo_root/Sources/ParcApp/ThemeRenderer.swift" \
  "$repo_root/Sources/ParcApp/AutoArchiveEducationView.swift"
compile_and_run update-complete-card UpdateCompleteCardTests \
  "$repo_root/Sources/ParcApp/ThemeRenderer.swift" \
  "$repo_root/Sources/ParcApp/UpdateCompleteCard.swift"
compile_and_run update-ready-card UpdateReadyCardTests \
  "$repo_root/Sources/ParcApp/ThemeRenderer.swift" \
  "$repo_root/Sources/ParcApp/UpdateCompleteCard.swift" "$repo_root/Sources/ParcApp/UpdateReadyCard.swift"
compile_and_run tab-creation-provenance TabCreationProvenanceTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"
compile_and_run recent-tab-switcher RecentTabSwitcherTests \
  "$repo_root/Sources/ParcCore/RecentTabOrder.swift"
compile_and_run same-container-focus SameContainerFocusTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"
compile_and_run peek-referrer-pool PeekReferrerPoolTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"
compile_and_run folder-undo-manager FolderUndoManagerTests \
  "$repo_root/Sources/ParcApp/FolderUndoManager.swift"
compile_and_run folder-document-close FolderDocumentCloseTests \
  "$repo_root/Sources/ParcApp/FolderUndoManager.swift" \
  "$repo_root/Sources/ParcCore/NoteStore.swift" \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift"
compile_and_run profile-removal ProfileRemovalTests
# Isolated doubles stand in for native preparation/commit callbacks; this does
# not load Chromium or remove any actual browser profile.
compile_and_run profile-removal-controller ProfileRemovalControllerTests \
  "$repo_root/Sources/ParcApp/ProfileRemovalController.swift" \
  "$repo_root/tests/ProfileRemovalTestSupport.swift"
compile_and_run profile-removal-sheets ProfileRemovalSheetTests \
  "$repo_root/Sources/ParcApp/ProfileRemovalController.swift" \
  "$repo_root/Sources/ParcApp/ProfileRemovalDialog.swift" \
  "$repo_root/Sources/ParcApp/ProfileRemovalButton.swift" \
  "$repo_root/Sources/ParcApp/SettingsHoverButton.swift" \
  "$repo_root/Sources/ParcApp/ProfileRemovalSheet.swift" \
  "$repo_root/Sources/ParcApp/UnusedProfileRemovalSheet.swift" \
  "$repo_root/tests/ProfileRemovalTestSupport.swift"

compile_and_run sidebar-plural-duplicate SidebarPluralDuplicateTests \
  "$repo_root/Sources/ParcCore/NoteStore.swift" \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift"
compile_and_run sidebar-split-copy SidebarSplitCopyTests

compile_and_run sidebar-plural-removal SidebarPluralRemovalTests \
  "$repo_root/Sources/ParcCore/NoteStore.swift" \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcApp/FolderUndoManager.swift"

python3 "$repo_root/tests/FolderDeletion/check.py"

compile_and_run sidebar-keyboard-close SidebarKeyboardCloseTests \
  "$repo_root/Sources/ParcCore/NoteStore.swift" \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcApp/FolderUndoManager.swift"

compile_and_run closed-items ClosedItemsTests \
  "$repo_root/Sources/ParcCore/NoteStore.swift" \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"
# Every close's window Undo/Redo, Clear's included, over a real temporary store.
bash "$repo_root/scripts/test-close-undo.sh"
# Each tab's back/forward entries kept for the next launch.
bash "$repo_root/scripts/test-tab-history.sh"
# Handoff's web page activity, published and continued.
bash "$repo_root/scripts/test-handoff-activity.sh"
# The frozen pane a window keeps when its page moves to another window.
bash "$repo_root/scripts/test-page-placeholder.sh"
compile_and_run browser-data-export BrowserDataExportTests \
  "$repo_root/Sources/ParcCore/BrowserDataExport.swift"
# Native site-scope text restoration and button/AX; no actual profile mutation.
compile_and_run command-bar-scope-menu CommandBar/ScopeMenuTests \
  "$repo_root/Sources/ParcApp/CommandBarScopeEditing.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

# Offscreen privacy banner and the sidebar background double-click rule; no profile or browser.
# A busy dialog button shows the onboarding button's spinner.
spinner=$(python3 -B "$repo_root/tests/Support/declarations.py" "$repo_root/build/tests/command-bar-privacy-spinner.swift" PArcButtonSpinner)
compile_and_run command-bar-privacy CommandBar/SearchPrivacyBannerTests \
  "$repo_root/Sources/ParcApp/CommandBarSearchPrivacyBanner.swift" \
  "$repo_root/Sources/ParcApp/SidebarTablistBackground.swift" \
  "$repo_root/Sources/ParcApp/PArcDialog.swift" "$spinner" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

compile_and_run command-bar-background CommandBar/BackgroundOpenTests \
  "$repo_root/Sources/ParcApp/CommandBarSubmission.swift" \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"

compile_and_run command-bar-result-navigation CommandBar/ResultNavigationTests \
  "$repo_root/Sources/ParcApp/CommandResultsTable.swift" \
  "$repo_root/Sources/ParcApp/CommandBarEditState.swift"

#
compile_and_run command-bar-row-diff CommandBar/RowDiffTests \
  "$repo_root/Sources/ParcApp/CommandBarRowDiff.swift"
# Return/Tab while a native answer is pending; pure model, no providers.
compile_and_run command-bar-native-hold CommandBar/NativeHoldTests \
  "$repo_root/Sources/ParcApp/CommandBarNativeHold.swift"
#
compile_and_run command-bar-ranking CommandBar/RankingTests \
  "$repo_root/Sources/ParcApp/CommandBarRanking.swift" "$repo_root/Sources/ParcApp/CommandBarRowDiff.swift"
# Actual selected-row scope resolver with inert native-publication fixtures.
bash "$repo_root/scripts/test-command-bar-site-search.sh"
# Production filtering -> ranking -> scope/Return, with inert publications.
bash "$repo_root/scripts/test-command-bar-navigation.sh"
# Trigger phrases and weighted bumps as the command bar builds command candidates.
compile_and_run command-bar-command-ranking CommandBar/CommandRankingTests \
  "$repo_root/Sources/ParcApp/CommandBarRanking.swift" "$repo_root/Sources/ParcApp/CommandBarRowDiff.swift" \
  "$repo_root/Sources/ParcApp/CommandBarCommandCandidate.swift" \
  "$repo_root/Sources/ParcCore/CommandBarTypedCommand.swift" "$repo_root/Sources/ParcCore/CommandBarMenuItemInfo.swift" \
  "$repo_root/Sources/ParcCore/CommandBarCommandPresentation.swift"

# Offscreen native row/table interaction, no provider or browser operation.
compile_and_run command-bar-pointer CommandBar/PointerSelectionTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultsTable.swift" \
  "$repo_root/Sources/ParcApp/CommandResultRowView.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

# Offscreen surface, palette, hairline, row highlight and cell colours; no browser.
compile_and_run command-bar-appearance CommandBar/AppearanceTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultRowView.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" \
  "$repo_root/Sources/ParcApp/PopoverBackgroundView.swift" "${tooltip_sources[@]}"

#
compile_and_run command-bar-site-color CommandBar/SiteColorTests \
  "$repo_root/Sources/ParcApp/CommandBarSiteColor.swift" \
  "$repo_root/Sources/ParcApp/CommandBarScopeEditing.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

#
compile_and_run command-bar-result-text CommandBar/ResultTextTests \
  "$repo_root/Sources/ParcCore/CommandBarResultText.swift" \
  "$repo_root/Sources/ParcCore/CommandBarCommandPresentation.swift"

# Offscreen rows: title/subtitle layout, Switch to Tab and the selected icon tile.
compile_and_run command-bar-result-row CommandBar/ResultRowTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

compile_and_run command-bar-folder-copy CommandBar/FolderCopyTests
compile_and_run command-bar-document-alias CommandBar/DocumentAliasTests \
  "$repo_root/Sources/ParcCore/NoteStore.swift" \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift"

compile_and_run command-bar-folder-move CommandBar/FolderMoveTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

compile_and_run command-bar-favorites CommandBar/FavoriteActionTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

compile_and_run command-bar-spaces CommandBar/SpaceActionTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

#
compile_and_run command-bar-typed-commands CommandBar/TypedCommandTests \
  "$repo_root/Sources/ParcCore/CommandBarTypedCommand.swift" \
  "$repo_root/Sources/ParcCore/CommandBarMenuItemInfo.swift" \
  "$repo_root/Sources/ParcCore/CommandBarCommandPresentation.swift"

# Closed-bar render must not snapshot tabs/history/spaces/folders; open bar still does.
compile_and_run command-bar-reconcile-inputs CommandBar/ReconcileInputsTests \
  "$repo_root/Sources/ParcCore/CommandBarReconcileInputs.swift"

# Open-bar identical query/result fingerprints skip tab/history scan + reload.
compile_and_run command-bar-open-results-skip CommandBar/OpenResultsSkipTests \
  "$repo_root/Sources/ParcCore/CommandBarOpenResultsSkip.swift"

# Empty-query history top-8 reuses while query/revision/excluded-URL/tab URLs match.
compile_and_run command-bar-history-scan-skip CommandBar/HistoryScanSkipTests \
  "$repo_root/Sources/ParcCore/CommandBarHistoryScanSkip.swift"

# Closed Find render must not filter/dismiss/update; open bar still does.
compile_and_run find-reconcile-skip KeyboardNavigation/FindReconcileSkipTests \
  "$repo_root/Sources/ParcCore/FindReconcileSkip.swift"

# Identical LiveShortcutToolTip.didChange fan-out skips; string changes still update.
compile_and_run shortcut-tooltip-discovery-skip ShortcutTooltipDiscoverySkipTests \
  "$repo_root/Sources/ParcCore/ShortcutTooltipDiscoverySkip.swift"
python3 "$repo_root/tests/ShortcutTooltipDiscoverySkip/check.py"

# Identical Peek title/URL/loading/capture/crash/favicon ticks skip refresh/onUpdate.
compile_and_run peek-presentation-skip PeekPresentationSkipTests \
  "$repo_root/Sources/ParcCore/PeekPresentationSkip.swift"
python3 "$repo_root/tests/PeekPresentationSkip/check.py"

# Drop-reserve layoutSubtree skips when frames match and the subtree is clean.
compile_and_run split-layout-flush-skip SplitLayoutFlushSkipTests \
  "$repo_root/Sources/ParcCore/SplitLayoutFlushSkip.swift"
python3 "$repo_root/tests/SplitLayoutFlushSkip/check.py"
# The outgoing page stays on screen until the incoming page has drawn.
compile_and_run page-switch-hold PageSwitchHoldTests \
  "$repo_root/Sources/ParcApp/PageSwitchHold.swift"
# Sidebar outline/list layoutSubtree skips when frames match and the subtree is clean.
compile_and_run sidebar-outline-layout-flush-skip SidebarOutlineLayoutFlushSkipTests \
  "$repo_root/Sources/ParcCore/SidebarOutlineLayoutFlushSkip.swift"
python3 "$repo_root/tests/SidebarOutlineLayoutFlushSkip/check.py"
# Sidebar outline configure skips setContent/needsLayout when content fingerprint matches.
compile_and_run sidebar-outline-configure-skip SidebarOutlineConfigureSkipTests \
  "$repo_root/Sources/ParcCore/SidebarOutlineConfigureSkip.swift"
python3 "$repo_root/tests/SidebarOutlineConfigureSkip/check.py"
# A Space swipe on the real sidebar builds no rows once its pages are prepared.
python3 "$repo_root/tests/SidebarSpaceSwipe/check.py"
# Sidebar header TranslucentButton glyphs, face states and the URL bar surface/reveal.
python3 "$repo_root/tests/SidebarHeaderGlyphs/check.py"
# Parc tooltips: configuration, palette, keycaps, placement, layout, drawing and presentation state.
python3 "$repo_root/tests/Tooltip/check.py"
#
python3 "$repo_root/tests/FloatingSidebarSurface/check.py"
#
python3 "$repo_root/tests/IncognitoWindowTheme/check.py"
compile_and_run mini-player-layout-flush-skip MiniPlayerLayoutFlushSkipTests
python3 "$repo_root/tests/MiniPlayerLayoutFlushSkip/check.py"
compile_and_run pane-content-hosted-layout-flush PaneContentHostedLayoutFlushTests
python3 "$repo_root/tests/PaneContentHostedLayoutFlush/check.py"

# Capture element-lens 60 Hz timer idle-stops; identical settled focus is a no-op.
python3 "$repo_root/tests/CaptureLensTimerIdle/check.py"

# Shortcut smiley cue 60 Hz timer idle-stops; identical presentation skips needsDisplay.
bash "$repo_root/scripts/test-shortcut-smiley-timer-idle.sh"

# Settings theme-editor appearance-button 60 Hz idle-stops; identical presentation skips needsDisplay.
bash "$repo_root/scripts/test-theme-appearance-timer-idle.sh"

# Identical layoutChrome chrome-geometry fingerprint skips; Cmd-S changes still run.
compile_and_run layout-chrome-geometry-skip LayoutChromeGeometrySkipTests \
  "$repo_root/Sources/ParcApp/SidebarMotionController.swift"
python3 "$repo_root/tests/LayoutChromeGeometrySkip/check.py"
python3 "$repo_root/tests/LayoutChromePageHostSkip/check.py"

# Note editor layoutDocument chrome fingerprint skip; typing height still reflows.
compile_and_run note-editor-chrome-layout-skip NoteEditorChromeLayoutSkipTests
python3 "$repo_root/tests/NoteEditorChromeLayoutSkip/check.py"

# Documents Library NoteStore.changes fingerprint skip; identical catalogs no-op.
python3 "$repo_root/tests/DocumentsLibraryCatalogSkip/check.py"

compile_and_run sidebar-new-space SidebarNewSpaceTests
compile_and_run sidebar-space-moves SidebarSpaceMoveTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift"

compile_and_run command-bar-folders CommandBar/FolderActionTests \
  "$repo_root/Sources/ParcCore/CommandBarSpaceAction.swift" \
  "$repo_root/Sources/ParcApp/CommandResultCell.swift" \
  "$repo_root/Sources/ParcApp/CommandBarAppearance.swift" "${tooltip_sources[@]}"

# Uses real record snapshots and NSTableView input; no file or browser action.
compile_and_run download-library-selection DownloadLibrary/SelectionTests \
  "$repo_root/Sources/ParcApp/DownloadLibrarySelection.swift" \
  "$repo_root/Sources/ParcApp/DownloadLibraryTable.swift"
python3 "$repo_root/tests/DownloadLibrary/check-view.py"
# Library rail selection playback, offscreen: parks on selection-end, deselection lets a play finish.
python3 "$repo_root/tests/LibraryRail/check.py"
#
python3 "$repo_root/tests/DownloadLocation/check-picker.py"
#
python3 "$repo_root/tests/MenuImages/check.py"
#
bash "$repo_root/scripts/test-arc-dialog.sh"

compile_and_run sidebar-window-move SidebarWindowMoveTests \
  "$repo_root/Sources/ParcCore/WindowPresentation.swift" \
  "$repo_root/Sources/ParcCore/NoteStore.swift" \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift"

xcrun swiftc -warnings-as-errors -parse-as-library "$repo_root/Sources/ParcCore/DockReopen.swift" \
  "$repo_root/tests/DockReopenTests.swift" -o "$repo_root/build/tests/dock-reopen"
"$repo_root/build/tests/dock-reopen"
