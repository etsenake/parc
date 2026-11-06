# Downloads in Library

Downloads opens in the shared Library shell beside the existing page. That shell is the 112-point rail, the depth layer behind it, and the page card at the Library's edge, `max(min(window width − 56, the page's width), 417)`, with a 6-point continuous corner. Every page but Spaces is 417 points wide ([Library width](space-management.md#library-width-on-the-spaces-page)). Archive’s Filter control is the existing chip, framed at `fittingSize.width`, so the title is not clipped to a fixed 72 points.


Each live row carries its original profile ID, manager GUID and unguessable item-incarnation string. The incarnation and action capabilities are never saved to the session. Persisted metadata remains browsable after restart, while file/transfer actions wait for a live manager snapshot. Unknown profile updates are rejected. Opening Downloads initializes each owned regular profile through the existing CEF profile registry without creating a page, waits for the real manager history-ready signal, republishes snapshots and returns its authoritative GUID set. Only then are stale persisted records for that exact profile removed. Loading, failure and Retry are visible; a profile retired during loading returns failure, not a fabricated empty history. A profile filter cannot retarget an action to the currently selected browser profile.

The row shows genuine transfer bytes, status text, paused/completed/canceled/failed states and the currently supported primary control. Its menu exposes supported Pause, Resume, Cancel, Retry and Review, plus Open, Show in Finder, Copy File, Copy Download Link, Open Source URL, Open When Finished, Hide from Parc and Move to Trash. Disabled file actions remain disabled for pending, missing, unavailable or review-required items. Indeterminate progress stops animating with Reduce Motion. Native table selection, arrow keys and Return retain the original row cursor; Space preview, Command-C, Command-F, Escape and contextual menus use their separate original-row boundaries.

- Open, Reveal and Open When Finished resolve the live item and execute Chromium `DownloadCommands` after checking its current eligibility. Retry and security/scanner review retain their existing production pipelines.
- Copy File writes the selected safe completed file URL to the macOS pasteboard. A missing path never falls back to copying metadata as though it were a file.
- Space opens an owned Quick Look preview of that same eligible file. Navigation between selected rows, filter/category changes, item removal, profile loss and window teardown replace or dismiss the preview. Preview availability is revalidated on manager updates; playback does not autostart.
- Hide from Parc dispatches the captured original item directly to `DownloadItem::Remove`, matching the reference menu/reducer. Completed files remain on disk; Chromium may discard unfinished partial files. It never removes a persisted row optimistically. The current original manager capability and Profile/context/GUID/incarnation are revalidated before dispatch.
- Move to Trash dispatches directly, resolves the original safe completed file and uses the real asynchronous `NSWorkspace.recycle` outcome. The download record is removed only after the file moves and the same item/profile/path remains current. Failure retains the record and reports the error. A concurrent second Trash request for that item is refused.
- Review sheets retain their exact item/profile and original browser window. Decisions and help links use the genuine review DTO, policy and callbacks. Source/help navigation uses an existing Space belonging to that original profile; if none exists it is refused. Choosing the first existing Space for another profile is an explicit Parc adaptation.

## Keyboard selection and original-item commands

Ordinary Up/Down moves through actual displayed downloads, skipping date headings and stopping at either end. With no selected item it chooses the first item. The reference has one optional selected item: Shift-Up/Down moves that same cursor, Command-click cannot add a second item, and table Select All is disabled. Headings never participate. Search-field composition stays with the text editor, and Return/Down from search returns to the existing selected row when possible. Unmodified Return or keypad Enter confirms the existing cursor, or selects the first displayed item when none exists; it never opens the file. Search submission moves native focus to that cursor without file output. Space and Delete retain their separate preview/removal routes; modifier variants do not accidentally invoke the plain command. Responder-chain Copy validates the current selection. Text-field Select All and composition remain native text-editing operations; they are not intercepted as table commands.

Selection survives progress/name updates only for the same public record, Profile, manager GUID and live incarnation. Replacing a manager item, publishing a newly live lease for restored metadata, removing a profile or filtering an item out cannot carry its highlight to another record. Menus capture the original window, Library context and selected item identity. Search/profile/category changes, detach or a different selection invalidate those captured commands. Row controls and preview use the same current original-item resolver.

Every action resolves exactly one captured original item and its current capability. Fabricated or stale plural sets are refused before dispatch, rather than converted into a subset or sequential bulk operation. Hide from Parc and Move to Trash have no extra confirmation surface: this matches the recovered direct action chain. Native policy/security review, asynchronous file outcomes and inline failure feedback remain authoritative. An unrelated attached sheet still prevents an action from escaping its original window.

## Reference and adaptations








## Completed native row, preview and settings experience

The Library requests real local-file thumbnails through QuickLookThumbnailing only after the native manager approves the completed file. Requests belong to the original Profile/GUID/incarnation, file URL, Library context and attached row. Row detachment, a new search/filter context or Library retirement cancels them; stale callbacks cannot publish. A bounded per-Library cache holds completed images. Missing/unsupported thumbnails retain a native file symbol. Final completion also rechecks the original file-copy policy and captured byte count, even when the item incarnation is unchanged. There is no Downloads directory enumeration or synchronous image decode. Ordinary metadata updates reload only the changed original rows; a new context rebuilds row callbacks even if the filtered result list happens to be identical.

Rows show the original name, Profile/source, real status/bytes, actual progress and supported primary control, with separate Preview and More actions. Hover, selected/unemphasized and Increase Contrast states use the window's native theme. Narrow and regular widths retain the controls and full-name/status accessibility and tooltips. Reduce Motion keeps indeterminate progress static. Failed admissions produce visible inline feedback rather than only a beep. During an accepted asynchronous Trash operation, conflicting actions and preview are disabled for that exact original item; its real completion restores capability-derived state, and failure keeps the record.

One native Quick Look child panel follows the selected eligible original file. It has Previous/Next, original-item More, Open and accessible position controls; Up/Down move through the current displayed eligible files without wrapping, Return opens only when allowed, Command-C copies only through the original Library resolver, and Space/Escape close. The system preview never autostarts media. Selection/context changes, file disappearance, profile/item replacement, category/window teardown or a conflicting sheet retire the original preview. Closing returns focus to the table only when that child actually owned focus. The borderless overlay covers its exact original parent and follows that window’s frame; the centered modal scales with the parent, as described below. Generic Quick Look formats beyond the original image/movie/PDF predicate remain the established native adaptation, with explicit Open retained.

Profile Download Settings now acquire the actual owned regular engine context asynchronously when it is cold, without opening a page. Loading, failure and Retry use the original selected profile and callback generation. Closing Settings, changing/removing that profile or native profile death prevents a stale preference snapshot from being installed. The existing policy-aware DownloadPrefs setters and the owned folder panel (since DL33, the Download Location picker's Other… row, below) remain authoritative; neither a failed change nor a managed preference is presented as success.


The delivered routes are connected to production owners: entry/search/filter, date order, single-item keyboard selection, real progress/security/error/Cancel/Retry, direct file actions, asynchronous output feedback, preview and profile preferences. The reusable component checks exercise the actual AppKit Library/table/preview/thumbnail owners with disposable metadata and injected image completion; they neither open Chromium nor act on personal files. Native/application compiler checks establish source compatibility, not browser runtime acceptance. Production Library catalogs now skip no-op reloads: History ignores unrelated BrowserStore ticks without sorting the profile history, Downloads still observes `$state` and `$transientDownloads` but returns before filter/sort when those arrays and profiles are unchanged, Documents skips card rebuilds when page identity and titles are unchanged, and filter expansion no longer flushes CATransactions. PERF09 remains LEFT with the Performance owner; this is not family completion.

## Entry activity and completed-file drag


The actual SharedDownloads writeback1022f55a8 filters downloading status, sorts createdAt descending and publishes the first original item's progress/incognito flag (fresh REA `ev_27fd753efbaa250c0c98b0bb2b10a46d415d3f8436d2e4fab7d0268523509181`). DownloadProgressBadge102217a20/102217df8/102218e18 supplies the24-point ring,2.5-point stroke, arrow/check icons and1.45-second completion landmarks. The entry-motion delivery below replaces the initial native curve approximation and ID-based equal-date ordering. Static unknown-length display and status-confirmed completion remain documented adaptations; no contemporary populated motion match is inferred from an empty Library.





## Private-window Downloads

Downloads remains available in an Incognito window through the same sidebar and menu command. Its rail also offers Media when the original normal parent profile and private context remain valid. Downloads alone does not initialize the persistent capture or document catalogs; Media opens its parent catalog only when selected. Regular and private windows now display the same merged regular/live-private collection through the existing search, original-Profile filters, rows, selection, progress, actions and preview. Private records live only in the application store's separate memory projection; they never enter serialized BrowserState. Encoding an individual private record is explicitly refused.

`PCNativePrivateDownloadContext` identifies one existing OTR manager with a random context ID and weak Profile lifetime. It does not create or keep a private Profile alive. Refresh and every file/action/security operation revalidate that context and its actual registered private owner, GUID and native incarnation. The existing original manager methods remain authoritative. Closing one presentation does not remove another window's rows or cancel a transfer. Context destruction revokes the native token before the deferred application notification removes its records from every view, invalidating pending selection, preview, drag and captured menu actions. Regular and other private records remain untouched. Source/help URLs return to a live window of that same private context; a retired context cannot be recreated from a row. Choosing an available window within that shared context is an explicit Parc routing adaptation, not a recovered modern window-ranking claim.


Finite production checklist: entry/search/Profile filter/order; original row/selection/keyboard/context/AX actions; progress/Cancel/Pause/Resume/Retry/security/errors; thumbnails/preview/focus/teardown; copy/open/reveal/Trash and async outcomes; policy-owned Settings; active/completed entry indicator and lazy file drag; private manager publication/actions/lifetime. All are wired to their original owners. Existing AppKit activation/Quick Look/layout and explicitly unobserved timing/haptic differences remain documented reference adaptations. Reloading every Downloads row from unrelated BrowserStore ticks and flushing CATransactions on filter expansion are production defects and are fixed in source; PERF09 stays LEFT with its Performance owner.


The private increment passes the actual pinned native application check with zero diagnostics, the fixed157-source warnings-as-errors Swift app check, and67 actual Library/model +34 selection/table +28 entry/provider assertions. The component exercises the complete production Library rail and real lazy catalog owners against disposable paths, including private publication isolation and original action/drag/confirmation retirement. Visible native private-rail and filter screenshots were inspected with synthetic metadata; no personal file, private download or browser navigation was exercised.

## Populated list presentation

The shipped Arc1.122 Downloads renderer selects the shared ContentCell list path:56pt row,12pt leading/trailing insets,24pt leading slot,8pt horizontal and2pt title/subtitle spacing,14pt regular title and12pt secondary subtitle. The later original-artwork attribution below corrects the initial32pt file-image assumption: real file images and thumbnail requests use24pt; the independent progress/empty-icon accessory frame is32pt. Status remains foremost; full Profile/source context is retained in the subtitle, tooltip and accessibility label. Long names truncate without covering controls. Original item/file ownership and asynchronous cancellation are retained.


The compact-row increment passes the exact157-source warnings-as-errors app compile and139 actual Library-view,34 selection/table and28 entry/provider assertions. The visible native component covers completed, downloading, paused and failed synthetic records; it confirms actual controls and text separation without a personal download/file operation. The subsequent preview increment below completes its attributed parent geometry and transition owner; the accessory visibility/hover owner is recorded below.

## Parent-owned media preview

The preview is a transparent borderless child covering its original browser window. Its backdrop is black at70% opacity, with10pt corners; the centered content uses max(round(parent dimension×0.8)−50,100), clamped to a smaller actual parent if necessary. The native Quick Look view retains the exact approved completed file and does not autostart. A compact toolbar exposes Close, Previous/Next, the full original title/position through accessibility, original-item More and policy-gated Open. The same existing selection/menu resolver governs every output action.

Opening from a visible original row uses its artwork frame and the recovered damping ratio0.9/response0.25 spring. User dismissal returns toward the currently valid original artwork with ratio0.95/response0.15, beginning at the presentation layer when interrupted. These response values feed an actual settling-duration spring, not a fixed-duration approximation. Backdrop fades separately. Reduce Motion and an unavailable source row use immediate presentation/dismissal. Parent resize settles the active geometry and relays out the same child; original item/Profile/context/window retirement or a competing sheet closes immediately and consumes its callback once. Focus returns only through the existing exact original Library/key-window guard.


Quick Look file formats, native button/focus rendering, metric-derived toolbar height, current native theme surface and original-file layer animation are deliberate adaptations. The original source-image/shadow path is implemented in the later transition increment below; modern populated appearance is not claimed exact. No downloaded file or browser action was created for comparison. The trailing accessory state owner is recorded below; large-history performance remains the separately queued post-polish task.


Integrated publication verification: the current160-source full app passes warnings-as-errors with zero diagnostics and unchanged inputs. The actual combined Library/preview, selection and entry/provider components were rerun against the current model and pass160+34+28 assertions. No engine change or browser functional test accompanies this preview increment.

## Row accessory interaction

The original trailing More action is shown when its row is hovered/highlighted or selected. It collapses outside those states and is absent during the original scroll view’s live-scroll sequence, even on a selected row. Scroll completion restores the selected/current-pointer state; key-window changes and detachment clear stale pointer ownership. Its32-point target and8-point corner leave8-point spacing and return their space to the title when hidden. The earlier provisional primary/Preview buttons are removed by the original populated-row control correction below; actual commands remain in the original-item menu.

The More button’s idle/hover glyph and hover/pressed background use source-owned values for GrayA11/A12 and GrayA6/A7. Original Arc1.122 consumers and current1.170 named-color resources are attributed separately. AppKit retains real press, disabled, focus and menu dispatch; no fade, spring or haptic is invented. Hiding the focused accessory returns keyboard focus to its same native table. Original row context/keyboard menu access remains available. No menu or file action is duplicated by the presentation owner.





## Original artwork-to-preview transition

The preview now retains an actual 2× bitmap of only the invoking row's already-owned artwork (24pt for files, as corrected by the later original-artwork attribution). ContentCell 10231459c→1023146ac and native ImageRenderer helper 1009d85a4 (fresh REA `ev_55b239b2e3fac2b0e610372f8296670dcdb7f139bb9370c9fd2631191e375174`) establish this producer; DownloadCell and DownloadsPagePreviewPresenter pass the same image and original view rectangle into MediaPreviewWindow 1022304f0. The original image/anchor remains the invocation's source while Previous/Next changes the live file. No file is reread or live Quick Look content captured for this image.

Opening scales the outer modal from that original rectangle while crossfading the artwork out and live content in; closing reverses the handoff from the current presentation transform. Actual ModalContainer 102233914/102233d34 and root 102231d48/1022322b8 establish the separate image/content, backdrop and shadow animations; fresh transition REA is `ev_cd2e5306684f8ee053f183ae519f0dcf3feba50e91e518e244d8b0c3fa9a2b57`. The retained original source-image aspect controls its centered frame. The unclipped outer shadow has radius 5/offset (0,−3), with 10 pt continuous content corners. Opening uses ratio 0.9/response 0.25, closing 0.95/0.15; the entire modal no longer incorrectly fades with the content. These consumers correct the earlier direct-content-only adaptation. The prior modal updateLayer citation 102233520 is superseded by its exact entry 1022335b4.


DL24 is complete with applicable original-source transition, component and full-app compiler checks; the current count is maintained in the single family table in `docs/parity.md`. No requirement was added or reweighted. DL27/32/33 remain open, including entry interpolation and remaining focus/visual/motion attribution. The later selection and filter deliveries below resolve the prior plural/confirmation and filter differences. DL-PERF remains after polish. No browser functional test or personal file operation was run.


The merged collection (DL30) is covered by actual disposable production-model/Library components: same GUID/incarnation in regular and multiple private managers stays distinct; both window presentations resolve the original lease; individual/private-state serialization refuses or excludes private data; authoritative reconciliation/context death withdraw only the exact manager; pending menus, drag providers and confirmations retire in both views. Native application compilation and the full current Swift source cohort are separate checks. No browser functional test, personal file operation, private download or navigation was performed.



## Original single-item selection and direct removal



DL11 and DL20 are reconciled by removing the earlier extra range/plural and confirmation behavior, not by inventing a plural menu or a confirmation appearance. The fixed requirement denominator is unchanged. DL18's earlier confirmation wording is corrected to the recovered direct manager action. After the filter delivery below, the remaining Downloads requirements are DL27, DL32 and DL33; modern populated appearance and untraced transitions/haptics are not declared matched.

The current production component checks pass222 actual Library/model assertions,38 selection/table assertions and28 entry/file-provider assertions. They cover single-cursor Shift navigation, disabled table Select All, refusal of fabricated plural commands, direct Hide/Trash dispatch, and original regular/private item retirement. Actions are intercepted: no personal file is opened, hidden, copied or trashed. The combined164-source whole-module app check passes with warnings as errors and zero diagnostics; all264 compiler inputs and52 component inputs are unchanged. These are not browser functional tests or modern populated appearance evidence.


## Original filter header, chips and ordering

Filter replaces the search field with **Filter Downloads…**, **Done**, and the actual local Profile chips. Selecting a different original Profile applies that filter; selecting it again clears it. Done retains the query and shows the chosen Profile as a removable chip below Search. Removing that chip clears only the Profile filter. Nil already means all profiles, so the extra All Profiles row is removed. Search and filtering never change the active browser Space or retarget a captured download action.




DL06 closes this filter interaction/order/entry transition. No requirement is added or reweighted. DL27, DL32 and DL33 remain LEFT; modern populated preview/row fidelity and remaining haptics are not inferred from an empty Library. No browser functional test, personal file action or large-folder performance investigation is part of this delivery.



## Original entry animation owner

replacing the earlier linear Core Animation approximation. The source-owned
SwiftUI subtree draws the 24-point background, 1-point outline, 10-point heavy
arrow and 21.5-point ring with a 2.5-point track and rounded progress stroke. It
retains separate ease-out progress interpolation, linear 1.5-second repeated
ring rotation and the nested physical spring (mass 0.1, stiffness 0.5, damping
1.2, initial velocity 0.5), keyed by original progress. Completion uses the
original default/spring/ease-out/ease-in transactions, 9-point checkmark and
ring opacity 0.5. SwiftUI owns interpolation and delayed transaction behavior.
Its colours are the window theme's SemanticColorPalette roles read from the
environment: the disc fills with `cutoutColor` (+0x130), the outline is
`foregroundPrimary` (+0x10) at 0.5, and the icon, the 0.2 track and the
near-white disc; neither the system accent nor a fixed colour is involved.

This trace corrects an earlier inference: the original completion function
writes `completionScale`/`completionOpacity`, but the actual View associated
type/body and both ring helpers never consume them. The synthetic echo ring is
`ev_c3cf59ab204e5e763edb3051c570c2712617bfd00bbd9ecefc2d6f45137dc088`,
`ev_2cc0b638aae6c886e3cfd81281df8ac44655bb6476fc71fff10b1bd48bfbc1ef`,
`ev_0f570fb79f45a04a30765b38f04a56de3af0f3a359bc6ac5596928d1b93c3b2e`.
Full-image assembly resolves the external SwiftUI calls and literal values
missing from raw decompilation; neither is recovered original source.

The AppKit wrapper retains the original Profile/GUID/incarnation and genuine
completion outcome. Equal creation dates retain provider order. Progress/color
updates retain one animation tree; replacement/reactivation, detach, close and
accessibility changes retire that tree. Repeated publication does not restart
completion or extend its 1.45-second retirement. A stale timer cannot clear a
replacement, and reentrant owner retirement cannot recreate the renderer.
Reduce Motion disables visual motion and retains the short static check with
the same deadline: an explicit accessibility adaptation. The existing Downloads
button remains the sole input/AX target. The hosting view explicitly suppresses
its accessibility bridge as well as hiding the SwiftUI decoration. Unknown
length remains unknown and is not announced as an invented percentage.

DL27 closes this renderer/interpolation/retirement requirement. DL32 and DL33
remain LEFT for populated/focus/accessibility comparison and remaining
transition/haptic attribution. No requirement is added or reweighted, and no
modern original animation match is claimed. No browser download or personal
file action was used for checking.

The final current-main app cohort passes 167-source warnings-as-errors
whole-module typechecking with zero diagnostics and unchanged inputs. The actual
entry/file-provider component passes 44 assertions, including renderer reuse,
accessibility suppression, replacement/reactivation, reentrant teardown,
physical-window retirement and real completion expiry. The prior 253 Library
and 38 selection assertions retain exact matching source inputs. A visible
inert component shows the real progress renderer and subsequent completion
retirement; the AX tree exposes only its existing Downloads buttons. It does
export is `PARC_ENTRY_COMPONENT_APP` in `tests/DownloadLibrary/check-view.py`.


## Original row progress owner

The actual Arc1.122 `DownloadCell` Body record103c2d040 embeds
`DownloadProgressBadge` in its leading content. Constructor1023a65e8 passes
closure1023a84d0 to `ContentCell`; that closure calls1023a7360. Fresh REA
`ev_c2a793bc5ca7388a4093eb78bcf62fa72d1c4374bacd5723709c2d48b7f96de4`,
resolved against the original full-image symbols and `DownloadData.Status`
metadata103a83230, establishes active progress, paused and terminal branches.
Active progress passes its actual Double to the same badge already recovered
for DL27, with4pt trailing padding in a32×32pt leading frame. Paused builds
EmptyView. Pending/failed/cancelled use the `EmptyFavicon` resource; completed
uses its original optional thumbnail/file-state branch.

Parc now uses that shared circular renderer in the leading slot and removes the
provisional bottom progress bar. Same original Profile/GUID/incarnation updates
retain the actual native cell, SwiftUI animation host and unchanged focused
control. The closures for actions, preview and thumbnail are rebound to current
context; a disappearing focused action returns only to its original table.
Pause/completion/security review leave the progress subtree immediately, without
replaying the entry button's delayed completion lifetime. Context retirement,
replacement and detach remove the original host; reopening obtains a new one.
Unknown byte totals remain unknown in the model. Genuine Chromium review keeps
its shield/action. The system globe substitutes the proprietary EmptyFavicon;
Quick Look/file icons and native security/focus remain explicit adaptations.

Fresh selection consumer REA
`ev_ce6a6bce6e087a8c84e08b6ac23fa69f37922257a2b527ed103867eef6949eef`
at102339948 scrolls the nonnil original selectedID with no explicit animation or
haptic in that consumer, consistent with native `scrollRowToVisible`. This does
not establish absence throughout Downloads. DL32/DL33 stay LEFT; no requirement
is added or reweighted. The actual visible synthetic-record component shows the
leading ring and paused empty slot and exposes no duplicate badge AX element.
No populated reference download or personal-file action was performed. Focused
production components pass269 Library +38 selection +44 entry assertions.



## Original Return and selection ownership

keypad Enter to `HomeReducer.Action.View.Key.enter`. The key enum is
`down`, `up`, `enter`, `f`; the original Home reducer forwards it through the
current page's `HomeKeyboardHandlerProvider` subject. The composed Downloads
reducer scopes `PageItemsContainerReducer<Download>` and returns no additional
effect for its `itemsContainer` action.

when the optional cursor is nil. For an existing cursor, its enter branch at
branch attribution, not an inference from the enum name or an empty installed
Library. Fresh REA is
`ev_a63d4b9bc771518ac9a0a62f20bf9e4af4aeab45f193758fb6a6dd8b680fde27`
(container),
`ev_b3a282e651a10b2cf16134abc28d12a25c8282103c75fb925ac39659573e67dc`
(Downloads reducer), and
`ev_300f3c35fcc973c90d0ef8f1df1c2f662c0adef33884683884af9726624998c7`
(native key producer), paired with original enum/field metadata and the full
image's composed reducer witnesses.

Parc therefore removes the earlier inferred Return-to-Open behavior from the
native table and Search submission. Both now retain or establish the original
cursor, skip headings and leave all file output on its separately guarded
controls/menu routes. An active text composition remains with the native editor;
a detached or invalid owner or competing sheet cannot confirm a new cursor.
The native Search-to-table focus handoff is an explicit AppKit adaptation, not
a claim that the original SwiftUI editor has that same responder structure.

DL32/DL33 remain LEFT. This correction establishes one remaining keyboard
consumer; modern populated row/preview comparison and the remaining bounded
transition/AX attribution are not declared matched. The generic Home permission
card has a spring/opacity appearance modifier, but the actual Downloads loaded
producer has not been shown to use that permission state, so this animation is
not applied to download rows. A separate newly attributed call from the actual
Downloads EmptyStateView to the same modifier establishes a real empty-state
entrance; its implementation is documented below. No browser/file operation was exercised.

Final reconciled verification: 170 production Swift sources pass warnings-as-errors whole-module typechecking with zero diagnostics and270 unchanged source/header inputs. Actual Library, table-selection and entry components pass 274 + 39 + 44 assertions with 52 exact unchanged inputs. Return, keypad Enter, empty results, retained selection and native composition are checked without opening a file or browser. The fixed count remains 31/33 (93.9% DONE, 6.1% LEFT), latest 0.0 percentage points.


## Original empty-content entrance

whole content stack and attaches `HomeAppearAnimationModifier`, initialized by
`spring(response:0.35,dampingFraction:0.6,blendDuration:0)`, and independently
changes opacity to1 with `easeOut(duration:0.125)`. This is a positively
attributed Downloads consumer; the unrelated generic permission-card branch is
not evidence that Downloads needs another protected-folder scan or permission UI.

Fresh REA: body
`ev_daf98774830fba7cce0fd8d4451068e0f5657c971149dbb970fb4ce0dd2bf27d`,
initializer
`ev_17241d73161c477e31487c4ad70d175deb5b84709e48ec73847dc3d737d5d78a`,
and appearance
`ev_9f2e412f0a381ae83da576862f2686c93ce8b26ea91d9d911669a89c225b21ef`,
paired with the retained Arc1.122 full-image callsites and modifier setters.
No haptic call appears in these bounded functions. This is not a claim that
all Downloads haptics are absent.

Parc now animates the actual empty icon and message as one native subtree,
using the recovered response/damping and independent fade. The Core Animation
spring conversion is an explicit AppKit rendering adaptation; exact SwiftUI
interpolation is not asserted. Loading and failure placeholders remain still.
Same empty-content publications do not replay the entrance, and the view never
takes input focus. Hidden/detached content, original window closure, invalid
Library ownership, geometry changes and accessibility changes settle the owned
animations to fully visible final values. Reduce Motion bypasses the entrance.
Unrelated layer animation ownership is preserved.

DL33 remains LEFT until the remaining transition/haptic comparison is resolved;
DL32 retains its focus/accessibility and populated-reference boundary. The fixed
count stays31/33,93.9% DONE and6.1% LEFT,latest0.0 percentage points. No new
requirement, weighting, browser test or personal download was introduced.

Final native verification: 297 Library, 39 selection and 44 entry assertions pass
with 53 unchanged input files. A visible disposable native component confirms
the actual empty subtree, its labels and unchanged Search focus; its owned window
frame-by-frame interpolation. The first empty publication now renders immediately
instead of waiting for a later state update. No browser or personal-file action ran.

The reconciled 174-source application passes warnings-as-errors whole-module
typechecking with zero diagnostics and 274 unchanged source/header inputs.


## Original row pointer activation

and requires the original window and a readable local file before presenting
its filename extension conforming to data. A missing previewable file reports
its failure; it does not fall through to Open. Fresh REA evidence is
`ev_34014b06caed41065a9ea9c8c159f17d73e39cccd96bcdae891156b6c47dc2f2`,
`ev_358bbcab2e9981117d607607312236aeb83b43bb9b6d1feffb16dd9cf3c4d55e`
and `ev_80fbc3b2d8b08b41af93048a2ce3ddf7711ca23d271dbb879af032d447521500`,
paired with original-image metadata and symbol-resolved assembly. The shared
whole-program corpus was checked first and was still analyzing; no second
whole-program import was started.

The non-media callback emits SharedDownloads.Action case1,
Open When Finished flag through the manager. This is distinct from the
Return/cursor action and from Quick Look's broader supported file types.

Parc now captures the exact original row before AppKit tracks a click, then
commits only after native selection and mouse-up. Modifier selection, the
second double-click event, an admitted file drag and context-menu intervention
do not duplicate that output. Completed media uses the existing owned preview;
completed non-media reaches the real Open action. Unfinished items use only the
manager's actual Open When Finished capability. Security-restricted/partial
files are not previewed; this is the modern native safety-policy adaptation.
The explicit Space/Preview route retains the existing broader Quick Look
support as a documented AppKit adaptation.

Resource metadata for the one approved file is resolved off the main thread.
Before delivery, the view rechecks original Profile/OTR/GUID/incarnation,
window, context, selection, focus, key state, current file URL and operation
state. Replaced items, intervening menu/input, category retirement or changed
file ownership cannot retarget a pending click. A real native table component
checks mouse-up timing and cancellation in an actual key/active synthetic
window; file-output callbacks in the Library component are intercepted, and
only disposable files are used. No browser download or personal file action
is exercised. DL32/DL33 remain LEFT for remaining row/control/focus/AX
comparison and bounded transition/haptic attribution; the fixed denominator
and completed count are unchanged.

The exact production component passes 322 Library, 39 selection and 44 entry
assertions; the reusable visible native pointer runner passes 10 assertions
with its actual key/active window, then exits. The reconciled 175-source
application passes warnings-as-errors whole-module typechecking with zero
diagnostics and 275 unchanged source/header inputs. These checks do not claim

Final shared-main reconciliation also passes 176 Swift sources / 276 unchanged
source-header inputs with zero diagnostics. The reused native component inputs
are exact: 52 whole files plus the unchanged production shared-control prefix
from SidebarView, whose unrelated row implementation advanced independently.


## Original Library Search composition

the magnifier and filter glyphs drew at about 12–13 points because AppKit symbol
images carry padding, the Filter label was bright semibold text, typed text used
the muted grey, the page inset was 10 points and the filter glyph's translucent
1.170 at 2x and corrected on October 31. Values below are labelled **recovered**
Measurements carry about ±0.5 point of uncertainty from the theme grain and
colour management.


  .resizable()`, `Color.primary.opacity(0.4)`, 15×15 frame (lazy
  backed by `NSTextField` with `PlainTextFieldStyle`, so the placeholder is the
  system `placeholderTextColor` (black 0.498 light, white 0.549 dark) and typed
  text is primary.
  padding 10, the same primary 0.05/0.1 background.
  `GrayA11`, leading, horizontal padding 12, top 8, bottom 4. Titles
  `RelativeDateTimeFormatter` (`.full`) relative to now.

rendered value from the same views at 2x in brackets:

- Page inset from the rail divider to the field: 8 [8]. Field top 10 [10],
  height 36 [36]. Trailing inset after Filter: 8.5 [8].
- Field width 212.5 [212 on a 304-point page]. Gap 3.5 [3].
  Filter width 72.5 [73 = 10 + 15 + 4 + 34 + 10, where the 33.67-point
  “Filter” text is rounded up by `fittingSize`].
- Magnifier ink 15×15 at 13.5–28.5 inside the field [14.5–29.5]. Its stroke
  carries 1.42 times the ink of a regular-weight symbol; Parc draws it
  semibold, which matches (0.95 alpha-pixels across the stroke in both). This
  weight is measured, not recovered.
- Placeholder ink 44–176 horizontally, cap top 13 and baseline 23 inside the
  field [identical]. Darkest placeholder pixel ≈0.50 of the fill [0.50].
- Filter glyph ink 10–24.5 and text ink 30–62 inside the button, cap top 13
  [identical]. Glyph stroke matches regular weight.
  0.05; the difference is attributed to colour management and grain and is not
  compensated.
- List origin ≈56 below the page top; section heading ink at 12 with cap top
  ≈11.3 [12.5 and 11]. ContentCell list rows (8 inset + 12 padding, 24-point
  slot, 8 spacing) put titles at 52; title and subtitle baselines measure 24.5
  `VStack(spacing: 2)`].

