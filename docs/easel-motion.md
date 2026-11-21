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
outlines, marquee geometry, object transforms and live renderer frames follow
the current input directly; guides fade in and tick as described under Snaps
and live feedback. The two original captured-card modes keep actual page
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

The board behaves like a desk. New shapes, text, tables, code blocks, images,
links, cards and diagrams pop from 80% on the Notes pop spring with a 0.12 s
fade. A new sticky drops like paper: it lands from 108%, 8 points higher and
tilted 3°, while its lifted shadow tightens on the settle spring. A stamp slams
down from 160% and clear with 12° of extra tilt, overshoots to about 90% on the
toggle spring, and leaves an ink ring and a burst of specks in its colour.
Connectors, doodles and sections fade in. Commands that add several objects at
once (templates, paste, Mermaid import, duplicated groups) stagger them outward
from the group's centre, the whole spread within 0.25 s.

Deleting or cutting puffs objects away: they shrink to 85% and fade in 0.18 s,
and up to eight of them leave a small puff of soft specks. Duplicates and
quick-create copies glide out of their source on the settle spring, finish
with a small squash, and their text editor fades in as they land. Align,
distribute and Tidy up glide each object from its old spot; layer moves settle
from 103% when brought forward and 97% when sent back. Colour, fill, stroke,
dash, arrowhead, shape and font changes cross-fade from the old look over
0.15 s.

Undo and redo animate structural changes quickly: objects that come back pop
from 92%, ones that leave poof without specks, moved, resized or turned ones
glide back to where they were, and restyled ones cross-fade. Undoing typing,
table edits and anything else that only changes words stays instant, as do
live drags, pinches, drawn and dragged-out objects. Connectors attached to a
moving object follow their route directly.

A body drag picks objects up: they lift to 102.5% on the lift spring with a
soft shadow growing beneath them, and stickies and stamps tilt with horizontal
pointer speed (up to 5°, damped by the press spring) and level out when the
pointer rests. Letting go settles them on the settle spring with a tiny landing
squash while the shadow tightens. Live page cards get only the shadow. Trying to
move or delete a locked object shakes it sideways three times and taps the
refusal haptic; the keyboard gets the shake without the tap. ⌘C and Copy as
Image sweep a bright line once around the selection.

Other features join through a few canvas calls. `withObjectMotion(_:)` wraps a
single commit (`.appear`, `.vanish`, `.copies`, `.arrange`, `.layer`,
`.restyle`); `recordingMotion(_:_:)` does the same around a session change that
bypasses `commit`, and undo and redo use it with `.history`.
`pulseObjects(_:)` pops objects to 105% on the press spring with a brief glow
(find results and followed links use it), `shakeObjects(_:)` plays the
refusal shake, and `playCanvasBurst(_:around:tint:)` plays a `.ripple`,
`.confetti`, `.puff` or `.glow` from `EaselCanvasBurst`, a pooled overlay view
in canvas coordinates that follows zoom and leaves the view when idle.

`EaselObjectMotion` in ParcCore owns the timeline and its maths: one
transition per object, delays for staggers, ghosts for deleted objects, the
old look of restyled ones, the carried selection's lift and tilt, the held
stamp, glides that continue from where an object is shown, and the document
diffs that pick what moves. Boards without live pages paint each moving object
through a translate, rotate, scale, transparency and shadow layer around its
normal drawing, redrawing only the objects' own bounds on the display link.
Boards with live pages sample the same curves into Core Animation keyframes on
each object's layer, carry and hold update the layer each frame, restyles use a
layer fade and deleted objects poof before their layer leaves. Live page
renderers never transform.

Selection outlines and handles fade in over 0.1 seconds when an object becomes
selected, hover outlines fade in the same way, and a resize handle grows to
135% on the Notes highlight spring while the pointer is over it. Marquee
selection, guides and active transforms still follow the input directly.

When one command touches more than 40 objects, only the ones in view animate
and the rest land instantly; bursts play for at most eight objects per command,
and under Reduce Motion such a big change doesn't animate at all. Any pointer
press, pinch, window change, hiding or Reduce Motion turning on settles every
transition and burst at once, removes fading layers and lets the display link
rebind to the next window. Under Reduce Motion every effect becomes a short
fade in place: no scale, tilt, offset, shake, lift or specks, and layer moves
and pulses don't animate; the copy sweep and pulse glow keep only their fade.
Haptics stay. Exports, Copy as Image, PDF and thumbnails draw the document,
never a presentation.

