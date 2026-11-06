# MEDIA12: PiP history and Mini Player filter

This is a source investigation and proposed passive interface, not a change to
The current Chromium source is the pinned local `work/engine-source/chromium/src`;

## Recovered store and filter

`arctypes.py fields` identifies `MediaControlsData.pipSessions` as a dictionary
keyed by `MediaContentID`, with `PIPSessionHistory.recentStates` an array of
state; missing key or empty array returns no state. Windows-data continuations
which creates an empty keyed history if necessary and appends the supplied
when the prior count is at least 10, retaining at most the latest 10 states
append `active` and `hidden` respectively, but their initiating actions are not
media control, not demonstrably the PiP history entry. The outer dispatch
identifies `WindowContentAction.onDidTeardownBlueprint` (case 0) as one removal
producer. With no matching current PiP source it schedules removal with no
state; when a source matches, it supplies `removed`. The async closure first
removes the control and then appends that state if supplied. This does not

| Last state | Visible filter |
| --- | --- |
| Missing or empty history | admit |
| `pendingActive(presentationSourceRect: CGRect?)`, with or without rect | reject |
| `active` | reject |
| `pendingHidden` | reject |
| `hidden` | admit |
| `pendingRemoved`, `removed` | reject |
| `userRequestedClose`, `userRequestedMinimize`, `userClosed` | reject |
| `closeFailed` | reject |
| `requestFailed` | admit |

The implementation's spare representation holds the payload-bearing
`pendingActive` in a separate case; for the remaining cases the stringifier
maps zero to `active`, 1 to `pendingHidden`, 2 to `hidden`, 3 to
`pendingRemoved`, 4 to `removed`, 5 to `userRequestedClose`, 6 to
`userRequestedMinimize`, 7 to `userClosed`, 8 to `closeFailed`, and the
remaining case to `requestFailed`. The predicate admits its no-history marker
and representation 2, rejects the other numbered representations including 8,
and admits the final remaining state. The no-history case is distinct from
`pendingActive` with no source rectangle.

The descriptions identify `pendingActive` as requested without an available
view, `active` as currently playing in the PiP window, `pendingHidden` as an
exit request before `shouldHidePIP`, and `hidden` as formerly focused PiP
contents following `pendingHidden`. `pendingRemoved` describes an exit likely
from closing a tab or window; `removed` is removal other than user-close.
User-requested close and minimize await `shouldHidePIP`; `userClosed` follows
completion of user-requested close. `closeFailed` and `requestFailed` describe
`pendingRemoved` becomes `removed`; `userRequestedClose` becomes `userClosed`
unless a current-event modifier branch selects `hidden`; all other known
cases, including missing history and `userRequestedMinimize`, produce `hidden`.
call the control-removal continuation. The outer dispatch is `WebContentFeature.Action.webContentFrameAction` and
`WebContentFrameAction.onPiPAction`; the inner branch checks group 5 and
`ADKClient.WebContentFrame : ADK.WebContentUIDelegate` witness table at
as `onPiPAction` case 28. The Objective-C WebContentChromium callbacks for
call witness offsets `0xf8`, `0x108`, `0x110` and `0x118`, respectively.
The witness table resolves these to the above constructors. Thus values 0–3
are destroyed, show, hide and close, respectively; a missing weak delegate
emits no action. The two values in the mapped-state append route are hide
independently confirms four group-5 values. The modifier
meaning is also open. These descriptions do **not**
recover all transition producers, sequencing or history removal. In particular,
`hidden` is not a synonym for arbitrary window closure, and the filter is not
proof of what re-admits a dismissed Mini Player control. Do not replace this
policy with a PiP Boolean or claim re-admission parity from these branches.

`MediaControlDataSource` retains `contentID`, sidebar container and item IDs,
web-content frame ID and browser ID. Those fields establish association, not the
lifetime or retention semantics of the backing source document. No recovered
producer path here establishes whether history is explicitly removed on source
retirement, navigation or another event; that remains open.

## Chromium and Parc event boundaries

and `exitPictureInPicture`, taking a `WebContentFrameIdentifier` and returning
WebContent returns false. A present WebContent is called through
`ADK.WebContent` witness slots `0x130` and `0x138`. WebContentChromium
out-parameter and returns its synchronous Bool. False request constructs
failure share false; neither call establishes eventual window presentation or
does not equate it to a Chromium DOM frame or prove its navigation lifetime.

Chromium's `MediaSessionImpl::EnterPictureInPicture()` and
`ExitPictureInPicture()` return void. The later video service request result
and the manager's controller-existence Boolean are distinct stages, not the
same source-bound synchronous command result. A passive seam must report these

* `PictureInPictureServiceImpl::StartSession` constructs a pending request for
  a particular `RenderFrameHost` and wraps its callback with a default null
  result. `StartSessionInternal` returns early for an inactive frame; otherwise
  it obtains `VideoPictureInPictureWindowControllerImpl::StartSession` result
  before returning the Mojo callback. Immersive confirmation rejection,
  inactive/non-fullscreen paths and destruction or invalidation can also finish
  without reaching that result. Blink-side rejection before the browser service
  is another boundary. An observer of only `StartSessionInternal` cannot claim
  all request failures. Even a browser-side failed request is an adaptation,
