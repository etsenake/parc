# Reopen Closed Tab

The existing File command, Cmd–Shift–T and command-bar action now read the initiating physical window’s close cache. They first reopen that window’s last eligible closed saved tab, then take the last step of its most recent manual Archive group. A fresh window does not acquire another window’s history by scanning the durable Archive. The separate Library Archive remains available for persisted items.

## Reference contract



Evidence is retained under `work/native-reopen-closed-completion/evidence/`, including the entry, producer, typed field decoding and full Mach-O assembly. No additional appearance comparison or browser functional test was performed for this batch. The existing command surfaces are retained; no new visual or motion equivalence is claimed.

## Production ownership

`WindowClosedItems` belongs to one `BrowserWindowController` and is cleared with that original window. A committed close records exact post-close model values, original Profile/Space and, for a complete archived Today split, its original group ID, child order, orientation and widths. Single saved-tab close replaces the priority slot. A committed saved-only collection now chooses one original target by descending activity in the initiating physical window. Missing activity dates are distant past; equal dates retain stable model order as an explicit Parc tie adaptation. Shared tab access dates, archive-protection refreshes and other windows do not rank this command. Actual manual Today close groups keep their separate existing stable model step order.

Every shell close path in this slice uses the existing shared whole-set retirement coordinator, including beforeunload consent and original child-page retirement. A refused, canceled, partial or stale transaction does not create a reopen capability. Closing a saved item retains its existing saved destination and unload/reset semantics. Reopen creates the normal page owner for the original saved record after its prior owner has closed; it does not resurrect a destroyed WebContents, transplant a live page or duplicate a tab record.

The command first validates the original Profile/Space and exact post-close item values. It then requires each target to be unclaimed and absent from the initiating window’s live wrappers, with no retirement or transfer underway. A valid but temporarily busy top item remains at the top. A removed or changed durable record expires. An archived split must remain absent before restoration. A saved split must instead still be present with exactly the original ID, members, title, orientation and ratios; Reopen selects that retained group without appending or replacing it. Changed, dissolved or newly overlapping groups expire the capability.

`BrowserStore.restoreClosedItem` commits the targeted current-state change durably before publication. Only successful persistence consumes the window’s record. Save failure preserves both the archived model and the retryable record. Original selection is restored through the existing physical-window presentation and native selection owner. This is a targeted transaction, not a whole-store undo snapshot.

## Bounded support and remaining work

