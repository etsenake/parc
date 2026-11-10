# Picture-in-picture observation boundaries

PiP behavior is accepted; this document explains why generic engine notifications
must not be used as a complete source of Mini Player suppression state. The
implemented producer is [presentation suppression](media12-producer-contract.md),
with [native event mapping](media12-chromium-events.md).

## Generic observers are insufficient

`PictureInPictureWindowManager::Observer` has parameterless enter/exit callbacks.
It cannot identify source document, request, session replacement or close reason.
A reused video controller may replace its session without another enter event;
UI closure and generic manager closure have different notification paths. A
late-installed observer cannot reconstruct history from the current PiP bit.

Video requests carry an originating RenderFrameHost through pending confirmation
and active session. Delayed/default callbacks must retain their original identity
and cannot terminate a newer session. Document PiP uses a separate opener/child
WebContents lifecycle. These must not be collapsed into an unqualified Boolean.

## Current consumer contract

The production Mini Player uses original-page presentation leases and one-shot
suppression fences around actual app presentation-set mutations. Generic media
refresh, Mojo snapshots and parameterless notifications do not manufacture a
producer event. Original-document replacement and eligibility loss invalidate
suppression. The linked producer guide owns the exact re-admission operations.

Source/component checks cover these boundaries.
