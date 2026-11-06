# Space theme Undo across popovers

SPACE14 connects every completed existing-Space theme edit to the originating
browser window's **Update Theme** Undo history. Closing the transient popover
does not discard those records. Reopening the editor exposes the same Undo and
Redo history; a parent inverse refreshes an open editor from the restored theme.
Setup and not-yet-created Space drafts keep their existing local history and
commit/cancel ownership. Application appearance changes retain SPACE13's
separate **Update Appearance** entry in the same window chronology.

## Recovered contract

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The retained theme-picker material and local component/type/cross-reference/
annotated-function helpers answered this row. No REA/decompilation slot or
`work/spaces-profiles-checks/space14`.

- `SpaceStyleEditor.SpaceStyleEditor.State` has its transient `undoStack` and
  `isGestureInProgress`; `Action.Delegate` case 0 is `registerUndo(State)`.
  editor presentation, handles `registerUndo`, and obtains the originating
  window's Undo registration dependency through its own Identifiable ID at
- The parent projects the supplied editor snapshot through the existing
  `WindowAction.UndoAction.undoUpdateSpaceTheme(spaceID:theme:)`, enum case 2,
  complete WindowTheme, not a retained view controller or color-only value.
  “Undo updating a space's theme” and the exact English action name.

The cross-popover contract therefore retains complete theme values in the
original window and rebuilds transient controls on a parent inverse. It does
not require keeping the old popover, pad coordinate snapshot or local history
alive after dismissal. Pointer/rotation/scroll geometry and physical haptics
remain the separately owned SPACE15/SPACE16 requirements.

## Parc implementation and explicit adaptations

`BrowserStore.saveSpaceTheme` commits the complete theme only when the original
Space ID, Profile ID and before-image still match. `SpaceThemeChange` captures
both complete values and the original identities. Its Undo/Redo transaction
changes only that theme: current Space selection, tab owners, name, icon and
ordering remain untouched. The existing atomic settings persistence routine
writes before publishing the new state. A failed write leaves both shared state
and the window history direction unchanged so an inverse can be retried.

`FolderUndoManager.appendSpaceThemeChange` stores the record in the original
window's existing history. Records hold the store weakly and owner callbacks
hold the browser window weakly; neither keeps a retired editor alive. The native
Edit menu, popover responder and editor context menu use that same history.
Each changed discrete action or completed gesture registers once. No-op commits
preserve Redo, and a genuine new edit replaces its Redo branch. Existing Space
switch/dismissal gesture completion remains in the original popover owner.

`SpaceThemeEditorView` exposes an authoritative transaction callback only for
existing Spaces. It retains its separate local path for setup and creation
drafts. On parent Undo or a competing shared-model edit, `synchronizeTheme`
rebuilds the editor model and its pad, updates controls, and retires pending
control input. A cancelled rotation stays suppressed through its physical end;
continued phased scrolling and momentum stay suppressed until a fresh direct
begin. An unphased wheel burst can resume after the existing 0.2-second idle
boundary. Thus inherited input cannot overwrite the inverse or clear Redo.
A rejected or failed commit resets the displayed draft to the
actual saved theme. The original window clears its stale preview at this same
boundary. Application appearance and its observer are preserved.

Parc's nonoptional `SpaceTheme` represents the empty/default theme explicitly;
Profile/before-image checks, atomic disk commits and conservative rejection of
a competing edit are data-safety adaptations to Parc's shared local model.
Deletion or Profile reassignment invalidates a record instead of recreating or
retargeting a Space. Temporary native-window unavailability disables the
operation without discarding its record. A closed original window has no
remaining window history. History is intentionally not persisted across app
restart; the saved theme is persisted.

## Checks and limits

`scripts/test-theme-undo.sh` compiles the actual BrowserStore, theme editor view,
window Undo manager and theme registration adapter. Disposable model and inert
AppKit checks exercise sequential popovers, release of the retired editor,
Undo/Redo before and after reopening, complete theme restoration, multi-Space
selection preservation, original-window availability, no-op/branch behavior,
gesture commit on close, stale shared edits, interruption by a parent update,
actual persistence failures and retry, deleted/reassigned targets and local
draft history. No window is displayed and no browser or engine is loaded.

The focused Undo component passes 40 assertions, the shared appearance
component passes 72 assertions, and all 796 BrowserStore model assertions pass.
The shared appearance component check covers the unchanged app-parent contract
against this integrated editor. Finished-tree compilation uses the full Xcode
whole-module SIL pass with warnings as errors. Check results and independent
review clearance are recorded in `work/spaces-profiles-checks/space14`.
Functional browser tests remain prohibited; these results establish source and
component behavior, not integrated browser runtime or full visual acceptance.

Independent `space14_review` cleared the complete finished source after the
physical noise-input interruption finding was fixed. The revised final SIL
pass completed with zero diagnostics; source-identical reconciliation preserves
the published Extensions changes. Review and publication manifests retain the
exact checked source hashes. SPACE14 is complete under the current implementation
rule; the other theme interaction, haptic and material rows keep their scope.
