# Space theme physical feedback

The theme editor provides intensity and noise detents through
the native AppKit haptic performer. Feedback belongs to admitted editor value
changes. Commit, cancellation, Undo, parent refresh and color/preset/texture
actions do not add haptic effects.

## Detents

Noise rotation and drag can emit feedback when an accepted value change crosses
or touches a 0.1 detent; slider, dial click, wheel, keyboard and accessibility
noise adjustments are silent. Intensity uses 0.2 detents for all admitted input.
The inclusive old/new range counts both arriving at and leaving a detent.
Unchanged/clamped values are silent; crossing several detents emits one pulse.
Noise values clamp to 0…1 and round to twentieths except during rotation.

Requests use `NSHapticFeedbackManager.defaultPerformer`, generic/now, obtained
anew for every pulse. No timer, retained performer or separate preference is
involved. Color, preset, texture, appearance, gesture end and Undo are silent.

## Parc ownership and integration

`ThemeHapticFeedback` implements these predicates against the previous
and accepted model values. The view performs feedback after its gesture
admission check and model mutation. This avoids pulses from rejected input,
out-of-range values clamped to the same value, or programmatic refresh.
`SpaceThemeNoiseGesture` owns input provenance and the physical mapping; its rotation
and drag cases alone qualify for noise feedback. Keyboard and accessibility
noise adjustment use the existing slider case and stay silent. Intensity
changes use the reducer's unfiltered predicate, including its existing native
keyboard/accessibility routes. These routes are Parc input adaptations, not
new haptic patterns.

Input admission precedes feedback: the intensity slider discards normalized
pointer changes below 0.001 before mutation. Physical mapping and cancellation
remain in [theme input](space-theme-input.md).

Parent Undo and shared-theme replacement cancel the control input
before subsequent feedback admission. Dismissal/commit and control retirement
have no pending haptic job to drain or cancel. Feedback does not retain a
window, editor, gesture or device. Global appearance remains a separate parent operation.

The macOS SDK's `NSHapticFeedback.h` defines generic=0 and now=1. It directs
clients to request `defaultPerformer` each time because the appropriate input
device, accessibility settings and user preferences can change. AppKit may
suppress a request, including when a Force Touch trackpad has no finger contact.
Parc therefore uses this genuine API without inventing a capability or
preference toggle. The tab-reordering haptic setting is unrelated. The app's
macOS 13 minimum is above this API's macOS 10.11 availability.

## Checks

`scripts/test-theme-haptics.sh` injects the feedback action so it can inspect
detent and control ownership without producing physical feedback. Its checks cover
the inclusive boundaries, reversal, multiple crossings, repeated/clamped
values, gesture provenance, silent non-haptic actions and parent cancellation.
