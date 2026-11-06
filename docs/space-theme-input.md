# Space theme pointer, rotation and wheel input

SPACE15 connects the shared theme editor's physical controls to their recovered
coordinate mappings and transaction boundaries. A pointer gesture previews the
theme and commits once when it ends. A delivered wheel direction is a separate
quantized edit, after a 200 ms latest-event throttle. Parent Undo, another control
or dismissal retires input before a stale physical continuation can edit again.

## Recovered contract

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The retained `theme-picker` evidence and local components, Swift-type,
cross-reference and annotated-function helpers answered this row. There was no
new REA/decompilation call, second-version trace or browser functional test.
Annotated receipts are retained under `work/spaces-profiles-checks/space15`.

| Input | Recovered boundary | Behavior |
|---|---|---|

`SpaceThemeNoiseGesture` preserves this provenance through the production
control callback and model. Keyboard and accessibility step actions use slider
provenance. Physical feedback consumes the same admitted event in SPACE16; this
row does not synthesize a haptic or change the feedback policy.

## Native ownership and adaptations

Parc implements the recovered SwiftUI callbacks with its existing native AppKit
controls. AppKit supplies rotation degrees per event; accumulating the initial
one-degree recognition threshold and dividing admitted degrees by 720 expresses
the reference's half-turn contribution. Ending/cancelled events retire the
physical sequence without applying their payload again. A physical cancellation
finishes the latest admitted gesture value through Parc's existing owner commit
path. Parent state replacement instead discards the transient draft and restores
the authoritative theme through SPACE14.

`ThemeNoiseControl` uses Combine's same main-queue latest throttle. Dial-local events are queued even
when the pointer is over the ring; center hover is checked only at delivery.
Parc receives native events in the original control/window rather than adding
an application-global event observer. Its
subscription holds the control weakly, is replaced when input is retired, and
cannot deliver a queued pre-Undo event into the restored model. The raw phased
scroll/momentum barrier remains independent of those discrete transactions:
physical end can be followed by momentum, so only a new physical begin or an
unphased burst after 200 ms idle releases a cancelled stream. A partially
recognized rotation is also a physical stream and cannot resume after parent
replacement. A new rotation retires a pending wheel value before recognition,
including when it ends before that value's scheduled delivery. These
original-owner interruption guards are Parc's explicit
native adaptation; they do not choose a current key window or move a history
record to another editor.

The editor tracks the active control, commits its completed preview and retires
its input when another control starts, including pending wheel values and
subthreshold rotation that have no model snapshot yet. Pad and intensity retain a physical
pointer latch; a cancelled drag/up cannot enter a newer gesture merely because
the shared editor has begun another one. Explicit finish/dismissal, local Undo,
parent Undo and authoritative commit rejection all retire queued input.
Cancellation also restores the cursor. Keyboard/AX increments remain discrete
and first finish the prior physical transaction, then read the authoritative
post-commit value for their independent step. New physical latches are captured
after that same callback so a rejected previous commit cannot erase them. The
pad captures the model knob center and refreshes immediately at drag start,
including when the first color is unchanged. Control geometry, colors and rendering
ownership remain compatible with SPACE17's material/text/motion work.

## Drawn knob position and cursors (October 31)

Josh reported that a grabbed colour never stayed under the pointer and that
the pad showed a crosshair. The cause was in Parc's drawing, not the mapping.
`ThemeColorPad` set `isGeometryFlipped` on its knob container. AppKit flips a
backing layer only where a flipped view sits under an unflipped superview, and
everything beneath that layer, including the pad's own sublayers, already uses
the views' y-down coordinates. In a Space popover the flip is on the editor's
layer. In onboarding the editor sits inside the flipped
`OnboardingThemeEditorPopoverBackground`, and the flip is on a flipped ancestor
above it. In both, the extra flip drew every knob at `340 - y` while the model,
hit-testing and pointer used the unmirrored pad coordinates. A press on a
visible knob therefore missed it, became a pad click, and drew the colour at
the pointer's mirror image. Later drags tracked x but inverted y, and the arrow
keys moved the primary knob opposite to the vertical arrow. The cursor showed
the open hand only over a knob's mirror image. Removing the flip draws saved

|---|---|---|

