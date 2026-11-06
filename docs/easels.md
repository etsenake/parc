# Local Easel editing


## Object-wide text styles

`EaselItem.textStyle` stores a family and size. An absent style in an existing version-1 document resolves to Clean / Body without rewriting the document. Unknown enum values fail decoding rather than discarding formatting. The style applies to selected whole objects on the canvas. While a text object is being edited, the palette applies to the actual selected range; with a collapsed caret it changes future typing attributes. A text-only object selection displays family, size, decrease and increase controls; mixed selections do not display text controls. Size changes grow the object when needed and preserve its existing minimum frame.

| Family | Body | Heading 2 | Heading 1 | Title | Display | Font |
|---|---:|---:|---:|---:|---:|---|
| Mono | 15 | 24 | 44 | 60 | 80 | Space Mono Regular for Body; Bold otherwise |
| Fancy | 16 | 28 | 48 | 60 | 80 | EB Garamond Regular |
| Hip | 18 | 21 | 44 | 60 | 80 | Söhne Breit Buch / Dreiviertelfett / Extrafett |
| Clean | 15 | 24 | 44 | 60 | 80 | System Regular / Bold / Heavy |


Double-click or Return enters the selected text object. Escape returns focus to the canvas. Changing a style preserves the UTF-16 selection and returns focus to the text editor. The `NSTextView` owns a local undo manager; keyboard/menu undo and redo use it before falling back to document history. Range style changes finish the current native typing-history boundary and register an actual native undo operation. Bold and italic emphasis survive palette changes when the selected font provides those traits; unsupported combinations report an error before changing text. Marked-text composition is left to the native input method and is not serialized or restyled mid-composition. Document transactions coalesce consecutive edits during the same native editor lifetime under one ephemeral editing UUID, while every edit remains durably saved. Native Undo/Redo retains individual action boundaries; document Undo after the editor closes restores its original object state. An intervening transaction, undo or redo breaks that grouping. Shared-session updates use the latest saved document and discard obsolete local typing history when another owner changes the edited text or its range attributes. The canvas, editor and clipboard all use the same attributed-string conversion; updates carrying the current semantic content do not reset native typing history.

## Content-hugging text fill and native metrics

The selected-text palette's **Text fill** control applies to complete selected
text objects, including while their native range editor is active. Mixed
selection shows a mixed checkbox; non-text selections do not offer it. The
backward-compatible optional `EaselTextStyle.fill` stores `contentHugging`; missing
or `none` means off. Existing documents do not receive a migration write. The
private styled clipboard, duplicate, durable save/reopen and document Undo/Redo
retain the style. Composition refuses changes. Fill changes break native typing
coalescing without replacing the original text, range attributes or selection.
Native fill inverses update the same durable editing group, so leaving the
editor cannot replay already-undone fill. They retain its original document
history anchor and refuse a changed style or an intervening shared-owner
transaction. Failed saving retains the saved objects.

A black fill follows the visible text lines with white display ink. The original
colors, links, fonts, paragraph attributes and image bytes remain unchanged;
turning fill off restores them. Canvas drawing, native editing and CAP21's
memory-only annotation renderer use the same TextKit glyph measurements.
Native range editing uses temporary foreground attributes, never saved white
ink. Notes do not enable this canvas presentation mode.

`EaselFillStyle` is `none` / `contentHugging`. Original text-view initialization
bounds, then derives its visible vertical frame from ascent, descent, cap
those glyph frames and adds the same horizontal padding. Empty lines remain
with tangent arcs clamped to their adjacent midpoint distances.

The older secondary values (Mono/Clean 24/36/66/90/120, Fancy
24/36/72/90/120, Hip 27/32/66/90/120) are **not attributed line heights**.
No data reference to the getter is indexed. The actual visible geometry above
consumes native metrics instead; Parc does not impose a speculative line-height
constant or alter imported paragraph metrics.

Its existing five-by-four editor inset and five-point line-fragment padding
owner: each line uses its actual fonts, image attachments keep their real cell
bounds, and authored sizes remain intact on resize. The checkbox and expanded
native palette are presentation adaptations; [static appearance](easel-appearance.md)
and [motion](easel-motion.md) describe the completed native treatments and boundaries. No engine or browser provider is
involved. All reference findings came from retained contracts and local
annotated-function/type/cross-reference helpers, with no new heavy decompile.

The finished integrated tree passes whole-module SIL across 257 Swift sources
with zero diagnostics. Inert components pass 283 model, 531 rich-text, 165
canvas, 51 capture-destination, 10 native input and 25 CAP21 assertions. These
cover all twenty palette fonts/sizes, actual emoji/CJK/Arabic fallback faces,
inline image bytes, blank-line gaps, finite clipping, synchronous smoothing,
real mixed-checkbox activation, failed persistence and native/document history
boundaries including another owner's transaction. Windows remain hidden and
pasteboards are private. Fresh independent review cleared the corrected source;
these checks do not establish browser or installed visual acceptance.

## Range formatting and persistence

`EaselItem.richText` is optional, so existing version-1 documents continue to load without a migration write. When present it contains ordered, contiguous UTF-16 runs covering the object's original `text`. Validation rejects overlaps, gaps, overflow, surrogate splits, unsafe links, non-finite font/paragraph metrics, excessive run counts and range data on non-text objects. Native font identity, size, traits, variable axes, sRGB ink/background, underline/strike, links, kerning/baseline and supported paragraph/tab/list attributes are retained. Inline image attachments use the bounded range carrier described below; non-image attachments, table/text-block and other unsupported attributes fail explicitly. Missing fonts in a subsequently changed OS environment use the recorded size/weight and native system fallback; Parc does not download fonts.

The editing palette adds real Bold, Italic, Underline, Strikethrough and Link controls. Mixed or unrepresentable family/size selections show no single palette value. Emphasis controls reflect the actual range. Link editing retains the original editor, selected range and content revision, accepts http/https/mailto/tel addresses, and retires with the editor; an intervening edit invalidates the pending action. Ordinary web links use the Easel's existing open-URL callback, while explicit mail/telephone links use the OS handler. The canvas has no new browser or document owner.

