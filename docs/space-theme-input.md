# Space theme pointer, rotation and wheel input

A pointer gesture previews a theme and commits once when finished. Wheel events
are separate quantized edits after a 200 ms latest-event throttle. Parent Undo,
another control or dismissal retires old input before it can edit newer state.

## Input mapping

| Control | Mapping |
|---|---|
| Empty color pad | Zero minimum distance; normalize each axis as `(location - halfDimension) / halfDimension`, y down. |
| Color handle | Capture initial center, then add pointer translation. Grabbing a companion promotes it to primary color. |
| Color conversion | Display P3 HSL hue from angle; `clamp(radius / 0.99, 0...1)` interpolates saved lightness range. |
| Intensity | Clamp absolute x to padded wave width, normalize, suppress changes below 0.001. |
| Noise dial drag | Ten-point threshold on the 80-point surface. Angle is `(atan2(y-center, x-center) + π/2) / 2π`, wrapped into one turn. |
| Noise rotation | Begins on the central knob, recognizes after one degree, adds accumulated degrees / 720. |
| Noise wheel | Latest nonzero vertical delta each 200 ms; hovered center adds/subtracts 0.125 without magnitude scaling or sign reversal. |

Noise stays in 0…1. Rotation is continuous; other inputs round to twentieths.
Rotation/drag share one history snapshot; changed ring clicks/wheel events each
have their own. Keyboard/accessibility steps use slider provenance and finish
prior physical input before reading authoritative state.

## Native ownership and adaptations

Native events belong to the original control/window. Throttled wheel delivery
checks hover when delivered, retains the control weakly and cannot survive input
retirement into an Undo-restored model. Ending/cancelled rotation retires without
applying another payload; physical cancellation commits the latest admitted draft,
whereas authoritative parent replacement discards it.

A cancelled phased wheel/momentum stream resumes only with a new physical begin,
or an unphased burst after 200 ms idle. Subthreshold rotation also counts as an
active stream. Starting rotation retires pending wheel input even if recognition
never completes. Switching controls commits previous preview and retires every
queued or partially recognized input, including a gesture without a snapshot.

Pad/intensity hold a physical pointer latch so an old drag/up cannot enter a new
gesture. Finish, dismissal, local/parent Undo and commit rejection retire input
and restore cursors. A new latch is captured after the prior commit callback,
so rejection cannot erase the new gesture. `onPreview` remains transient;
`onCommitChange` owns existing Spaces and `onCommit` owns setup/creation drafts.
[Theme Undo](space-theme-undo.md) owns persistence/rollback and cross-editor history.

## Drawn knob position and cursors (October 31)

Drawing, hit testing and pointer mapping all use the same y-down coordinates;
backing sublayers must not introduce another geometry flip. Direct handle drag
keeps grab offset, clips to radius 0.99 and does not spring while tracking.
The pad uses an arrow, handles an open hand, an active handle drag a closed hand,
and buttons a pointing hand. Release outside the pad restores the arrow.

AppKit resolves one cursor from the actual pointer. Buttons win over handles
beneath them, and disabled-button presses must not fall through to grab a handle.
During a pad drag the cursor is recomputed after moving the primary handle;
beyond the rim it returns to arrow. Buttons, including preset swatches, retain
Parc's pointing-hand behavior.

## Knob hit geometry (November 1)

The 40-point center button has a 20-point circular press region. Press/release
inside cycles texture and never starts a ring drag. Elsewhere in the 80-point
square the interaction is a ring click/drag. Rotation must begin within the
center circle; beginning outside remains ignored until end. Wheel hover and cursor
use the center's rectangular 40-point frame, so a corner can hover but still be
a ring click. These distinct regions must not be replaced with one oversized hit
radius.

## Checks

`scripts/test-theme-input.sh` exercises production model/AppKit controls with
explicit event objects: axes/clipping, linked handle promotion, offset tracking,
one-transaction Undo, intensity cancellation, dial thresholds, rotation/end,
wheel throttle and parent interruption. Inert geometry checks cover drawn layers,
button-over-handle precedence, disabled buttons, cursor restoration and circular
versus rectangular hit regions. Model, appearance and original-window Undo suites
remain applicable. These checks do not post OS input or establish physical
trackpad, haptic or browser-runtime acceptance.
