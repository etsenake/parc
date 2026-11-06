# MEDIA12: Chromium event boundaries

Source inspection: local Chromium tree `work/engine-source/chromium/src`, Git
revision `d0c02bfad08ec92a6ffcf989e53cd995e6381a4c`. This describes the
runtime test. Paths below are relative to that Chromium tree unless noted.

## Session notifications

`content/browser/media/session/media_session_impl.cc:1232` sends an initial
info, metadata, images, position and actions snapshot immediately when an
observer is added. `RebuildAndNotifyMediaSessionInfoChanged` at 1580 compares
the whole current info struct to its previous struct and sends a clone only
when unequal. `RebuildAndNotifyActionsChanged` at 1916 builds a set and
notifies only when the whole set changes; metadata/images are independently
compared at 2000. These callbacks report snapshots, not a cause or a new
producer. For example title, mute, audio output, visibility, PiP, remote
playback, or a site-declared camera state can change them. The existing Parc
bridge `Engine/ParcNative/native_media_controls.mm:247` intentionally reads
current synchronous state when an asynchronous Mojo callback arrives. That
avoids applying stale payloads, but a transient inactive interval followed by
reactivation before delivery is invisible to that current-state read. Merely
counting callbacks or comparing each callback payload without document identity
can misattribute old queued messages to a replacement document.

`GetMediaSessionInfoSync` at 1120 maps audio focus ACTIVE/SUSPENDED/INACTIVE
to the reported state, then lets `is_ducking_` override it. Playback state is
separate and can be influenced by the routed website service. A paused player
can be SUSPENDED while still controllable; `IsControllable` at 820 rejects
inactive and one-shot-only sessions. Player add/remove, suspend, focus and
ducking paths include 458–569, 599–639, 875–890, 995–1035 and 1543–1576.
re-admission trigger. An active-to-suspended transition is not an inactive
interval; ducking is not a fresh player. Audio focus state can change for
reasons other than an independently new media object.

## Real input capture versus website declarations

`chrome/browser/media/webrtc/media_stream_capture_indicator.cc:322` registers
started streams in `MediaStreamUI::OnStarted`; its destructor removes started
streams. `AddDevice`/`RemoveDevice` at 740–766 maintain counts and synchronously
notify only on each per-WebContents, per-device-type zero crossing. Device
audio/video map to microphone/camera callbacks; tab, window and display
capture use separate categories (150–187). Multiple overlapping streams do
not each emit a start, and one stopped stream does not emit false while
another of the same type remains. `IsCapturingAudio/Video` at 846–875 includes
inner WebContents recursively, while callbacks name the actual WebContents
whose count changed. Observer lifetime is explicit (`media_stream_capture_indicator.h:140`);
acquire the indicator via `MediaCaptureDevicesDispatcher` and unregister before
observer destruction. The initial state must be queried separately; registering
an indicator observer does not itself emit a snapshot. Unregister on destruction
can emit false before removing usage (`media_stream_capture_indicator.cc:1004`).

By contrast Blink `third_party/blink/renderer/modules/mediasession/media_session.cc:211`
accepts website action handlers, and 315–340 accepts website declarations of
microphone/camera state. `MediaSessionServiceImpl` stores those values and
forwards changes only for the routed service (`media_session_service_impl.cc:113`,
`media_session_impl.cc:1685–1707`); toggle commands dispatch the declared
website action (`media_session_impl.cc:1402`). Neither handler presence nor a
declared unmuted/on state proves a device stream is running, and a real device
stream does not imply a usable website toggle action. Current Parc `Eligible`
accepts toggle handlers alone (`native_media_controls.mm:91`); that is a policy
adaptation, not actual recording evidence.

## Identity and integration mapping

The `MediaSessionImpl` is WebContents user data created once on demand
(`media_session_impl.cc:245–253,1038–1058`), so its identity survives a primary
document replacement. Per-frame `MediaSessionServiceImpl` is a self-owned Mojo
receiver with a weak session reference (`media_session_service_impl.cc:21–46`);
committed cross-document navigation clears that frame's playback state,
metadata and actions (`media_session_impl.cc:303–322`, service 48–55).
Parc's `PrimaryPageChanged` already retires the old document episode and
revalidates actions against its original primary frame.

