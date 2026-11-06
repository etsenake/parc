# Easel embedded page ownership


## Reference and adaptation


The current Chromium adaptation uses an actual background `TabInterface` in the exact native Browser, with an explicit auxiliary provenance flag. This retains Chromium's ordinary navigation, renderer, Profile, permission, dialog, media, security and beforeunload owners. It does not add a saved Parc tab. A per-content session omission flag prevents the auxiliary renderer from becoming a restored ordinary tab or closed-window/group/split entry. Original extension/window IDs and actual navigation data remain truthful; regular webpage history and Profile storage retain their upstream behavior.

## Admission and lifetime

`PCBrowserView.beginEmbeddedNavigation(_:validateOwner:completion:)` returns a `PCNativeEmbeddedPageRequest`, or nil when the wrapper has no eligible registered window. The wrapper must already occupy its original Easel canvas. The request invokes a pure main-thread app validation before context preparation and again after asynchronous Profile acquisition. The app binds window, Space, Profile, document revision, object identity and authored URL. Reentry is followed by another native ownership check. No requested URL loads before admission.

Cancellation marks the request settled immediately and delivers its cancellation callback once on main. A queued Profile callback then cannot create content. Once admitted creation begins, cancellation cannot claim that the content never existed: the result is the actual `PCNativePage`, and callers use real page or whole-set retirement. The real initial empty renderer is classified and attached before its requested URL navigates exactly once. Failed attachment retires that actual empty renderer without force-closing unrelated pages.

`isEmbedded` is stable page provenance. `embeddedOwnerValid` binds the original Browser, Profile and physical window through weak native identities; parking a view does not invalidate it. Ordinary cross-window façade transfer remains refused. A native ownership change publishes a page update and revokes the old lease unless it is the explicitly admitted collection transfer below. Embedded content remains excluded from ordinary `containerForPage` adoption after detach/reconcile. Hiding preserves the same wrapper and live page.

The native factory supports the exact existing off-the-record Browser identity without resolving its regular parent. The current Easel authoring/persistence shell remains regular-profile scope; this backend does not expose private Easel persistence.

## Input, presentation and retirement

The Easel owner contributes actual visible child pages to `visibleNativePages` and its single interacting child to `selectedNativePage`; it then calls existing selection/layout reconciliation. Selected object state exposes the native content; deselection restores the canvas blocker and first responder. Embedded Back/Forward/Reload/Stop use the existing guarded native navigation actions. The legacy page entry points additionally require the exact embedded owner and native selected-page/security state. Existing site-info, permissions and dialogs keep the original physical window and Profile. Fullscreen is only accepted if the actual shell callback can host it.

The app routes selected/closed callbacks for auxiliary pages to their existing Easel object, never to a new saved tab. Original new-content requests still use Chromium's normal creation path and shell adoption with intact request/opener/security data. There is no URL-only replacement of a created page.

Removing/replacing browser objects, Undo/Redo and closing the parent tab include all original child pages, including views in other windows displaying the same document. The app's exact-snapshot mutation gate invokes `requestClosePages` and commits only after actual retirement succeeds. Synchronous document replacement or deletion is refused while affected child pages remain; a separate document-deletion interface is not supplied by this batch. Hiding/switching an Easel does not close its children. Native whole-window and Profile retirement already enumerate these actual Browser pages. Refusal, navigation during consent, independent destruction and partial outcomes retain their existing transaction semantics.

## Checks and limits

The candidate checks actual pinned native application/page/host and four session translation units, the Objective-C façade and a complete Swift application cohort. An isolated native component uses the exact production request-class fragment to check pending cancellation, asynchronous delivery, cancellation after commit and once-only completion without creating a Browser, WebContents or profile. Compiler/component checks do not claim runtime, appearance or motion acceptance. The paired canvas integration supplies object UI, shared-document mutations, focus and lifetime consumers; this engine slice does not independently establish full Easel parity.

## Physical-window collection transfer

A same-Profile folder/whole-split move captures each original Easel editor's pool, object records, wrapper/page identities and a one-shot generation. Pending creation, retirement or another transfer refuses the entire collection. Existing regular and auxiliary pages enter one `TransferLiveTabs` operation; a successful native insertion may rebind the embedded lease only after the real CEF host, TabInterface, destination strip, Profile and supplied NSWindow agree. The page's embedded/session-omission provenance and original WebContents remain unchanged. Rollback applies the same check in reverse. No captured URL is loaded and no provider/page is reconstructed.

The shell moves the original editor subtree, attaches each surviving original child view, and rebinds the retained pool's callbacks to the actual destination. Pool input and shared destructive edits stay gated through native settlement; only after all children and collection claims agree are the one-shot gates released. A destroyed child is accounted for without releasing its parent sidebar claim. Uncertain ownership retains the existing collection recovery reservation and offers genuine retry or close consent. Failed destination creation does not close a caller-owned NSWindow merely because its native strip is empty.