Parc implementation notes:

- `LibraryHeaderGlyph` scales each symbol so its painted ink fills the 15-point
  alignment rect. The bitmap is two points larger, with the glyph one point
  inside, so the magnifier and filter strokes are not cut off at the image edge.
  Fitting the ink exactly to a 15-point bitmap clipped the magnifier's left side.
- `DownloadSearchField` is the plain NSTextField: 14 medium, primary text,
  attributed system-placeholder colour, no bezel, focus ring or clear button.
  NSTextField's start 3 points inside its frame) and centres its line box.
- `DownloadFilterButton(_:symbol:style:)` takes an explicit style. `.header`
  is the GrayA11 Filter/Done action and ignores `ink`; it must be sized with
  `fittingSize.width`. `.chip` (the default) keeps the chip drawing for filter
  screenshot, Done spans 348–408 points across the 416-point Library; Parc's
  render spans 349–408. Downloads and Archived Tabs
  both use `DownloadSearchField` in `DownloadSearchBackdrop` and the `.header`
  action. `LibraryPageHeader` carries the shared inset, top, height, spacing
  and content origin for Downloads, Archived Tabs/History, Media and Easels.
- The Downloads table uses the plain style so the recovered row insets apply
  directly; the inset style had added 16 points per side and 10 at the top.
  each item from its own timestamp: “Today”, “Yesterday”, otherwise
  `RelativeDateTimeFormatter` (`.full`) relative to now. A nil `createdAt`
  that title string, so one calendar day can split (for example “2 days ago”
  and “3 days ago”). Parc does the same for a download that has `startedAt`.
  A download with no start date is a Parc adaptation: it still sorts as distant
  past, so the section stays at the bottom, but the heading is the plain word
  “Earlier downloads” heading and no Downloads count footer. Easels has no count footer either. Loading,
  load failure and action failure still use the bottom status line.
