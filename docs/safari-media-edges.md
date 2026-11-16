# Safari-mode media behavior and boundaries

Safari identity changes the page-facing media decisions above Parc's playback
backends. Native HLS uses AVPlayer; FairPlay Media Source uses native sample-buffer
renderers; ordinary clear playback normally uses Chromium's renderer. Source
owners and API details are in [FairPlay web surface](fairplay-safari-surface.md),
[identity](fairplay-identity.md) and
[native HLS](../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md).

Picture in picture is complete. This guide describes current behavior, concrete
limitations and explicit product decisions.

## Implemented behavior

| Area | Current source contract |
| --- | --- |
| Moving media | Same-origin document moves preserve the playing owner; visibility, mute, Now Playing, input and presentation follow the displayed element. Frame retirement transfers eligible loading rather than restarting playback. |
| Element loading | Muted-attribute/autoplay state, lazy/preload decisions, buffered readiness, seeking, key waits and rate-zero/end state follow the Safari-identity route. |
| Keys and renderer handoff | Late keys, replacement and detach are supported. The normal Chromium-to-FairPlay transition prerolls on the existing clock rather than restarting the page's media element. |
| Native HLS | Live/DVR timeline, start dates, track changes, key requests, clear data playlists, private asset policy and native error/readiness propagation are implemented. AirPlay changes the existing player's output context. |
| Casting | Connecting and short-played casts survive eligible background/cache transitions. Mini Player retains its admitted casting episode across navigation, keeps route state after its media session ends and offers Stop casting for the original route. |
| Audio | Ordinary playback and native HLS apply pitch policy; output-device selection/fallback and added supported tracks reach their renderers. Added clear audio tracks share the output's timeline and playback rate. The FairPlay Media Source pitch-control gap is described below. |
| Reverse playback | Plain files support silent negative rates inline and in background; time advances continuously while frames may drop. Native HLS retains AVPlayer's route. |
| Media Source | Buffer admission, ranges, duration, eviction, worker lifetime, track switching and managed-buffer event timing use actual parser/player state. |
| Transport streams | Multiple audio tracks, PMT-declared audio types, MPEG-1/2 video and SAMPLE-AES support are present. MPEG pixel aspect ratios feed the natural display dimensions. |
| Formats and recovery | Ogg, clear PCM, ALAC, AMR/H.263 and additional Dolby Vision parsing/capabilities are supported; compatibility-ID 2 carries SDR tagging. AV1 capability respects hardware under Safari identity. Native decoder flush recovery replays from a retained keyframe before resuming its clock. |

## Accepted behavior and scope

- Keep Chromium's useful behavior for HTTP servers without byte ranges.
- Spotify's Safari route remains the supported identity path without Widevine;
  its service-side lossless FLAC exclusion is retained.
- Keep useful Ogg behavior: ambisonic Opus, rejection of garbage after abort,
  incomplete/bad-checksum page handling and FLAC's header-derived final duration.
  Mixed Ogg/video capability queries remain unsupported.
- Keep Dolby Vision profiles 4/7 base-layer playback and long-lived cached cast
  restoration where Parc already provides it.
- The accepted non-perceptible differences in play-promise, end-of-stream idle
  arrival, extra timeupdate and removal/fullscreen scheduling remain, along with
  the `text/vtt` Media Source capability difference.
- Reverse playback has no special optimization for 4K files with 5–10-second
  keyframe gaps; it would be expensive, and such files are rare.
- FairPlay `cenc` encryption and an element disabling its own video track remain
  outside the earlier agreed media scope. Late-CDM attachment, audio-output
  selection and additional Dolby Vision support remain supported.
- Further 3GPP MIME answers, MPEG-4 Part 2 in 3GPP and raw `.amr`/`.awb` files
  stay unsupported: Safari identity applies only to sites that need FairPlay,
  and those streaming sites don't serve 3GPP. Preserve the H.263/AMR route.

## Casting ownership and controls

