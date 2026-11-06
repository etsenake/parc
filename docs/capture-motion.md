# Capture motion, focus and native feedback

CAP24 keeps presentation below the existing capture, Library, image-editor and
macOS sharing owners. It does not obtain pixels, change a destination, extend a
native document lease or claim that a completed sharing service delivered to a
recipient. Source/component completion is separate from functional browser,
VoiceOver, Full Keyboard Access and whole-browser appearance acceptance.

## Recovered motion

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The recovered-components, Swift-type, cross-reference and annotated-function
helpers resolved this row. No new heavy decompilation or second-version trace
was needed. Original annotated instructions are retained under
`work/capture-coordination/cap24`.

- `Capture.ContentCaptureView.FocusRectAnimator` owns a published frame, opacity,
  a **90 ms latest-value main-queue throttle** to target changes. Lazy spring
- Parc reuses its already recovered Motion oscillator arithmetic from
  `DownloadArrivalSpring`, with separate origin/size vectors. The lens, gray
  cutout and dim cutout draw one shared rectangle sample. A new target retains
  current position and velocity; throttling keeps the latest target. A native
  main-run-loop timer drives the AppKit paths. The timer is a platform adaptation
  of Motion's animation owner. Native offers remain immediately authoritative;
  pending geometry is presentation only. Clearing a target, beginning a drag,
  retiring capture or detaching immediately cancels the pending target/timer.
  Reduce Motion settles to the latest target, including an already pending one.
  Parc applies that reveal only to a newly acquired image, not every catalog
  refresh or edit. A phase change cancels it; Reduce Motion shows the final
  image immediately. This is image reveal, not an invented white flash.
  to click-eligibility text and hover state. Its hovered opacity is **0.1**,
  The prior speculative description of a spring decoration is replaced by this
  actual call-site contract. Parc crossfades its single native text rendering,
  preserving one accessible instruction. CAP18's native static gradient remains
  its documented rendering adaptation.
  **response 0.5, damping 0.7, blend duration 1**. CAP19's compositor supplies
  flattened, exact owned preview bitmaps, so Parc blends the previous display
  image out with the physical 0.5/0.7 spring. It does not animate or resample
  committed output bytes. A new preview settles the previous bitmap blend
  before beginning the next; detachment and Reduce Motion remove it. This
  bitmap crossfade is an explicit native adaptation of the original SwiftUI
  property transaction; it does not claim reproduction of SwiftUI blend-duration
  velocity across different bitmap contents.

## Library preview

The existing [shared MediaPreviewWindow contract](download-library.md) applies
to saved captures and external files: presenter types retain actual selected
**0.9/0.25 opening** and **0.95/0.15 closing** damping/response springs. Centered
geometry is retained by `DownloadPreviewGeometry`; its native spring uses the
actual settling duration. No second reference recovery was needed.

Both Media sources now provide their actual invoking thumbnail and an exact
item-bound visible artwork rectangle. The external-file Quick Look owner uses
its existing transition. Saved captures use an owned borderless child over the
original parent, with the same separate modal transform, thumbnail/live-content
crossfade, backdrop and shadow. Copy/export still uses the immutable saved PNG;
only the small display thumbnail participates in the transition. Controls remain
native and source/title/date remain selected-item metadata.

Closing starts from the current presentation transform. If its source item is
no longer visible/valid, or Reduce Motion is enabled, closure is immediate.
Profile/item/window retirement, parent minimization or a competing original-window
sheet cancels animations and closes once. Parent resize/move settles and relays
out the same preview. Changing Reduce Motion during a close completes it
immediately; during opening it settles the final presentation. CAP23's mixed
ordering, next/previous delegation, revision guards, file-access lease and
thumbnail/clipboard cancellation remain their original owners. Moving between
mixed items replaces the preview immediately through that existing coordinator.

## Focus, keyboard and accessibility

captured-image action owner. The action view owns selected ID and search binding.
Parc uses its native responder chain with its existing unified reversible editing
flow; native AppKit controls and labels are explicit platform adaptations.

