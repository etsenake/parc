# Sidebar item selection

Parc keeps an ordered window-local sidebar selection separate from pages shown
in a split. Eligible items are visible Today/pinned rows, folders and complete
split containers in one Space. Favorite pointer selection has a separate owner.

Command-click toggles; Shift-click ranges from the original anchor through visible
order; Command-Shift adds the range. A multi-set retains the visible active item
without changing page selection or focused split pane. A singleton follows normal
activation. Plain activation/Escape clear the set, and Option does not alter it.
With sidebar focus, arrows move/extend selection and Delete uses the guarded
Close Tabs in Selection operation. Renderer/native text editing keeps its keys.

Rows expose selected state and real accessibility actions separately from active
page highlighting. Selected-row context menus offer Copy Links, eligible moves,
Close/Delete/Archive and Clear Selection. Folders include original descendants;
whole splits remain one item. Explicit row buttons retain their own target.

## Select All and plural commands

Command-A selects displayed eligible rows only while the sidebar owns the key
window's first responder. Collapsed descendants and Favorite tiles remain outside
that set. Other text fields, native editors and webpages retain responder-chain
Select All; no global monitor intercepts it.

The focused multi-set supplies Copy, Copy URLs, Copy URLs as Markdown and Close.
Standard Copy also takes a single selected row: a folder reached with the
arrows, or the current row when nothing else is selected. A tab copies its
address, a split all its pages and a folder its contents; Copy URL, Markdown and
Close keep their single-page meaning there. Plain clicks still activate rows.
Existing command IDs, custom/disabled bindings and address-result paths remain.
Tracked menu actions capture original selection/native capability; expiry cannot
fall through to a newly active page. Standard Copy uses native responder dispatch.
Quote is unavailable for a multi-set because no plural quote contract exists.

Exports use original records and the link formatter the split pane menu's
Copy Links shares. Plain copies put one address per line as text plus a
rich-text version linking each title to its address; Markdown copies stay
Markdown only. Ancestors suppress duplicate descendants; splits keep child
order. Deduplication uses tab ID, so distinct tabs with one URL stay distinct
lines. Only web and local file addresses are copied: Notes, Easels, Parc's own
pages, blank tabs and malformed destinations are skipped. A Copied Link or
Copied Links notice confirms the copy. These exports do not impersonate
live-page clipboard policy.
Fresh/default Close bindings prefer Parc; migration preserves existing implicit
website priority and explicit custom/disabled choices.

## Ownership and cancellation

Movement captures window, Profile, Space, selection/focus, hierarchy and native
identities. Pasteboard text is only a locator. Stale, foreign, retiring or
transferred targets refuse without expanding the captured grant. Mixed moves
stage every root, reject the complete proposal on any failure and save/publish
once. No page is cloned or closed for a move.

The selection is ephemeral, not session-persisted. Moving keyboard focus within
the same window retains it, but its commands require focus in the sidebar list.
Losing the window's key status clears it, except for the owning close-consent
sheet. Hierarchy disclosure preserves still-visible selected rows;
collapsed/removed rows cannot remain selected.
Dragging an unselected row clears the multi-set and takes its single-item lease.
The pane split-creation path never consumes a multi-set.

## Explicit Delete/Archive of the original selection

Context/AX Delete applies to ordinary folders; Archive Tabs applies to tab/split
roots. The capability binds revision, window, Profile, Space and complete hierarchy.
Selected ancestors suppress descendants. Whole-set retirement, document save/IME
barriers and durable Undo/Redo are shared with
[folder commands](folder-commands.md).

Only the operation's own consent/beforeunload sheet may retain its selection while
key focus changes. Ordinary key loss, selection change, detachment or changed
hierarchy expires it. Refusal cannot redirect to a current tab.

## Saved versus mixed keyboard Close

`SidebarKeyboardCloseTarget` distinguishes saved-only deselection from a collection
with any Today root. Saved-only close unloads content while preserving folders,
bookmarks and complete saved split identity/geometry. Any Today root archives the
whole captured set, including saved references, through one consent and durable
transaction. Folder-bearing commands retain folder confirmation; tab-only keyboard
close adds no warning. Explicit Delete keeps its separate confirmation policy.

Saved Reopen chooses one most-recent eligible original item in the initiating
window; it does not invent a bulk saved stack. Archived Today steps retain original
whole-split geometry/focus. Complete Undo retains mixed-command saved references.
See [Reopen Closed Tab](reopen-closed-tabs.md).

## App-tray move boundary

Command reset and Shift activation do not create Favorite range selections.
Original Favorite tiles and complete Favorite splits can use one-use move
capabilities; tray admission validates every root and the twelve-root capacity.
Supported modifiers and cross-Profile routes remain with
[folder moves](folder-moves.md) and [split groups](split-groups.md).

## Remaining selection limits

Close is unavailable when the selection contains only empty saved folders,
because the close transaction requires at least one tab. Explicit folder Delete
remains available. Favorite tiles do not join range or multi-selection.

## Checks

Model, copy-command and ownership checks cover visible Select All, export
identity/order, single-row copy targets, the rich-text flavor, stale grants,
save failure and saved/mixed close semantics.
