# Sidebar item selection

Parc has an ordered, window-local sidebar selection distinct from the original pages currently shown in a split. This slice covers visible Today and pinned rows, folders and whole split containers in one Space. It does not change Favorite tiles, which have a separate reference ownership path.


Rows expose selected state and native accessibility actions. The original active tab highlight remains separate. Context menus on a selected row expose Copy Links, eligible same-Space moves, Close Tabs in Selection and Clear Selection. A selected folder includes its original descendants for copy/close. Keyboard Close classifies the original roots: with no Today root it unloads saved content and preserves folders/bookmarks and complete saved splits; with any Today root it archives the entire original selected collection, including saved references, and removes ordinary selected folders through their confirmation. This is one native consent and one durable archive transaction, not per-tab mixed behavior. An original split is one selected item; its pages remain the same objects. Individual row close/reset/capture controls retain their explicit original target.

Dragging a selected item moves the whole ordered set, with a count in the native drag image. No multi-set is offered to the separate pane split-creation path. Dragging a nonselected item clears the set and uses its ordinary single-item capability. Folder ancestors suppress selected descendants for movement; copy/close deduplicate original tab IDs. Mixed moves stage every proposal, reject the entire proposal on any invalid target/cycle, save once and publish once. No page is cloned, replayed or closed for a move.

## Select All and plural commands

When the sidebar itself is the key window’s first responder, Edit → Select All / Command–A selects its displayed eligible original rows. Collapsed descendants stay hidden, Favorite tiles stay separate, and page/pane selection does not change for a multi-set. A sole ordinary row uses the existing singleton activation route. Text fields, Easel text and webpages retain their real responder-chain Select All. No global key monitor intercepts Command–A.

The same focused multi-set supplies ordinary Copy / Command–C, Copy URLs / Command–Shift–C, Copy URLs as Markdown / Command–Option–Shift–C and Close Tabs / Command–W. An all-Today selection uses the Archive Tabs title. Existing command IDs, custom/disabled bindings, single-page and highlighted-address-result routes are preserved. The explicit URL/Markdown/Close menu actions capture the original selection and native owner capability while the menu tracks. If that selection, hierarchy, window, profile or original page ownership expires, the captured intent is refused; it cannot fall through to a different current tab. Standard Copy remains an actual nil-target responder action. Quote is unavailable for a focused multi-set because this slice has no recovered plural text-selection/quote contract.

Plain and Markdown exports use original sidebar records and the existing folder link format. Selected folders include their original descendants, selected ancestors suppress duplicate descendants, and splits retain original child order. Deduplication uses tab identity: distinct tabs with the same URL remain separate lines. Internal or malformed destinations are not exported. This is an explicit extension of Copy All Links; it does not impersonate the Chromium live-page text/quote clipboard-policy route. Current native-page plain/Markdown/Quote paths retain their existing policy checks.


## Ownership and cancellation

A move capability captures exact originating window, Space, profile, current selection/focus, hierarchy and each original native pane/browser/page identity. It rejects a stale target, foreign window, changed hierarchy, expired profile, transfer, retirement or unavailable native owner. The pasteboard is an identifier only, not authority. A callback cannot use a new selected set to expand its captured grant. A close operation enters the existing whole-set beforeunload coordinator; after admission, the coordinator owns closing pages and the final model gate revalidates the captured Space/profile/hierarchy and active selection rather than incorrectly rejecting its own retirement flags.

The sidebar clears local selection when its Space/hierarchy or active page changes, when its window loses key status, or when it detaches. A folder's expansion or collapse alone is no hierarchy change: as AppKit's outline keeps its selected rows across disclosure (an inert probe, [accessibility](sidebar-accessibility.md)), the set keeps its visible rows, which a folder row's `AXDisclosing` relies on; the folder's own click remains a plain row activation and clears the set. Selected rows that disappear through collapse/removal cannot remain selected. Native menu/AX commands use the same prepared operations. A failed move save publishes none of the proposed placements. The local set is deliberately not restored from session storage.

## Reference and adaptations



