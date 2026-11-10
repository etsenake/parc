# Space theme Undo across popovers

Parc connects every completed existing-Space theme edit to the originating
browser window's **Update Theme** Undo history. Closing the transient popover
does not discard those records. Reopening the editor exposes the same Undo and
Redo history; a parent inverse refreshes an open editor from the restored theme.
Setup and not-yet-created Space drafts keep their existing local history and
commit/cancel ownership. Application appearance changes retain a separate **Update Appearance** entry in the same window chronology.

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

`SpaceTheme` represents the empty/default theme explicitly.
Profile/before-image checks, atomic disk commits and conservative rejection of
a competing edit are data-safety adaptations to Parc's shared local model.
Deletion or Profile reassignment invalidates a record instead of recreating or
retargeting a Space. Temporary native-window unavailability disables the
operation without discarding its record. A closed original window has no
remaining window history. History is intentionally not persisted across app
restart; the saved theme is persisted.

## Checks

`scripts/test-theme-undo.sh` compiles the actual BrowserStore, theme editor view,
window Undo manager and theme registration adapter. Disposable model and inert
AppKit checks exercise sequential popovers, release of the retired editor,
Undo/Redo before and after reopening, complete theme restoration, multi-Space
selection preservation, original-window availability, no-op/branch behavior,
gesture commit on close, stale shared edits, interruption by a parent update,
actual persistence failures and retry, deleted/reassigned targets and local
draft history. No window is displayed and no browser or engine is loaded.
