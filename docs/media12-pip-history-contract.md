# Picture in Picture and Mini Player state boundaries

PiP and Mini Player episodes have separate owners. PiP is accepted product
behavior; this document describes the existing state boundary and is not a
proposal to reopen it. Production code is in
`Engine/ParcNative/native_media_controls.mm`,
`native_background_picture_in_picture.h` and `native_media_episode_store.h`;
the window host (`native_appkit_host.mm`) decides shell visibility, with the
still-visible hold's maths in `native_background_picture_in_picture_hold.h`.

## Automatic video PiP

The auto-entry policy combines shell visibility, current Chromium PiP state,
media eligibility and explicit signals. Shell visibility is independent of paint
visibility: a page can remain shown to Chromium while its window is occluded.
Leaving the app must not blank the live renderer merely to drive PiP.

Leaving Parc backgrounds the pages it shows. Ordinary video counts as occluded
while Parc is inactive; a page that runs its own automatic handler, such as
Meet, counts as occluded once its window leaves the active key-window chain,
which also reports the page hidden. The one exception is a page plainly still on
screen. When Parc as a whole is inactive, the page is shown, macOS reports its
window visible, the displays are awake and the screen is unlocked, Parc measures
each shown page on its own rectangle, so both halves of a split and Peek are
judged separately: the part inside its window on any display, minus visible
normal-level windows stacked above Parc's window (other Parc windows included,
overlaps counted once). With at least half of the page's area visible, the page
is held visible and does not enter PiP. Parc measures when it resigns active and
once more a quarter second later, so a covering window that registers late still
sends the page to PiP after that pause. Nothing monitors after that: a window
that later covers the page while macOS still reports Parc's window visible
leaves the hold in place. The hold ends for good once Parc becomes active, the
page stops being shown, macOS reports the window not visible (the usual
one-second occlusion path then enters PiP), the displays sleep or the screen
locks. It also ends once the page's PiP is open, so it blocks entry without
closing anything; switching between Parc windows keeps Parc active and is
unaffected. Window bounds come from the window server's list, which needs no
Screen Recording permission (only window names do); without that list the
measurement uses display edges and macOS's occlusion state alone.

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
still-visible hold's gates, display clipping and window coverage. The historical
full-state observation proposal is not a current implementation requirement.
