# Easel motion and feedback

Canvas and capture-image editing share one transient motion owner. The native
scroll view performs magnification; document frames, original image bytes,
native text history and embedded pages keep their existing owners. Ordinary
Easels admit the recovered 0.3333–4 magnification range. The fixed capture editor
retains its existing 0.01 minimum so an original large image can fit its window.
That fit is programmatic and silent. Ordinary canvas minimum extent uses the
actual document-space clip bounds, with an idempotent size guard; zooming out
cannot expose an undersized canvas or resize a fixed capture canvas.

## Pinch feedback

The beginning of one native live magnification captures its actual starting
zoom and previous zoom. A gesture starting below 0.99 emits native generic/now
haptic feedback when its previous value was below 1 and its current value is
at least 1. Starting above 1.01 uses the opposite crossing. Starting inside
the inclusive 0.99–1.01 band is silent for the whole gesture. The original
direction remains fixed: returning to the original side is silent, and another
crossing in the admitted direction can pulse again. There is no snapping or
forced zoom change. Native hardware and system preferences decide whether a
requested pulse is felt; the tab-reordering preference is a separate owner.

The observer binds the exact canvas, scroll view and gesture window. End,
window resignation/closure, replacement, detachment, hiding, document closure
and a new pointer transaction retire that lease. Late notifications from an
old scroll view cannot deliver feedback. Programmatic fit/layout changes and
ordinary scrolling have no gesture lease and stay silent. Native content
bounds drive the actual magnification sample; no delayed task can reconstruct
an interaction or persist zoom into an Easel document.

## Annotation transitions

The text palette uses the reference's 0.1-second native implicit-animation
group when logical visibility changes. Hidden input and accessibility state
change immediately. There is no delayed hide completion, explicit opacity
curve, translation or spring. Reversal therefore cannot revive an obsolete
palette. Its geometry and content remain the static appearance owner's work.
Native popovers and sheets retain their existing AppKit presentation.

Body dragging hides passive annotations and single-object handles. A
single-object resize retains only the active handle, while a group transform
keeps its control points. A pinch hides
handles and passive palettes while native magnification proceeds. The same
handle eligibility governs drawing, pointer hits, cursors, accessibility
children and retained accessibility actions. Gesture visibility changes notify
the existing keyboard/accessibility structure without changing focus. Selection
outlines, marquee geometry, guides, object transforms and live renderer frames
follow the current input directly. They do not acquire invented animations or
haptic pulses. The two original captured-card modes keep actual page
positioning/retirement and the immutable screenshot; motion never substitutes
a snapshot for a live renderer or changes its crop frame.

Parc reads Reduce Motion before each native annotation group and settles its
owned palette layer animations immediately when the preference turns on.
Owner retirement suppresses new annotation animation and settles those layers
after its synchronous visibility refresh. Normal eligible pinch completion may
still reveal current annotations. These are explicit accessibility
and lifetime adaptations; the recovered Easel group does not read that setting.
Neither adaptation changes the current geometry, selection or focus.

## Reference and checks

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
Retained contracts and `components.py`, `arctypes.py`, `arcidx.py` and `arcfn.py`
resolve the mechanisms without new heavy decompilation. Local helper receipts
are in `work/easel-coordination/easel28/evidence`.

- `EaselUI.ZoomInteraction` has `zoomAtPinchBegin` and `lastRecordedZoom`.
  directional comparisons and generic/now emission. This is the Easel site
  previously labelled “sound effects” in the shared haptic inventory.
  construction uses their first and last entries as bounds. Pinch remains
  continuous, so intermediate levels are not invented detents.
  0.1 before setting the native view hidden and its annotation hidden flag.
  The ColorPicker, ControlPoint, SearchBar and TextMenu witnesses store that
  flag; TextMenu also invalidates its cached frame. DragHandle layer update
- The bounded Easel call inventory has no other direct native haptic emitter.
  provider loading; Parc opens its local document synchronously. The spring at
  Neither is reassigned to local insertion or editor entry.

Focused inert checks cover both threshold directions, inclusive initial-band
silence, repeated crossings, invalid samples, actual native magnification
notifications, source replacement/retirement and immediate hidden reversal.
Feedback is injected in the component, and its windows never appear. Shared
capture-canvas checks preserve original pixels, independent in-memory history
and model-only output. Whole-module compilation and independent source review
are recorded with the delivered row in the parity ledger. They establish
source/component behavior, not functional-browser or installed-motion
acceptance. No functional browser checks are authorized or performed.