## Snaps and live feedback

Snapping clicks under your fingertip. Each kind of snap taps
`EaselCanvasHaptics.snap()` once when it engages, through its own
`EaselSnapTicker`, and stays quiet while it holds: an alignment or spacing
guide during a drag or resize (keyed by anchor and line), a rotation landing on
a new 15° step (primed with the starting angle so grabbing the handle is
silent, and quiet while Command turns freely), and a connector end taking a
shape's side magnet, automatic outline or pinned point, and a resize landing
on another object's size. Keyboard nudges,
programmatic changes and undo never tick, and every ticker resets when the
pointer gesture ends.

A guide fades in over 0.08 seconds as it engages and its marks along the moving
object pop from 35% on the pop spring; a guide that holds doesn't replay.
Resizing one shape, section, image, video or web item snaps its width or height
to a visible unrotated one within 6 points on screen, keeping the opposite edge
(or the centre with Option) still; an alignment guide on that axis wins, and
Command or a kept aspect ratio skips it. Matching sizes show a dimension line
with end ticks over each object, faded in and popped like guides.
Dragging a connector end over an object gives the object a soft glow ring that
fades in on the highlight spring, and the magnet the end will take grows to its
larger dot on the same spring.

Connectors made for you draw themselves from start to end over 0.25 seconds and
pop their arrowhead and label at the end: quick create, new mind maps, children,
siblings and attached topics, Mermaid imports, templates, pasted and inserted
connectors, and branches revealed by expanding a mind map (deeper ones a beat
later). A connector you drag out pops its arrowhead when you let go, and an end
you drop onto an object pops its head there. Duplicates keep gliding instead.

Carrying objects over a section they would join brightens its tray: a tint and
a heavier border fade in over 0.1 seconds and fade back out when they leave.
Dropping them in flashes the border once. Moving things within the section
they're already in stays quiet.

Collapsing a mind-map branch folds its topics into the collapsed topic, gliding,
shrinking and fading in 0.2 seconds; expanding glides them back out of it. A new
child or sibling grows out of its parent while its neighbours glide aside.
Changing page with Page Up, Page Down, the switcher or a page link slides the
board 24 points in the direction of travel while the old page cross-fades away
(0.22 seconds). A sticky that grows or shrinks while you type eases to its new
height on the settle spring. Inserted or duplicated table rows and columns
slide open and deleted ones close up. Erased strokes poof like deleted
objects.

The rules match object motion: effects play only on screen, read Reduce Motion
when they start and settle on any pointer press, pinch, window change or
hiding. Under Reduce Motion guides and drawn connectors only fade, pages only
fade, and folds, slides, growth and pops don't move. Boards with live pages
fade between pages without sliding, and the page cross-fade never snapshots a
board with live pages. `EaselCanvasFeedback.swift` owns the state and its own
display link, which stops when the last effect ends; `EaselSnapFeedback` in
ParcCore holds the curves, connector trimming, rotation steps, equal-size
matching and the section a carried selection would join. Exports and previews
draw the document, never these frames.

## Checks

`scripts/test-easel-motion.sh` covers both threshold directions, inclusive
initial-band silence, repeated crossings, invalid samples, native magnification
notifications, source replacement and immediate visibility reversal. Feedback
is injected, so the component does not emit physical haptics. The windowless
`EaselObjectMotionTests` suite covers every entrance, poof, glide, squash,
pulse, shake, cross-fade, carry tilt and Reduce Motion curve, cascade delays,
stamp growth and wheel timing, speck plans, ghost bookkeeping and the document
and undo diffs,
`EaselFloatingBarTests` the tool bar flourishes, `EaselControlMotionTests` the
hover and press scales, hover shadow, digit roll columns and directions and the
pulse keyframes, and `EaselSnapFeedbackTests` the guide, reveal, highlight,
tray, flash, fold, growth and table curves, connector trimming, rotation steps,
section drop targets and equal-size snapping. Shared capture checks protect
original pixels and independent in-memory history.
