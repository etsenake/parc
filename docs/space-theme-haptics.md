# Space theme physical feedback

SPACE16 reproduces the original editor's intensity and noise detents through
the native AppKit haptic performer. Feedback belongs to admitted editor value
changes. Commit, cancellation, Undo, parent refresh and color/preset/texture
actions do not add haptic effects.

## Recovered contract

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The retained theme-picker evidence and the recovered-components, Swift-type,
cross-reference and annotated-function helpers resolve the complete theme
haptic route. No second reference version or new REA/decompilation was used.
Annotated receipts are in `work/spaces-profiles-checks/space16`.

The global haptic inventory in [Split groups](split-groups.md#split-gesture-and-context-inventory--sp33)
`NSHapticFeedbackManager.defaultPerformer` for each request and calls
`performFeedbackPattern:performanceTime:` with pattern 0 (generic) and time 1
(now). It has no timer, retained performer, application preference, Reduce
Motion branch, hardware probe or alternate sound effect. Its two function
references are the noise and intensity reducer effects below.

  clamps the requested value to `0...1`, and rounds to twentieths except for
  identifies these as **rotation** and **drag**. Slider (0), dialClick (2)
  and scrollWheel (3) are silent. The predicate receives step **0.1** at
  `0x20`, clamps and stores its new value, then invokes the same predicate
  this reducer. A positive result constructs the same haptic effect at
  any element of `stride(from: 0, through: 1, by: step)`. Either endpoint
  counts, so arriving at and leaving a detent can each emit a pulse. It
  returns a Boolean: crossing several detents in one update still produces
  **one** pulse. No time-based throttling or delayed replay is present.

These are the complete producer references, not a search limited to one
control callback. The shared producer does not appear on color-pad, preset,
color-count, texture-selection, appearance, gesture-end or Undo routes.

## Parc ownership and integration

`ThemeHapticFeedback` implements the recovered predicates against the previous
and accepted model values. The view performs feedback after its gesture
admission check and model mutation. This avoids pulses from rejected input,
out-of-range values clamped to the same value, or programmatic refresh.
SPACE15 owns `SpaceThemeNoiseGesture` and the physical mapping; its rotation
and drag cases alone qualify for noise feedback. Keyboard and accessibility
noise adjustment use the existing slider case and stay silent. Intensity
changes use the reducer's unfiltered predicate, including its existing native
keyboard/accessibility routes. These routes are Parc input adaptations, not
new haptic patterns.

The original input admission still precedes these effects. In particular,
than `0.001` before calling its setter; those inputs do not reach the intensity
reducer or produce feedback. Rotation recognition, pointer drag thresholds
and scroll delivery retain the [SPACE15 input contract](space-theme-input.md).

SPACE14's parent-Undo and shared-theme replacement cancel the control input
before subsequent feedback admission. Dismissal/commit and control retirement
have no pending haptic job to drain or cancel. Feedback does not retain a
window, editor, gesture or device. Global appearance remains SPACE13's separate
parent operation.

The macOS SDK's `NSHapticFeedback.h` defines generic=0 and now=1. It directs
clients to request `defaultPerformer` each time because the appropriate input
device, accessibility settings and user preferences can change. AppKit may
suppress a request, including when a Force Touch trackpad has no finger contact.
Parc therefore uses this genuine API without inventing a capability or
preference toggle. The tab-reordering haptic setting is unrelated. The app's
macOS 13 minimum is above this API's macOS 10.11 availability.

## Checks and limits

`scripts/test-theme-haptics.sh` injects the feedback action so it can inspect
detent and control ownership without producing physical feedback. Its checks cover
the inclusive boundaries, reversal, multiple crossings, repeated/clamped
values, gesture provenance, silent non-haptic actions and parent cancellation.
The finished control source passes **42 haptic assertions**, including the
actual delivered wheel route, pointer drag/release and rotation cancellation.
The shared input suite passes **79 assertions**, the appearance component
passes **72 assertions**, and the integrated Undo component passes **40
assertions**. Their editors also inject silent feedback. The finished
whole-module SIL pass completes with warnings as errors and zero diagnostics.
Check receipts, source hashes and independent clearance are retained beside
the annotated evidence.

No functional browser test or physical-device feel comparison is claimed.
The delivered contract is source and inert-component behavior; AppKit remains
responsible for whether the current hardware actually performs a request.
