# Capture editing and captured-item contexts

The capture palette's **Edit** opens a fixed image canvas with Select/Move,
Image, Text, Circle, Rectangle, Arrow and Draw tools, annotation color and real
Undo/Redo. Formatted text color updates its real attributed runs in the same
undo transaction. It uses the existing Easel canvas and model transactions with an
isolated memory-only session. It creates no saved Easel, profile files or browser
provider. Apply renders model artwork at the captured pixel density, without
selection handles or controls; Cancel, idle-canvas Escape and Command-W discard
the draft. Escape first ends a native text/gesture/selection operation when one
is active.
Image imports use a sheet owned by this editor. Native text retains its own
composition, rich formatting and undo commands.

**Crop** remains an independent action in the user-authorized unified capture
flow. Original capture PNG/pixels, the accepted full-size edited source, the crop
and optional Portrait composition are separate retained layers. The editor
reopens its accepted object snapshot, preserving annotation identity rather
than baking its previous output into a second background image. Re-editing
shows the full original-sized canvas so later recrops retain annotations.
The edit renderer retains the original RGB color profile, including Display P3.
Applying an edit atomically reapplies the current crop and frame; errors leave
the previous output intact. Removing a frame restores the exact edited crop.
An unchanged Apply and all cancellations preserve the committed PNG bytes.
Retake creates a new identity and clears the prior editor snapshot. No edit
calls the capture provider.

The existing output owners still consume the current committed PNG. An edited
Library save replaces the same ID/revision only through its existing atomic
transaction. Copy, Save, Easel and active-capture Messages retain their previous
lease, destination and success/cancellation semantics. Source document, window,
Profile, Space, capture identity and native security validity are checked before
editing commits; retirement closes only the editor's own sheets.


`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The recovered-components, Swift-type, annotated-function and cross-reference
helpers resolved these questions. No fresh heavy decompilation was needed.

`EaselUI.ModalImageEditor` with the captured NSImage and an optional completion,
hides its existing image view and presents the editor in the original window.
non-nil, then unhides the capture view and notifies its retained callback.
with fixed CanvasMode, a nil browser provider and an NSImage-sized document.
The provider seeds one genuine image object. This is the shipped editing
mechanism; a crop-only substitute was incomplete.

`04 06 07 01 00 02 03`: Move, Image, Text, Circle, Rectangle, Arrow, Freehand.
eligible-provider branch. The capture editor has no such provider. Parc uses
its existing native Easel insertion, selection, resizing, rich text and history
controls for this tool inventory. Its fitted scroll/magnification view, native
color well, explicit Apply/Cancel and full-original edit coordinates are
Parc presentation/ownership adaptations for the reversible Crop/Portrait flow.
CAP24 separately owns capture/Library motion, focus and accessibility polish.

## Captured Library contexts

Both a captured thumbnail's context menu and its preview's More menu expose
Send via iMessage, AirDrop, Copy Image, source-page open/copy and Delete. Preview
and Save remain explicit local affordances. External-file Finder/hide/open/Quick
Look actions remain CAP23's separate file owner. No browser-capture menu pretends
that the source page is a filesystem file or hides a capture in place of deleting
its real saved asset.

to the original URL's absolute string, with optional URL nil. It adds no title
or attribution prose. This differs from the active palette caller's URL+image,
non-nil image before its URL fallback. Parc's valid saved PNG path sends the
actual image, never the website URL or a thumbnail.

Library menus capture exact item/revision, selection and view generation. Async
reads recheck these before invoking a service. Real AppKit capability checks
and decode failures refuse unavailable actions. The service owns immutable
payloads after explicit invocation; cancellation remains quiet, real failures
are surfaced, and completion is not claimed to establish recipient delivery.
Profile/view retirement detaches callbacks. macOS has no public cancellation API
to retract an already invoked external composer. No outgoing share was invoked
while implementing or checking this row.

## Checks and handoffs

`test-capture-editing.sh` passes 25 assertions over the real memory session/canvas renderer and
Library payloads without a visible window, browser or service invocation.
`test-portrait-capture.sh` additionally covers accepted edits through crop/frame,
original-byte retention, exact edited-source recrop, backing density and refused
wrong-size edits. Shared Easel component checks protect persistent session and
ordinary canvas behavior. The finished application receives warnings-as-errors
whole-module SIL (`cap21-final3`, 29 seconds, zero diagnostics) and fresh
independent exact-source review, which cleared before publication. The
review fixes cover formatted text ink/semantic-color replacement, idle Escape
ownership and original RGB profile preservation; each has focused inert coverage.

CAP18's private overlay geometry and `CapturePresentation.pixelCrop` remain
unchanged. CAP19 retains compositor/desktop density ownership. CAP20 retains
UUID-ranked destinations and the palette-specific Messages payload. CAP23's
mixed-media navigation, thumbnail cancellation and file permissions remain
unchanged. CAP21 adds only the shared editor, edited-source transaction and
captured-item contexts; no new native/engine provider is required.