Selection owns the overlay, Visible Area and Cancel loop. Preview owns the search
field followed by its enabled real action rows. Crop, Portrait and the actual
image editor own their own loops; hidden controls never remain in the active
loop. Rebuilding a focused action returns focus to its live search field. Row
focus updates the selected destination and Up/Down traverses enabled rows.
Search Up/Down/Return retains CAP20's genuine stable action identity and expansion
policy; active marked text remains with the native input method. Modified
plain-action keys are not interpreted as unmodified capture or deletion commands.
Selection messages, selected destinations and real failures expose native AX
values/notifications; errors additionally announce their actual message. The
instruction and decorative transition images do not duplicate AX content.

Capture returns to its original renderer only through the existing verified
finished callback. A canceled/failed save, image edit or native Messages operation
returns to the live capture search owner only if the original document, lease,
window and state still match, the original window is key and no sheet remains.
If macOS completes sharing before returning key status, one pending request is
consumed on that original window's next key notification. Parc never activates
another app or forces a background window forward.

Library records the initiating search selection or collection as a weak native
focus bookmark. Closing a preview waits for the original window to become key;
a changed responder, retired Library/Profile/window or later preview cancels the
bookmark. It is consumed at most once. The original field editor, its owning field and selected
text range survive where valid. A shared field editor reused by another text field
counts as intervening focus. Library sharing callbacks use the same guarded
original-window bookmark; retiring their owner cancels that pending return. Native Quick Look, file panels, editor sheets and
the Messages composer retain their OS lifecycle; no synthetic event monitor,
composer animation or fake cancellation is installed.

## Haptics and service ownership

The indexed `performFeedbackPattern:performanceTime:` call sites do not establish
any capture-selection, capture-menu, saved-preview or Messages haptic. The nearby
scale 1 from outside 0.99/1.01 and requests pattern 1/time 1. It is not a capture
completion callback. CAP21's current image-editor controls do not invoke that
scale gesture. No capture/menu/composer haptic is fabricated or borrowed from it;
Easel gesture completion remains the Easel family's separate requirement.

The real `NSSharingService` continues to own its composer, animation and native
feedback after `perform(withItems:)`. CAP20 owns the current image + original URL
payload, capability checks and real success/cancel/failure dispatch. CAP24 adds
only the guarded return-focus path. Existing attributed interface sound effects
remain their existing owner and are not duplicated.

## Checks

`scripts/test-capture-motion.sh` compiles the production overlay/control source
slices and actual motion/focus implementations with an inert native-target double.
Its 44 assertions cover latest-target replacement, interrupted settling, immediate
retirement, Reduce Motion, delayed/once-only/invalid/intervening focus, shared
field-editor owner replacement, search and both directions of the enabled key
loop, focused-row replacement, marked text, busy destination rows, active reveal
cancellation and live external-preview reduction. It never orders a window,
posts input, constructs a renderer or invokes an output service. The Media
tile's artwork anchor is the tile's drawn, aspect-fit thumbnail. The Media tile
checks in `tests/DownloadLibrary/ViewTests.swift` cover it through the real
preview's open-from rectangle.

The updated `scripts/test-portrait-capture.sh` checks the real compositor,
reversible image state and isolated preferences with the motion helper linked.
Whole-module warnings-as-errors typechecks and the final integrated SIL pass
completed with zero diagnostics (final SIL 29 seconds). Static renders of the
actual saved-preview source confirm light/dark toolbar legibility and compact
control layout; the render fixture never orders a window or invokes an action.
Receipts and checked input hashes are
retained under `work/capture-coordination/cap24` and
`work/claude-split-checks/cap24-*.json`. These establish compiler and component
behavior, not browser runtime, VoiceOver/FKA or pixel-matched acceptance.

Independent review cleared the complete CAP21-integrated source after correcting
actual artwork anchors, reciprocal reverse traversal, shared-field-editor owner
validation and live external-preview Reduce Motion. The final source manifest
contains 257 matching Swift files; review did not repeat the author checks.