An already admitted Mini Player row survives a live cast; casting alone cannot
create a row. Remoting is requested from the media session's single player when
the receiver is picked. A successful launch retains its original active or cached
document; failed launches withdraw pending requests. See [Mini Player](media-mini-player.md).

A cached page's native pipeline and eligible URL/HLS readers can continue casting.
Its JavaScript stays frozen, as every browser freezes cached pages, so a Media
Source cast stops once it plays out its buffered range. Receiver controls do not
thaw the page or provide a reverse play command to its paused source pipeline. A source that is destroyed or evicted cannot keep
feeding that route. An active cast from a moved element remains with its starting
tab until it ends; closing that starting frame ends its presentation connection.

A requested paused video without a measured frame rate uses a 30-fps estimate
for receiver capability checks. A request waiting for a receiver remains pending
until a route/start failure, sink loss or remoting stop clears it. Chromium uses
Stop casting to return locally; it does not offer a synthetic “This Mac” device.
Tab mirroring is represented as Cast even on a Safari-identity page.

A second audible player joining the session before the device pick is handled
makes Chromium refuse the remoting request, and navigating in the instant before
Parc first sees a new route can make that earlier-page cast open the media
chooser instead of the direct Stop menu. Both stay, like the same-site Connecting
label in [Mini Player](media-mini-player.md#cast): the first matches Chrome and
would need a Chromium change, and the others last only a moment.

Availability observes the default presentation's sources and, on those pages,
Cast speakers that can take the tab's sound, so a home with only speakers still
gets the Mini Player's Cast button ([Mini Player](media-mini-player.md#cast)).

## Moved elements and renderer boundaries

An interrupted HLS response resumes through the destination frame only when a
strong ETag or Last-Modified identifies the resource. Without one, the partial
response fails rather than combining bytes from potentially different resources.

A document without a frame cannot create a new player. An existing player can
survive a move through such a document while its owning frame lives. If that
frame closes before the element reaches another framed document, its resources
are released and the frameless reload fails. A deferred `preload=none` first play
in a frameless document likewise reports an unsupported source.

Reverse playback, an in-progress resume or a CDM change can take the renderer's
restart path instead of the seamless handoff. Unsupported VP8/MP3 cannot enter
the FairPlay renderer; the [integration guide](../Engine/ParcNative/fairplay_chromium/README.md)
owns its codec boundary and missing pitch-control forwarding: pages cannot disable
pitch preservation on the FairPlay Media Source route. A disabled first clear-audio track is silenced after
decoding while its clock drives the mixed tracks, so it still consumes decode work.

## Native HLS alternatives and format boundaries

A Media Source element can switch to its next `<source>` for AirPlay and restore
its prior time when the alternative has future data. An explicit `load()` starts
a new load and clears that pending time. Ordinary WebM files have no native
AirPlay route or Media Source alternative-switch eligibility. The availability
probe accepts a non-blob alternative before CSP is checked during its actual
load, so an alternative blocked by CSP can still make AirPlay appear available.

Out-of-band `<track>` sources remain Blink-owned rather than native alternate
tracks. The [web surface guide](fairplay-safari-surface.md) owns output-protection
notification boundaries.

Each encrypted elementary stream emits its own initial `encrypted` event;
combined audio/video is not coalesced into one event. SAMPLE-AES setup reads the
first registration/private-data descriptor of each type. Later duplicate
descriptors are not searched, and parser selection follows the PMT stream type
even if its audio-format declaration disagrees. These descriptor cases and the
CSP-blocked AirPlay alternative above stay: no real site, stream or packager is
known to hit them, and searching later descriptors would change Chromium's
reader for every transport stream.

MPEG-1/2 video uses VideoToolbox in the GPU process, including its software decoder
when hardware decoding is unavailable. This is a process dependency, not a
requirement for an MPEG hardware decoder.

## Checks and maintenance

Focused source, parser, renderer and episode-store checks live with their owners.
Keep cross-feature priority in [the backlog](backlog.md), remove resolved work in
the same change and preserve the explicit scope decisions above.