* The video controller calls `Show` after a successful request, sets the video
  bit, and uses `Close`, `OnWindowDestroyed`, `CloseInternal` and
  `OnServiceDeleted` for distinct shutdown paths. The manager closes an existing
  controller when another source takes the PiP slot. Its UI exit method exposes
  close/pause, return/focus and close-only intentions, but `CloseInternal` can
  The native overlay's `Action` has close, return, minimize and system-close
  distinctions before making terminal calls that can synchronously destroy the
  overlay. No use of a raw overlay/controller pointer after those calls is safe.
* Document PiP is a separate controller owned by the opener WebContents. It
  observes a child and the opener, sets the document bit on `Show`, clears it
  on close, and closes on opener primary-page change. Child destruction,
  navigation and opener destruction can trigger closure. `should_pause_video`
  classification. The video presenter therefore cannot cover document PiP.
* `WebContentsImpl::SetHasPictureInPictureVideo` and
  `SetHasPictureInPictureDocument` independently call the same
  `MediaPictureInPictureChanged(bool)` observer. The Boolean does not identify
  kind, request failure, close reason or focus-transfer state; overlapping kinds
  also mean the latest Boolean is not a reliable combined state. Reading the
  distinct current bits helps identify present kinds but cannot reconstruct
  missed transitions or reasons.
* Parc `MediaState` is WebContents-owned, clears its episode on
  `PrimaryPageChanged`, and removes its registry entry at destruction. A media
  snapshot captures weak WebContents, primary `WeakDocumentPtr`, Profile and
  browser ownership. PiP requests may originate in a subframe: bind any event
  to the originating `RenderFrameHost`'s weak document as well as the source
  WebContents and a generation/episode token. A primary-document replacement,
  source destruction, or originating document invalidation retires the event;
  never hold a document, Profile, browser or overlay alive to keep history.
  Do not allow a late callback from a prior request to affect the new document,
  a newly admitted episode or another profile. This is a Parc safety contract,

## Candidate observations by state

The entries below are proposed observations, **not** established one-to-one
lifetime contract; unknown is a separate state from no history.

| --- | --- | --- |
| `pendingActive` | Video `PictureInPictureServiceImpl::StartSession` entry for the originating frame. | Blink can reject earlier; immersive flows can be cancelled or invalidated. Document PiP has a separate request path. |
| `userRequestedClose`, `userRequestedMinimize` | Native video overlay `Action` immediately before its respective terminal manager call; system close is separate. | Other video presenters and document PiP need separate hooks; no guarantee of eventual completion. |
| `closeFailed` | No matching Chromium result identified. | `Close` returns void and manager's false means no controller, not established ADK failure. |
| `requestFailed` | Video `StartSessionInternal` unsuccessful `PictureInPictureResult` at the original frame. | Inactive-frame, immersive, default-callback, Blink-side and document request paths need separately attributed outcomes; do not treat cancellation as failure. |

## Proposed passive seam and next action

The narrow useful seam is a typed, UI-sequence observation attached to the
**original source**, carrying PiP kind, originating weak document and monotonic
request/session identity, and an event such as `requestStarted`,
`requestResult(success|failure|cancelled)`, `shown`, `uiIntent(close|return|minimize|systemClose)`, `replaced`, `closed(reasonKnown|unknown)`, or
`sourceRetired`. The sink must never start, close, pause, focus, or alter an
existing PiP operation; callbacks must tolerate synchronous destruction and
must be ordered/invalidated by identity. UI intent occurs before the existing
terminal call, while completion should be emitted only after a verified matching
controller/session outcome. Distinguish unknown/cancelled from failure and do
not infer `hidden` from generic closure. Request identity is necessary when
one video session replaces another in the same WebContents without an
intermediate closed window.

Video coverage requires hooks at the service request and all its early/default
completion paths, the controller's successful show/shutdown and manager's
replacement path, plus the native presenter action before its terminal call.
Document coverage needs its own controller and child lifecycle hooks; the media
Boolean remains useful only as a coarse invalidation. Determine a dependency-
legal common observer/bridge before implementing hooks; content cannot depend
upward on Parc's Chrome/CEF target. A minimal bounded adaptation can expose only
explicitly observed native video events, retaining unknown outcomes as unknown;
transition equivalence.

Next: identify the `pipSessions` key deletion path and lifetime.
Use retained indexes and helpers
first. Both shared decompilation slots were occupied or retained at the
2026-10-29 21:29 UTC status snapshot, so no decompilation was started; revisit
only after a meaningful handoff and nonblocking acquisition. The MEDIA12 owner
can assess a passive typed Chromium seam with the identified unknowns; any
overlay needs its own review and must preserve PiP behavior and source lifetime. No functional browser or
PiP test was run under the current prohibition.