The fixed follow-on checks the full 136-source Swift cohort and both actual pinned application/page native units with zero diagnostics. `tests/EaselPagePool/run.py OUTPUT_DIRECTORY` compiles the actual pool, canvas and durable shared session with hidden AppKit windows and injected engine replies, then runs 32 assertions. It covers original identity, pending creation, source/destination and generation guards, pure gate release, rollback, metadata callback rebinding, shared replacement refusal and real closed-child accounting. It performs no real browser navigation. Cross-Profile relocation is specified below; exact installed drag/focus/motion/AX appearance remains separate work.


## Cross-Profile relocation — EASEL29

Included Easel moves use the existing inter-Profile decision and durable
`moveAcrossProfiles` transaction: sidebar collections, splits, Space assignment
and Space-to-folder conversion all reach that same boundary. The original child
pages retire through genuine native consent before the document changes Profile.
The destination opens a new auxiliary page under its own actual Profile from the
durable browser URL. Cookies, authentication, navigation history, permissions and
renderer identity never cross the Profile boundary. Same-Profile physical-window
transfers above keep their original page; that path is unchanged.

returns `WindowAction.deleteAndReloadWindowContentsFor` after the inter-Profile
loss-of-progress warning, optional remembered decision and reload effect.
and browser identity. These establish document continuity with destination
Parc's explicit session retirement and per-Profile file relocation are local
adaptations to its already established storage model.

The native shell captures the exact original Easel editor set before asking to
retire pages. Every original editor must be free of marked text, an unfinished
pointer gesture or an open webpage input. It finishes the same durable text-edit
boundary used by EASEL24; a rejected empty-text save keeps the editor and refuses
the move. Admission is checked again before native unload and after completion.
A newly opened/replaced editor cannot inherit an earlier editor's approval.
Pending page creation refuses, and EASEL23's live cards participate in the same
`pages`/`hasPendingCreation`/`disposeAfterClosure` pool interfaces.

Only after all original editors and native pages close does the source store
explicitly retire its session. Late AppKit/Combine/native callbacks may still
retain that session, but can no longer save, navigate metadata, import assets or
callback synchronously. A new destination session retains the exact document
and object identities, authored/current browser URLs, captured provenance and
original PNG bytes. A failed subsequent state save reverses the file move; a
fresh source session resumes editing while the retired session stays revoked.
Failed closure/relocation also refreshes the affected source editors, including
static Easels/Notes that have no native page-completion callback to redraw them.
Mixed Note/Easel collections apply the same narrow source-session revocation to
already-flushed Notes, whose existing native close transaction retains editors
until completion returns.

Referenced image assets are copied with unchanged bytes. A preexisting asset
name is reusable only when its bytes match; a collision refuses the move while
preserving both stores. Rollback attempts every document reversal before any
asset cleanup. It removes newly copied destination assets only when the entire
collection reverses successfully. Any failed reversal preserves all copied
assets, including assets shared by several moved Easels, so a document left in
the destination retains its usable image data. The existing storage adaptation refuses document aliases that
would remain in a different Profile, including cross-Profile split copies of
Notes/Easels; it does not silently share sessions or duplicate private state.
This restriction is unchanged and is distinct from an included whole-document
move.

Checks use real temporary documents and hidden AppKit canvas/pool components
with injected engine replies. They cover retained-source write revocation,
original URL/capture/asset identity, rollback, asset collisions, changed editor
admission before/after unload, pending/live child refusal and a fresh destination
wrapper/request with the exact new Profile. These do not exercise real browsers,
native beforeunload presentation, login state or installed drag/motion/AX.

The finished integrated source passes 114 inter-Profile model assertions,
310 EaselStore assertions and 76 pool assertions, plus whole-module SIL with
warnings as errors (61 seconds, zero diagnostics). Fresh independent review
cleared the exact source, including the two-document/shared-asset failed-reverse
fix. Final receipts are `work/easel-coordination/easel29/{inter-profile.json,
easel-store.json,pool-rebased/receipt.json,published-source-inputs.json}` and
`work/claude-split-checks/easel29-rebased.json`. No EASEL29 engine overlay changed.

## Keyboard and accessibility entry — EASEL26

The canvas's native object focus view invokes `focusPage(for:)` on the existing
pool. Entry validates selected object, active original window/Profile owner,
shared-session liveness, transfer/retirement state and the actual native view's
attachment. A live page focuses its own native host; a missing page can expose
its existing recovery/Return control. A detached or revoked live page cannot
claim recovery focus as successful page entry. No provider call or navigation is
performed by this path.

The selected surface contributes its actual page and native controls to the
object accessibility subtree. Unselected or revoked surfaces are omitted from
page-side key traversal. Return/Cancel validates the original surface, clears
canvas selection, synchronously revokes the page's interactive selection, and
focuses the same canvas. Native input-method composition and browser key
handling retain their existing owners. See [the canvas contract](easels.md#canvas-keyboard-and-accessibility-ownership--easel26)
for the source evidence, native control adaptations and limited component checks.
