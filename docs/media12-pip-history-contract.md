# Picture in Picture and Mini Player state boundaries

PiP and Mini Player episodes have separate owners. PiP is accepted product
behavior; this document describes the existing state boundary and is not a
proposal to reopen it. Production code is in
`Engine/ParcNative/native_media_controls.mm`,
`native_background_picture_in_picture.h` and `native_media_episode_store.h`;
the window host (`native_appkit_host.mm`) decides shell visibility, with the
still-visible hold's decisions, maths and timing in
`native_background_picture_in_picture_hold.h`.

## Automatic video PiP

The auto-entry policy combines shell visibility, current Chromium PiP state,
media eligibility and explicit signals. Shell visibility is independent of paint
visibility: a page can remain shown to Chromium while its window is occluded.
Leaving the app must not blank the live renderer merely to drive PiP.

Leaving a window backgrounds the pages it shows. A window is focus away when it
is outside the active key-window chain: Parc as a whole is inactive, or another
Parc window is key that is not this window, one of its sheets or one of its
child windows. One rule then covers ordinary video and pages that run their own
automatic handler, such as Meet: a shown page in a focus-away window counts as
occluded, so automatic PiP may start, unless it is held because at least half of
it is still visible. A handler page that is not held is itself told it is
hidden. The hold needs the page shown, macOS reporting its window visible, the
displays awake, the screen unlocked and no PiP already open for the page. Parc
measures each shown page on its own rectangle, so both halves of a split and
Peek are judged separately: the part inside its window on any display, minus
visible normal-level windows stacked above that window, whoever owns them (other
Parc windows included, overlaps counted once). Floating windows such as the PiP
window never count.

Parc measures when a window becomes focus away, either because Parc resigns
active while the window was in the key chain or because the window loses its
place in the chain while Parc stays active, and once more a quarter second
later. A page below half at either check enters PiP straight away. A window that
was already focus away does not start over when Parc later resigns active. While
a held page could actually enter automatic PiP (eligible playing video, or a
page with its own handler), Parc measures again every half second. That catches
a window that later grows over the page even while macOS still reports Parc's
window visible, which it does while any part of the window shows and can do
under a full cover by a window with transparent areas. A page below half across
a full second of consecutive readings loses its hold and enters PiP; any reading
at or above half restarts that second. No timer runs while no held page could
enter PiP; the page's media state tells its window when its playback, muting or
own handler changes. The hold ends when the window returns to the key chain
(owned PiP then exits as before), the page stops being shown, macOS reports the
window not visible (the usual one-second occlusion path then enters PiP), the
displays sleep or the screen locks. It also ends once the page's PiP is open, so
it blocks entry without closing anything. Window bounds come from the window
server's list, which needs no Screen Recording permission (only window names
do); without that list the measurement uses display edges and macOS's occlusion
state alone.

Chromium owns automatic entry for a page with its own handler, including its
activation and lifecycle ordering, and only that entry may open a document PiP
without a gesture, so Parc's video policy never enters that page itself. Parc
passes its window occlusion to Chromium's helper (see the
[media hooks](chromium-hooks-media.md)) and does not report a video that its
own policy is already entering. No timeout stands in for the renderer's hidden
confirmation that entry waits for, because the media action travels on a
different pipe.

Eligibility requires the site's auto-PiP permission, a controllable playing
session, an unmuted tab and video. The policy distinguishes idle, pending entry,
owned active PiP, user-closed and cancel-pending states. It does not take ownership
of a manually opened or otherwise foreign PiP session.

Returning to the foreground exits owned automatic PiP. If entry is still pending,
`cancel-pending` remembers that intent so a late successful entry is exited
instead of being mistaken for foreign PiP. A silent entry timeout allows at most
one retry while still backgrounded. Repeated ordinary reconciliation cannot
create an endless retry loop. User closure while backgrounded suppresses
immediate re-entry; later genuine visibility/media transitions drive policy.

## Mini Player episodes

Mini Player admission, dismissal and capacity eviction use their own source-bound
episode identities and suppression fence. A view refresh or temporary lost
window owner cannot resurrect a dismissed episode. Explicit presentation-set
producers consume a valid lease to admit again; see
[producer contract](media12-producer-contract.md) and [Mini Player](media-mini-player.md).
Do not substitute a single PiP visibility flag for this episode policy.

## Native event limits

Chromium video and document PiP use distinct controllers. Their generic
`MediaPictureInPictureChanged(bool)` callback identifies neither request failure
nor close reason and cannot reconstruct a complete prior event history. Request,
show, user intent, cancellation, replacement and actual close are separate facts.
A void exit call or a manager's controller-existence Boolean is not proof of
successful asynchronous closure.

Any additional event consumer must bind to weak source WebContents, the primary
and originating documents, PiP kind and a request/session identity. Navigation,
source retirement or invalidated origin must retire pending events. Late replies
cannot affect a newer request, episode or Profile. Never retain a document,
Profile, browser or presenter merely to keep history. Terminal native callbacks
may destroy their owner synchronously; do not use raw pointers afterward.

## Checks

Pure state-machine and native component checks validate cancellation, retry and
episode ownership; `tests/NativeBackgroundPipHold/run.sh` covers the
still-visible hold's focus-away gate, display clipping, window coverage and
half-second re-measuring. The historical full-state observation proposal is
not a current implementation requirement.
