# Folder commands

The folder **Duplicate** context command copies one original saved subtree in the same Space and Profile. It retains folder names, nested and empty folders, mixed folder/tab/split order and each split's orientation, ratios and mapped anchor. Every copied folder, saved tab and split receives a fresh sidebar identity. Note/Easel items retain their original validated document identity, as described below. Original saved records, live pages, selection, close consent and history remain owned by their existing objects.

The complete tree is saved atomically before publication. A stale hierarchy, changed saved-item snapshot, foreign Profile, source retirement, malformed/cross-container split, invalid destination or disk failure refuses the entire model copy. Native context classification also rejects private/mixed windows; a normal window containing only unmaterialized saved items remains eligible. The one-shot menu or accessibility action retains the originating window, Space, Profile, original item/native owners, focused pane and selection. It never redirects to another window's active tab.

For an original materialized page, the new saved destination is that exact page's current URL. Otherwise it is the original saved URL, not a persisted last-live URL or another selected page. Saved title and mute state are copied. Ordinary copied tabs stay unmaterialized until selected. Ordinary web split children request fresh background pages after the save; typed Note/Easel children remain local document references. The model returns those exact new IDs; the window creates fresh `PCBrowserView` wrappers in its hidden owned page container and the native bridge uses `WithNativeRoutingBrowser` to acquire the actual Profile and physical window. This existing factory reserves the binding during asynchronous Profile acquisition and constructs a first Browser without calling Show. `AddAndReturnTabAt(..., false)` then uses Chromium's real new-tab navigation and page attachment. No original WebContents is transplanted, reloaded or closed, and no POST/body/history clone is claimed.

A first empty Browser's TabStrip necessarily gains an active tab, but its native Browser remains unselected and hidden. For an existing Browser, the background insertion leaves its active tab unchanged. The ordinary native layout/selection owner remains authoritative: the copy command does not select then restore. Page-creation refusal leaves the already saved copied tree intact and uses the existing page failure/Retry and close owners. Actual creation is not promised merely because the model committed. The facade retains the existing pending-close lifecycle during asynchronous creation, and native attachment revalidates the exact container/window/Profile. Global quit and Profile removal reject creation.

## Folder row, creation and rename



## Folder context menu and icon



## Peeked folders


## Reference and adaptations





## Remaining commands

The context command supports one original folder subtree containing ordinary tabs, intact splits and validated Note/Easel references. Plural same-Space context roots are implemented below. Cross-window/Space/Profile context copies, Favorites/app-tray context entry and additional custom icon/title presentation remain separately scoped. The command-bar route below has its own ordered-collection/same-profile Space eligibility. No independent document-level clone action is claimed.

The literal **Delete** context command and **Delete Folder** accessibility action now implement the ordinary-folder deletion branch. The former Remove/reparent operation is retired. The originating window presents **Delete your “name” folder?** with “Deleting this folder will archive the tabs inside it.” and Delete Folder / Cancel. It binds the original folder, nested/empty descendants, exact tab records, mixed order, complete split groups, Space/Profile, selection/focus and native page owners. Cancel rebuilds its one-shot menu/AX capabilities. Changed hierarchy, removed Profile, retirement, pending native creation, private/mixed contexts and invalid typed-document references refuse. Validated Note/Easel descendants use the reference-preserving route below.

After confirmation, every original descendant page joins the existing native whole-set retirement transaction, including owners in other windows and their Peek children. Chromium's genuine beforeunload decisions precede the final originating-window/model revalidation. The saved tree remains intact until retirement completes. One durable model transaction then deletes the subtree's folder records and archives its original tabs as manual entries in the original Profile/Space. Complete splits retain original IDs, order, orientation and ratios through Archive provenance. Unrelated siblings retain mixed order; no child is reparented into the visible sidebar and no page is recreated. Folder records themselves are deleted, so restoring archived tabs uses the existing compatible-Space/root restoration owner, without inventing a folder archive. The archive preserves original saved tab kinds and destinations. Folder IDs are cleared on archived records, stale container-order entries are removed, and selections cannot retain deleted children. Persistence failure retains the saved tree and surfaces the error even if its approved live pages have already closed.


