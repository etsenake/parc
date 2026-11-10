# Mini Player

The sidebar Mini Player controls original live Chromium media sessions from eligible Parc windows. It does not open a URL, create a second page, or replace the renderer. The hover chrome’s Open Picture in Picture control calls the existing MediaSession user-enter path; PiP window chrome remains the accepted PiP work and is not reopened here.

## Experience and ownership

A new ordinary playback row requires a controllable active media session and the source conditions described below. An admitted controllable session can remain visible while suspended; the existing compatibility path also accepts sessions exposing Chromium camera/microphone actions. Rows show the original page title and favicon, actual play/pause state, supported previous/next actions, tab mute, a volume drawer, and supported camera/microphone controls. Unsupported actions are disabled or absent. The title and unoccupied row area return to the exact existing page; Peek returns to its original parent and child. Playback actions do not select the source page.

The shelf supports five simultaneous rows, keeps stable row order across metadata updates, expands on hover, and provides an explicit Show All/Collapse button for keyboard and accessibility access. Individual native buttons, the native slider, Return on a focused row, and Space for play/pause are keyboard accessible. Close Mini Player dismisses the exact media-control episode while playback and the source page continue. The dismissal remains attached to the original native page through profile selection or window transfer; a real inactive interval or replacement document admits a new episode. Closing a browser window releases its presentation.

Snapshots carry the original WebContents, primary document, actual Profile (including its original off-the-record Profile), BrowserWindowInterface, and opaque media-episode ID. A weak presenting-window lease is separate from that source. An action revalidates both, current capabilities, and the matching context. Page retirement, transfer, profile removal, replacement documents, renderer failure, closing windows, a non-key/inactive host, an attached sheet, or a native security reservation rejects execution. No title or domain grants eligibility. A regular host receives regular live rows from other physical windows; a private host receives only rows from its exact original off-the-record Profile. Selection of another profile does not retarget a row. Returning to the source validates the presenting host and original source, restores the original window when minimized, and revalidates the episode after activation before selecting it.

MediaSessionObserver notifications trigger the existing native-page update path. Each snapshot reads synchronous current MediaSession information; stale queued observer payloads are not replayed as current state. Commands call native Resume/Suspend, PreviousTrack/NextTrack, ToggleMicrophone/ToggleCamera, and WebContents tab mute. Native Hide only removes the control episode. The source renderer and its media objects stay intact.

## AirPlay