- AppKit field-editor and accessibility ownership remain an explicit adaptation
  of the SwiftUI/native-field bridge. Native editing, IME, query, Profile
  filter, Return cursor and context invalidation are unchanged.

no status line, item-count footer or folder button (no "On this Mac" string or
routes are Parc's, following macOS conventions. The folder-source menu opens
from a right-click on empty grid space or on the empty-state message. From the
keyboard, Shift-F10, Control-Return or accessibility Show Menu opens it when no
item is selected; with a selection they open the item's menu. Adding Option, or
using the "Manage Media Folders" accessibility action, always opens the folder
menu. A status line appears at the bottom only for a folder that needs access
or a failed file action. A failure stays visible through the refresh that
follows it, until the next search edit, menu or item command, or the Media
presentation closes. The grid starts directly under the header. Private Media keeps its NSSearchField without the folder
button.

Rendering harness evidence (October 31, not committed): the actual Downloads
and Media views rendered at 2x in light and dark themes, idle, hovered and
NSTextField text twice, so the harness draws each field's cell interior once.
No browser functional test or file operation was performed.

43 pixels tall, so 43/36 of a point) shows a Today heading and one completed
row: a document icon, the lowercase filename, and “Disk Image from github.com”.
There is no item-count line. Parc’s rendered page, scaled to the same 36-point
field, uses that heading and the 24-point file image. Recovered artwork
completed file and shows the file icon while that thumbnail is pending.
EmptyFavicon remains the missing, failed, cancelled and pending artwork. The
.png row’s picture is that thumbnail; the .dmg and .pdf rows show the document
icon. A download with no start date is grouped under “Earlier”, the Parc adaptation described above.