A minimal explicit interface for the owner to evaluate is: keep a
per-original-document producer generation and independently track (1) current
media-session eligibility/state and (2) actual camera/microphone capture flags.
Initial observation seeds state without classifying subscription snapshots as
new starts. Process genuine capture zero crossings at their synchronous source;
requery aggregate capture for the original top-level contents, including inner
contents. Keep website action support as a separate control capability. Any
readmission on a capture start, session transition, or after loss of aggregate
recovered. Reset the generation on primary-page replacement and invalidate
queued notifications for the old generation; host transfer, title, metadata,
action-list churn, mute and state-preserving changes must not independently
create an episode. To preserve a short inactive-to-active transition without
replaying stale Mojo payloads, source-owned transition delivery needs a
document-bound synchronous record or an ordered document-tagged sequence;
reading only the latest state after a coalesced callback cannot establish that
an interval happened. Retain existing source/host/lease validation before
presentation or commands. Whether individual stream starts inside a nonzero
count should trigger another episode remains unresolved: the public capture
indicator intentionally does not expose them through these callbacks.

## Existing Parc capture boundary

The existing `Engine/ParcNative/native_appkit_page.mm` `NativePageState`
subscribes to this indicator at 321-341 and removes the observation during
teardown at 348-352 and 974-980. `CaptureChanged` at 834-844 walks the
callback's WebContents-to-outer chain and calls `Notify` when it reaches the
original page. `PostNotification` at 928-957 posts a non-nestable task with
weak page/observer and state lifetime checks; generic page notifications have
no captured payload and intentionally refresh current state, including after
a document change. Thus these notifications are invalidations, not recording
start/stop events, and can neither prove transition chronology nor identify
which callback caused the refresh. Requery after leaving the indicator stack
also avoids reading the not-yet-erased usage during unregister. Multiple posted
notifications may observe the same final value.

`PCNativePage.captureState` (`native_appkit_page.mm:354-360,1157-1159`)
creates a fresh `PCNativeCaptureState` whose camera/microphone values query the
indicator aggregate, including inner contents, and which privately retains a
weak original WebContents and WeakDocumentPtr (`100-135`). It is therefore
the existing suitable passive current-state boundary; another capture
observer is unnecessary for current-state refresh. The public flags alone do
not carry a producer generation. The current stop path verifies the weak
document and parent before use (`363-384`); any new media integration must
similarly bind its own episode to the original document, never treat an
old queued generic invalidation as a new-document producer event. Capture
notifications cover per-WebContents zero crossings, not every new stream or
all possible changes to the inner-contents topology. More precise ordered
producer events would require a separately justified source-owned interface,
not an assumption about this posted refresh.

## Ordering fence and limits

`content/public/browser/media_session.h:98-110,140-142` exposes synchronous
current info/actions and an untagged Mojo observer; it does not expose a
producer generation or a synchronous sequence number. The observer's queued
initial payload is indistinguishable at its consumer from an ordinary change
without additional source-side labeling. Neither reading the latest state on
callback nor marking a counter when a callback is delivered can tell whether a
notification was produced before dismissal. An inactive/active interval can
also be coalesced before a current-state requery.

Chromium overlay seam is a synchronous, UI-sequence-only event recorder with
monotonic generation and original primary WeakDocumentPtr. Candidate source
boundaries are `RebuildAndNotifyMediaSessionInfoChanged` after the whole-info
comparison at `media_session_impl.cc:1580-1598` and
`RebuildAndNotifyActionsChanged` when the set changes at 1987-1997. The
recorder would capture immutable old/new relevant state and allocate its
sequence at the producer, then defer delivery without entering the app shell
from Chromium's mutation stack. An initial subscription supplies only a
baseline and current high-water mark; dismissal synchronously records that
mark. A queued record is usable only when its document still matches and its
sequence exceeds the dismissal fence, followed by a fresh source, eligibility,
profile and host validation. Subsequent same-document events must have larger
sequences, and destruction/unsubscription must invalidate queued work. An
ordered record can preserve an intermediate state without treating an old Mojo
payload as current. If both session and capture changes need one ordering, they
must share a UI-sequence allocator and dismissal fence, not independent
counters compared as though globally ordered.

This seam is an engineering option, not an established admission rule: info
and actions are rebuilt in separate steps and info contains fields unrelated
to playback; an event on every changed struct would incorrectly conflate mute,
visibility, sink and other changes with new producers. Capturing relevant
`AddPlayer` insertion branches at 487-500 and 535-545 distinguish a newly
inserted normal-player key from updating an existing key, but focus changes can
Capture callbacks are synchronous zero-crossing hints within
`NativePageState::CaptureChanged`; the existing posted generic notification
does not retain their sequence or cause. Per-device counts do not reveal
individual overlapping stream starts. Any such seam requires an owner-reviewed
contract and overlay/build coordination; do not mutate the shared Chromium
source or infer admission from an arbitrary event.

