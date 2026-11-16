# Reopen Closed Tab

Reopen belongs to the physical window that recorded the close. Its in-memory
`WindowClosedItems` first consumes the saved-item priority slot, then the newest
committed manual close step. It never searches another window's stack.

## Production ownership

A record describes the exact committed close: Profile, Space, items, split
identity, order, orientation and ratios. Consent refusal or an uncommitted
retirement creates no record. Restoration uses the original item/document
identity, including Note and Easel aliases, and creates a normal new page after
the original page closed.

The original Profile and Space must still exist. Changed afterimages expire a
step; a temporarily busy/retiring owner leaves it available for retry.
`BrowserStore.restoreClosedItem` writes the complete restoration atomically
before consuming the step. Failed saves leave a retryable record.

## Bulk saved Close → one Reopen target

Closing saved items unloads their pages without archiving their sidebar items.
A bulk close records one target using the physical window's most recent item
activity, with stable ordering for ties. An unchanged retained saved split is
selected as a group. Window session records preserve subsecond activity dates
for this ranking; the close stack itself does not survive relaunch.

## Partial split Reopen

`ClosedSplitMembership` records the original container and whether the close
dissolved it. The afterimage must match the actual surviving group or its
expected removal.

- If the container survives, insert the returning pane at its recorded position,
  accounting for previously restored siblings. Keep survivors' current relative
  proportions and restore the returning pane's original share.
- If it dissolved, recreate its original ID, orientation, title, icon and anchor
  using surviving original members in original order, with normalized ratios.
- Refuse a group with four panes, fewer than two members, invalid ownership or a
  survivor already in another split. Restore the returning pane alone instead.
- Survivors must remain live in the same Profile/Space. Their existing pages
  remain owned by normal selection; the reopened pane receives a new page.

A restored split is selected with the reopened pane focused. Missing original
Space/Profile expires the record instead of borrowing another destination.

## Closed Peeks, folders and the cache lifetime

A user dismissal records a Peek only after its page actually closes. Promotion
is not a close; closing its parent records only the parent. The saved-item slot
still has priority. Reopen selects the surviving original parent and opens the
Peek through that parent's real native Browser. If the parent has no live page,
selection creates it and the step remains for the next Reopen.

Undo Close Peek takes the same route when the parent page now lives in another
window: it moves that page here with the ordinary transfer checks, waits for it
to arrive, then opens the Peek over it. It isn't offered while the other window
has a live Peek over that parent, and a move or Peek that fails leaves Undo
offered and the Reopen step in place.

Folder deletion records the actual `FolderDeletionUndo`: original folders,
children, order, split provenance and expansion flags. Undo and Reopen share the
same restoration transaction. Whichever restores first expires the other.

The action vocabulary is `openPeek`, `expandFolder`, `insertItem` and
`regroupItems`. Steps span Spaces within one physical window and restore into
their original Space. The stack and saved slot clear when that window closes.
Private close/Undo state remains in that private store and ends with it.

## Close Undo

Committed ordinary Today close, Clear Tabs and folder deletion participate in
Undo/Redo through the same retirement and restoration owners. Background closes
do not steal selection. Pinned items unload in place. Redo requires the original
post-Undo state and fresh close consent; a changed or newly pinned item refuses.

A close arriving during pending Redo preserves ordering after successful Redo,
and clears the Redo branch if it is refused. Closing a split's sidebar anchor
keeps surviving panes in that sidebar slot. Library restoration, Undo and Reopen
must invalidate each other's stale alternatives rather than duplicate items.

### Back/forward history

Tab Undo/Reopen and reopened Peeks restore committed navigation entries and the
current index through an opaque native navigation state. The new WebContents
belongs to the original Profile. A mismatched Profile or expired private context
refuses before creating a page and falls back to the address-only route. A
failure after native insertion closes that new page and reports the error.

`ClosedPageHistory` is memory-only, bounded to the newest 100 entries. The page
owner captures it at retirement and publishes it only after actual closure.
Only Undo/Reopen consumes it. Normal opens, transfers, saved-tab unload and
Library Put Back cannot later reuse stale history.

Regular Profiles also persist navigation archives in `<root>/Tab History/`:

- Save version, index and bounded length-prefixed entry records, including
  Chromium's saved scroll/form state. Refuse malformed or trailing data.
- Write two seconds after navigation/load changes, on app deactivation, and on
  Quit before closing pages; hash unchanged records to avoid rewriting them.
- Restore only the first page for the same tab, address and persistent Profile.
- Drop records on tab close/reset, relevant pinned-to-Today moves and history
  deletion; prune deleted/archived tabs and all records when restore is off.
- Private pages have no persistent archive. Older engines without the native
  methods retain address-only behavior.

Scrolling alone and window close do not trigger an archive write. After a crash,
scroll state is therefore only as recent as the last saved navigation record.
History deletion clears stored archives; live pages retain their navigation
lists and can later write them again as a live session.

## Related restoration paths

Restoring a closed record preserves its original creation/referrer identities
and marks selected items read. [Folder commands](folder-commands.md#selection-after-ordinary-delete)
describe close-time successor selection and the window's referrer pool.
Library Put Back has its own [archive restoration](archive.md) path; it does
not consume this window's nested-folder Undo/Reopen record.

## Validation

`bash scripts/test-close-undo.sh` uses temporary stores and real Undo owners for
consent, ordering, split regrouping, two-window/Space isolation, stale records,
save failure/retry, Peek dismissal and private in-memory behavior.
