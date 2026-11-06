# Page capture

Parc's capture session belongs to one existing renderer document in one native window. File → Capture Portion… starts region selection; Capture Visible Area and Capture Full Page request the corresponding original-page pixels. The same registered menu actions appear in command search, and the page menu has the same entry points. Capture Portion uses the existing configurable Command–Shift–2 binding. Holding Command and Shift while dragging directly over an eligible page starts the same region session; its separate checkbox in Settings → Shortcuts → Capture Portion enables or disables that gesture without changing the keyboard binding.

Move over a page area to reveal its outline, then click or press Return to capture that exact offered target. Drag to choose a freeform region. Capture Visible Page remains available through its button, or Return when no target is selected. Tab and Shift-Tab reach the native controls; an accessibility action captures the selected area. The output palette searches real actions: Save to Library, Copy, Save…, Send via iMessage…, Edit, Retake, New Easel and existing Easels. Edit opens the shared image canvas for text, images and shape/drawing annotations. Crop separately edits the full captured source; accepted annotations survive recrop. See [capture editing](capture-editing.md). Retake returns to live region selection. Escape dismisses the session. Save uses a native PNG save sheet and reports actual write failures. New Easel creates and opens a local document with the current capture; each existing Easel row inserts into that exact document. Both use the same asset import, document mutation and undo transaction as the webpage image chooser. The source page URL is retained as provenance; it is never replayed to obtain an image.

## Reference and adaptation



Fresh REA records `ev_a9274004d54b3dbfdd2c05aed3e455bbcc3c0659e1abdd34bbc7b485dd9753e3` and `ev_39347d7c1b6d00ac47d715c331cc3ecf317895aea46e7973f917765e471cf6db` cover the owner and drag slices. Their raw-slice Ghidra pseudocode truncates external branches and loses image globals. The retained Mach-O section mapping, SHA, LC_FUNCTION_STARTS boundaries and annotated original assembly are authoritative for the statements above; pseudocode is not original source.



Parc retains the page-owned selection and searchable output structure. CAP18 replaces the initial fixed side-by-side preview and approximate palette with the recovered original-rectangle frame, side/vertical palette anchors, row metrics and named light/dark state colors. Narrow split fitting, local crop editing and conservative cancellation remain explicit adaptations. See [capture presentation](capture-presentation.md) for the recovered contract, resource provenance and component checks; this is not pixel-matched browser acceptance. The element outline and clear veil interpolate together from their current presentation paths, with immediate clearing and Reduce Motion. CAP24 replaces the provisional interpolation with the recovered 0.35/0.87 spring and 90-ms latest-target throttle; [capture motion](capture-motion.md) records interruption, Reduce Motion, native focus and feedback ownership.

## Native capture mechanism

`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`.
Viewport helper `0x685af2c` forwards to the same region route, `0x685afbc`.
That route requires visible initialized original WebContents and a live
main-frame widget; its surface-copy call uses the selected rectangle and zero
output size, preserving device-scale pixels. REA
`ev_95e1cb277f01f0920cb8a6c2589cf759603fb0780c34683587b55f51db2b4495`
corroborates the path; complete original instructions establish the external
failure branch that the raw decompilation truncates.

Full-page `0x685b274` uses the page-owned protocol wrapper. Continuation
`0x684435c` constructs `Page.captureScreenshot` with `fromSurface=true` and
`captureBeyondViewport=true`; callback `0x6844cc8` resets the same temporary
view override and decodes the returned PNG. REA
`ev_0e6abe78f1cd45eb920b135a2c14d244fe8ddc07bfec50cec777c3ce599720e0`
and original image literals distinguish this from viewport copy.

Parc implements those two native paths above its independent Chromium. It
keeps a weak original document, Profile/OTR and browser-window identity, checks
real screenshot policy and permits one pending operation per WebContents.
Cancellation rejects stale protocol/worker results and restores only the
screenshot's temporary scrollbar/document preferences and original renderer
geometry. Full-page capture refuses an already attached debugger so it cannot
take over another client's device emulation. Integral outward rounding,
current Chromium's dimension limits and explicit 10-second surface /

## Ownership and output

`PageCaptureController` adds a shell sibling over the actual renderer viewport. `viewportFrame` is the native lease's admission rectangle in the stable page host, excluding a native infobar shelf; `viewportSize` is the upper-left-DIP capture space. The renderer is not reparented. The selected page may be a split pane or the accepted Peek page; both retain their actual native identity.