## Original populated-row controls

The original `DownloadsUI.DownloadCell` supplies one trailing control: the More
ContentCell with left artwork/progress and right accessory closures;
with a highlighted 32×32 frame or absent 0×0 frame. Fresh REA evidence is
`ev_2be6c078afd50d40d1f36fd654ac85e56e7525e8e309a5aa542553c29bed9143` and
`ev_b95c777b01db5a3bdca39450212b92915be7ed2fadbf40f74a8b28e243ca33db`
imports and original constructor ownership independently of those bounded
Ghidra slices.

Parc removes the provisional inline Preview and primary action buttons. Real
Pause/Resume/Cancel/Retry/Review/Open/Reveal and file/source commands remain in
the captured original-item menu, with their existing native capability,
security, original window/Profile/incarnation and asynchronous result checks.
The existing single-click media preview/file Open/unfinished-toggle route and
Space preview are unchanged. The left warning/progress artwork and status
remain visible. The native More button stays focused across progress/state
updates and retains its actual hovered tint; when scrolling removes that exact
control, focus returns to its original table.

The native cell speaks its title/status once; passive labels, artwork and
progress decoration no longer create duplicate accessibility children. More
remains a separate native button. This is the AppKit table adaptation of the
original shared ContentCell accessibility label and image trait; Parc does not
replace native table semantics with a decorative image role.