The range controls retain their native owner inside the recovered compact rail's disclosure. [Static appearance](easel-appearance.md) records recovered geometry, semantic surfaces and native control adaptations; [motion](easel-motion.md) records annotation transitions and their lifetime rules. Default selection and empty-object disposal are recovered and implemented below.

## Clipboard boundary

Copying a text object or a selected range publishes the version-3 Parc styled-text carrier, real RTF (RTFD when images are present) and plain text. A copied substring rebases its original range attributes to zero. The private carrier preserves the palette and native font metadata; legacy version-1/2 private carriers remain readable. AppKit's RTF exporter may substitute its private system font, so external RTF imports preserve the actual font carried by the RTF rather than falsely relabeling it Clean. Cut deletes only after successful publication of all representations.

Canvas paste creates a text object with its actual mixed runs. Native editor paste inserts attributed content at the original selection using the existing native text/undo owner; Paste as Plain Text inserts words using receiving typing attributes. Supported mixed font, color, emphasis, link, paragraph and list metadata survive both paths. Unsupported non-image attachment/table/attribute data produces an explicit Paste as Plain Text error without changing the editor or clipboard. Size limits are checked before decoding and before publishing. Existing image/file/link paste and captured-image-to-Easel persistence are unchanged.

The editing palette also provides Text, Heading 1–3, Bulleted List and Numbered List. Paragraph commands operate on the whole original paragraphs touched by the selection; a selection ending exactly at the next paragraph start excludes that paragraph. A collapsed caret applies to its current paragraph. Existing inline colors, emphasis, links and fonts remain attributed ranges. Heading sizes are 32, 26 and 22 points; the selected font family and emphasis are preserved. The separate object-wide four-family/five-size palette stays available.

Lists use actual `NSTextList` stacks and tab-delimited marker characters, with matching paragraph indentation. They render, copy and persist through the existing native codec. Marker removal validates the actual supported native marker format; imported tab-delimited words are retained even when list metadata is present. Return continues a nonempty list; Return in an empty item or Backspace at its content start reduces one nesting level, exiting at the outer level. Tab and Shift-Tab change list nesting up to seven levels and otherwise retain native text behavior. Return after a heading prepares body typing. Structural insertion, deletion and joins renumber supported ordered lists and retain the original selection, rather than replaying plain text. Each paragraph operation has one native undo record for text, selection and typing attributes; the original EaselSession retains durable document undo. Composition and multiple-caret states refuse paragraph commands. No new global keyboard shortcut is introduced.

`EaselRichText.Paragraph.heading` is optional for backward-compatible documents and preserves native `headerLevel` through the codec. A system font at a heading size outside the object palette is restored through the public AppKit system-font API; its private name is never passed as a named font that could silently substitute Times. Inline image authoring is described below; the non-image/external clipboard boundary is resolved in EASEL21 below. Table editing is not supplied by the recovered rich-format carrier, and embedded browser objects retain their separate owner.

## Typed markdown

In an ordinary text paragraph, typing a space after `#`, `##` or `###` turns that original line into Heading 1, 2 or 3. Typing `- ` or `* ` begins a bulleted list; `1.` followed by whitespace begins a numbered list. Up to six leading tabs select one of seven native nesting levels. The resulting lists use the existing Return, Backspace, Tab and Shift-Tab behavior above. Existing heading/list metadata prevents interpreting another list prefix inside that structure.

Single `*word*`, `_word_` and `-word-` delimiters apply native bold, italic and strikethrough to the enclosed original word ranges when the closing delimiter is typed. Multiple words separated by whitespace are supported; the recovered expression requires a word boundary and word characters, so punctuation-bearing bodies stay literal. Delimiters disappear while links, color and other supported attributes remain. The prior typing attributes are restored for subsequent input. This recovered syntax is distinct from general Markdown: double asterisks, double tildes, backticks and Markdown links have no inferred authoring behavior.

Conversion is an exact native input-range operation, not a whole-document parser. It requires a single typed character at a collapsed caret and verifies that the actual post-insertion text and caret still match the admission. Selection replacements, imported/RTF/private/plain-text paste, active marked-text composition and Undo/Redo do not trigger conversion. Incomplete and unsupported syntax stays literal. The native text delegate and rich-codec validation may refuse a conversion without deleting the accepted input. Only the affected line is transformed; unrelated imported lists are not normalized.

The same text view, native undo manager and durable EaselSession own the resulting edit. Typed insertion and conversion share the native input transaction; undo/redo restores the original attributed content, selection and typing state without rerunning the matcher. Escape retains the existing editor dismissal and canvas-focus return. There is no new asynchronous operation, popover, shortcut or special Escape/Backspace rollback.

## Reference and checks



`bash scripts/test-easels.sh` exercises real model save/load/undo/failed-write behavior and native attributed editing/clipboard conversion in an app-shaped font-resource bundle. It uses a unique named pasteboard and temporary documents, never the user's clipboard or browser. Full app compiler checks are separate from these components and do not establish browser runtime or complete visual parity.

### Paragraph authoring evidence and limits




### Markdown authoring evidence and limits




## Canvas selection and original-object transactions

The native canvas owns transient selection separately from the shared document. Dragging empty canvas creates a marquee in either direction; release replaces selection, Shift adds intersecting objects and Command removes them. Shift takes precedence when both modifiers are held. The temporary outline does not persist or mutate document history. Escape cancels the marquee and preserves the prior selection. Existing Shift-click selection and responder-chain Select All remain available; Return enters the selected text object's original native range editor, whose Escape returns focus to this canvas.

Moving a selection retains each original ID, frame, kind and drawing points. All selected objects receive one translation, clamped as a group at the canvas origin so their spacing survives. Movement and resize guides now use the original-group content/guide owner described below. One original-group frame now supplies the selected objects’ corner and edge resize controls, described below. Arrow keys move the selected group by one point, or ten with Shift, using the same geometry transaction. Native text editing keeps its own arrows and selection.

