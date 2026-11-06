# Mini Player producer re-admission investigation

This is a focused evidence handoff for MEDIA12, not a completed parity claim.
`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The pinned Chromium checkout used below is commit
`d0c02bfad08ec92a6ffcf989e53cd995e6381a4c` (156.0.8078.48).

## Established producer and store boundaries

  creates an entry and applies the five-entry limit. Close removes both the
  establishes when a later producer event occurs. See `media-mini-player.md`.
  a `WebContentFeature.Action` effect. The ordinary branch reads the
  `WebContentState.mediaSessionState` status, in addition to source predicates;
  its recording branch invokes the separate recording feature flag. The
  field is not a self-sufficient eligibility or trigger rule.
- Its recording predicate calls `ADKClient.isRecording` for the frame at
  is `isRecording(WebContentFrameIdentifier) -> Bool`, and each stored closure
  occupies two words, placing this entry at `+0x400`. The live factory
  contains index 1. `ADKModels.TabTrait` identifies index 1 as
  `mediaRecording`, distinct from index 2 `tabCapturing` and index 11
  `desktopCapturing`. The retained Core `0x68e8a88–0x68e8b30` distinguishes
  those capture traits. A site-declared action capability is not that trait;
  mapping a real Chromium capture indicator to it is an adaptation.
  Reflected `FeatureFlagMetadata` contains `id`, `default`, and
  `requiresRestart`; the Boolean metadata construction for
  `media-tray-for-recording-tabs-enabled` stores two zero bytes at
  `requiresRestart` false. A remote value or override can change the effective
  value; this does not establish a particular running installation's value.
  no effect or a dismiss action according to input bit 24. With the flag
  true, the recording branch selects result 0 or 2 according to the
  per-identifier flag propagated as input bit 0, as detailed below.
- The other ordinary-path source call at `+0x3f0` is reflected
  `getMediaContentType(frame)` (field 63). The live factory installs
  Index 2 wins and produces `audioVideo` (2), else index 1 produces
  `audioOnly` (1); no supported index or missing WebContent yields optional
  none (4). The evaluator requires a non-none type and ultimately accepts
  only 1 or 2; it then requires the session status byte to be active.
- The source `getWebContents` call at `+0x70` and WebContentChromium witness
  `+0x78` return the original `WebContentFeatures`. Its vtable slot `+0x4a8`
  fields `_mediaSessionState`, `_isMuted`, `_isAudible`. The descriptor's
  six-accessor group also places this getter at reflected field 17
  `_isMuted`. The evaluator excludes a muted source on the ordinary branch.
  The meaning of every incoming packed flag remains open.
  `WindowData+WindowContentPresentation.swift`, invokes a supplied closure at
  possible `WebContentState`, before appending an identifier and flag at
  presentation-related route, not a complete semantic classification of
  the set or the producer events.
- A concrete independent re-evaluation route is
  `WindowAction.LifecycleAction.applicationDidBecomeActive` (reflected tag
  enumerates its identifiers and appends each with flag 1 at
  traversal is hash-backed; this evidence does not establish chronological
  yields result 2 both in the flag-enabled recording branch and in the
  otherwise eligible ordinary branch. Thus the activation sweep yields no
  effect or dismissal, depending on input bit 24; it cannot present or
  re-admit. The separate window reducer
  14; reflected case order identifies it as `presentPipForOccludedWindow`.
  Neither entry proves that a media-session callback itself causes evaluation.
  the 16-byte state to `WebContentState` field-offset slot `+0x34` and joins
  reducer cleanup. The reflected `ADK.MediaSessionState` fields are status,
  next/previous capability, camera/microphone toggle capability, camera and
  microphone state, and volume. A write does **not** itself establish a call
  to the evaluator or prove that each field change re-admits a removed row.

## Presentation mutations that can produce admission

mutation to a WindowContents snapshot and compares original and mutated
other additions depend on modal and focused-content resolution. The adaptive
and flag 1. For flag 0, an extant original WindowContent and WebContentState
may produce `presentMediaControls`. Its ordinary branch requires audio-only
or audio-video, active status, no recording trait and unmuted WebContentFeatures;
the default-off recording flag excludes recording sources from that branch.
Additional original ownership and dispatch gates apply.

in `WindowData+ItemSelection.swift`, resolves a WindowContent at
continuation. A successful replacement can therefore send a still-owned
outgoing split content through that producer path. Separate follows
focus it preserves that pane and removes other displayed contents; otherwise
it removes the supplied set. Retained source evidence is in
`work/split-family-operations/EVIDENCE.md` and `work/split-pane-controls/EVIDENCE.md`.

intercepts `WebContentFeature.Action.presentMediaControls` tag 12, resolves
the source association when absent. The `google-meet-auto-picture-in-picture-enabled`
and its source predicate holds. That feature flag's Boolean fallback is false.
host `meet.google.com`, the `UserDefaultsClient.boolForSetting` value for
`autoPipGloballyDisabled` must be false, and the Automatic Picture-in-Picture
site setting (type 29) must not be blocked (value 2); a missing setting object
`UserDefaultsClient`; the setting's reflected case is 125. Remote flags and
site settings remain authoritative. This does not establish Parc PiP behavior. The
nested frame-action handler does not intercept `onUpdateMediaSessionState`
tag 29. No generic media callback or every visibility change is established
as a producer.

A Parc implementation must bind the outgoing source and document before the
mutation, observe actual removal from its applicable presentation set,
preserve accepted event order and revalidate source ownership and current
eligibility. Same-content selection, focus within an unchanged split,
transfer/retirement and host refresh are not substitutes. Modal and Peek
equivalence and the Chromium content-type/recording correspondence remain
adaptations or open questions.

completion and preview highlighting do not call it; the relevant trigger is
the committed presentation-set removal, not the input or refresh itself.
The presentation set starts with every split ID; modal selection resolves
the `.window` source or the focused split's mapped sidebar item through
Peek dismissal initiates actual modal closure and optional reopen state
Exact nested modal membership and any separate live modal-exit producer remain
open.

The complete list of state changes/events which schedule evaluation after close
or eviction remains unproven. In particular, the indexed calls and a field
write do not prove that every media-session update, UI refresh, or unrelated
window-content mutation produces a new `presentMediaControls` action. They
also do not prove that only an inactive-to-active transition does so. The
and the connection from tag 29 to those paths require resolution before
claiming exact re-admission.

## Chromium mapping constraints

Pinned `content/browser/media/session/media_session_impl.cc:1232–1245`
sends an initial info, metadata, images, position and actions snapshot when
an observer is added. Its info notifications at `1580–1600` compare the whole
current `MediaSessionInfo` before sending; action notifications compare the
whole action set at `1990–1997`. Info rebuilding is also called for mute,
PiP and other changes. Thus neither observer subscription nor every info or
title and display refreshes likewise have no established re-admission link.

For a future implementation, preserve the original `WebContents`, current
primary document, actual Profile/OTR Profile and current source owner. Capture
the accepted producer event and its monotonic source order at the producer
boundary, before asynchronous/coalesced UI refresh; revalidate the current
source lease and current synchronous eligibility before acting. Discard stale
events from a replacement document or retired source. A callback's delivery
time alone does not prove that its underlying change followed dismissal:
queued pre-dismissal notifications require a producer-side ordering or fence
that makes this distinction. Reading the latest synchronous state protects
against applying stale values but does not recover a missed intermediate
transition or establish its chronology. Only a new, explicitly
qualified event after close/eviction may release that source's suppression;
ordinary reads, initial observer replay and host availability must not do so.
Keep arrival ordering independent of the order in which hosts enumerate
sources; enforce each privacy domain's pool independently, and issue a new
episode identity on re-admission. These are Parc safety and chronology

The existing implementation suppresses a closed or evicted still-eligible
episode until ineligibility or primary-document replacement. That is a
replace it with unconditional re-admission on `Changed()`, an initial Mojo
callback, or a coalesced shelf refresh. A transition-only event mapping is
also an adaptation until the original producer triggers are established.


Helper-first `arcidx.py callers` / `arcfn.py` classification of every direct

| Caller | Source file / role | Parc producer |
|---|---|---|

Space switch is a Parc presentation-set replacement that uses the same lease
path; it is an explicit adaptation of leaving the prior Space's displayed IDs,

Nested modal: opening or dismissing Peek alone does not remove the parent
split ID (matches prior evidence). Non-split Expand replaces the set and is
wired. In-split focus changes do not mutate the set and must not fire.

## Split separation producer increment

bounded producer, not evidence that every refresh or modal change admits.

Parc captures one-shot leases for original attached, rendered split pages
before Separate, then consumes only removed pages after a successful commit
and the expected selection capture, before the explicit render. Source owner,
profile, document and a dismissal/eviction revision must still match; closing,
retirement, transfer, an intervening dismissal or eviction, or replacement
document rejects the event. Synchronous current eligibility and the existing
admission gate remain authoritative. A dismissed, evicted or never-admitted
eligible source receives a new episode ID; an existing admission keeps its ID
and order. The capture is deliberately limited to displayed splits without Peek, Library
or fullscreen; generic render changes do not produce this event. Privacy-domain
capacity and actions retain their existing checks. The engine overlay must be
applied and packaged by the dedicated engine owner; no browser runtime or
visual acceptance is claimed.

## Selection / fullscreen / Expand producer increment (October 31)

Parc now shares `presentationSetMediaRemoval` across ItemSelection mirrors,
tab-fullscreen enter, Space switch and non-split Peek Expand. Ordinary Mojo
`Changed()`, chrome ticks, host availability and in-split focus still must not
re-admit; dismissal/eviction suppression clears only on ineligibility,
primary-document replacement, or a consumed presentation-set producer.
PiP-history filter stays documented without a Chromium Boolean substitute.
No browser functional test or live media experiment was run.