The focused actual native suite passes 348 assertions, including one trailing
control in completed/active/paused/failed/security-review states, preserved
real menu capabilities, original focus and metadata updates, 32-point targets
and narrow-row containment. The visible synthetic light/dark native rows now
expose one complete cell label with no synthesized decorative text/image
children; when shown, More remains the separate actionable child. Populated
unavailable because its Library is empty; no download is created to manufacture
a reference. DL32 stays LEFT for the remaining shared row-background/selected
state comparison; DL33 stays LEFT for the original arrival transition and
remaining motion attribution. Neither fixed requirement is counted complete
by this control correction.

## Original row background and selected state

The shared ContentCell list renderer now supplies the Downloads background:
a continuous twelve-point rounded rectangle, full fifty-six-point row height,
with eight-point horizontal insets. Hover or original selection applies primary
color at ten-percent opacity; inactive selection uses the same fill. The earlier
one-point/two-point inset and separate eight-percent inactive tint are removed.
The row retains its existing cursor, hover, scroll-suppressed More accessory and
original item actions; live scroll suppresses More while preserving selection.

REA `ev_8f3b1ccc81460c1c96eb5919af6a40b676d43b650eeb40d6dd36d7d195950a87`.
The list branch applies its background before horizontal padding at
Full-image literals/accessors establish primary opacity 0.1, spacing eight and
continuous radius twelve. The snapshot environment's Gray7 substitution is not
an inactive-selection rule.

A retained passive native layer draws this background once beneath the cell,
resolves semantic color in its actual appearance and neither intercepts pointer
input nor contributes accessibility children. The original row/window owner
clears stale hover on retirement and reattachment. Increase Contrast's native
focus outline is an explicit accessibility adaptation; the recovered normal
background has no new delayed transition. Essential populated artwork/status
comparison and the separate arrival owner remain tracked under DL32/DL33.

A selected-row native appearance check also exposed the image-only More control
as AXUnknown when returned as the cell's explicit child. It now declares its
native button role and accessibility element while keeping the original
NSButton action and keyboard owner; no synthetic menu or action is introduced.

The final actual native Library suite passes 359 assertions; the reconciled
182-source application / 282 source-header inputs pass warnings-as-errors
with zero diagnostics and unchanged inputs. The inert light/dark selected-row
component confirms background composition and the explicit native More button
appearance limit; neither DL32 nor DL33 is silently counted complete.


## Original state-specific row subtitle