Preview geometry is merged into the latest shared EaselSession document. Unrelated objects, selected-object text/style, assets and z-order updates remain current. A selected object disappearing, changing kind/points/frame or moving to another document invalidates the entire original geometry transaction. Escape, first-responder loss, window resignation, tool change and canvas detachment retire pointer state without writing. Accepted movement or resize is one real durable transaction and one document undo operation; failed saving leaves the document unchanged.

Duplicate, Bring to Front, Copy and Delete context commands retain the original document, selected objects and native window while the menu tracks. Changed original content, selection or detached ownership refuses execution. Paste and Paste as Plain Text also validate the captured native window and menu generation before reading the clipboard or dispatching an import. Duplicate gives each copied object a new UUID, retains its actual content/rich ranges/image asset references and relative geometry, and appends the group in selected z-order. Selection changes only after a successful save. Undo removes the complete duplicate group and Redo restores those same UUIDs. Imported images and text still use their existing persistence and native editing owners.

### Canvas evidence and adaptations

Parc still CPU-draws ordinary objects into the canvas dirty rect and only hosts per-object surfaces for embedded pages. Layout and pointer invalidation dirty the union of frames whose pixels actually change rather than every object. This is a paint-path correction, not a claim that the Easels family is complete.




The reusable Easel checks now exercise real file-backed group transactions and native canvas mouse/key/menu events in a never-displayed isolated window. They include cancelled marquee/move, original geometry conflicts, concurrent content preservation, exact menu targets, save failure, native text focus and owner detachment. The final fixed-cohort app typecheck passes for 72 Swift sources with zero diagnostics; components pass 118 store, 255 native text and 24 native canvas assertions. These checks do not establish functional browser or complete appearance parity.


## Original-group frame resizing



Corner hit regions are 20×20 points; edge strips are 10 points thick and exclude the corners. Idle edges hide below a 30×30-point group; an active edge remains visible while shrinking. The white/accent corner squares, edge pills, crosshair corner cursor and immediate preview use Parc's existing AppKit drawing. Their exact visual design is an explicit adaptation, not a recovered screenshot. No new animation or haptic is introduced. Body moves with cumulative pointer travel of at most three points cancel; frame handles use their separate precise end route without that threshold.






## Content hits and transient alignment guides

Pointer and context-menu selection now share the original-object content hit policy. Selected objects retain rectangular manipulation targets. Unselected large circles reject transparent corners; arrows/freehand use a round, 30-point-wide stroke hit region. A small object receives a centered minimum 30×30-point target, scaled to the screen. Rectangle, text, image and link/card objects retain their content bounds. The actual selected native text editor continues to own text selection, composition and caret interaction. No bitmap alpha sampling or web-card navigation is invented.

Marquee selection delegates to content geometry too: arrow segment/rectangle intersection, original freehand sample inclusion, filled ellipse intersection and ordinary frame intersection. Already-selected objects retain frame-based manipulation selection. Empty stroke/circle bounds no longer obscure objects behind them. Parc's existing rendered arrowhead and local drawing points are the authoritative path coordinates; imported image pixels and rich text remain untouched.

A transient guide solver belongs to one original group gesture. Visible, nearby original targets offer top, bottom, left, right, vertical-center and horizontal-center anchors in the recovered order. Orthogonally overlapping neighbors also offer the recovered 24-screen-point separation. Admission is strictly within six screen points, doubled for the horizontal-center guide; acquiring a new guide requires axis velocity below 125 points/second, likewise doubled for that center guide. Once acquired, perpendicular travel increases its release radius up to 3.5 times the admission radius. Command suppresses guides immediately and reversibly. The native canvas menu exposes the actual checked **Use Alignment Guides** state.

Guide corrections feed the original group's move or frame-control proposal, not independent member edits. A changed/removed guiding target loses its guide; changed selected geometry cancels the gesture. Later guide corrections supersede earlier ones, and only lines satisfied by the final group are drawn. Preview, Escape, window/responder loss and single durable undo retain the existing transaction. The toggle is local to the canvas/window; it does not change content or personal system preferences.



Final fixed-cohort verification: 72 Swift app sources, zero diagnostics; reusable components pass 177 model, 255 native rich-text and 53 native canvas assertions. Checks use isolated file-backed documents and never-displayed windows, including hit-through targeting, guide acquisition/release, 24-point spacing, fast motion, hysteresis, exact target replacement, modifier/toggle behavior and single undo. Compiler/component evidence does not establish browser or installed appearance acceptance.


## Canvas anchors and original resize centering

The logical canvas offers left and right margins at **42/1000 of canvas width**, plus its horizontal center, before the existing object and spacing guides. These use the same acquisition, release and Command-suppression path. The recovered producer does not add vertical canvas margins or a canvas vertical-center guide.

At each original gesture begin, the editor captures the guides whose independently adjusted original union would remain unchanged within the recovered strict **1e-6 normalized** tolerance. It does not interpret the ordinary six-point snap radius as an existing alignment, nor persist guide state in the Easel document. A later gesture recomputes from the current original objects and canvas.

For frame controls, a captured centerX guide keeps the original horizontal center; a captured centerY guide keeps the original vertical center. These are independent axes. Live Option adds both axes, and releasing Option returns to the captured axes without accumulating deltas. Command and **Use Alignment Guides** suppress subsequent snap corrections/highlights through their separate live path; they do not rewrite the already captured centering policy. An exactly aligned fixed axis retains its actual guide even when the frame-control adapter has no correction for that axis. Body moves remain translations.

The same window-owned gesture retains original document, selection, members and geometry. Cancellation, commit, selection changes, original geometry replacement, focus loss and detachment retire its anchor snapshot. A later change to a guiding neighbor retires that snap target but does not alter the starting center of an accepted original gesture. Parc explicitly cancels on logical canvas-width change rather than retargeting captured anchors to new coordinates. The existing shared-session save and single undo commit remain the durable owner.



