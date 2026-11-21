# Capture motion, focus and native feedback

Presentation stays below the existing capture lease, Library, image editor and
macOS sharing owners. Animation cannot obtain pixels, change a destination,
extend a document lease or prove delivery to a message recipient.

## Motion

| Surface | Behavior |
|---|---|
| Selection rectangle | Latest target throttled at 90 ms; response 0.35, damping 0.87 spring; shared geometry for lens and cutouts. |
| Newly acquired image | One-second opacity reveal with cubic (0.215, 0.61, 0.355, 1). Edits and catalog refreshes do not restart it. |
| Selection instruction | 0.2-second ease-in-out crossfade; one accessible instruction. |
| Capture mode | The scrim fades in over 0.2 seconds as the mode bar pops in like a Notes card; the bar fades out for a drag; Cancel fades the scrim, hint and bar out over 0.18 seconds. Reduce Motion keeps only short fades. |
| Portrait preview | Response 0.5, damping 0.7 spring blends owned preview bitmaps, never committed output bytes. |
| Output palette | Notes card pop (scale 0.95 to 1 with a short fade, 0.07-second close); the highlight glides on the Notes spring; submenus pop beside their row; the card glides to new sizes and pages push over 0.22 seconds. |
| Saved Library preview | Opening damping/response 0.9/0.25; closing 0.95/0.15 from the current presentation transform. |

New selection targets retain current position and velocity. Clearing the target,
beginning a drag, retiring capture or detaching cancels its pending timer.
Reduce Motion settles the latest target, shows final images immediately and
turns the palette's pops, glides and pushes into short fades.
Changing phase cancels reveals; a newer Portrait preview settles the old blend.

## Library preview

Saved captures use an owned borderless child over the original parent, anchored
to the invoking thumbnail's visible artwork rectangle. The display thumbnail
crossfades into live preview content; Copy/export still uses the immutable PNG.
External files retain the native Quick Look owner. See [Library](download-library.md).

An invalid or hidden source rectangle makes closing immediate. Item/Profile/
window retirement, minimization or a competing sheet cancels and closes once.
Parent move/resize settles layout. Turning on Reduce Motion settles an opening
preview and completes a closing one. Mixed-item navigation, revisions, file
leases and clipboard/thumbnail cancellation stay with the Library coordinator.

## Focus, keyboard and accessibility

Selection owns the overlay and the mode bar's enabled buttons. Preview keeps focus in
the palette's search field; its rows are a menu whose items VoiceOver reads, and
Up/Down/Return, Right/Left and Escape drive the rows and submenus from the field,
whose help names the highlighted row. Each submenu focuses its own search.
Crop, Portrait and the actual image editor own their own loops; hidden controls
never remain in the active loop. Rebuilding rows keeps the search focused and the
highlighted row by identity; active marked text remains with the native input
method. Modified
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

Capture adds no capture-menu, preview or composer haptic. Existing interface
sounds retain their original owner. `NSSharingService` owns its composer and
native lifecycle; Parc only supplies the current image/original-URL payload,
capability checks and guarded success/cancel/failure callbacks.

## Checks

`scripts/test-capture-motion.sh` covers latest-target replacement, interruption,
Reduce Motion, once-only focus return, shared field-editor replacement, enabled
key loops, marked text, busy rows and owner retirement using inert doubles.
`scripts/test-portrait-capture.sh` covers the actual compositor and reversible
image state.