Chromium bubble message. Completed files show Image, Disk Image, PDF, Movie,
Audio, Zip Archive, Archive or Download, followed by the original source domain.
Paused/cancelled rows retain that source; failure and a missing completed file
use their original distinct labels. Active downloads show compact received/total
bytes with duplicate units elided and the actual estimated remaining duration.
Open-on-finish shows its integer progress; unknown totals remain blank.

REA `ev_f56f2ff35723fbfb0b2afe0b1ca81996469986cd98e0a785ef464208f914ce41`
`ev_902405a424f7035c06c0c88461332600e5fe1740f47f012c2683b9e187058478`.
The reference is the same retained Arc1.122 ARM64 image identified above.

Chromium's actual DownloadItem MIME and TimeRemaining enter the existing native
snapshot and original-item model. No time estimate is restored from disk.
Current Chromium's public-suffix parser and asynchronous-file-free UTType
extension/MIME inference adapt the old DomainParser/URL resource type to the
current native services; exact old suffix data is not claimed. Security warnings
and pending operations retain their genuine text. Full source/Profile context
remains in tooltip/accessibility without duplicate speech. The asynchronous
thumbnail completion checks current policy and original bytes as well as the
item/context/file lease. Populated artwork/placeholder comparison and the
DownloadToLibrary arrival owner remain DL32/DL33; this is no whole-family closure.

## Original file artwork and title states

Arc1.122's DownloadCell selects the shared ImageOrPlaceholder renderer for an
available or not-yet-known-missing completed file. Its list image is24×24 points,
stretched with low interpolation; the actual Quick Look request is24 points at
2× with lowQualityThumbnail. The earlier32-point attribution referred to the
distinct custom accessory frame, not this file image. A pending image uses a
continuous radius8 rectangle at5% semantic primary. Failed, cancelled, pending
and known-missing items instead center the14-point EmptyFavicon within that
32-point accessory frame. Paused has no leading image; active progress retains
its already-delivered renderer. Genuine Chromium security review still owns the
explicit warning symbol and status.

`Resources/Library/` (DL33; earlier it drew a source-owned silhouette). The installed1.170 template resource and an inert SwiftUI renderer
comparison establish its72/255 mask opacity applied to semantic primary. The
file placeholder, ordinary/selected title and selected background preserve the
semantic color's own alpha instead of replacing it. Display titles use the
original file URL's last component lowercased; original filenames, paths and
actions are untouched. Failed/cancelled/known-missing titles use secondary;
other titles use primary at85% ordinarily and100% while highlighted/selected.

The asynchronous native file icon and Quick Look request share the same original
file/item lease. An icon may display provisionally while the thumbnail is
pending. A successful thumbnail wins; a missing thumbnail waits for that
original icon. Cancellation, item replacement and validation reentry retire
both producers and prevent stale delivery/cache insertion. Native file-icon
lookup is dispatched off the main queue; no directory is scanned. Parc retains
its bounded64-entry scoped cache and stricter Profile/GUID/incarnation, current
file policy, byte count and exact URL validation. The shared historical cache
policy is an explicit implementation adaptation; DL-PERF remains after polish.

Reference: Arc1.122 ARM64 SHA256
`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
Image loader102315778 (`ev_74003936010a478202e397b7b670828153d09af5bbd31381cf9e1a47a5f4e262`),
image renderer102315f70 (`ev_9758a5020b3f52dc1cb4ea23adfa6acedf1b22b0d8d672b7bda859ef2c6205c4`),
24-point defaults102311b60/102311bb8, custom accessory1023a7360, title
configuration1023a6a48–6a60 and color1023188ec establish these branches. Original
ThumbnailProvider1009f7ff8→1009f80e4 owns Quick Look; asynchronous fallback
1009fa7a8→1009f9958→1009f9970 invokes NSWorkspace.iconForFile and rejoins the weak
provider. Full-image imports/field metadata distinguish list rendering from the
separate grid-only padding, size reduction and shadow branches.

download was created to manufacture a comparison. Applicable original renderer
and resource contracts are implemented, while the dedicated whole-product
polish pass remains separate. No browser or personal-file action was exercised.

Final artwork checks: all187 production Swift sources pass whole-module
typechecking with warnings as errors, zero diagnostics and unchanged inputs.
The actual Library/provider component passes424 assertions, including
provisional/final ordering, validation reentry, cancellation, semantic color,
placeholder geometry and preview image size. The layout fixture now pins its
synthetic records to one day so a midnight run cannot change its row indexes.
focus was restored. DL32 closes without a denominator change:32/33 DONE,
1/33 LEFT, +1/33×100=+3.0 percentage points. DL33 remains active.

## Original DownloadToLibrary arrival

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`. The renderer
and owner contracts (with bounded disassembly receipts and REA pseudocode) are
retained outside Git under `work/claude-downloads-rea/renderer` and `owner`; the
earlier cohort is `work/downloads-arrival-motion`. Below, a plain statement is
adaptation with its reason. Recovered pseudocode is evidence, not source.

**Creation, not replay.** `WindowViewController` sinks the app-wide download
`ev_39e18a69a71375648829f2611419445255b335d717c417d63fcbdfb196b10bec`);
`onDownloadsInitialized` replays nothing. `NativeDownloads` therefore runs its
`Created` callback only from a genuine `OnDownloadCreated`, never from
constructor enumeration, and only for an item whose initiating `WebContents`
has a live primary frame. Restored and imported items attach none. The engine
instead of `webContentsURL` equality, so two panes with one URL cannot resolve to
the wrong page, and refuses a window holding a security reservation (arrival
pixels swallow clicks; the same rule applies at resolution and the Swift owner
retires on `PCNativeWindowSecurityStateChanged`, as the command bar does).

`ev_f0554e4ac0c66b377d87370284c229abb2c215bfc4ef3d15718d86776c7ed298`; skipImage
(`ev_7e49cfc5ef70a28053a3851025212592e199c43a22942dd05d38824da273da4f`) does not
`NSEvent.mouseLocation` when there is no anchor or the centre is not finite. No
timeout exists, so Codex's 2-second fallback is removed. Resolution is identity
only: the same live primary document, page, Profile, window and item
place). *[A]* The visual-viewport offset/scale and page-zoom factor correct
both agree. The bridge delivers `-nativeBrowser:downloadDidBegin:` with
`sourceScreenPoint`; an older engine never calls it.

**Window owner.** `BrowserWindowController` checks the receipt's window,
identity, Profile and private context and hands it to `DownloadArrivalOwner`:
= 2); no sidebar or Library control frame is read anywhere. The window palette
is captured then too. Any window's resign key plus resign main, combined with
`ev_4bb6c35347fae10b4b48ec2d97ec8597af35599a4f345fdcde2c7c3ff6be8bac`), forces
`ev_bea5f7a156d6b51dac6a43e16b6a4d596bb6a8f929138ae0ed4a4ddd27f1c770`), and the
controller exists only while animating, so Parc keeps the same guard and routes
no such event. Window close force-dismisses *[I: close resigns key and main and
ends the owner]*.

(`ev_e1fa0ac733a915281684fa78fbceaab9d79fc231e07d5979db74b3ff076a8d38`) makes a
plain borderless `NSWindow`: non-opaque, clear, shadowless, frame = parent frame
(`.floating`), `orderFront` without key or main promotion. The first arrival is
appended before the window is ordered; `isAnimating` is then true for the
controller's whole life. *[I]* The parent-sized root overflows the inset window
`ignoresMouseEvents` and `ViewAction {didTap, didSwipeLeft}` has no caller
`ret`), so drawn pixels swallow clicks, transparent pixels pass through and
nothing handles taps or swipes. Resize, full screen and Space changes are not
tracked; the child moves with its parent.