The shell snapshots the original page, tab, Profile, Space, native window, app-owned container frame, page-host frame and root/window geometry. Selection/profile/Space/transfer/close/layout changes retire the session. Native validity independently owns the original document, renderer bounds, profile, screenshot policy and security reservation. Its full-page capture owns any temporary renderer-surface resize and restores it before delivery. A generation guard drops stale image callbacks.

Read-only capture eligibility does not require key focus so the owning command bar can list the command. Starting the lease and every capture still requires the genuine key source window after that panel is dismissed. The native callback and invalidation are asynchronous on the main sequence. A screenshot result contains actual PNG bytes or an actual error; missing pixels never become a placeholder image.

The output lease survives its own Save/Easel sheet and OS message composer but retains original-document and security validity. Each output revalidates it. Canceling an owned save sheet cannot dismiss an unrelated sheet. Successful Copy/Save closes capture and restores the original renderer only if its window and selection remain current. A successful Easel insertion closes capture and opens the saved local document through the ordinary model route.

## Element selection



Hover callbacks are paired with the current shell phase and monotonic request generation. Pointer exit, drag, Retake, capture completion and dismissal clear usable offers and accessibility actions; a pending query cannot restore a target after a transition. A click before the first hover reply asks the same native geometry service and captures only a genuine result. Native click validation remains authoritative even when a reply races pointer input. The app keeps the current mouse-move setting only for this overlay and restores it on dismissal. Keyboard and accessibility entry invoke the same opaque token path, with native Tab traversal to visible-page/cancel controls. The three-point direct mouse drag threshold remains an explicit current-AppKit choice; CAP17 retains the native pan threshold. CAP24 supplies the recovered lens motion and bounded native-feedback contract in [capture motion](capture-motion.md).

Original document/profile/window/selection/geometry invalidation applies equally to hover and click. The output PNG continues through the existing preview, crop, Copy, Save, Easel and separately integrated Library/Portrait owners; this follow-on adds no independent image or output pipeline.

## Remaining family work

Richer editing affordances and the [capture motion/focus contract](capture-motion.md) retain separate owners. CAP17 supplies the original gesture/shortcut; CAP18 supplies the recovered static preview/palette geometry and visual states with explicit compact-pane/crop adaptations. Portrait composition and output are implemented below; its controls, backing density and live desktop source are completed in [Portrait fidelity](portrait-capture-fidelity.md). The [CAP22 capability investigation](capture-capabilities.md) distinguishes this screenshot producer, website stream indicators and existing filesystem recordings; it establishes no standalone recording workflow. No browser functional tests or runtime parity claim accompanies this source batch.

Saved captures now have a local Library path: the capture palette's Save to Library toggle commits the real PNG and original metadata, and Library's Media category browses, previews, copies, exports and deletes those captures. See [saved capture Library](capture-library.md) for ownership, disk failure behavior, reference evidence and explicit adaptations. This is separate from OS media discovery and recording.

## Direct destinations and Messages

The palette places output actions first, Edit/Retake next, then New Easel and actual profile-owned Easel rows. Search filters the real titles, Up/Down skips unavailable rows, Return executes the selected row, and Escape dismisses capture. Each existing row carries its original document UUID. CAP20 now ranks existing destinations by original profile-owned Sidebar activity, initially shows two with Show More, and searches all real destinations using lowercase substring matching of the current displayed labels. Selection survives title changes by UUID. See the [destination and message contract](capture-destinations.md) for exact recovered ordering, original source attribution and explicit local ownership adaptations.

`EaselImagePlacement` validates the actual PNG before creating anything, reopens the exact destination ID, imports the original bytes and commits one undoable image insertion. It preserves existing contents and source URL metadata. A new document is removed if its insertion fails. The result retains the actual session until its editor adopts it, preserving undo history. A stale/deleted destination reports an error and refreshes the list; it does not create a substitute. No selected page is recreated or navigated to obtain pixels.


`CaptureMessageSharing` checks the real service's ability to perform with the prepared URL/image items, owns its delegate and original source-window/frame, and passes those same item types to macOS. Unavailable service disables the row. Cancel/failure callbacks return to the existing capture preview; success retires the capture without claiming recipient delivery. Duplicate output is disabled while the service owns its operation. An original-document/profile/window/security invalidation detaches the callback and retires Parc's preview. AppKit provides no public service cancellation operation: once the user invokes the composer, Parc cannot retract its immutable payload or close that separate OS-owned UI. No actual message or share action was invoked during implementation.