Supported here: single and bulk saved-only close with one window-recent priority; whole retained saved split selection; original Note/Easel alias identity; manual ordinary Today close steps; complete original Today split close/restore; partial Today split rejoin/regroup ([below](#partial-split-reopen)); closed Peeks and folder deletions ([below](#closed-peeks-folders-and-the-cache-lifetime)); original-window priority/order; exact Profile/Space and item validity; explicit restored-item focus; consent/cancellation; permanent removal expiry; save failure/retry; and cache disposal on window close. Normal profiles are supported; this slice does not add private-window history.


## Validation

The private exact-source app cohort and standard model runner are checked without launching a browser. The new model suite exercises independent physical-window caches, saved priority, stack consumption, original split restoration, stale/cross-profile rejection, existing retirement refusal, save failure/retry and durable restoration. Check receipts bind all source/header inputs and report actual exit status; compiler success is not runtime or whole-NAV-04 acceptance.

The merged 81-source Swift app passes with zero diagnostics (119.79 seconds). Exact production component inputs retain 696 BrowserStore, 23 Folder Undo, 37 profile model, 17 profile retirement-controller and 41 ClosedItems assertions. The combined source preserves auxiliary Easel page retirement and consumes saved-tab reopen priority before the embedded-page selection return. No browser was launched for these checks.

## Bulk saved Close → one Reopen target




Only a committed original retirement invokes cache recording. Notes draft/composition/save barriers and native beforeunload continue through the existing whole-set coordinator. Visiting a retained group child consumes its saved priority; stale original records expire rather than falling through to another saved candidate. A consumed or expired saved target resumes the pre-existing Today stack. Local documents and their shared sessions/assets are not copied, deleted or rewritten. The focused component covers original-window versus shared recency, equal/missing dates, a single saved slot, original typed split identity and persistence, consent refusal, stale groups and save failure/retry.

The bounded bulk-saved increment passes the complete 128-source app compiler with warnings treated as errors and zero diagnostics. The actual store/cache component now passes 73 assertions, with fresh 36 keyboard-close, 41 plural-removal and 34 mixed-document assertions. Exact command inputs and private headers are bound to the frozen source; no engine code changes. These checks do not replace visual/runtime acceptance.

## Partial split Reopen


### Reference contract




### Production behavior


`BrowserStore.restoreClosedItem` still un-archives the original record first, then applies the membership in the same durable commit:

- **Selection.** The rejoined split is selected with the reopened pane focused, through the existing physical-window presentation and native selection owner. Survivors keep their live pages; the reopened pane gets its normal new page owner.

The saved-item priority path, complete-split steps, Archive Library Put Back and stack order are unchanged.

## Closed Peeks, folders and the cache lifetime

### Reference contract



### Production behavior

- **Lifetime and ordering.** Close steps and the saved slot stay in process memory owned by the physical window and clear when it closes. Steps from every Space share the one window stack; each restores into its own Space. A window session record now also saves its independent item activity dates at subsecond precision, and the single restored window seeds those dates for bulk saved-item ranking. Older records and new windows start with no saved dates; ties or missing dates retain model order. Restoring the other window records belongs to Windows and lifecycle.


### Checks

`tests/ClosedItemsTests.swift` now has 160 assertions. The partial-split set (64 added earlier) gains a regroup skipped by a grouped survivor. New: the Peek step and its parent, URL scheme and Profile-removal validity, saved-slot precedence, expiry of an archived parent, a folder Delete restored with its collapsed flag and children, saved priority replaced by a folder step, and Undo-first expiry. `SidebarKeyboardCloseTests` still passes. The whole-app Swift typecheck passes with warnings as errors. The engine source is published for the next overlay apply and was not compiled here; overlay hashes were updated and all 262 entries match. No browser functional test ran and Parc was not launched.

## Close Undo


### Reference contract



### Parc


- **Undo** restores each closed tab still in the Archive from this close, by the identity an Archive preview checks (ID, Profile, Space, creation and archive dates, provenance). Only its place and archive state return (archive date, provenance, section, folder), so a title or address edited in the Library since, a Note's for example, is kept. It returns to its container at its position anchored by surviving neighbours; a split closed whole regroups with its ID, title, icon, orientation and widths when every pane returns. A pane closed out of a split that kept others rejoins it at its index, share and sidebar slot, or regroups the split this close dissolved, and that split goes back to its place, even when another window shows the split's other panes, as after a Library card Clear (which clears only this window's tabs); selecting the split then brings those pages here. Only panes that are closing or mid-move between windows stay apart. The window then selects the tab that was focused when it closed, through the same owner as folder Delete's Undo (`WindowPresentation.finishClosedTabsUndo`), switching to its Space; any other close leaves selection and Space alone. It is one durable write before publication; a failed write leaves the tabs archived and the Undo retryable. A tab reopened, put back, deleted or archived again since stays as it is; a split that can't regroup returns its panes alone in its slot. An archived item open in a Library preview waits.
- **Private windows.** A private window's close removes its tabs. Its group keeps the removed records; Undo puts them back in place, each with its back/forward entries, and Redo removes them again. A private Clear shows its toast, and a private Peek dismissal undoes too. Reopen Closed Tab still keeps no private history.
- **Lifetime.** Per physical window, in memory, cleared when the window closes. Quitting leaves the tabs in the Archive, which is consistent. An entry stays while any recorded tab can return; Undo expires the close's Reopen steps because their afterimages are gone.
- **Adaptations.** Like every shortcut toast, the undo toast also closes when a keyboard binding changes.


### Back/forward history


- **Engine (overlay 301).** `-[PCNativePage captureNavigationState]` serializes the page's committed entries (`sessions::ContentSerializedNavigationBuilder::FromNavigationEntry`, skipping the initial entry) and the current index into an engine-internal `PCNativeNavigationState`, handed to the app as an opaque `NSObject` so the app links against older engines. `-[PCNativeBrowserWindow openNavigationState:profilePath:container:background:completion:]` builds new contents from it (`ToNavigationEntries`, `NavigationController::Restore(index, RestoreType::kRestored, …)`), inserts them into this window's Browser for that Profile (this window's own private Browser in a private window) without loading an address first, calls `LoadIfNecessary` and attaches the page as `openURL:` does. `-[PCNativePage openPeekWithURL:navigationState:]` builds the restored contents with the same parent provenance a created Peek carries, inserts them as the parent Browser's active tab, and the usual reconciliation offers them as that parent's Peek. A value from another Profile, or a private context that has closed, is refused before any page exists (error code 1): the tab opens its address alone, the Peek opens through `openPeekWithURL:`. A failure after the contents were inserted closes them through `TabStripModel::CloseWebContentsAt`, as a refused embedded page is, and reports error code 2, which the app shows rather than retrying.
- **App.** The window that owns a closing page captures its entries when the page's retirement begins and, once the page actually closed, hands them to the store's `ClosedPageHistory` (memory only, never in the session file, the newest 100), so whichever window later restores the tab by Undo or Reopen gets them, as after a Library card or folder preview close of another window's page. A private window's store, and so its entries, is its own and ends with it. A Peek's entries are captured when its dismissal starts. Only a tab Undo or Reopen restores uses them: `-[PCBrowserView restoreNavigationState:url:]` replaces that tab's first `loadURL`. A pinned tab's unload, or a tab put back from the Library, opens its address as before, and a page created for the tab any other way (a background open, a transfer) drops its restored entries, so stale ones can never be applied later. Each call checks `responds(to:)` or `instancesRespond(to:)`, so an engine without them opens the address alone.

### Checks

`bash scripts/test-close-undo.sh` (also run by `scripts/test.sh`) drives real temporary `BrowserStore`s and `FolderUndoManager`s. The Clear set is unchanged: consent refusal, the clear-button archive and whole-split archive item, untouched pinned items, folders, other Spaces and earlier archives, Undo Clear Tabs / Redo Clear Tabs titles, exact records, split geometry and order after Undo, no selection change from another Space, the durable write, Reopen expiry, Redo refusal and manual-reason Redo, Undo after Redo, two Spaces in one window (last first), two windows, Reopen-then-Undo-then-Redo, Put Back-then-Undo-then-Redo, archive deletion, a tab edited or archived again since, a split that cannot regroup, a tab opened since, a failed write and retry, Redo retirement, a Clear of the selected split undone with its Space active, a pane rejoining its surviving split and regrouping a dissolved one, Redo's commit check failing once a tab is pinned, and the Library case. New: ⌘W on the focused tab (Archive Tab, manual reason, the window selects it on Undo, Redo and Undo again), a background tab's close (no selection), a pinned tab's close (no group), a pane whose close dissolves its split (Archive Tabs, the other pane keeps the slot, Undo regroups in place), a pinned Note (it only unloads, with no group), Clear then ⌘W (the later close undoes first), a close committing during a pending Redo (joins after it, below the redone close) and during a refused one (clears the Redo), a private window's close and Clear (records removed and restored, Redo removes again), and Close Peek (open failure, Undo remembering the Peek it opened, Redo closing exactly that Peek while another sits over the same parent, refused and accepted Redo, the new record, Reopen taking it, a reopened Peek that left some other way, an archived parent), a Clear that takes the focused Today tab (Undo reselects it), a pinned tab closed with a Today tab (only the Today tab archives and returns), and the closed-page history cache (restore-only use, once, the 100-entry limit, a fresh close resetting it, a failed Reopen). `tests/FolderUndoManagerTests.swift` adds a group waiting on a pending Undo and dropped by window close, and `testClosingSplitAnchorKeepsSlot` in `tests/BrowserStoreTests.swift` reproduces the split jump (it failed before the fix) for a split out of view, its dissolution and the split in view; its Easel test now expects a pinned Easel, in a folder or a pinned split, to unload in place. No browser was launched.