**Flight.** Source = parent base point + (15, −15) (half the 30-point icon,
and (32, 40) without it. `vy0 = 1600 − 1100·y/H` (1600 for H = 0); T is the
largest positive root with g = 2648.7 (the earlier cohort's smallest-root note
steps; the scale rises (0.8, 1.2) → 1.6 at the apex and falls to 0.7 (bin) or
0.3 (no bin, plus eight extra frames past (32, 40), unclamped). With the bin a
fresh 0.48/0.72 spring launched with the landing velocity from (70, 70) to
(70, 70) supplies the bounce at 60 fps; Motion's velocity setter negates its
the final scale and adds linear, forwards-filled `position`/`transform` keyframe
a 30-point `backgroundExtra` circle under template `arrow.down.circle` in
`maxContrastColor`, shadow blue 0.25/radius 8/(0, 4), starting at alpha 0 and
−35°, with `spring(0.3, 1)` to alpha 1 and `spring(1.2, 1)` to 5° on appear
SwiftUI chain (`renderingMode(.template).resizable(capInsets: 0, resizingMode:
its ring meets the 30-point disc; the review corrected an earlier ~26-point
raster. The icon and bin shadows are plain layer shadows and exact, not
adaptations.

frame, 8-point padding, a 46-point continuous 12-point card in
`palette.background`, card-only radius-12 shadow (white 0.15 dark, black 0.3
light), centred 53 points from the leading and bottom edges when shown. Its
centre is `TranslucentButtonItem(.animatedIcon(.things), ._32)`, the sidebar
Library button's `BoxOfThingsIcon`; `DownloadArrivalBinItem` returns that item:
size `_32`, medium weight, `maxContrastColor` foreground, clear backgrounds and
(0.9/0.82) from −80 to 53 with the first arrival. Each download enters the
spring when the bin is shown and leaves the group. The drained group
to −80; its resolution (ε 0.01) orders the window out and releases it, exactly
once. Without the bin, completion is immediate at the last T + 1. *[A]* The live
springs tick on the view's display link with the frame interval (a 60 Hz timer
measuring elapsed time before macOS 14) in place of Motion's CVDisplayLink, and
a resolved spring settles on its target before its completion *[I: Motion's
runtime order is not traced]*.

owner path's bounded call closure (649 functions); every
`NSHapticFeedbackManager`, `performFeedbackPattern`, `NSSound` and
reduce-motion site in the binary lies elsewhere. Parc adds none: the DL33
transition/haptic comparison resolves to no haptic and no Reduce Motion gate.

**Checks.** `tests/DownloadLibrary/check-arrival.py` compiles the exact
production arrival sources with a manual clock and a disposable borderless
parent far outside every display: model-fixture trajectories, keyframe and
spring data, child-window rules, bin show/hide, concurrent and dropped
arrivals, exact retirement, forced dismissal, untracked resize and rendered
pass-through coverage. With `PARC_ARRIVAL_ACCEPTANCE=<dir>` it renders the real
layer tree at sampled times in light and dark. `NativeDownloads` unit tests
cover history/detached items never arriving and identity-only admission. The
engine overlay (version 233) adds `native_download_arrival.h/.mm`; its apply and
Parc refuses `TYPE_POPUP`/`TYPE_APP_POPUP` windows in
`DownloadArrivalOwner.admits(popupWindow:)`; DevTools windows do not implement
the delegate and picture-in-picture windows are never created. The arrival
component passes 99 assertions. No browser, download or personal file was
representable icons over the SwiftUI bin and the child window's colorScheme
source (Parc reads the child window's own appearance).

## Original Library entry

(Library contract and REA retained under `work/claude-downloads-rea/library`).
Parc's former trailing `arrow.down.circle` Downloads button is removed, as the
Sidebar owner's contract for the Downloads owner anticipated
([sidebar resizing](sidebar-resize.md#sidebar-chrome-spacing),
[sidebar accessibility](sidebar-accessibility.md#downloads-entry-downloads-owner)).
`SidebarLibraryEntry` now sits in the 32 × 32 slot at x 8 (y height − 41) and the
Space strip runs 40…width − 40.

**Presentation.** The button is `TranslucentButtonItem` at size `_32` with the
foreground values, press scale 0.95 on a 0.3/0.6 spring and a 0.1-second hover
ease-in. Its icon payload `0xe000000000000008` is
star, a triangle and a dot that pop out on hover (0.5-second critically damped
spring), twinkles at 0, +0.15 and +0.30 seconds, a light beam in Dark Aqua, and
with a provenance README and SHA-256 hashes (`LibraryArtwork`). The tooltip is
"View Library" after 0.45 seconds of mouse idle; accessibility is one button
labelled "Home" with no value (DL26's spoken progress is gone); it takes no
keyboard stop or ring and is out of `linkKeyViews`. *[A]* AppKit drives hover,
press and click with SwiftUI Button semantics. The tooltip is Parc's rebuilt
(the button with View Library's live keycaps, a cell's title, its Cancel
button) and sits at that part's bottom-trailing corner.

**Click and unread.** A click opens the Library's Downloads page when a
download badge became visible less than 300 seconds ago and the Library has not
opened since, otherwise the last selected Library page; clicking while the
`sidebar.libraryDidOpen()`. Private windows always open Downloads and never

browser catalogs; Documents, Desktop and Screenshots contribute immediate
children of those folders to the hover flyout (`HomeBadgingFile` /
`fileQueryResultsLoaded`). The Library pages for those folders remain with
the Library polish owner.

**Badge.** The badge cell is 40 × 56 at (−4, −30) from the button
newest-first stack. That returns the cell to the bottom slot and cancels the
overlay's −30, so the cell's bottom meets the button's and the 0.8-scale ring
overlaps the icon's top-right (centre 10 points right of and 12 above the
download, or the newest item under 300 seconds old. It dismisses files,
captures and failed or cancelled downloads after 5 seconds and a completed
download shows DL27's progress renderer; on completion the cell shows its
QuickLook image with no transition; failed, cancelled, paused and pending show
an empty cell. The start scale is 0.8 for a running download and 0.55 otherwise
0.2-second (0.78, 0, 0.7, 1) curve while nudging the button 6 points down, then
a spring (mass 1, stiffness 500, damping 25, velocity 10) returns both at
+0.22 seconds; hide runs 0.14 seconds linear to x − 14, y + 20, opacity 0,
scale 0.2 and −45° and clears after 0.16 seconds. Detach, window close, losing
the badging condition and turning a source off retire the visible item, its
timers and the renderer exactly once. *[A]* Parc swaps to the thumbnail when
DL27's 1.45-second completion retires, since DL26/27 confirm completion by
status rather than by progress reaching 1.

in a locked or floating sidebar and is off-screen with a hidden one; nothing
in its geometry or `canExpandHomeBadge` reads the sidebar presentation.
and the Library rail's Downloads item, `DownloadsPage.SidebarView`
AnimatedPageSidebarItemView>>`). The hidden-sidebar arrival bin shows no
progress: `DownloadBin` holds only the palette and colour scheme, and its view
model only flights.

field 1 (`downloadsState`) and returns `inFlightDownload?.progress`.
`SharedDownloadsFeature.State.inFlightDownload` is an optional
`InFlightDownload` with fields `progress: CGFloat` and `isIncognito: Bool`;
the Bool byte's spare value 2 is nil. Non-nil builds
`DownloadProgressBadge(progress:)` in place of the icon. Nil builds the page-4
frames neither: its only constants are 65, 80 and 11. The animated icon's
`constraintEqualToConstant:`), then pins its `scaleAspectFit`, `playOnce`
composition aspect-fit in the same 28 × 28 slot (`LibraryRailTile.iconSize`).
matches to within that image's 0.8-point pixel pitch (Downloads 21.0 points
in both). The badge's own 24-point disc takes the icon's place in the VStack,
so the label rises 2 points. The label's
`Color.primary.opacity(isSelected ? 1 : 0.7)` is a foreground environment
stays at full opacity on an unselected tile.

**Ring contract.** `inFlightDownload` is written by SharedDownloads
`DownloadData.status` tag is 0. That is `inProgress(Double)`; the cases are
`inProgress(Double)`, `paused(Double)`, `notStarted`, `completed`, `failed`
`(a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)`, takes the
first item and returns `InFlightDownload(progress:isIncognito:)` from its
`inProgress` payload, or nil when nothing is in progress. So:
- The ring shows one download's own progress, the newest in-progress one,
  never an aggregate. Paused and not-started downloads do not count, even
  when newer, and never badge the rail by themselves.