The integrated CAP20 destination component passes 43 assertions over production activity ranking, expansion/search/selection, original URL/image-only payloads, Easel import, exact PNG round-trip, shared-session adoption and undo/redo, append preservation, expired source, deleted UUID and invalid image. Final whole-module SIL after CAP17/CAP18 integration passes in 29 seconds with zero diagnostics. Earlier native capture and queued-engine-overlay checks remain historical evidence; CAP20 changes no engine inputs. Destination ranking and capture message attribution are resolved as detailed in the linked contract. Share-composer cancellation appearance, new-row motion/haptics and full visual matching remain comparison details; no runtime acceptance is claimed.

## Portrait capture

Capture Portion, Capture Visible Area and Capture Full Page enter the same
page-owned preview and searchable output palette. Capture Visible Area is also
available while selecting a portion. Frame in Portrait Mode opens the existing
Color/Page/Desktop, gradient and Parc-watermark controls using the captured pixels.
Apply Frame commits a composed PNG and returns to that same output palette; Edit
Portrait Frame and Remove Frame are then available. Cancel or Escape in crop or
framing returns to the unchanged preview. Escape from the shared preview dismisses
the capture and restores original-page focus. The separate File/page-menu Portrait
entry is removed. The Developer toolbar's compatibility shortcut captures its
viewport once and opens this same framing editor, without a second pixel owner.

This unified flow is an explicit user-requested Parc improvement (CAP-10), not a
native PNG and pixels, the unframed crop, and optional retained composition. Editing
a frame always renders from the unframed crop, never from its previous framed output.
Removing the frame restores the exact unframed PNG, including full-resolution source
pixels that Portrait had scaled down. Crop starts from the original image, permits
recrop, and reapplies any accepted frame atomically. Rendering/encoding failure leaves
the previous output untouched. No framing or crop action calls the native capture API.

Copy, Save, Library, Easel and Messages all receive the currently previewed PNG
through their existing output owners. A saved Library item keeps its ID/revision
transaction while a changed crop/frame updates its bytes; canceling an edit does not
write. Framed output has Library kind `portrait`; removing the frame restores the
original region/viewport/full-page kind. Retake creates a new capture identity and
repeats the acquisition mode (region returns to selection). Source URL/title,
profile, Space and capture date remain those of the original page lease.