On Safari-identity pages whose video plays through the native HLS route
(FairPlay HLS included), the row's transport ends with an AirPlay button
(`airplayvideo`) once AirPlay devices are nearby
([NATIVE_HLS.md](../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md#airplay)).
Pressing it opens the system's AirPlay route list at the button: the same list
Safari shows, since only Apple's AVKit services may list or choose AirPlay
devices. The button uses a 24 × 24-point plate, 14-point symbol, 5-point corners,
GrayA4 hover and GrayA5 press, retaining selected appearance while its list is
open. Connecting pulses opacity 0.4–1 over 0.75 seconds unless Reduce Motion is
on. Connecting/connected states use the Space's contrasting tint and expose the
device name in their label and tooltip.

## Cast

On Chrome-identity pages the same last button is Cast, with Chromium's Cast
glyph (`media_router_idle`, drawn at AirPlay's 13-point ink width) and
AirPlay's style and states: held selected while the chooser is open, the
connecting pulse, the Space-contrast tint, "Connecting to <device>" and
"Casting to <device>".

A page with a default presentation request, as Cast SDK sites such as
YouTube set, casts that presentation, as Chrome's media controls and toolbar
do (`CreateWithDefaultMediaSource`), so the site's own receiver app plays it.
The button shows once a receiver answers one of the request's presentation
URLs. Choosing a device starts the presentation, and the page receives its
connection (`OnPresentationResponse`). The state follows the router's route:
Connecting while a local route for one of those URLs launches (the page only
learns its route once it connects, so a second tab of the same site shows
Connecting for that moment too), then Casting while the route the page started
lives, and back to available when the TV, the site or Stop casting ends it.
While it casts, the dialog shows the page's Cast item with Stop casting.

Any other page casts its media session's remote playback source. The button
shows once a receiver answers that source and the media can be cast: one
player, Remote Playback not disabled, known codecs, longer than 15 seconds,
not encrypted (FairPlay and Widevine can't be cast). Pressing it opens
Chromium's global media controls dialog for that page's session at the
button, the dialog a page's Remote Playback prompt opens, even for a
background tab. Choosing a device starts Chromium's media session remote
playback, as Chrome's own media controls do
(`CreateCastDialogControllerForSession`, then `RequestMediaRemoting`), so the
cast takes the requested-remoting path that keeps it alive across navigation,
the back/forward cache, background tabs and frozen pages. Remoting is
requested from the session's one player at the pick, as Chrome does, so a
page that enters the back/forward cache while the cast launches casts from
there; no other page's video is asked. A launch that fails takes the request
back through the tab's remoting sources, which reach a cached page too
(`CastRemotingConnector::ParcDropRemotingRequests`), so a later tab cast isn't
taken by that video; a launch whose page is gone ends. While it casts, the
dialog offers Stop casting. The state follows the router's remote playback
route for that tab and the player's `remote_playback_started`: Connecting
until the receiver plays, Connected after (tab mirroring, where Chromium falls
back to it, once its route connects), and back to available when the TV or
the user ends it. `MediaNotificationService::ParcCastRouteForWebContents`
picks the route for both kinds of page (`native_gmc_presentation.mm`).

A row already shown stays while its tab's cast connects or casts, even after
the page drops or ends its media session, as sites do once their receiver
plays: it keeps the page's title and icon, shows Connecting or Casting to
<device>, and on a page with a default presentation its Cast button opens the
dialog with the page's Cast item and Stop casting. A cast never
adds a row, and the row goes once the cast ends with no session left
(`MediaEpisodeHeld`). The row also stays when the tab navigates while its
cast carries on from the cached page (`KeepMediaEpisodeAcrossPageChange`),
a Safari-identity page included; the new page's own player never reports that
route, so it shows the route's state. When neither a session nor a
presentation is left, the page presents Safari, or the cast plays from a page
the tab has left, the dialog can't stop it, so the Cast button opens a menu
whose first item, Stop casting to <device>, ends the tab's route; when the
current page has media of its own, Cast... below it opens the dialog.

## Volume adaptation

Parc uses a separate `MediaSessionImpl` user volume multiplier, clamped to 0...1 with non-finite input refused, and composes it with Chromium's existing ducking multiplier. Existing player observer delivery and new-player initialization use the composed value. The default factor is 1, preserving normal upstream behavior; a replacement primary document resets the factor. The slider is exposed only when the session has actual normal player observers; a metadata-only controllable session cannot advertise it. Ordinary MediaSession-controlled media players receive genuine renderer volume changes. Uncontrollable WebAudio-only/independent output paths are not represented as a supported volume row; this is not a claim that every output stream has a new mixer.

## Episode admission and dismissal

New ordinary playback requires a controllable active session, an unmuted original
tab and an audio-only or audio-video entry in Chromium's routed player inventory.
Null/empty/unknown/video-only inventories do not qualify; any audio member in a
mixed inventory does. Camera/microphone action capability remains a compatibility
admission path; declaring an action does not by itself prove active recording.
The gate applies to new episodes, not existing retention on mute/pause/transfer.

At most five episodes are admitted per privacy domain. Regular pages share a
pool; each exact off-the-record Profile has its own, so private activity cannot
evict regular or unrelated private rows. Oldest admission is evicted first;
metadata does not reorder it. Snapshot reads cannot admit a row. Closing or
retired sources are withdrawn before a new source may evict another.

Dismissal and eviction remain suppressed through temporary window unavailability.
Re-admission requires loss of eligibility, primary-document replacement or a
consumed presentation-set producer through the shared lease/fence path. Ordinary
Mojo updates and chrome refreshes do not suffice. See [producer contract](media12-producer-contract.md),
[Chromium events](media12-chromium-events.md) and [PiP state boundaries](media12-pip-history-contract.md).

## Motion and hover — MEDIA14

Deck geometry/opacity and volume use response 0.25/damping 0.9 springs only when
their targets change. Reversal starts at presentation values; transfer, teardown
and Reduce Motion settle owned layers. The 33-point volume drawer remains
attached for its fade, while collapsed controls immediately reject pointer,
keyboard and accessibility actions. Lost slider capability returns focus to its
volume button or row.

Hover expands immediately. Leaving waits two seconds to collapse; re-entry and
teardown cancel it. Focus inside the deck defers collapse until a later window
update after focus leaves. Dismissing below two rows clears pending expansion.
No Mini Player-specific haptic is added.

## Validation

Pinned native compilation and Swift checks cover bridge integration. Inert deck
checks cover layout, fade, focus/AX/input gating, hover delay, dismissal and
transfer settlement. They do not establish live playback, casting/AirPlay device
behavior, keyboard/VoiceOver or haptic acceptance. Capability guards remain
truthful: WebAudio-only output is not a supported volume slider and encrypted
media is not cast as an unprotected remote source.
