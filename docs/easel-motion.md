# Easel motion and feedback

Canvas and capture-image editing share one transient motion owner. The native
scroll view performs magnification; document frames, original image bytes,
native text history and embedded pages keep their existing owners. Ordinary
Easels admit the 0.3333–4 magnification range. The fixed capture editor
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

The selection toolbar presents like the Notes format bar: it pops from 95% to
full size with a short fade about the edge nearest the selection and leaves the
same way, and Reduce Motion keeps only the fade. A new selection pops it again
in place, a moved or resized selection glides it, and scrolling or zooming moves
it without animation. Its geometry and content remain the static appearance
owner's work. Native popovers and sheets retain their existing AppKit
presentation.

Body dragging hides passive annotations and single-object handles. A
single-object resize retains only the active handle, while a group transform
keeps its control points. A pinch hides
handles and the selection toolbar while native magnification proceeds. The
toolbar also hides while objects are dragged, resized or drawn, during a
marquee, while the press that made a new selection is still down and while
focus is outside the canvas, and it returns when that ends. The same
handle eligibility governs drawing, pointer hits, cursors, accessibility
children and retained accessibility actions. Gesture visibility changes notify
the existing keyboard/accessibility structure without changing focus. Selection
outlines, marquee geometry, guides, object transforms and live renderer frames
follow the current input directly. They do not acquire invented animations or
haptic pulses. The two original captured-card modes keep actual page
positioning/retirement and the immutable screenshot; motion never substitutes
a snapshot for a live renderer or changes its crop frame.

Parc reads Reduce Motion before each annotation transition and settles the
toolbar's layer animations immediately when the preference turns on.
Owner retirement suppresses new annotation animation and settles those layers
after its synchronous visibility refresh. Normal eligible pinch completion may
still reveal current annotations. These are explicit accessibility
and lifetime choices.
Neither adaptation changes the current geometry, selection or focus.

## Checks

`scripts/test-easel-motion.sh` covers both threshold directions, inclusive
initial-band silence, repeated crossings, invalid samples, native magnification
notifications, source replacement and immediate visibility reversal. Feedback
is injected, so the component does not emit physical haptics. Shared capture
checks protect original pixels and independent in-memory history.
