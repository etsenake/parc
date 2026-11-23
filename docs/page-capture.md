# Page capture

A capture session belongs to one existing renderer document in one native
window. File → Capture Portion…, Capture Visible Area and Capture Full Page,
command search and page menus share those native actions. Capture Portion uses
the configurable Command–Shift–2 binding. Its separate Shortcuts preference
enables Command–Shift drag over an eligible page without changing that binding.

## Selection and destinations

Capture mode floats a mode bar near the bottom of the page: Element, Region,
Visible Area, Full Page and Cancel, each showing its key (E, R, V, F, Escape).
Element, the default, outlines the page area under the pointer; click or Return
captures it, and a drag still selects a freeform rectangle. Region drops the
outlines for a crosshair and only drags. Visible Area and Full Page capture at
once, and Return with no outlined target also captures the visible page. A
one-line hint above the bar says what a click or drag does right now, and an
accent chip shows the outlined or dragged size in page points. The bar fades out
during a drag. Letter keys follow the typed letter, or the key's position on
non-Latin layouts. Left/Right move between the bar's buttons, Tab/Shift-Tab reach
them when keyboard navigation is on, and accessibility actions reach every control.

The searchable output palette offers Save to Library, Copy, Save…, Send via
iMessage…, Edit, Crop, Frame and Retake, with Easel and Note submenus for
sending to a new or existing document. Edit uses the shared image
canvas; crop preserves accepted annotations. Easel insertion uses the same asset,
document mutation and Undo transaction as other image imports. The source URL
is provenance and is never replayed to obtain pixels. See
[capture editing](capture-editing.md) and [capture presentation](capture-presentation.md).

## Native capture mechanism

Region and viewport capture copy the original compositor surface at device
scale. Full-page capture uses the page-owned DevTools screenshot route in one
pass: it reads the page's CSS size with `Page.getLayoutMetrics`, then asks for
a single `Page.captureScreenshot` of the whole page with `fromSurface`,
`captureBeyondViewport` and a clip whose scale keeps the picture within 16,384
pixels a side and 80 million pixels. Chromium renders a capture taller than
16,384 device pixels as repeats of its top, so a page that would exceed the
limit at device scale is rendered at the largest scale that fits instead of
being stretched afterwards. Ordinary pages keep full device sharpness. The
capture refuses an attached debugger and restores only its own temporary
document preferences and renderer geometry.

