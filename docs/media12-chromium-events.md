# Chromium media event boundaries

The native bridge combines current media-session snapshots with explicit
presentation-removal leases. These event types have different semantics; do not
infer a newly admitted episode from any observer callback. The implementation
lives in `Engine/ParcNative/native_media_controls.mm` and
`native_appkit_page.mm`; [admission policy](media12-producer-contract.md) defines
when the application may create a new Mini Player episode.

## Session notifications

Chromium `MediaSessionImpl` sends initial info, metadata, images, position and
actions when an observer subscribes. Later callbacks report changed snapshots,
not their cause. Mute, sink, visibility, PiP, artwork or website-declared capture
state can change them without creating a new media producer.

Parc re-reads synchronous current state when an asynchronous callback arrives.
This prevents applying stale values but cannot recover an inactive/active interval
coalesced before delivery. Observer registration and callback counts are therefore
not chronological evidence. The session belongs to WebContents and survives
primary-document replacement; Parc retires/revalidates document-bound episodes
at that boundary.

Active, suspended, inactive and ducking are distinct from playback state and
controllability. A paused player can remain suspended and controllable; ducking
is not a fresh player. Newly admitted playback uses the stricter policy, while an
existing held episode or cast follows its own lifetime rules.

## Real input capture versus website declarations

`MediaStreamCaptureIndicator` tracks actual started streams. Per-WebContents,
per-device counts notify synchronously on zero crossings. Overlapping streams do
not each emit a new start, and stopping one does not emit false while another
remains. Aggregate queries include inner WebContents, while callbacks identify
the actual changed contents. Initial state must be queried separately and the
observer must unregister before destruction.

Website MediaSession microphone/camera state and toggle handlers are declarations.
They neither prove that a device stream is running nor guarantee that actual
capture exposes a usable toggle. A frame's declared values can outlive an
individual stream and must not substitute for current-document capture state.

## Existing Parc capture boundary

`NativePageState` owns the capture-indicator subscription and follows the callback's
outer-WebContents chain. It posts a non-nestable invalidation with weak owner and
state-lifetime checks. A later refresh reads current state after Chromium's
mutation stack unwinds; it carries no captured start/stop payload or sequence.
Multiple notifications can observe the same final value.

`PCNativeCaptureState` binds original WebContents, primary document and parent.
Its Stop callbacks revalidate those identities. Passive flags answer current
capture, not when a producer began. Adding another observer merely to read the
same current state does not make chronology more precise.

## Ordering fence and limits

The current re-admission path captures a one-shot original-document presentation
lease before the app mutation and consumes it after successful removal. The
source's suppression revision prevents an intervening dismiss/evict from being
undone by queued work. Generic metadata or initial observer replay cannot consume
that lease. No inferred trigger from callback timing is required.

Any future event-based producer needs source-assigned sequence/document identity,
relevant old/new fields and a dismissal fence captured in the same ordering
domain. A high-water counter read at delivery is insufficient: an unrelated mute
change can advance it while an old eligibility event remains queued. Info and
actions are rebuilt separately and cannot be treated as an atomic joint change.

## Media player content-type adaptation

`MediaSessionInfo.audio_video_states` is an optional list over the session's
routed player inventory. It can contain audio-only, video-only or audio-video
entries, omit players in other frames, and be empty for a service without players.
Normal and one-shot players can contribute; ambient players are not a complete
part of this inventory.

Parc playback admission requires an audio-only/audio-video entry in addition to
active controllable state and an unmuted source. Null, empty, video-only and
unknown entries do not satisfy that branch. The separate microphone/camera
capability path is not suppressed merely because playback has no audio entry.
This describes the implemented boundary, not all sound produced by a page.

## Validation

Focused inert checks cover stale documents, one-shot fence consumption,
dismissal/eviction ordering, privacy domains and metadata-only changes.