The lease exposes only the actual original document's optional Chromium
`GetThemeColor()` as `pageThemeColor`, after its ordinary validity check. The shell
retains this tint when capture completes, so later frame edits use the captured context. There is
no URL lookup, cross-profile source or Space-theme substitution. Color backgrounds
blend the nine already bundled ThemeEditor brand colors. Page mode uses the genuine
page theme or the recovered palette-at-0.95 fallback. Desktop mode captures the original window screen’s actual system wallpaper
window with permission and exact display/PID ownership, retaining those pixels
for the composition. Unavailable desktop images disable that choice with an
explanation; see [live desktop fidelity](portrait-capture-fidelity.md#live-desktop-and-lifetime).
Independent preference keys remember each changed option without overwriting
another simultaneously open capture's unrelated setting.

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`)
The reference operates on NSImage logical dimensions: it scales the source down
to a maximum side of 2160 without enlarging it, then adds 384 on each axis. Parc now applies those constants to logical dimensions and retains the original
window’s backing density for deterministic PNG export; see the [density contract](portrait-capture-fidelity.md). It draws the content at inset 192 and its eight-point frame,
uses outer/inner corner radii 10/6 and a shadow offset of −4 with blur 16. The
optional brand mark is centered at y=96 beneath the page. Its color background
uses hue-shifted gradients and the recovered pale-color branch. These constants
are from original-image instructions, not the separate thumbnail's 140×96 layout.

REA evidence `ev_de91f297da4a633beeb02f133b80af3e18723d505008e0b0b9dd79546e885c7c`,
`ev_877fd86c80e0a44efaa185b7f3eb3fe1b5a06fc192afd9da4c7299ad07e29cfe` and
`ev_d3676433fade61e214e05227bf737e5e6eeae55d807c787cb8eb2b0210269b87`
retain bounded raw-slice analyses. Raw-slice decompilation truncates external-call
control flow; the complete, annotated original-image instructions establish the
compositor branch and constants. This is recovered behavior, not original source.

Portrait Mode opens a separate configuration popover with the capture button,
watermark toggle and preview. Escape returned to the original page. The screenshot
surface omitted that separate popover, so its detailed geometry is not attributed
to this observation. Parc currently uses a compact native card in the original
a 32-point skeuomorphic Apply Frame control, the 140×96 preview chrome and the
color/website/desktop row. Escape still returns to the shared preview. It can extend beyond a narrow split pane while the lease
and dimming overlay remain attached to the original page. Return confirms;
Escape returns to the shared preview; source invalidation, window movement,
selection changes and teardown still retire the existing capture owner. Parc intentionally uses its approved P silhouette and name
in the watermark. The [monochrome UI mark](app-icon-marks.md) uses the same
background-dependent ink as the wordmark and leaves the bowl/exterior clear.
haptic or unmeasured motion is added.

The final 58-file combined Swift app check and native capture syntax check pass
with zero diagnostics. Standalone compositor and isolated-preference checks pass using a labeled
red/blue pattern: source pixels survive composition, backgrounds affect only the
exterior, remembered options reload, the optional watermark changes output, and
preview dimensions remain bounded. These checks do not run a browser or claim

The CAP-10 combined 61-file Swift app compiler check passes with zero diagnostics.
CAP-10 extends the reusable compositor component with actual production
`CapturedImage` checks: repeated frame changes do not double-frame, removal restores
exact original/cropped PNG bytes, crop preserves/reapplies framing, failed edits
leave committed pixels intact, and tall images regain their original resolution
when framing is removed. These are deterministic image/component checks; they do
not establish browser-runtime or exact visual/motion parity. No new native provider,


## Capture entry and drag admission — CAP17

event must contain the complete modifier mask `0x120000` (Command and Shift),
and `dragToCaptureDisabled` must be false. The mask tests presence, so Option,
Control or Caps Lock do not suppress an otherwise admitted drag. The gesture
on `.began`, then forwards the same recognizer throughout its lifetime. The
selection view records the point when the native pan begins, after AppKit's
threshold; it does not substitute the earlier mouse-down point.

binding. Parc uses its own defaults key and absent-value enabled fallback. The
existing Keyboard delivery already recovered Command–Shift–2 from MainMenu
record263 and owns customization, priority, migration and command search; CAP17
does not replace that registry or re-register its default.

`PageCaptureGesture` is attached once to the window root but admits only a hit
inside the actual visible renderer container, excluding chrome, native infobars,
Library and other overlays. A split pane is admitted through the existing pane
activation owner. The pending admission retains weak original page/browser/window
identities, document revision, Profile and Space, and checks native screenshot
eligibility before recognition and lease creation. Changed ownership or a newly
disabled preference cannot begin a stale admission. Every ongoing gesture uses
the existing controller's geometry/document/security reconciliation and freeform
region pipeline. Cancellation retires that capture; terminal events clear the
gesture's weak session. Site Control Center capture actions revalidate their original page/document,
window, Profile and Space after native popover dismissal and before execution;
changes during that asynchronous interval cannot capture a different page.
No app-wide event monitor, synthetic mouse event,
replacement renderer or separate screenshot producer is installed.

The File, page and pane-title menus expose Portion, Visible Area and Full Page
through that original owner. Menu hints use current configured bindings. The
pane-title menu no longer offers a separate Portrait entry. Site Control Center places Visible Area in the ordinary second button slot
Full Page remain beside it in the existing four-column geometry. Portrait
framing remains an output edit for every acquisition mode. These are explicit
Developer toolbar's retained compatibility action still captures once and opens
the shared frame editor. CAP18 owns selection/crop/preview/palette geometry;
CAP17's `handleCaptureGesture` only forwards points and terminal states into the
existing selection fields. CAP22 owns recording investigation and CAP23 OS media
discovery; neither changes screenshot admission.

Reference recovery used the retained component/type/cross-reference/annotated
function helpers only, without a new heavy decompilation. The original annotated
instructions are retained in `work/capture-coordination/cap17/entry-arc1122.asm`.


CAP17's complete source passed whole-module SIL in 31 seconds with zero diagnostics
and fresh independent code review. Inert checks passed 108 shortcut-detail,
63 Site Control Center and 14 gesture admission/lifetime assertions. The
Site Control Center check includes an original owner changing during native
popover dismissal and after `didClose` but before queued dispatch; neither may
execute its old capture action. The gesture check uses isolated preferences and
recognizer/owner doubles without posting input or constructing a renderer.
Receipts and checked hashes are retained in `work/capture-coordination/cap17`;
final compiler receipt is `work/claude-split-checks/cap17-final5.json`. These
checks establish source/component behavior, not browser-runtime or appearance
acceptance.

CAP19 closes the remaining Portrait controls, backing-density, color/contrast and dynamic desktop implementation; [the focused contract](portrait-capture-fidelity.md) supersedes the earlier compact-card/static-wallpaper adaptations above. Whole-family motion/focus remains CAP24.

## Private capture increment — WIN11