A page too large for full sharpness also gets a vector PDF, as Safari's Full
Page screenshot does: one unbroken PDF page at one point per CSS pixel, sharp at
any zoom. Before the screenshot, Paint Preview records the whole document, with
its subframes, in memory and with no scrolling; the screenshot waits for that
recording because it resizes the view. While the screenshot runs, a sandboxed
Paint Preview compositor writes the recording through Skia's PDF backend. The
PDF receiver copies either inline bytes or shared memory into owned bytes before
delivery, so large PDFs keep the same capture path as small ones. The result
carries both the PNG and the PDF once both finish. A recording that takes
longer than 10 seconds, a failed recording or compositor, or a PDF still
unfinished at the 30-second deadline leaves the PDF out and keeps the PNG.
Ordinary pages stay image-only and keep their speed. Private windows record the
same way, in memory only. The compositor method is the kept
`paint-preview-pdf` patch ([hooks reference](chromium-hooks-browser.md#page-and-window-patches)).

One operation per WebContents owns the original document, Profile/private
context, native window and screenshot-policy lease. Bounds round outward and
respect Chromium's current dimension limits. Surface capture has a 10-second
deadline; the full operation has a 30-second deadline. Cancellation invalidates
protocol, Paint Preview and worker callbacks. Results contain genuine PNG bytes or an error;
missing pixels never become a placeholder.

The engine's PNG carries device pixels but no density, so every app would open
a Retina capture at twice its size with each pixel stretched over four.
`CapturedImage` writes the window's backing density (144 DPI at 2×) into the
PNG's `pHYs` chunk without touching a pixel, and crops, edits and frames encode
the same density. Copy, Save, Library, Easel, Note and Messages all take that
one PNG, so every output opens at screen size with full device sharpness.

A Full Page too long or large for full Retina sharpness comes back as a
scaled-down PNG (at most 16,384 pixels a side and 80 million in all) plus a
vector PDF of the whole page in `pdfData`, one long page at a point per CSS
pixel. The controller keeps that PDF only with the original, unedited output,
the same rule as the Make live layout: crop, frame, edit and retake drop it.
Easel and Note sends draw their snapshot from it ([destinations](capture-destinations.md#sharp-long-captures));
Library, Copy, Save and Messages keep the PNG.

## Ownership and output

`PageCaptureController` adds a sibling over the real viewport without reparenting
the renderer. `PageCaptureEdgeGuard` extends it across any window-frame band
within 24 points of a window edge, so presses there select (clamped to the page)
instead of moving the window; neither view lets a press move the window. Split
and Peek capture retain their exact native page. Admission
records the original tab, Profile, Space, window, page host and viewport geometry.
Selection, transfer, close, layout or owner changes retire the session.

Read-only eligibility may populate command search without key focus. Starting
or using the lease requires the genuine key source window after the command
panel closes. Native validation independently checks the document, bounds,
policy and security reservation; asynchronous callbacks carry a generation.
The frozen picture a moved tab leaves behind uses a separate placeholder lease
that skips only the key-window rule and copies only the whole visible page; see
[windows lifecycle](windows-lifecycle.md#moving-selected-content-between-windows).

An output lease survives its own Save/Easel sheet and OS message composer while
retaining document/security validity. Every output revalidates it. Canceling a
sheet cannot dismiss another sheet. Save reports actual filesystem errors.
Successful Copy/Save returns focus only to the still-current original page;
Easel insertion opens the saved local document through the normal model route.
Sending to Messages submits one payload. The app cannot retract an attachment
already accepted by the OS composer.

## Element selection

The native original-document query resolves `elementsFromPoint` geometry and
returns an opaque latest-target token. Capture rechecks that token, point,
document, zoom and owner with a two-point margin. It does not render a screenshot
in page JavaScript. In Element mode a click without an offered target performs
the real query; Region mode never queries targets, so a plain click does nothing.

Outline and clear veil animate together from their current presentation paths
using the 0.35/0.87 spring and a 90-ms latest-target throttle. Pointer exit, drag,
Retake and cancellation immediately clear the target and invalidate callbacks.
Reduce Motion and focus belong to the same session; see
[capture motion](capture-motion.md).

## Capture in Portrait Mode

Portrait capture shares the normal capture/edit/output session. Frame, Edit
Frame and Remove Frame are reversible transformations of the original image
and accepted crop. Removing a frame restores the exact unframed capture; repeated
framing cannot stack a frame on an already framed image. Saving updates the
same Library identity and its actual capture kind.

Desktop framing uses the actual wallpaper/display and its permission owner.
Page framing uses the actual webpage theme color, not the Space theme. An
optional "Captured in" line with Parc's P is composited under the picture.
The frame keeps every captured device pixel one to one at any size, inside an
even margin of 8% of the picture's mean side (40–160 points) in whole device
pixels. Only Easel's image limits ever thin that margin or, as a last resort,
scale the frame.
See [portrait fidelity](portrait-capture-fidelity.md).

## Gesture and private-window boundaries

The drag recognizer admits the actual renderer, excluding chrome and overlays.
A split activation uses its real page owner. Weak exact-owner admission and
preference generations reject stale gestures after selection or settings change.

Private captures do not create a persistent private catalog. An explicit Save
to Library can write into the parent Profile's normal catalog; that deliberate
save is distinct from ordinary private browsing history. Private preferences
remain in memory. Private captures deliberately offer no Easel destination; see
[capture Library](capture-library.md#private-media-ownership).

## Checks and limits

Component checks cover geometry, invalidation, crop/frame identity, output
transactions and real image bytes.
Capture is still-image output; website recording/stream controls and discovered
external videos are described in [capture capabilities](capture-capabilities.md).
