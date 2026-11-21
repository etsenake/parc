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

## Tool bar

The floating tool bar rises 12 points and fades in on the Notes open spring the
first time an Easel view appears. The current-tool pill slides between buttons
on the pill spring. A hovered button lifts its glyph 1.5 points on the
highlight spring, and the Notes press squish stays. Arming a tool by click, key
or quick action plays a short flourish on its glyph: the sticky hops, the
marker, highlighter and washi tape tilt and swing back, the eraser wiggles, the
stamp squashes then pops, shapes, connectors, text, sections, tables and code
blocks pop, and the hand opens; Select has none. Flourishes are kicked-spring
keyframes from `EaselToolFlourish` (0.36–0.42 seconds, starting and ending at
rest). While any drag, draw, marquee or resize passes under the bar it fades
to 35% so the board shows through, and returns when the pointer leaves the bar
or the button comes up. The Recenter chip pops in from 90% on the pop spring
and fades out. Under Reduce Motion the bar only fades in, the pill and chip
fade in place, and lifts and flourishes don't play; turning it on settles them.

## Controls

Easel controls move like the Notes ones. Styling tiles, shape cells and template
cards rise on hover (the Notes highlight spring), their shadow grows, and they
squish when pressed and spring back on release; wide tiles such as the fill
modes only squish. Keyboard highlight lifts a tile the same way, and a lifted
tile draws above its neighbours. A chosen colour's or shape's ring springs
into place from slightly larger on the check spring, and the selected fill, stroke
width or dash style is one pill that slides between tiles on the pill spring
(it fades in on the first choice and out when a mixed selection has none). The Label
Background box cross-fades when it flips. Recolouring a swatch button in the
selection toolbar pops it, and a toolbar button whose face changes cross-fades.
Connector ends and routing are NoteMenuList menus and keep their own motion.

The timer's digits roll vertically, only the columns that change: adding time
rolls up, counting down rolls down, and rolling digits are clipped to the clock in the
panel. Start, Pause, Resume and Again cross-fade with a small pop. Pausing blinks the clock
twice and leaves it dimmed on the chrome button, which no longer animates while
it sits paused. At 00:00 the chrome button shakes and glows in three softening
pulses, and a panel that is open shakes the clock and glows behind it; the toast
and the VoiceOver announcement are unchanged. The page switcher's rows are views of
their own: new rows fade in with a small rise, removed rows fade out, the rest glide on
the reorder spring, and the current-page check slides to its new row on the pill
spring while the two rows cross-fade. The page button, timer button, code Copy chip and
the web link box squish or cross-fade the same way; a bad web address shakes
its field and springs the red border. The Copy chip is always wide enough for
Copied!, so it cross-fades to a check and back without moving the bar. The crop
zoom knob grows while it is held.

Under Reduce Motion nothing scales, shakes, rolls or slides: lifts, squishes and
rolls become 0.15 s fades, glows are a single fade, pills and rings fade in
place, and turning the preference on settles whatever is running. Every effect is
a Core Animation layer animation that ends on its own; no timer or display link
stays behind. The scale, shadow, roll direction and pulse maths live in
`EaselControlMotion`, `EaselDigitRoll` and `EaselPulseTrain` (ParcCore), and
`EaselControlSurface` and `EaselRollingText` in `EaselCanvasControlMotion.swift` apply
them.

## Checks

`scripts/test-easel-motion.sh` covers both threshold directions, inclusive
initial-band silence, repeated crossings, invalid samples, native magnification
notifications, source replacement and immediate visibility reversal. Feedback
is injected, so the component does not emit physical haptics. The windowless
`EaselObjectMotionTests` suite covers pop, fade, glide, lift and Reduce Motion
curves, chained glides, ghost bookkeeping and the document diffs,
`EaselFloatingBarTests` the tool bar flourishes and `EaselControlMotionTests` the
hover and press scales, hover shadow, digit roll columns and directions and the
pulse keyframes. Shared capture
checks protect original pixels and independent in-memory history.