The remotely gated folder-archive mode and its folder restoration are distinct remaining work; its deployed default was not established and Parc does not claim to implement that branch through Delete. Plural Delete is implemented below; toast, exact native alert styling/motion and empty-folder confirmation elision remain separately scoped. Parc currently confirms all eligible ordinary folders with an AppKit warning sheet and destructive primary button, and uses the supported original-window replacement selection described below; no browser appearance or execution acceptance is claimed. Open/group-opening semantics likewise remain separate from Duplicate's recovered shouldOpen options. Current folder Copy All Links, bulk disclosure, hierarchy moves and original selected-item Close have their own implemented owners.

## Checks


The Delete follow-on passes the actual BrowserStore component with 598 assertions, including original-owner refusal, beforeunload cancellation, stale/reentrant intent, one-shot completion, nested/empty folders, exact split archive/restoration, untouched siblings and durable-save failure. The full 72-source Swift application passes with zero diagnostics; no functional browser tests ran.


## Selection after ordinary Delete

Delete and ordinary original-item Close capture the originating physical window's selected tab IDs, focused pane, referrer pool and previously selected original item before the existing close transaction. Background removal preserves that selection and first responder. Surviving original panes retain focus. If no selected pane survives, the decision first prefers an adjacent child whose actual creation referrer is the closing tab, then a subsequent pooled sibling with the same referrer, then the actual pooled item that was active before creation. It next prefers the actual previously selected item when its outer Space/Profile container matches, then falls back to the previous/next whole sidebar item and finally descending last-active date. Traversal uses original mixed pinned/Today order, descends collapsed folders and keeps a split as one item. Closing descendants and unavailable original page owners cannot become replacements. No URL comparison or replacement-page clone supplies provenance.