- `DownloadProgressBadge`'s Body ends in `_ValueActionModifier<Double>`:
  progress reaches 1 while the download is still in progress. A badge that
  first appears at 1 does not play it.
- The rail body is `PageSidebarItem<_ConditionalContent<DownloadProgressBadge,
  AnimatedPageSidebarItemView>>` with only appearance actions and no
  transition modifier. The badge leaves and the icon returns as soon as
  nothing is in progress; nothing holds the badge for its completion. Whether
  the store's write runs in an animated transaction was not traced; Parc
  swaps immediately. While anything stays in flight, the same
  badge view persists: its progress follows the newest in-progress download,
  and a completion it has played is neither replayed nor undone; its animated
  fade reaches opacity 0 about 1.45 seconds in. *[I]* That persistence
  follows from SwiftUI keeping the conditional branch's identity and state;
  it was not observed.
- Colours and widths are DL27's recovered renderer above: the window
  palette's `cutoutColor` disc with a 0.5 `foregroundPrimary` outline, and a
  2.5-point `maxContrastColor` track at 0.2 under a rounded stroke, in a
  21.5-point ring.

*[A]* Parc maps `.downloading` to `inProgress`, as the flyout's
`LibraryFlyoutDownloadStatus` does. Live snapshots map Chromium's
`IN_PROGRESS` to `downloading` (or `paused`) whatever the byte count, so a
running download shows its ring from its first snapshot, at 0 until bytes
arrive (or the 0.2 ring with an unknown total). `.pending` comes only from `BrowserDownloadStatus.inferred`
(`receivedBytes == 0`) for a record without a status; which state, if any,
applies the same filter and newest-first order, with `startedAt` for
`createdAt`. `DownloadActivityBadge.updateInFlight` keeps one renderer while
anything is in flight and marks completion when progress changes to 1 or
more. A played completion keeps DL27's 1.45-second deadline: the renderer is
then dropped, while the activity, and so the tile's empty badge slot,
remains until nothing is in flight. That deadline is what ends the checkmark
under Reduce Motion, which has no fade, and after an accessibility display
change rebuilds the renderer at full opacity. The sidebar entry keeps DL26
and DL27's newest active item, status-confirmed completion and retirement.
`LibraryRailTile`'s badge takes the sidebar entry's feed and window gate.
That is the window's download items for its live profiles, filtered to its
private or normal kind, while the window can badge
(`BrowserWindowController.refreshDownloads`, and once when the Library opens).
It does not take the entry's visible-item lifecycle, its Downloads source
preference or its hidden-entry gate; those belong to the sidebar's badge
cell. The rail badge uses the window palette's badge roles. The tile keeps
its radio-button role, selection, hover and pointer input, and relayouts only
when the badge takes or gives back the icon's place.

Unresolved: the `inProgress` payload is filled outside the main executable
(the shared reducer receives `DownloadData` through
`ADKClient.DownloadAction.update`), so its value is not recovered. In
particular, whether it reaches 1 at the last byte before the status leaves
so is its value for a download of unknown length. Parc uses the item's own
received over total bytes, and keeps DL27's static partial 0.2 ring for an
unknown total, which never completes the badge.

## Original Library flyout

Hovering the entry expands its badging stack into up to four rows (flyout
contract retained under `work/claude-downloads-rea/flyout`). It expands when
`canExpand`, eligibility and a non-empty item list all hold: the button, the
flyout or the visible badge is hovered; the button region reports after
0.15 seconds of lingering, the flyout region on entry, and 0.5 seconds on the
dock strip to the button's right reports it left; hovering within 100 ms of the
flyout cannot reopen by itself after the Library closes.

Rows are unique by file, newest first, the first four, the newest beside the
has a 40 × 40 icon (a capture's image in a radius-7 dashed outline, dash [3, 2]
at 0.3; the progress ring while running; a 256-point QuickLook thumbnail once
complete; nothing for paused, pending, failed or cancelled), a 12-point gap, a
14-point title over a 12-point relative-date or download subtitle, and for a
running download a 24 × 24 `xmark` cancel at 0.6 alpha; padding 4, hover
SidebarItemBackground, radius 12. Rows animate with
`interactiveSpring(0.15, 0.86, 0.25)` staggered by min(reverseIndex/4, 1) ×
0.05 seconds; collapsed rows wait 20 points (newest) or 56 points lower at
gradient mask fades the sidebar content behind the rows over 0.1 seconds
"Download — <file>", "Capture — <title>" or "File — <title>" with no value.

**Expansion motion.** The visible badge is one of those rows. Collapsed, the
it is a full row at (0, 0), scale 1, opacity 1. All of this rides the row's
staggered spring keyed on `displayAsExpanded`, so expanding carries the badge
up into its row's thumbnail slot as the title, subtitle and cancel insert, and
collapsing carries it back to the button's corner. The renderer is the same
pose without animation: opacity 1 when expanded, unchanged when collapsed.
*[A]* Parc keeps the visible cell separate, because DL27's renderer must keep
one superview and its window. It sits in its row's slot with the row's
modifiers; the stack keeps that row's slot and frames but does not draw it.
Other running rows draw their own renderers, which fade with their rows and
(only `DownloadProgressBadge` has `_reduceMotion`). Under Reduce Motion Parc
fades rows in place without the 20/56-point travel or the 80-point insertion
drop, and the visible cell fades at the button while the stack draws its row.

**Actions.** A completed media or PDF row opens DL23/DL24's parent-owned
Previous/Next step through the previewable visible items snapshotted at the tap
`DownloadFileDrag` and captures through `LibraryCaptureDrag` as PNG
its dividers: Send via iMessage and AirDrop are always enabled and call
from Parc and Move to Trash dispatch the original item through
`performLibraryDownload`; a capture's Delete asks "Are you sure you want to
the item switcher and command bar not presented and no `.window`-source modal;
Parc maps these to `libraryView`, `tabSwitcher` and `commandBar`, and has no
`.window` modal because every Peek belongs to a tab. *[A]* A capture tap opens
the Library's Media page and the preview list holds downloads only; a visible
item outside the four rows keeps its cell at the button and fades on expansion,
the Delete confirmation is an `NSAlert` sheet.

## Original download prompt default and Download Location

`download.prompt_for_download` as false (`0x2dfd310`–`0x2dfd334`) and only the
Download Location picker writes it (`ProfilePreferences` reducer case 4
`ClearSeededDownloadPrompt` runs once per persistent Profile directory: it
clears a stored user true back to the default and records the directory in
`parc.downloads.seededPromptCleared.v1` only after Chromium commits the cleared
pref; a stored false is kept and managed values stay in force. A deliberate
"ask" chosen in an older Parc is cleared once because it cannot be told apart.

folder's name and 16-point icon, "Other…", a divider and "Ask every time"
panel, sets the folder and then turns asking off; cancel restores the effective
row. *[A]* A disabled "Unavailable" item covers loading and failure, managed
values disable the picker, the panel is a sheet retired on pane, profile or
removal changes, and help and Retry stay below the row.

## DL33 checks and closure

The final reviews found no open blocking or major issue after their fixes. The
whole-module typecheck passes with zero diagnostics and unchanged inputs; the
native units (`downloads.cc`, `native_appkit_application.mm`,
`native_download_arrival.mm`, `downloads_unittest.cc`) pass the pinned
syntax-only check; the overlay manifest (version 233) validates read-only with
every hash recomputed. Components pass 432 Library view, 39 selection, 44
entry/provider and 228 Library entry assertions, 99 arrival assertions, 33
picker assertions and all eight sidebar suites. Light and dark in-process
renders of the arrival, entry, flyout and picker were inspected against the
contracts. No browser, download, share or personal file was used. The engine
source still needs the engine owner's overlay apply and build before the
arrival plays in a package; the Swift side is inert on an older engine.

DL33 closes: 33/33 DONE, +1/33 × 100 = +3.0 percentage points, and the Downloads
family is complete. DL-PERF-01 remains the separately queued post-polish task.