REA records `ev_3ce4fff41291cbec820dc5cd9ff8766ff3aa0bc17e1dcc21e93e72d8aad8bd3a` (proposal policy) and `ev_4719a6a4f51a236c16266490cc04fdfc10ba6fa29c8bad13c1f8f44c58c08650` (complete selected-rows notification control flow) retain the bounded analysis. The policy raw-binary decompilation truncates at an unbound external call; the corresponding full-image assembly/import and Swift metadata records establish the mechanisms above. Generated pseudocode is not original source.



## Selection-command reference and adaptations





## Checks

The model suite passes 540 assertions, including the prior 26 selection/movement checks and 12 added visible-row Select All, stale/foreign-profile export, ancestor/ID deduplication, split order and serialization checks. The copy-command component passes 25 default/migration assertions, including recovered Close Tab priority, preserved user choices, fixed responder Select All and reset behavior. The full 69-source app compiler check passes with zero diagnostics; exact inputs and receipts are retained with the immutable candidate. No functional browser tests were run; source/component/compiler completion is distinct from integrated runtime and exact visual parity.


### Explicit Delete/Archive of the original selection

The plural context menu now adds Delete for selected ordinary folders or Archive Tabs for tab/whole-split roots, plus the corresponding AX action. It captures the original selection revision/window/Profile/Space and complete hierarchy; a selected ancestor suppresses its descendants. The existing Close command and Delete key retain a distinct invocation; their saved-only versus mixed-collection branch is described below. Explicit Delete/Archive shares the single-folder native retirement, typed-document barriers and durable Undo/Redo owner; see [plural removal](folder-commands.md#plural-selected-item-delete-and-archive).

A command may retain its original selection only while its own confirmation/beforeunload sheet takes key focus. An actual selection change, window detachment, ordinary key loss outside the owned sheet or changed original hierarchy expires it. Context execution never falls through to a new active page. The plural prompt/AX labels are source-owned adaptations; modern multi-selection appearance remains unverified. The recovered original saved-item keyboard branch and its remaining Reopen boundary are described below.


### Saved versus mixed keyboard Close

Cmd-W and the existing focused-sidebar Delete-key/Close Tabs in Selection route now use `SidebarKeyboardCloseTarget`. Exact root/Space/Profile snapshots distinguish saved-only deselection from any-Today whole-collection archive. A saved split remains the same sidebar object after all members unload, with original title, ID, order and geometry. Selection revision is retained only through the command's own sheet and rechecked before model commit. The existing actual native page, Note composition/failed-save and shared-document alias barriers are unchanged.

Any Today root, including a Today split, sends the complete original collection to the same durable archive/removal and window Undo/Redo transaction as explicit Delete. A tab-only keyboard close has no added warning; a folder-bearing close retains ordinary folder confirmation. Explicit context/AX Delete remains separately available and keeps its prior confirmation policy. A refused or stale set never falls through to the newly focused tab.


Bulk saved Reopen now follows the recovered complete-deselect consumer: one most-recent eligible original item in the initiating window, with unchanged whole saved splits retained. It does not create a bulk saved stack; see [Reopen Closed Tab](reopen-closed-tabs.md#bulk-saved-close--one-reopen-target). Empty-only folder deselection, Favorite/app-tray selection, cross-focus selection, exact modern plural appearance/motion/haptics remain separate. No functional browser or personal-content operation ran.

Committed keyboard archives retain the existing exact-window Today Reopen steps, including whole split geometry and original focused pane. Saved references archived by a mixed command use the complete Undo record; the independent saved-only Reopen slot uses its recovered window-recency consumer.

## App-tray move boundary

Favorite pointer selection remains the dedicated AppTray phase owner: Command reset and Shift activation do not create outline range/multi-selection. Individual original Favorite tiles and whole Favorite split roots now carry the shared one-use move capability; ordinary selected collections may move into the tray only if every root is eligible and the twelve-root limit admits the complete result. Profile-wide tray order and groups feed actual positional/Control–Space selection. Folder, cross-Profile and external/copy sources refuse. See [Favorite moves](folder-moves.md#favorite--app-tray-moves) for exact native/editor lifetime, evidence and appearance limits.