AppKit tracking areas replace SwiftUI's nested push/pop modifiers. The pad's
`mouseMoved` and `cursorUpdate` resolve one cursor from the pointer; a cursor
update during either kind of drag changes nothing. A pad button wins over a
knob beneath it because the button receives that click, and the knob does not
show hover there. A disabled `NSButton` passes its press to the pad, its next
responder, so the pad ignores a press inside any of its buttons rather than
grabbing the knob beneath. The buttons answer `cursorUpdate` with the pointing
when a knob drag ends, but no later `mouseMoved` reaches Parc's pad after a
release outside it, so that release restores the arrow instead.

during a pad drag pushes its open hand on the next drag event, and leaving
it pops the hand [D for the tracking options; I for the visible sequence].
`isDraggingKnob` is false). Parc places it without a spring, so the open hand
shows for most of a pad drag. Past the rim the knob stays on the 0.99 radius,
away from the pointer, and the arrow returns.

## Knob hit geometry (November 1)

Parc's texture click, wheel hover and pointing hand used a 28-point centre
radius, wider than the 40-point knob. The dial's composition comes from the

   `ClickGesture` (ring click), the 10-point `DragGesture` and the open hand.
2. The centre `Button`.
3. The two dot `ForEach` loops.

|---|---|---|

[I] SwiftUI routes a press or trackpad rotation to gestures on the view hit at
its start, limited by `contentShape`. An AppKit tracking area is rectangular.

The original Space, Profile and window commit callbacks are unchanged.
`onPreview` stays transient; completed mutations use `onCommitChange` for an
existing Space and `onCommit` for setup/creation drafts. SPACE14 owns durable
before-image validation, storage failure rollback and cross-popover history;
SPACE13's app appearance parent is preserved. The same input component is used
in setup; its separate setup composition remains OB20's requirement.

## Checks

`scripts/test-theme-input.sh` compiles the actual model and AppKit editor and
sends explicit event objects to inert controls. It covers normalized axes and
outer clipping, linked-handle promotion and offset drag, one-transaction pointer
Undo, intensity cancellation across controls, dial click/drag recognition,
rotation threshold/scaling/end/cancel, latest wheel throttling, separate wheel
Undo, end-zero filtering, hover-at-delivery, pending-event dismissal, parent
interruption before recognition and release of a transient editor. Its
knob-position and cursor checks host the editor in an offscreen borderless
window that is never ordered in. They follow the drawn knob through every
geometry-flipped layer while it is pressed, dragged and held at the rim. They
also resolve the cursor over the pad, the knobs, a knob's mirror image, the
pad buttons and chevrons, and during and after knob and pad drags. With the
primary knob beneath +, they check the button's pointing hand, the suppressed
hover scale, the open hand on the knob outside the button, and that a press
on the disabled + cannot grab the knob. A background drag brings the primary
knob under the pointer with the open hand, keeps it through a cursor update,
shows +'s pointing hand over +, and returns to the arrow past the rim. Against
`32e456f4` the suite fails on
the mirrored knob placement. Variants fail on a crosshair background cursor, a
cursor update guarded only for knob drags, and a pad press without the button
guard. Rotation events carry a location over the knob. The knob geometry check
covers:

- clicks inside and just outside the 20-point circle, and in the frame's
  corners;
- a press on the knob dragged across the dial, released off and back on;
- rotation beginning on the ring and on the knob;
- the wheel and cursor in the frame's corner and beyond it.

Against `3a2128c6` it fails on the 24-point click. It does not post an OS event
or load a browser engine.

The existing model, appearance and original-window Undo suites remain applicable.
The input component passes 157 assertions after the November 1 review fixes
(148 after the pad-drag cursor and pad button hover styling, 141 after the November 1 knob geometry, 124 after the October 31 knob
and cursor correction, 79 before it). The model
passes 60, application appearance 80 and original-window theme Undo 40. The input suite also reproduced and then
closed a pending-wheel/short-rotation interleaving before independent review.
The corrective review adds stale-pad, pending-noise across controls, physical to
keyboard/AX history, and synchronous commit-rejection continuation coverage.
Whole-module Swift typecheck and the final SIL pass use warnings as errors with
Apple Swift 6.4 from `/Applications/Xcode.app/Contents/Developer`. Compiler and
inert-component results are source evidence; they do not claim browser runtime
or physical hardware acceptance. Final receipts and independent review are
recorded in `work/spaces-profiles-checks/space15`.
