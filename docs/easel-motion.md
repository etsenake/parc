# Easel motion and feedback

Canvas and capture-image editing share one transient motion owner. The native
scroll view performs magnification; document frames, original image bytes,
native text history and embedded pages keep their existing owners. Ordinary
Easels admit the 0.3333–4 magnification range. The fixed capture editor
retains its existing 0.01 minimum so an original large image can fit its window.
That fit is programmatic and silent. Ordinary canvas minimum extent uses the
actual document-space clip bounds, with a size guard that ignores differences
under a hundredth of a point: below 100% that bounds size drifts by rounding
error whenever the clip scrolls, so an exact guard would let each resize scroll
the clip and resize again without end. Zooming out cannot expose an undersized
canvas or resize a fixed capture canvas.

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

## Object motion

Objects move like Notes blocks. A new object (placed with a click, added from
the toolbar or a key, pasted, dropped or added by a template) pops from 95% with a short fade; a
deleted or cut one fades and shrinks a touch over 0.15 seconds. Duplicates and
quick-create copies glide out of their source on the Notes settle spring, and
their text editor fades in as they land. Align, distribute and Tidy up glide
each object from its old spot, and layer moves give the object a small settle
(from 103% when brought forward, 97% when sent back). Undo, redo, live drags,
drawn or dragged-out objects, typing and pinches never animate, and connectors
attached to a moving object follow their route directly.

`EaselObjectMotion` in ParcCore owns the timeline: one transition per object,
ghosts for deleted objects until their fade ends, glides that continue from
where an object is shown, and the document diffs that pick what moves. Commands
opt in by wrapping their single commit in `withObjectMotion(_:)` (`.appear`,
`.vanish`, `.copies`, `.arrange`, `.layer`), so anything else that commits, such
as a template gallery, can join with one line. The canvas paints each moving
object through a translate, scale and transparency layer around its normal
drawing, redrawing only the objects' own bounds on the display link until the
last transition ends. Boards with live pages run the same effects as Core
Animation on each object's layer, and deleted objects fade before their layer
leaves. Live page renderers never animate.

Selection outlines and handles fade in over 0.1 seconds when an object becomes
selected, hover outlines fade in the same way, and a resize handle grows to
135% on the Notes highlight spring while the pointer is over it. Marquee
selection, guides and active transforms still follow the input directly.

When one command touches more than 40 objects, only the ones in view animate
and the rest land instantly; under Reduce Motion such a big change doesn't
animate at all. Any pointer press, pinch, window change, hiding or Reduce Motion
turning on settles every transition at once, removes fading layers and lets the
display link rebind to the next window. Under Reduce Motion pops and glides become short
fades in place, deletes fade without shrinking and layer moves don't animate.

## Checks

`scripts/test-easel-motion.sh` covers both threshold directions, inclusive
initial-band silence, repeated crossings, invalid samples, native magnification
notifications, source replacement and immediate visibility reversal. Feedback
is injected, so the component does not emit physical haptics. The windowless
`EaselObjectMotionTests` suite covers pop, fade, glide, lift and Reduce Motion
curves, chained glides, ghost bookkeeping and the document diffs. Shared capture
checks protect original pixels and independent in-memory history. The Easel
canvas suite zooms a real canvas in its scroll view 3,000 times while resizing
from every bounds change and requires each step to settle.
