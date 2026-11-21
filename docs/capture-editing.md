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

Fresh annotations keep the classic capture look: outlined rectangles and
ellipses, straight arrows, marker strokes and fixed, non-adaptive ink, so old
snapshots reopen identical. Selecting annotations shows the Easel floating
selection toolbar (colour, outline, arrowheads, routing, text, arrange, layer
order); right-click a shape to switch it to any of the 32 shapes. The colour
well shows the selection's shared colour and recolours it. Anything a flattened
screenshot can't keep stays out: sections, object links, connector labels, alt
text, quick create, the tool palette and tool keys, and Mermaid, code, table,
web and video paste or drop. Pasted Easel objects keep only text, pictures,
shapes, arrows, drawings, stickies and stamps.

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

## Captured Library contexts

Both a captured thumbnail's context menu and its preview's More menu expose
Send via iMessage, AirDrop, Copy Image, source-page open/copy and Delete. Preview
and Save remain explicit local affordances. External-file Finder/hide/open/Quick
Look actions keep their separate external-file owner. No browser-capture menu pretends
that the source page is a filesystem file or hides a capture in place of deleting
its real saved asset.

Saved-capture Messages shares the decoded image with its original URL as text;
it adds no title or attribution prose. The active palette retains its separate
URL-plus-image payload. AirDrop receives the actual saved image, not its website
URL or thumbnail.

Library menus capture exact item/revision, selection and view generation. Async
reads recheck these before invoking a service. Real AppKit capability checks
and decode failures refuse unavailable actions. The service owns immutable
payloads after explicit invocation; cancellation remains quiet, real failures
are surfaced. The chosen service owns delivery after invocation.
Profile/view retirement detaches callbacks. macOS has no public cancellation API
to retract an already invoked external composer.

## Checks

`scripts/test-capture-editing.sh` exercises the actual memory session, canvas
renderer and Library payloads. `scripts/test-portrait-capture.sh` covers edits
through crop/frame, original-byte retention, recropping, density and wrong-size
refusal. Shared Easel checks protect persistent sessions and canvas behavior.
