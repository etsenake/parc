# Mini Player admission and re-admission

`native_media_controls.mm` owns media episode identities, privacy-domain capacity,
dismissal/eviction suppression and original-document leases. The application
publishes explicit presentation-set removals; an arbitrary media snapshot or
window refresh must not act as a new producer.

## Established producer and store boundaries

A dismissed or evicted source stays suppressed while its episode remains
eligible. Suppression can clear when eligibility ends, the primary document is
replaced, or an admitted presentation-set removal is consumed. Re-admission
creates a new episode identity and arrival sequence; an existing admission keeps
its identity and order. Each privacy domain enforces the five-entry capacity
independently.

Ordinary playback admission requires controllable active media, an unmuted page
and an audio-only or audio-video entry in Chromium's routed player inventory.
Microphone/camera toggle capabilities remain a separate compatibility path;
handler presence is not evidence of a real device stream. Existing paused or
casting episodes can remain held without satisfying a new-admission predicate.

## Presentation mutations that can produce admission

`presentationSetMediaRemoval` captures original outgoing pages before a mutation
and consumes only pages actually removed by a successful commit. Supported paths
include ordinary tab/MRU selection, Space switch, tab fullscreen entry, split
separation and non-split Peek expansion.

| Operation | Admission boundary |
|---|---|
| Tab or committed MRU selection | Original displayed pages removed from the new presentation set. |
| Separate / Separate All | Original attached/rendered split members removed by the committed operation. |
| Space switch | Original Space's displayed IDs removed by the successful switch. |
| Tab fullscreen | Members removed from the applicable presentation set. |
| Non-split Peek Expand | Replaced displayed set after successful promotion. |
| In-split focus, same-content selection, Peek open/close, cancelled MRU | No new producer merely from input or refresh. |

Each one-shot `PCNativeMediaPresentationLease` captures weak WebContents,
primary-document, Profile and Browser identities plus a suppression fence.
Consumption requires the same owner/document and unchanged fence; an intervening
dismissal, eviction, transfer or retirement invalidates it. Current synchronous
eligibility is checked after consumption. Title/artwork updates, initial Mojo
snapshot replay, host availability and generic `Changed()` calls cannot release
suppression.

## Chromium mapping constraints

A MediaSession survives primary-document replacement; its asynchronous snapshots
are not producer events. The bridge re-reads current synchronous state, while
explicit source leases establish chronology. Comparing a delivery-time counter
to a dismissal is insufficient because unrelated callbacks may advance it.

Chromium's audio/video inventory is routed by frame and may omit other frames or
ambient players. Device capture counts report per-WebContents zero crossings,
not individual overlapping stream starts. Website camera/microphone declarations
and actual capture remain separate. See [event boundaries](media12-chromium-events.md).

## Checks

Source/model checks cover exact owner/document rejection, suppression fences,
privacy capacity, order and genuine presentation removals.