The proposed decision stays bound to the exact hierarchy, Space/Profile, original selection/focus, pool and available page owners throughout native close consent. Folder Delete's existing durable save commits archives, folder removal and replacement together. Ordinary tab Close publishes its archive/reset and replacement in one model update and retains its existing deferred persistence schedule; this does not claim a new durable-before-close transaction. Refused consent or changed ownership/selection cannot publish an early replacement. Only the original `WindowPresentation` consumes the completed decision; other windows remove closed IDs through their existing owners. A newer original-window Space or page selection cannot be overwritten by delayed completion. The existing render/native-selection owner materializes or focuses the actual saved replacement, and an empty selection shows the window's [empty content](window-appearance.md#a-window-with-no-tab).

### Original creation and window-local referrer pool

`BrowserTab.referrerID` and `activeTabBeforeCreationID` now carry optional original saved identities. Existing sessions decode with nil fields. The actual initiating window supplies a validated creation receipt to command-bar foreground/background/split creation, external/scripted/Library/recent-page opening and original native new-page adoption. An explicit original source sets both fields to that source; otherwise the actual creation-active item sets only active-before. Same-Profile validation runs again at insertion. Native `PCNativePage.creationSourcePage` uses the original source WebContents, primary document, Browser, Profile and physical binding at adoption. Ordinary foreground/background OpenURL requests retain their full original parameters and callback; the carrier associates only the actual returned WebContents. Expired, subframe and cross-Profile sources stay nil rather than guessing from the later selected tab. Unrouted adoption then records the adopting window's current item as active-before, the creator's nil-referrer rule; a routed page does not, as described below. A page created from an accepted Peek takes that Peek's parent tab as referrer. Same-Profile matched-route adoption can carry the original source across physical windows as described below. [Today placement](#today-placement-and-modal-source-creation) covers where created tabs enter Today.

Plural Duplicate and command-bar copy-to-folder also bind the actual initiating window. Fresh copied records clear inherited referrers and carry that window's creation-active item, while retaining the existing atomic copy and background split-child creation policy. The recovered duplicate constructor supplies nil referrer and independently resolves the original current item; it does not copy the source tab's return chain. The saved-only insertion remains pool-neutral. An accepted shouldOpen request enters ordinary TabCreation and updates the same physical window’s pool; recent-page Duplicate and eager background split/ordinary-root requests now carry that update. A later native creation failure remains a real failure, not a claimed load.

Each physical `WindowPresentation` owns an ephemeral referrer pool. Explicit-referrer creation unions the source/new pair into the existing pool; a nil-referrer creation with an active-before item replaces it with that pair. Missing both leaves it alone. Selecting an item outside the pool clears it; selecting a pooled Favorite or pinned item reduces it to that singleton; pooled Today selection retains the chain. Parc updates this on actual focused-item changes, without treating repeated render/ACK refreshes as fresh selection. The pool is not reconstructed from all available tabs or persisted across process restoration.






The additional same-container follow-on passes the full 138-source Swift application compiler with warnings treated as errors and 51 actual model/window assertions, plus the exact existing 49 provenance, 39 folder-copy, 35 plural-duplicate, 696 store and 114 window assertions. It covers actual asynchronous close refusal/approval, stale return revocation, durable cross-Space selection, whole split geometry and Folder Delete returning across nested folders. No native API change or browser functional test is involved.

Checks for the preceding creation-carrier slice: pinned native link-routing translation unit and complete 138-source Swift application compile with zero diagnostics, Swift warnings treated as errors. The actual model components pass 49 creation/pool/focus assertions, 39 folder-copy, 35 plural-duplicate, 696 store and 114 window-presentation assertions. They cover stale/foreign receipts, old-session decoding, explicit/nil creation, pool transitions, actual close refusal/commit, later selection, split ownership and fresh duplicate provenance.

## Ordinary Delete Undo and Redo

A successful ordinary Delete registers a window-owned **Archive Tab / Archive Tabs** undo group. Edit > Undo and Command–Z restore that group's original folders, nested/empty descendants, saved tab identities, mixed child order and split identity/geometry. This uses the actual archived afterimages left by the approved deletion. It does not restore a blanket browser-state snapshot, fabricate a folder archive entity, reopen an independently restored item or reuse destroyed WebContents. Only the originating physical window selects the original focused item when the record says it was focused at close. Background folder undo preserves the current selection and first responder. Other windows reconcile saved metadata without adopting the restored selection.

Every restored tab must still equal its recorded archived afterimage, the original Profile/Space must exist and remain usable, restored folder/split identities must be absent, the original parent container must exist, and native ownership must permit the saved IDs. Independent Archive restoration, permanent deletion, changed originals, Profile removal or a missing parent invalidates that group. Unrelated saved items, sibling edits, history, downloads and current window selections survive. The root returns relative to surviving original siblings; its exact original mixed internal order is restored. Preexisting archived records whose deleted folder reference was cleared regain that reference only if the rest of the exact archived record is unchanged. Persistence failure leaves the archive/tree unchanged and keeps Undo retryable.

Redo reconstructs a genuine close action for the same original tree and member IDs. Normal title/navigation changes remain valid; added/reparented children or changed group membership refuse rather than close unrelated pages. The original native whole-set retirement/beforeunload transaction runs again, with current window selection and replacement-owner validation. It does not repeat the already accepted folder confirmation sheet. A cancelled close or save failure leaves Redo available. A successful Redo records its new exact archived afterimages for the next Undo. The history position moves only after actual completion, and a pending transaction blocks both directions. Menu commands bind the exact entry and history revision; duplicate, stale and prior-cycle invocations cannot consume another operation. Window close drops that window's cache and invalidates pending history completions. Undo history is intentionally process/window-local; the resulting restored saved state is durable.

The native Edit-menu owner is also complete. Chromium's `RenderWidgetHostViewCocoa` implements `undo:`/`redo:` even on noneditable pages. Parc therefore uses `PCNativePage.canUseWindowUndo`, backed by the existing exact ShortcutRouter owner/document/frame/visible/key/security/IME gate and `WebContents::IsFocusedElementEditable()`, to admit the browser-window operation. The application-level window gate also checks actual active/key/visible state and native security reservations for Sidebar or empty-window focus, without requiring a materialized Chromium Browser. Only an admitted original noneditable page or sidebar uses the folder group. Otherwise the menu retains the ordinary nil-target editing action. Command–Z / Shift–Command–Z reuse the genuine pre-renderer document/focused-node shortcut lease, with a group revision checked again at dispatch. Native text fields retain a separate ordinary AppKit UndoManager, Easel retains its own editor/canvas responder and editable web content retains Chromium's edit commands. No unscoped key monitor or synthetic key replay is added.

### Recovered storage and restoration contract




Explicit current-engine adaptations are the typed asynchronous `UndoManager` adapter (AppKit's built-in registration stack is synchronous while Chromium consent is asynchronous), exact archived-afterimage guards, surviving-sibling anchor/clamped-position insertion, native editing admission and tab-count prompt pluralization. No new installed appearance was inspected or changed for this batch. Toast presentation, exact Undo menu/selection motion, reference invalidation/caching bounds, Duplicate undo, remaining modal/cross-window provenance and feature-gated folder archive/restoration remain separate. Mixed typed descendants are covered by the follow-on below. The complete 73-source Swift app and actual pinned native shortcut translation unit compile; BrowserStore (641 assertions), WindowPresentation (114) and the real UndoManager component (23) pass. No functional browser tests or runtime/visual acceptance are claimed.


## Command-bar collection copies

The contextual **Pin to [folder]** row has a distinct force-open copy action. Command–Option–Return copies the original eligible collection to the captured same-profile folder, including whole folder trees and persisted splits, through one new-identity transaction. This complements the single-root context Duplicate owner; it does not broaden that context command's eligibility. The actual original live page URL or saved fallback, indexed first-five eager-root policy and independent split-child eager policy are described in [command-bar copy ownership](command-bar.md#contextual-force-open-copy-into-an-existing-folder). Typed Note/Easel items use the recovered shared-document reference branches below. Duplicate Undo remains unestablished in the inspected original dispatch/copy/insert path; the distinct ordinary-delete Undo owner is unchanged.


## Typed Note and Easel reference copies

Folder Duplicate and Command–Option–Return on **Pin to [folder]** now accept mixed collections of ordinary web items and actual local Notes/Easels. Each copied sidebar item receives a fresh ID, while a typed item retains its original document ID in the original Profile. Opening an alias resolves the same shared `NoteSession` or `EaselSession`; edits, inline-image bytes, imported image assets and Easel embedded-object IDs remain owned by that document. Copying does not finish a text composition, flush an editor draft, replace an embedded page, or create a second document. Ordinary saved-tab Close remains distinct from document deletion.

The native app resolves the exact Profile's existing document store and passes a typed capability alongside the original saved-item snapshot. Pure validation checks the real current file, tombstone state, loaded session and referenced image assets; the model revalidates that capability immediately before publication. A missing/corrupt document, changed store/session, wrong Profile, different document/kind or bare local URL refuses the whole mixed collection. All sidebar/folder/split records commit in one existing atomic BrowserStore save. Document and asset stores are read-only throughout, so sidebar persistence failure cannot leave orphaned copied documents or images. The original hierarchy, window, selection and security/retirement leases remain required.

Existing document deletion already gathers every matching original-Profile tab across Spaces and joins the real whole-set page retirement. It removes the saved aliases before deleting the document; retirement refusal or failed sidebar persistence leaves the document intact. If the subsequent document writer fails, the original Library record remains retryable. A Note tombstone or deleted Easel invalidates every alias. Typed-folder Delete is covered by the following shared-document close owner; no independent document-level clone command is inferred.





## Mixed-document folder Delete and Undo


Delete archives only those original sidebar records and removes the original folder records. It never calls the Note/Easel document writers or deletion APIs. Aliases outside the closing tree, live shared sessions, body/object IDs, inline-image bytes and imported asset files remain intact. Existing whole-set retirement includes actual web pages, Peek children and embedded Easel pages in every physical window. Notes use their actual `prepareToClose` composition/save barrier. The coordinator retains the exact original Note editor objects per window/tab across asynchronous native consent, rejects replacement owners, and repeats that real barrier immediately before unloading and again before publishing the saved close after asynchronous native completion. If a late save fails after actual web-page closure, the folder tree and original draft remain intact while the model transaction reports refusal. A newly composed edit or failed delayed save cannot inherit earlier close permission. This does not replace the Note editor's own save scheduling or Undo owner.

The window's existing Undo record retains validated original document references alongside its saved sidebar afterimages, folder locations and whole-split geometry. Undo restores the same alias IDs and original document IDs; shared document edits made through surviving aliases remain current. Availability rechecks the real stores. A temporarily missing file/asset disables Undo without deleting an otherwise valid history group, so recovering the original data permits retry. Actual document deletion, independent archive restoration or changed sidebar afterimages still invalidates that group. Redo uses the same original typed capabilities, exact current tree and genuine close transaction; only a successful commit replaces the record with the new archived afterimages. The native Edit-menu/keyboard routing and per-window focus transaction remain unchanged.


Parc's durable archive DTO, pure local store capabilities, conservative missing-content refusal and final native-editor barrier are explicit local ownership adaptations. The existing actual document-delete command remains separate and still gathers every same-Profile alias before touching the shared document. No new installed appearance was exercised: retained ordinary Delete wording is unchanged, and the installed reference Space has no named folder demonstrating mixed-document menu/Undo appearance. Multi-root context Delete/Undo, remotely gated folder archives, original next-focus branches, Duplicate Undo, toast and exact motion/AX appearance remain separately scoped.

The fixed 123-source application compiler passes with zero diagnostics. Focused actual-store/native components pass 34 mixed folder assertions, eight Note composition/failed-draft retirement assertions, 696 existing BrowserStore assertions and 23 real UndoManager assertions. They cover exact mixed split/alias identity, genuine asynchronous close callback boundaries, shared edits and image data, real persistence failures, unavailable/recovered assets, Redo consent and actual Library document-deletion invalidation. These checks do not execute Chromium or establish browser runtime/visual parity. All filesystem actions use disposable component directories.


## Plural selected-item Delete and Archive

An original same-Space selection now exposes **Delete** when it contains an ordinary folder, or **Archive Tabs** for tab/whole-split roots, alongside the existing Close Tabs in Selection action. The **Delete or Archive Selection** accessibility action uses the same original target. The initiating window confirms the captured collection. Ancestor folders own nested selected folders/children once; whole splits retain their original IDs, geometry and archive provenance. Favorites and foreign/malformed originals cannot partially participate.

This generalizes the single-folder transaction: one exact page retirement, one durable sidebar/archive save and one original-window Undo group. Every root's original container/order is recorded. Undo restores only those original identities and tolerates unrelated surviving sibling insertions. Redo validates root containers and full descendant membership, then requests fresh original native beforeunload consent; new children and moved roots invalidate it. Notes/Easels remain the same document references, and final original editor identity/composition/save barriers still run across all physical owners. Cancellation, stale selection, missing document assets and save failures leave the complete saved hierarchy unchanged. A late persistence refusal may leave already-approved pages closed; it never fabricates a partial archive or early Undo entry.


Plural prompt text/always-confirm presentation, the tab-only label and AX wording are native Parc adaptations. Retained installed appearance lacked a named ordinary folder or plural selection; no destructive reference action was taken. Exact plural alert/selection/toast motion remains open; the recovered mixed saved-item keyboard branch is described below. This does not implement the separately gated folder-archive entity mode or document deletion/cloning. Focused actual persistent-store/native-Undo and full-app compiler receipts are recorded in the parity ledger; no browser functional acceptance is claimed.


Keyboard Close remains a distinct invocation: saved-only selected roots unload content without removing ordinary folders or whole saved split records; any selected Today root takes the original whole-collection archive/removal branch. The latter reuses this transaction and native Undo/Redo, with the same original Note/Easel references and consent barriers. Folder-bearing keyboard commands confirm; tab-only keyboard commands have no extra Parc warning. Explicit context/AX Delete keeps its independent eligibility and confirmation policy. See [saved versus mixed keyboard Close](sidebar-selection.md#saved-versus-mixed-keyboard-close).


## Plural context Duplicate

The existing selected-item context menu now exposes **Duplicate** and the **Duplicate Selection** accessibility action. One original same-Space/Profile collection may contain ordinary tabs, nested/empty folders, whole splits and validated Note/Easel aliases. Selected ancestors own their selected descendants once. The originating window captures the actual selection revision, hierarchy, saved records and native owners; changing that selection, Space, document capability, page owner or hierarchy expires the command. Favorites, foreign records, pending retirement and partial/malformed splits refuse as a complete collection.

The single-folder entry and plural entry share one durable transaction. It allocates fresh folder/tab/split IDs, retains mixed order, parent placement, split titles/anchors/orientation/proportions and original same-document references, then saves every copied root and affected sibling order before publishing. A failed save changes none of the saved roots and creates no document or asset orphan. Original records, shared editor sessions, selected pages and live WebContents remain intact. The copies use the exact originating materialized URL or original saved fallback. Every copied web split child requests a fresh background page; only the first five ordinary top-level roots request opening, while ordinary folder descendants remain saved-only. Requests follow the original recursive root order. Typed document aliases never become renderer URLs. A native creation refusal leaves the already durable saved copy and the existing failure/Retry owner.


The final fixed 135-source Swift application compiles with warnings as errors and zero diagnostics. Actual persistent-store checks pass 35 plural-context assertions, 45 document-alias assertions, 39 copy-to-folder assertions and 696 existing BrowserStore assertions. The new fixture covers mixed/nested/empty roots, ancestor de-duplication, exact recursive open order, shared typed sessions/assets, actual filesystem failure and durable reload. These are isolated components, not browser execution or appearance acceptance.


### Same-Profile routed creation across physical windows

The original ATC navigation owner now attaches its captured source document/page receipt to the genuine destination page before the original navigation callback or deferred source observation can reenter adoption. Only a same-Profile route receives this receipt. It binds both weak original source Browser and the accepted destination Browser; source document replacement, source owner transfer/close/retirement, target destruction or a different final owner invalidates it. The original `OpenURLParams`, POST body, opener/security decisions and once callback remain under Chromium's navigator. No navigation or page is recreated.

The shell resolves the exact `creationSourcePage` through `PCNativeBrowserApplication.owner(of:)` and that binding's original controller, shared store and page-ownership registry. It validates the original page/view/window and rejects closing, transferring or retiring items. It never reads another window's selected tab as a replacement. Model insertion revalidates the source Profile and live saved identity; only the destination physical window updates its creation pool. Existing close eligibility still refuses an original page owned by another window rather than stealing it.



### Today placement and modal-source creation



## Duplicate Undo investigation boundary

The original context Duplicate producer and saved-item insertion examined here
do not register an Undo operation. This is a bounded mechanism finding, not a
existing ordinary Delete Undo contract must not be reused as evidence for a
Duplicate command. Parc therefore retains its current Duplicate behavior until
a separate actual registration/restoration owner is established.

(`ev_5cd3000bdf8770b1a16816434697740c0104bdfb110e2a6a4c63ec10a14a62b6`)
and full-image metadata resolve its two dependency keypaths to
`ImageCache.FaviconCacheClient` and `AnalyticsClient.AnalyticsClient`, rather
than an Undo manager. The emitted asynchronous callback
`FaviconCacheClient.cacheFavicon` field. The saved mutation passes through
records and applies their placement. These inspected callbacks supply no
Duplicate Undo payload or registration. Higher-level observer behavior and
other entry paths remain unestablished. No production change, browser action
or runtime/appearance acceptance is claimed by this investigation.

### Turn “name” into Space