Final fixed-cohort verification for this owner: 72 Swift app sources, zero diagnostics; the existing reusable component entrypoint passes 197 model/store, 255 native rich-text and 63 native canvas event assertions. The added cases cover the recovered canvas margins, exact versus near initial alignment, independent axis centering, Option/Command changes, original-target replacement, width/focus cancellation, fresh next-gesture ownership and one durable undo. Components use isolated file-backed documents and never-displayed windows; they do not establish browser or installed visual acceptance.


## Arrow endpoints and image aspect controls

A selected, ordinary two-point arrow exposes its actual start and end. The pointer target is 20 × 20 points around the rendered endpoint, with the recovered pointing-hand cursor. Dragging one endpoint retains the original opposite endpoint, direction, item identity and styling, including crossing, flat and coincident positions. A precise one-point endpoint drag can commit; it does not inherit the body-move travel threshold. Native Escape, focus/window loss, changed original points, selection and canvas-coordinate changes retire the preview. The shared EaselSession commits only the final original geometry, with one undo.


Image, web-card and link controls preserve the original frame ratio by default. Generic multi-object controls preserve it when any member has that policy, or while Shift is held. Command takes precedence and temporarily permits ordinary frame resizing; releasing it recomputes from the same originals. Single shapes and text retain their own plain frame-control owner. Corners project the proposed pointer geometry onto the original-ratio diagonal through the opposite corner. Side handles derive the other dimension about the proposed midpoint. Live Option and independently captured center axes use the recovered centered branch. Crossing preserves image pixels instead of reflecting the image payload.

The existing guide solver couples corner corrections on both axes. Shift on a single image uses its actual loaded image dimensions for the guide-correction ratio; the resize itself still uses the original frame ratio. Guide lines describe only the final accepted geometry. No image is resampled or rewritten: imported/captured PNG bytes and asset identity remain intact through resize, undo and reopen.


EASEL25 below resolves the endpoint selected/hover/pressed, guide correction and web-card/link intrinsic-size contracts. Keyboard/AX navigation and motion/haptics remain separate rows. This native document/editor work has no engine dependency.

The fixed 72-source app check passes with zero diagnostics. The reusable isolated component entrypoint passes 224 model/store, 255 native rich-text and 77 native canvas event assertions, including intrinsic-image guide correction, original endpoint crossing, modifier reversal, focus/Escape cancellation, one undo, disk reopen and unchanged PNG bytes. These receipts establish the checked source cohort, not installed visual acceptance.



## Endpoint and guide feedback — EASEL25

