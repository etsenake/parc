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
symbol, `PlaybackControlForeground`) with `HoverableButtonStyle` (radius 5,
GrayA4 hover, GrayA5 pressed, `alwaysSelected` while the list is open, as the
Connected tint it with the Space's contrasting hue (`maxContrastColor` on light
button; the tooltip and label read "Playing on <device>". All row buttons now

## Cast

On Chrome-identity pages the same last button is Cast, with Chromium's Cast
glyph (`media_router_idle`, drawn at AirPlay's 13-point ink width) and
AirPlay's style and states: held selected while the chooser is open, the
connecting pulse, the Space-contrast tint, "Connecting to <device>" and
"Casting to <device>". It shows once a receiver answers the session's remote
playback source and the media can be cast: one player, Remote Playback not
disabled, known codecs, longer than 15 seconds, not encrypted (FairPlay and
Widevine can't be cast) and no default presentation request. Pressing it opens Chromium's global
media controls dialog for that page's session at the button, the dialog a
page's Remote Playback prompt opens, even for a background tab. Choosing a
device starts Chromium's media session remote playback, as Chrome's own
media controls do (`CreateCastDialogControllerForSession`, then
`RequestMediaRemoting`), so the cast takes the requested-remoting path
that keeps it alive across navigation, the back/forward cache, background
tabs and frozen pages. While it casts, the dialog offers Stop casting. The
state follows the router's remote playback route for that tab and the
player's `remote_playback_started`: Connecting until the receiver plays,
Connected after (or at once when Chromium mirrors the tab instead), and back to available when the TV or the user ends it
(`native_gmc_presentation.mm`).

## Volume adaptation


## Reference and adaptations


- `MediaControlsDataStore.MediaControlDataSource` contains original content, sidebar item/container, WebContentFrame, and browser IDs. ControllerInput owns a window ID/incognito flag. MiniPlayer state separately carries the original source, title/icon, volume/mute, media type, audio/video transport capabilities, and recording camera/microphone capabilities.
- Recovered view state includes mini-player height/opacity/y/width offsets, expanded state, immediate/debounced hover-off publishers, volume-expanded state, marquee title preference, color palette, and a state-change animation. This establishes the shelf/expanded/control structure, not exact metrics or timing.


### MEDIA12 investigation and interim correction

New ordinary playback episodes require a controllable active session, an
unmuted original tab, and an audio-only or audio-video entry in Chromium's
routed `audio_video_states` player inventory. Null, empty, unknown and
video-only inventories do not qualify; a mixed inventory qualifies when any
content type: Chromium may omit audio in another frame or ambient players,
and may include one-shot players. It does not identify a producer event.
The existing toggle-capability admission remains an interim compatibility
exception; a site declaring an action is not evidence of actual recording.
The new gate applies only when admitting a new episode and does not change existing
episode retention, dismissal, action validation or source leases on mute,
pause or transfer. Exact recording and producer policies remain open; see
[producer contract](media12-producer-contract.md) and
[Chromium boundaries](media12-chromium-events.md).

association, adds a control and enforces the store's maximum; the separately
recovered close path removes both the control and its source-ID association.
Parc maintains at most five admitted episodes per privacy domain and evicts
the oldest when a new episode arrives. Regular pages share a pool; each exact
off-the-record Profile has a separate pool, so private activity cannot evict a
visible regular or unrelated private row. This is an intentional isolation
Admission order is preserved across hosts; arrivals coalesced into one app
refresh use the order in which Parc enumerates the live sources. Source leases
are checked before explicit admission; ordinary snapshot reads cannot admit a
row. Closing and retiring sources are withdrawn before new admissions, while
temporary transfers retain their episode. Native eligibility and retirement
are rechecked before a new source can evict another.
That establishes store operations, not the producer event that re-admits a
closed control. The visible-controls publisher maps datastore state through
entry; the predicate also distinguishes recorded PiP transition states. A
source byte with the host state's byte. The field layout indicates the source
browser-context type and host incognito flag, but the complete host policy and
producer trigger remain open. Parc now fans the retained original sources out
to registered regular hosts, or private hosts with the same actual OTR Profile,
while retaining the source document and owner for every action. This is an adaptation of that
These observations do not establish that a

`dismissMediaControls` actions. Its ordinary audio/video branch at
`active` case, alongside additional source conditions. The exact change
triggers and their Chromium correspondence remain open. Its separate
recording branch consults the `media-tray-for-recording-tabs-enabled` flag at
user close/minimize, and failed close/request outcomes. Chromium's existing
`MediaPictureInPictureChanged(bool)` cannot by itself distinguish those
transitions. No PiP Boolean has been substituted for that history.
The recovered history filter, observed transition boundaries and remaining
failure and removal questions are detailed in [PiP history](media12-pip-history-contract.md).
The pinned Chromium session and capture notifications, their document and
ordering limits, and a possible producer-side event fence are documented in
[Chromium event boundaries](media12-chromium-events.md). Neither document
The source predicate, its action paths and the activation sweep's negative
re-admission result are recorded in [producer investigation](media12-producer-contract.md).

Loss of a native window owner no longer resets a dismissed, still-eligible
session. Transfer or other temporary host unavailability therefore cannot by
itself make that episode visible again. Capacity eviction uses the same
suppression. Re-admission requires either session-eligibility loss /
primary-document replacement, or a consumed presentation-set producer
(Separate, ItemSelection mirrors, tab-fullscreen enter, Space switch, or
non-split Peek Expand) through the shared lease/fence path. Ordinary Mojo
callbacks and chrome refreshes still must not re-admit. See

## Validation

The private native bridge and modified MediaSession implementation are checked with the pinned Chromium compilation commands, using source overlays outside the active build tree. The complete Swift application is typechecked with the real bridge header. No browser functional test, playback experiment, installed-profile mutation, or PiP retest is part of this batch.

## Motion and hover — MEDIA14

The `MiniPlayerView` volume transition uses its stored animation in a transaction
main-queue Combine debounce with integer-literal stride 2 at
sets expanded immediately on hover-in, and has a separate immediate hover-off
`MiniPlayerFeature.State.isVolumeExpanded` into that field. The same stored
spring transaction animates the state change. This is an explicit slider
opacity, not a claim about other implicit SwiftUI transitions.

Parc applies a physically parameterized Core Animation spring to the deck's
changed deck layout and opacity and its sidebar list viewport, with the same
response and damping; this is an adaptation, not proof of identical SwiftUI
rendering. Only properties with changed model targets receive media animations.
Reversal starts from presentation values; moving the deck between windows,
teardown or turning on Reduce Motion settles precisely the layers it owns.
The slider stays attached for its recovered opacity fade while the collapsed
control immediately refuses pointer and keyboard input and leaves the AX tree.
Its percentage label follows the fade as an AppKit adaptation; focus moves to
the volume button or row if the focused slider becomes unavailable.
Hover expansion is immediate for one player and for the stacked shelf; collapse
after leaving waits two seconds and is cancelled by re-entry or teardown. The
volume slider is the in-card 33-point drawer, shown while the volume control or
slider is hovered or pinned by click, not a detached menu. Retaining a focused row
is an accessibility adaptation: when the deadline expires with focus inside,
the pending collapse is reconsidered on the owning window's next update after
focus leaves. AppKit [documents window updates](https://developer.apple.com/documentation/appkit/nswindow/update())
on event-loop passes. Dismissal below two rows clears the pending and expanded
`performFeedbackPattern:performanceTime:` reference in the Mini Player region
or in its direct/two-hop callees. This does not exclude indirect or system-owned
feedback; no Mini Player-specific haptic is invented. These source findings do
not establish live visual timing or tactile acceptance.

The off-screen inert deck check uses stand-in media objects and verifies stacked
card geometry/opacity animation, slider fade, collapsed focus/AX/hit-test
gates, capability loss/restoration, focus-preserving collapse, deferred hover-off,
dismissal/re-admission, and animation settlement on a window transfer. It does not exercise a
browser, media playback, live keyboard navigation, or haptic hardware.
