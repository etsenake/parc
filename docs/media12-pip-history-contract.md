# Picture in Picture and Mini Player state boundaries

PiP and Mini Player episodes have separate owners. PiP is accepted product
behavior; this document describes the existing state boundary and is not a
proposal to reopen it. Production code is in
`Engine/ParcNative/native_media_controls.mm`,
`native_background_picture_in_picture.h` and `native_media_episode_store.h`.

## Automatic video PiP

The auto-entry policy combines shell visibility, current Chromium PiP state,
media eligibility and explicit signals. Shell visibility is independent of paint
visibility: a page can remain shown to Chromium while its window is occluded.
Leaving the app must not blank the live renderer merely to drive PiP.

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

## Validation boundary

Pure state-machine and native component checks validate cancellation, retry and
episode ownership. They do not establish live playback, device interoperability
or every window-manager transition. The historical full-state observation proposal
is not a current implementation requirement or authorization for browser tests.