If such a seam is implemented, meaningful inert tests should exercise producer
sequence allocation versus a dismissal fence, initial subscription as baseline,
old-document invalidation, duplicate and unrelated-field updates, intermediate
inactive/active records, capture overlap, and queued work after teardown. These

The minimal record at the info seam would contain `kind=info`, a monotonically
increasing sequence, weak primary-document identity, and the old and new
`state` and `is_controllable` fields (with an explicit absent-old marker for
initialization). At the action seam, it would contain `kind=actions`, the same
sequence space and document identity, and old/new presence of
`kToggleMicrophone` and `kToggleCamera`; these are action capabilities, not
capture. Other action or info changes should not produce a relevant-field
record unless the subsequently recovered policy requires those fields. Store
the previous and new values at the source before replacing `session_info_` or
`actions_`. Info and action updates are independently ordered observations,
not a single atomic snapshot, so preserve both record types and their sequence;
do not assert a joint transition that Chromium did not publish atomically.
`state=kDucking` masks underlying audio-focus state; if a recovered rule needs
the unmasked focus transition, record `audio_focus_state_` and `is_ducking_`
at their source transitions instead of inferring it from the reported enum.
Similarly, true capture requires separately recorded device zero crossings,
with explicit source identity, not these action flags.

A high-water counter alone is insufficient. For example an unrelated mute
change can advance a counter after a dismissal, and a subsequently delivered
pre-dismissal eligibility callback could then be wrongly identified as new.
Each queued candidate must carry its own producer-assigned sequence and relevant
old/new fields; compare that event's sequence to the captured dismissal fence,
not a fresh counter value at delivery. A field-qualified change still is not
remain unrecovered, no concrete overlay patch is proposed for integration yet.

The capture indicator's callback is per `WebContents` usage entry, not per
render frame or individual device stream. The aggregate may include inner
WebContents. Conversely `MediaSessionServiceImpl` is routed per render frame.
Its `DidFinishNavigation` explicitly resets playback, metadata and actions but
does not explicitly reset the stored camera/microphone declarations at
`media_session_service_impl.cc:48-55`; do not use a cached declared camera or
microphone value as proof of current-document device capture.

## Media player content-type adaptation

`MediaSessionInfo.audio_video_states` is an optional list, not a single content
classification (`services/media_session/public/mojom/media_session.mojom:214-218`).
`MediaSessionImpl::GetMediaAudioVideoStates` at 2199-2224 iterates player track
bits. It emits `kAudioVideo` when both bits are set, `kAudioOnly` or
`kVideoOnly` for one, and no entry when both are unset. `ForAllPlayers` at
2227-2233 includes normal and one-shot players, not ambient or hidden players.
If a routed service has a frame, only players in that exact frame contribute;
otherwise all enumerated frames contribute. `ComputeFrameForRouting` at
1775-1844 selects an active eligible frame/service, generally the shallowest
frame with a player, or an appropriate topmost service as a fallback. A routed
service can therefore omit audio from another frame. Multiple player types can
coexist in the resulting list, and a site with only a service and no players
can produce an empty list.

Player track bits are reported through `MediaWebContentsObserver::OnMediaMetadataChanged`
(`content/browser/media/media_web_contents_observer.cc:601-620`) to
`MediaSessionControllersManager::OnMetadata` and `MediaSessionController::SetMetadata`
(`media_session_controllers_manager.cc:45-55`, `media_session_controller.cc:34-43`).
The latter updates bits and calls `AddOrRemovePlayer`; normal-player add/remove
rebuilds info (`media_session_impl.cc:458-569`), one-shot add rebuilds it at
1612-1628, and route changes rebuild at 1757-1771. The entire info struct is
compared before an observer notification, as described above. An initial
subscription is a snapshot, and an info change is not necessarily a start.
`IsMediaSessionNeeded` (`media_session_controller.cc:273-291`) generally
requires in-progress audio and an unmuted tab, with PiP and active remote
playback exceptions. This further limits which players appear in the list.

`any(kAudioOnly, kAudioVideo)` on this list is a conservative Parc adaptation
for the playback branch: reject null/empty, video-only and unknown entries,
while retaining the independently required session state and controllability
checks. It tests Chromium's routed session-player inventory, not all audio on
It may exclude audible players in other frames, omits ambient players, and can
observe one-shot entries together with normal ones. It does not establish
whether a media producer started, and must not suppress a separately established
recording branch merely because playback has no audio track. Apply only with