Arrow endpoints retain their original start/end identity and 20-screen-point
pointer target. The selected mark is eight screen points across with a 2.5-point
inside border. Hover uses the pointing-hand cursor; press does not change its
fill, size or border. The recovered `DragHandle` uses `EaselSelectionColor`
(#6CBAD9) around `FloatingElementBackground` (white in Aqua, black in Dark Aqua).
Parc renders those same circles and colors without adding a separate hover or
pressed tint. Screen dimensions follow the canvas magnification, including the
shared fixed capture editor. General frame-handle appearance belongs to EASEL27.

Endpoint gestures participate in the original transient guide owner, but refuse
predicate at class slot 0xc0. An exactly aligned original group anchor can still
be highlighted. Parc now preserves that behavior while keeping the opposite
endpoint fixed, ignoring frame aspect/centering modifiers and clearing feedback
on Command, guide-toggle suppression, stale target geometry or cancellation.

Active guides use two separate paths with 2.5-screen-point round strokes. The
pale path (white 0.92) extends 0.015 of canvas width beyond the union of target
and moving frames; for centers, that union includes the moving frame's center
clearance described below. The blue path marks the actual moving edge. Center guides
leave the moving object clear: they split the pale path outside its frame and
use cross marks at both ends, with seven-screen-point stems, 0.75-stem half-bars
and `7 / 1000 * 1.3` canvas-width clearance. They are feedback, with no separate
hit target or hover/pressed state. Lines are emitted only for final accepted
geometry. Canvas targets retain Parc's visible-viewport extent adaptation.

Single-content Shift guide correction now uses real immutable image dimensions
for both images and captured web cards; a web card without usable image size
uses the recovered square fallback. Links use the recovered 220 × 160 intrinsic
layout. Resizing still preserves the original frame ratio; only the guide delta
uses this intrinsic ratio. EASEL23's live card keeps the same captured image
identity, so no live-page recreation or engine query is needed. Image bytes,
text insertion/cleanup, composition and the shared one-undo transaction remain
under their existing owners.

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
resolve path ownership and style. Only the two unresolved path builders needed
(`ev_d6b6683eb55ff58c36d2efa17632332047db956892dcee0b181100976955be58`)
(`ev_8efb38f1862b2f6fbee7362d12690150a9210a5b4cb44228b0d66c4d8a1433db`),
checked against original annotated assembly and constants. Pseudocode is not
original source.

SHA-256 `8c216c86ec8213e286488579ba332989f69121848c3fdba2ec01a2386da592b2`;
by Parc. Check receipts and raw evidence are under
`work/easel-coordination/easel25`. Model and inert native checks cover endpoint
alignment/refusal, retired targets, guide segments, pressed rendering, intrinsic
card/link ratios, original identity/undo and immutable pixels. The checked EASEL25 cohort passes 290 model/store, 340 rich-text, 147 native canvas,
51 capture-destination and 10 native web-input assertions. Whole-module
warnings-as-errors SIL passes with zero diagnostics. Independent review cleared
the exact source after correcting native pointer velocity conversion under
magnification, with 0.5× and 2× regressions. The reviewed increment reconciled
EASEL22 without changing its source delta or the text editor undo owner. These checks do not claim installed
visual acceptance, browser behavior, AX acceptance or motion/haptic completion.


## Inline images in rich text

While editing a text object, ordinary Paste can insert a supported image from native PNG/TIFF data or one user-supplied local image file. RTFD paste retains its actual mixed text and image ranges. Image insertion replaces the original selected range, adds a preceding newline when necessary and a trailing newline, and centers the image paragraph. The image occupies one U+FFFC character inside the existing text object; it does not create another canvas item. Keyboard selection, Delete, Cut, native undo/redo and text before/after the image remain under the same NSTextView owner. Paste refuses an active input-method composition instead of replacing marked text.

Each inline image retains its original PNG, JPEG or single-frame TIFF bytes and format in an optional `EaselRichText.Image` value. No source path survives import. Local file paste copies the bytes once with normal security-scope access and a bounded read. The image stays available after the source file is removed. The same EaselSession validates and atomically saves the complete text/ranges; document undo and reopen preserve the original object ID and image bytes. The model permits exactly one U+FFFC UTF-16 unit per image run. Encoded inline images are limited to 4 MiB per text object and decoded images to 16 megapixels, with the existing whole-document size limit still authoritative. Animated/non-image attachments and unsupported attributes refuse without flattening the original text.

Copy and native selected-range export use version-3 private data plus genuine AppKit RTFD for images; ordinary text still uses RTF. Older version-1/2 private text remains readable. The attachment's actual file wrapper retains the original encoded bytes through RTFD. Image-only native cells without encoded bytes use their real TIFF representation. Plain Text keeps the surrounding words and omits the object-replacement character. The same import/export codecs serve canvas text-object paste and native text-range paste; captured/ordinary canvas image objects keep their separate existing importer.

The attachment cell owns a weak native text container and immutable original image size. It fits both dimensions into container width minus 60 points without upscaling, returns the full line width and reserves 60 points beyond the displayed image height. Later container resizing recomputes from the original image dimensions; presentation changes never rewrite the encoded bytes. Non-editing canvas text binds the cell to the current text-object width.

The real native canvas component exercises successful persistence and an actual failed save. Shared-session rollback restores the original editor and discards its rejected native history. Undo registration is restored before the durable delegate runs, and balanced in-flight groups close before empty history is removed. An intervening later edit invalidates that cleanup, preserving its own undo. The same original document/window and native composition lifetime remain authoritative; no browser or engine service is needed.


Explicit adaptations are local byte-bearing JSON ranges, bounded supported formats, ordinary PNG paste, one complete insertion undo and current canvas coordinate binding. The original Easel-specific `imagesEnabled` wiring/default is unobserved; Parc enables this recovered rich-text capability in its existing editor. No speculative image toolbar button was added. Retained installed Easel/tool appearance supplies only general context: exact inline image hover, selection, context commands and accessibility comparison remain unobserved. Native component/compiler checks do not establish installed appearance or browser acceptance.

The merged full app cohort passes all 77 Swift sources with zero diagnostics. The existing reusable Easel entrypoint passes 233 model/store, 290 native rich-text and 87 native canvas event assertions, using named private pasteboards, temporary documents and never-displayed windows. Exact inputs include the six bundled fonts. These checks cover original encoded bytes through native RTFD, JPEG/TIFF/PNG import, source-file removal, selected-image deletion, composition refusal, actual shared-session save/undo/reopen, persistence refusal and intervening-edit cleanup. They are distinct from browser or installed appearance acceptance.

## Embedded webpages and captured cards

An Easel may contain a durable `browser` object, created with **Add webpage** using an HTTP(S) URL. Each open editor owns its own real auxiliary Chromium page under that window's exact profile. Selecting one browser object enables its original page input; the surrounding canvas retains selection, marquee, move and resize ownership. Overlapping canvas objects and handles win hit testing in their actual z-order. Back/Forward/Reload/Stop, site information, blocked popups, renderer recovery and capture-stop controls use the existing native page services. **Return to Easel** restores canvas input. Hiding the Easel parks the same page; local document reload does not reconstruct it.

The durable browser URL begins as the authored address and follows genuine URL observations from the exact selected embedded page. The same page retains its native navigation history; metadata publication never replays a URL into another open editor. Real page retirement precedes object removal, creation undo, destructive model replacement and parent-tab/profile/window closure. Shared-session replacement guards protect other windows and synchronous callers, while native batch beforeunload decides actual closure. Refusal preserves the original document. Intervening document or selection changes cancel the proposed mutation. The native request is cancelable before page creation; after creation its ordinary page-close path remains authoritative. Child pages never become normal saved tabs or Chromium session-restored tabs.

Screenshot placement creates a `webCard` with the actual PNG, original source URL/title and capture time. It draws and copies the real image, supports explicit Open Source, and persists/undoes through the existing image importer. Ordinary context-image placement remains an image object. Original renderer geometry, when available, enables the separate Make Live action described in [live captured regions](easel-live-captures.md). The stored image remains the original snapshot.


The merged 80-source Swift application passes with zero diagnostics; exact component inputs retain 245 store/model, 290 native rich-text, 98 native canvas and 26 capture-importer assertions. The paired native creation/session integration passes seven changed production translation-unit checks, facade checking and 14 request-lifecycle assertions. These are source/component checks, not browser or appearance acceptance.


### Webpage address, search and durable navigation

**Add webpage** and the selected webpage's address control use one native Address/Search editor. An address receives the recovered HTTPS prefix when omitted; only credential-free HTTP(S) destinations are accepted. Search retains its own text and offers the recovered All, Images, Videos, News, Maps and Shopping categories, initially Images. It constructs an ordinary DuckDuckGo URL and submits through the original embedded page's navigation path. No autocomplete request, POST body or native document token is reconstructed. Return submits, Escape cancels and eligible dismissal returns the original focus; marked-text composition stays with the native text system. Invalid input remains visible with an error. Object/page selection, retirement, hiding, window loss and conflicting sheets invalidate the original popover owner.




The fixed-source app compiler and reusable `scripts/test-easels.sh` cover this batch. The native input component uses actual AppKit text fields/marked-text composition with never-displayed windows; the store component covers real persistence, stale/refused ownership, failed save, reopen and undo/redo. Exact counts and compiler receipts are recorded in the parity ledger; none establishes browser or visual acceptance.


## Default text, selection and empty-object retirement — EASEL24

Add Text inserts the recovered real string **Start typing to enter text** and
selects it for replacement. An untouched prompt remains ordinary content.
Double-clicking empty canvas creates the same text at the pointer, using the
recovered 280 × 28 initial frame with its top 14 points above the click. Fixed
capture canvases clamp that frame to their original image bounds. Toolbar
insertion retains Parc's existing centered placement and minimum frame.
Keyboard entry selects the whole original text; double-click entry selects the
native word at the clicked position, except that the default prompt remains
fully selected. Native spelling is enabled while editing. Escape retires text
input, clears the canvas selection and returns focus to the existing canvas.

Text remains saved while it is being edited. Final dismissal removes only the
original text object whose saved content is whitespace/newline-only; U+FFFC
attachments and non-text objects remain meaningful content. Deletion uses the
same durable session and typing group, so undo restores the original content
and redo restores deletion. A failed save retains the original document and
editor and refuses the pending insertion, context action or transfer. Explicit
document Undo/Redo retires editing without inserting a new cleanup transaction.
No document-load sweep deletes historical objects.

Native focus dismissal waits for the responder transition and preserves the
current editor while its text palette or shown range-link popover owns focus.
A retained closed popover cannot suppress dismissal. Clipboard/drop completion
reports the actual insertion transaction even when empty-object retirement
keeps the total item count unchanged. A queued event from an old text view cannot change the current editor. If another
window has already changed the original text/runs, late input reloads that
saved content; final empty cleanup cannot delete it. The existing rich-text
editor, composition and shared-memory capture canvas remain the owners.

`canFinishEditingForTransfer` is a pure admission check for EASEL29: no active
composition or pointer transaction. `finishEditingForTransfer()` repeats that
admission and returns success only after the same final-edit boundary succeeds.
EASEL29 owns all-window preflight, page-close consent, closed-session checks and
source-pool retirement; the API creates no browser or Profile owner.

### Reference and checks

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The recovered-components, cross-reference, Swift-type and annotated-function
helpers answered this row without fresh decompilation. `EaselInputPreferences`
retains font family/color preferences/max text size; existing object-wide style
and EASEL22's separate fill/metrics remain their own contracts.

  which creates that text at the pointer with 280 × 28 / minus-14 geometry.
  input variant or the actual default string. Other input passes through
  a browser without a URL; Parc's existing validated browser authoring cannot
  persist that state, so cancellation leaves no placeholder browser to remove.

Parc's local persistence, coalesced durable undo, shared-session conflict guards
and asynchronous responder settlement are explicit ownership adaptations.
The inert Easel suite covers default replacement, whitespace disposal, undo/redo,
failed persistence, active composition, stale editor events, queued focus cleanup
after a closed Link popover, replacement drop success and exact original content. Capture's memory-only renderer remains separately checked. Compiler
and inert component results do not establish functional browser, accessibility
or final appearance/motion acceptance; EASEL25–EASEL28 retain those contracts.

## External clipboard and non-image boundary — EASEL21

Native text Paste recognizes a credential-free HTTP(S) URL from either the
standard URL flavor or an exact plain URL. A nonempty selected label becomes a
link to that URL. If the selection's text is itself equal to its first link
attribute, Paste replaces that self-labelled URL with the incoming URL instead.
A caret inserts the new URL as its own label. The actual selected UTF-16 range,
text storage, delegate and native undo own the edit; one Undo restores the
original attributes and selection. Composition and attachment-bearing labels
refuse before mutation. Following typing and explicit Paste as Plain Text do
not inherit the pasted link.

The canvas accepts URL-only pasteboards too, producing its existing local link
object. CAP21's fixed, memory-only image editor receives annotation text instead
and never creates a browser provider or persistent Easel. Explicit plain paste
can extract the URL flavor as words. Private Parc rich carriers remain
authoritative over their plain fallback, including when that fallback looks
like a URL; version 1/2/3, native RTF/RTFD, and the existing image formats retain
their established conversion paths.

Failure returns without constructing a replacement file owner. Direct file
attachment persistence/open/download contract to implement. Parc explicitly
refuses unsupported attachments atomically and offers Plain Text for surrounding
words, preserving the source clipboard rather than silently discarding its file.
Directory/symlink wrappers are never followed. Supported PNG/JPEG/single-frame
TIFF bytes retain the existing bounded image carrier; PDF/vector/animated image
conversion remains outside that explicit local carrier adaptation.

rich/image branches. It reads the original selected substring, obtains the
URL equality. The helpers and bounded mapped constant read answered these
questions; no new heavy decompilation was needed. All addresses refer only to
the retained 1.122 arm64 main executable and its previously recorded SHA-256.

Explicit Parc adaptations are preserving existing label formatting, keeping
private rich-carrier precedence, refusing attachment-bearing labels and
credentials, and preserving the already-delivered external RTF/RTFD import
was intentionally delivered with EASEL07. These choices use current native
selection/save/undo owners and do not introduce a file schema, file opener,
network fetch or clipboard side effect on refusal.

Shared editing scope: EASEL21 owns `EaselClipboardURL`, attachment rejection,
`EaselStyledText.plainText`, native `pasteContent`/URL insertion and canvas
`readPasteboard` admission. EASEL22 owns text metrics/fill; EASEL24 owns empty
editing/default selection; EASEL23/29 retain page/capture/transfer ownership.

The finished rich-text component passes 340 assertions, the integrated canvas
139, capture destinations 43, native web-input 10 and the shared Notes editor
378. The whole app passes final warnings-as-errors SIL in 30 seconds with zero
diagnostics. The independent review's paragraph-normalization finding is fixed:
plain paste prepares native paragraph attributes before validation and commit,
with one-step Undo restoring both original styles and selection. EASEL24's
explicit insertion results preserve success when an empty object is retired
before URL paste. Fresh independent review cleared the exact integrated source
before publication. These local inert components use named pasteboards and
hidden windows; they do not claim browser or installed visual acceptance.

## Canvas keyboard and accessibility ownership — EASEL26

Each durable object has a stable native focus and accessibility view. It exposes
its kind, actual text or URL, current selection, and canvas frame; it does not
intercept pointer input or draw a second copy of the artwork. The canvas exposes
these objects as children and its real selected children. The focused child is
reported only while focus belongs to this canvas. Native text and an interacting
embedded page remain actual child controls, including the existing text palette,
page address/navigation/recovery controls and Return to Easel button.

Standard AppKit key-view navigation includes the object stops and newly added
objects; the isolated capture editor includes them in its own local control loop.
Focusing an object selects and reveals it. Existing arrows still move the
selected group, and Return enters the existing text editor or the original live
embedded page. Native text keeps composition, local typing Undo, range selection
and its own key handling. Unhandled keys from an embedded renderer cannot become
canvas Delete, Return or movement commands. No new global or endpoint shortcut
is introduced. A page's ordinary native control traversal and its Return to
Easel control provide the return path; unhandled Cancel reaches the same owner.

The object accessibility actions select/edit, duplicate, bring forward and request
deletion through the existing original-object command and real child-retirement
owners. Retained actions capture original object content and physical window;
changed content, detached views, composition and retired sessions refuse them.
Selected frame handles and arrow endpoints expose named one-point directional
actions through the existing original-group geometry lease. These controls retain
whole-group transforms, image aspect policy and one document Undo, and refuse a
replayed action after its original geometry or selection changes. This directional
accessibility presentation is a Parc adaptation to the existing pointer controls;

local type/index/annotated-function helpers, without another decompilation.
resolves an original selected object controller/content, falling back to the
selection and original content ownership; they do not establish additional
shortcuts or modern VoiceOver speech. Parc's durable IDs, native focus-stop
presentation, action names, and deterministic document order are explicit
adaptations to its drawn canvas and existing window key-view loop.

The embedded page path admits only the pool's currently selected original
surface, exact native page and physical window. Unselected surfaces expose no
page accessibility children and are excluded from the window key-view loop.
Transfer, retirement and disposal revoke entry. Return restores the same canvas;
it does not reconstruct the page or navigate its durable URL. Live captured
regions share this boundary with ordinary embedded webpages. This extends the
retained selected-blocker and original-page contract in
[easel-embedded-pages.md](easel-embedded-pages.md).

Checks use actual native canvas/session components with never-displayed windows,
plus the real page pool with injected engine replies. They check identity,
selection, geometry Undo, stale actions, composition and page focus boundaries.
They do not drive a browser, Tab walk, Full Keyboard Access or VoiceOver and do

The EASEL26 finished source passes 203 actual native canvas assertions and 88
actual page-pool/session assertions with an injected engine boundary. The full
Swift module passes `-emit-sil -Onone -o /dev/null` in 66 seconds with zero
diagnostics; all 264 recorded source/check inputs remained unchanged. Earlier
component fixtures that invoked canvas keys while a removed text editor retained
first responder now establish the intended native canvas focus explicitly.

Independent review resolved two focus-boundary findings: native object stops are
relinked when drawing and pointer gates lift, and an original crashed/covered
page enters its exposed recovery control before native page content. The exact
finished source is independently CLEAR. EASEL27 owns the subsequent generic
frame-handle screen-scale refinement and must pass the same scale to the
accessibility frame producer when its new `hitRect(in:scale:)` API lands.

Static canvas, native selection/palette/control states and link-popover appearance are documented in [Easel appearance](easel-appearance.md).

## Export as Image

Share menu at the pointer. Its first row, and for a local Easel its only row,
shortcut. File → Save Page As (Command-Shift-S) opens the same export while an
Easel is the focused content of the key window, and so does Command-Shift-S
on the canvas itself. The capture editor takes the same two commands for its
fixed image canvas.

An Easel exports the full canvas width, from the top down to the lowest
object's bottom edge or a canvas-width square, whichever is taller, plus 60
points. The capture editor exports exactly its image bounds. The saved
artwork of the moment the command is given is drawn at the pixel density
dark. Selection outlines, handles, guides, the marquee and the caret are
never drawn. An open text editor stays open, and its saved text is exported.
Embedded webpages and live captured regions export as their pages' real
pixels: the Easel first asks the engine for each live page's compositor
frame (overlay 296), selected or not, scrolled away, hidden or under a sheet,
and waits for every reply, for at most eight seconds. If the editor closed or
left its window during that wait, the export ends silently; if it is still
there but no longer the window's focused content, the export stops with the
failure dialog below. Rows render in 256-row strips as the encoder reads
them, and the encoder writes them straight to a temporary file on the
destination's volume, so a very tall Easel exports in PNG or
JPEG without holding its whole raw image or encoded file in memory. Then an
app-modal **Export Easel** save panel offers PNG and JPEG (PNG first, so the
suggested name ends in `.png`) and suggests the Easel's title, or Untitled
Easel for the capture editor. The panel opens from a plain main-queue turn,
never inside the engine's reply. Nothing is shown after a successful save.
**Exporting Easel** dialog, “Encountered problem exporting easel. Please try
again later.”, with the app mark and OK. Each window shows at most one,
queued behind any sheet it already has. JPEG cannot hold more than 65,535
pixels on a side, so a taller export saved as JPEG shows that dialog, as

used by the inter-Profile move prompt: PopoverBackground fill, 38-point
insets, an optional 62-point picture icon, an 18-point medium title, a
and neutral buttons with their return and ESC hints, 28 points from the
footer's sides and bottom, begun as a sheet on the window. Return and keypad
Enter confirm, Escape cancels, and VoiceOver reports the confirm button as
the default.

### Reference

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`. The
cross-reference, annotated-function and Swift-type helpers answered every
question; nothing was decompiled.

  string “Export as Image” (comment “Menu item title for saving the document
  as an image.”) only when the view's `saveEaselDocument` environment closure
  and calls `popUpMenuPositioningItem:nil atLocation:NSEvent.mouseLocation
  inView:nil`.
  `person.badge.plus`, “Share or Invite Collaborator”).
  `save:` to the Easel's canvas controller. `-[EaselCanvasViewController
  `WindowState.shouldShowEaselExportPanel` turns true and then reports
  `WindowContentAction.didTriggerEaselExportPanel`.
- The render: `canvasMode` `.verticallyScrolling` snapshots
  `(bounds.minX, bounds.minY, bounds.width, documentHeightAsFactorOfWidth ×
  `bitmapImageRepForCachingDisplayInRect:` / `cacheDisplayInRect:` in
  white from `NSApp.effectiveAppearance` and draws the snapshot over it. The
  result goes through `CGImageForProposedRect:nil context:nil hints:nil`,
  `NSBitmapImageRep initWithCGImage:` and `setSize:` to the point size, then
  `representationUsingType:3` (JPEG) with empty properties. No size limit is
  applied; JPEG's own 65,535-pixel limit makes that call return nil, which
  shows the alert.
  document's objects, takes each normalized position's `CGRectGetMaxY` and
  keeps the largest, starting from 1.0, so the export is never shorter than a
  canvas-width square.
  [capture editing](capture-editing.md)) hosts `InMemoryEaselViewController`
  in `.fixed` mode, so the same `save:` and canvas key reach this export with
  the whole-bounds branch. The suggested name comes from
  the in-memory capture document has none, so it falls back to Untitled Easel.
- The panel and writing: `NSSavePanel` with title “Export Easel”,
  `allowedContentTypes` `[png, jpeg]` and the Easel's title as the name, else
  `Data.write(to:options:[])`. Cancel returns silently. The failure alert
  “Encountered problem exporting easel. Please try again later.” / OK and
  a sheet on the canvas window. Its type is `DialogType.defaultDialog` (laid
  = 22 at the bottom, `DialogTitle` size 18, a 14-point regular
  The success path shows no toast or reveal.
  recovered for the extension prompt ([extensions](extensions.md)), which
  the engine's `extension_install_presenter.mm` retains. The prompt wraps
  the message in `.environment(\.lineSpacing, 4)` (key path getter
- Encoding: ImageIO's default JPEG quality produces bytes identical to
  `NSBitmapImageRep`'s default (quality 0.75), checked locally on the same
  pixels.


  the system sharing services only for an Easel with a shared link; local
  the panel's default `.png` name. Parc writes PNG for a `.png` name and JPEG
  otherwise.
  write cannot leave a truncated file. Like the PNG bytes, this declines to
  objects through its own canvas object renderer, and live pages through the
  Each live page's pixels go where its surface shows them, below the
  surface's 32-point control strip (or inside a live capture's clip), over
  the surface's rounded paper; the strip's own buttons are not drawn. Whether
  selection chrome is unobserved. An engine without overlay 296 lacks
  `snapshotEmbeddedPage(completion:)`; Parc then keeps the earlier export,
  the webpage card (title and address) and a live capture's saved
  screenshot. A page whose renderer cannot produce a frame within five
  seconds, that screenshot policy refuses, that is torn down before it
  answers or that has no visible area falls back the same way, and the
  export stops waiting for any reply after eight seconds. Parc
  the pixel size matches.
  frame's bottom edge or the canvas width, whichever is larger, plus 60
  result.
  appearance, not the Space paper shown on screen.
  untraced window-level flag. Parc routes File → Save Page As from anywhere in
  the focused Easel editor, including its title field, in the key window, and
  from the capture editor's sheet when it is key. Command-Shift-S on the
  canvas follows the same rule, so it does nothing while a Peek, a closing
  window or a moving tab owns the window.
  brand artwork Parc does not ship; Parc shows its own mark in the same alpha
  bounds, as the extension prompt does.

### Checks

`bash scripts/test-easels.sh` includes `tests/EaselImageExportTests.swift`. It
renders a real file-backed Easel through the actual canvas in a never-displayed
window and checks the width-square and far-below heights, backing scale, white
and black backing, saved stroke, fill and text pixels, a stroke crossing a
strip boundary, unchanged output under on-screen selection, an open text
editor that stays open while its saved text exports, and an export that keeps
the artwork of its own moment. A 40,110-point Easel (80,220 rows at 2x) encodes
to PNG, and a 30,110-point one to JPEG, each without raising peak memory by
half its raw size; JPEG refuses the taller one and leaves no file. Saving over
an existing file replaces it and leaves no temporary directory. The fixed
capture canvas exports exactly its bounds and takes Command-Shift-S. Two
windows exporting at once each wait for a later main-queue turn before
re-checking their owner, and each shows its own failure dialog; a canvas
that left its window during the wait ends the export silently. It also
checks the canvas key's modifiers, the Share menu row's title, glyph, font,
image visibility and action, the save panel's title, types and names without
running it, PNG/JPEG bytes and recorded resolution, JPEG bytes equal to
`NSBitmapImageRep`'s default, AppKit's no-context density, and the failure
dialog's wording, icon and width.

`tests/EaselPagePool/run.py` drives the real page pool with injected engine
replies across three pages: the snapshot is placed below the control strip,
the export draws the page's own pixels there and the strip as plain paper, a
page whose engine refuses or replies without an image keeps its card, a page
with no visible area is never asked, a reply withheld past the deadline is
dropped and a late reply changes nothing, a second export waits for the
first collection, and an engine without the selector is never asked and
keeps the card. `bash scripts/test-arc-dialog.sh` checks the shared dialog's
geometry against the recovered constants, its light and dark
PopoverBackground and button faces, real Return, keypad Enter and Escape key
events, the VoiceOver default button, a queued dialog waiting behind another
sheet, and the inter-Profile move dialog's width, bold Space name, button
order and its real sheet decisions (Move it, Don't ask again, Cancel,
Escape). `tests/EaselEmbeddedSnapshot/run.py
<chromium/src> --results <dir>` compiles `native_page_capture.mm` and
`native_appkit_page.mm` with their exact flags from `siso query commands`,
outside the workspace. No panel, menu or browser runs, so the title-row
button, File → Save Page As routes, app-modal panel and a real renderer's
frame are covered only by those compiler checks; overlay 296 still needs an
engine build.
