# Safari-mode media behavior and follow-ups

Safari identity changes the page-facing media decisions above Parc's playback
backends. Native HLS uses AVPlayer; FairPlay Media Source uses native sample-buffer
renderers; ordinary clear playback normally uses Chromium's renderer. Source
owners and API details are in [FairPlay web surface](fairplay-safari-surface.md),
[identity](fairplay-identity.md) and
[native HLS](../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md).

This guide keeps durable behavior and unresolved follow-ups. It is not an agent
queue, a release receipt or a claim that source checks establish live playback.
Picture in picture is user-accepted as complete and is not reopened here.

## Implemented behavior

| Area | Current source contract |
| --- | --- |
| Moving media | Same-origin document moves preserve the playing owner; visibility, mute, Now Playing, input and presentation follow the displayed element. Frame retirement transfers eligible loading rather than restarting playback. |
| Element loading | Muted-attribute/autoplay state, lazy/preload decisions, buffered readiness, seeking, key waits and rate-zero/end state follow the Safari-identity route. |
| Keys and renderer handoff | Late keys, replacement and detach are supported. The normal Chromium-to-FairPlay transition prerolls on the existing clock rather than restarting the page's media element. |
| Native HLS | Live/DVR timeline, start dates, track changes, key requests, clear data playlists, private asset policy and native error/readiness propagation are implemented. |
| Casting | Connecting and short-played casts survive eligible background/cache transitions. Mini Player retains its casting episode across navigation and can stop its original cast. |
| Audio | Pitch policy, output-device selection/fallback, added tracks and clear/protected supported formats reach the real renderer. |
| Reverse playback | Plain files support silent negative rates inline and in background; time advances continuously while frames may drop. Native HLS retains AVPlayer's route. |
| Media Source | Buffer admission, ranges, duration, eviction, worker lifetime, track switching and managed-buffer event timing use actual parser/player state. |
| Transport streams | Multiple audio tracks, PMT-declared audio types, MPEG-1/2 video and SAMPLE-AES support are present. |
| Formats | Ogg, clear PCM, ALAC, AMR/H.263 and additional Dolby Vision parsing/capabilities were added; compatibility-ID 2 carries SDR tagging. AV1 capability respects hardware under Safari identity. |

These statements replace older “in progress” claims for native HLS wiring,
`preservesPitch=false`, `getStartDate`, ordinary late-key handoff, ALAC, PCM and
Dolby Vision SDR compatibility. They do not erase the narrower boundaries below.

## Accepted behavior and exclusions

Preserve working functionality when updating compatibility behavior:

- Keep Chromium's useful behavior for HTTP servers without byte ranges.
- Spotify's Safari route remains the supported identity path without Widevine;
  its service-side lossless FLAC exclusion is retained. This is not signed-in
  service acceptance.
- Keep useful Ogg behavior: ambisonic Opus, rejection of garbage after abort,
  incomplete/bad-checksum page handling and FLAC's header-derived final duration.
  Mixed Ogg/video capability queries remain unsupported.
- Keep Dolby Vision profiles 4/7 base-layer playback and long-lived cached cast
  restoration where Parc already provides it.
- The user accepted non-perceptible play-promise, end-of-stream idle arrival,
  extra timeupdate and removal/fullscreen scheduling differences, and the
  `text/vtt` Media Source capability difference.
- The user accepted deferring expensive reverse-playback optimization for rare
  4K files with 5–10-second keyframe gaps. The retained estimate is 5–10 fps,
  up to two additional seconds to begin and up to 384 MiB of working memory;
  these are historical estimates, not fresh measurements.
- FairPlay `cenc` encryption and an element disabling its own video track remain
  outside the earlier agreed media scope. Later implemented late-CDM attachment,
  audio-output selection and additional Dolby Vision support remain supported.

## Retained follow-ups

These are specific unresolved items carried from the media audit. Unless noted
in the source contracts above, this documentation cleanup did not reproduce or
freshly prove them. Reconcile current source before claiming a defect still
exists or closing it. User-visible faults require a dedicated implementation
change and its appropriate checks, not a new documentation-only “done” label.

### Casting and Mini Player

- Two videos competing for a pending cast or a backend switch may lose a request
  before playback. A `no-store` page can end the cast when leaving the page.
- Frozen Media Source cannot supply data beyond its buffered range. A cast paused
  while its page is cached cannot resume from the TV until the page runs.
- An unmeasured paused cast assumes 30 fps; actual receiver limits still apply.
  A receiver that never offers remoting can keep a harmless request until resume.
- Navigation before Mini Player first observes the cast can open the chooser
  instead of offering Stop. Mirroring may label a Safari row Cast; another tab's
  launch can briefly show Connecting. Speaker-only receivers may lack the
  default-presentation button.
- Chromium's chooser ends a cast with Stop casting; it has no “This Mac” row.

### Moved elements and renderer transitions

- An interrupted HLS resource without a strong ETag/Last-Modified cannot safely
  resume after its original frame dies.
- Popup-to-frameless-document moves followed by popup closure, and first play of
  `preload=none` media while frameless, retain failure follow-ups.
- An existing cast remains attached to its starting tab. TV continuity after
  that starting frame closes is unverified.
- Reverse playback, mid-resume, CDM-change or unsupported-codec handoff fallbacks
  may still rebuffer. VP8/MP3 cannot join the FairPlay renderer.
- Added-audio synchronization away from rate 1 has only a reasoned 30-ms bound;
  a disabled first audio track may continue consuming decode CPU. Default audio
  device changes after fallback have no live acceptance result.

### Native HLS and AirPlay

- After switching to an HLS alternative, `load()` can lose the pending time;
  WebM alternative switching and the alternative's CSP preflight remain follow-ups.
- Live AirPlay reconnects at the live point with a gap rather than sharing one
  loader connection. Some assets expose more audio tracks than the first group.
- Out-of-band `<track>` sources remain Blink-owned rather than native alternate
  tracks. Explicit display-change output-protection notification is absent.
- Physical Apple TV acceptance and the effect of an open streaming connection
  on back/forward-cache admission remain unverified.

### Containers, codecs and low-level recovery

- TS descriptor ordering/type mismatch and one encrypted event for combined
  audio/video buffers remain follow-ups. Licensed AC-3/E-AC-3 SAMPLE-AES has no
  acceptance result.
- Non-square-pixel video reports Chromium's dimensions, which can differ from
  its display aspect and default element size. MPEG video requires GPU decoding.
  Plain `.ts`/`.mpg` playback and mixed H.264/MPEG-2 track choice remain unverified.
- 3GPP MIME answers, MPEG-4 Part 2 in 3GPP and raw `.amr`/`.awb` support remain
  an open scope decision; retain current behavior until that decision is made.
- Real Dolby Vision profile 20, `dav1` on older Macs, lower-case FLAC/Opus MP4
  aliases and complete runtime capability combinations remain unverified.
- Decoder `requiresFlushToResumeDecoding` recovery has no public live trigger.
  A picture retained after a decode error has no additional runtime acceptance;
  this does not reopen the accepted PiP feature.

## Validation and maintenance

The engine patches and focused native/renderer tests are the source of truth.
Fixture decoding, model assertions, compiler checks, compiled test objects and
physical playback are distinct evidence. This cleanup ran no browser, app,
engine build, licensed-service session or physical receiver test.

Keep cross-feature priority/status in [the backlog](backlog.md). Change this guide
when a behavior or boundary changes; remove a resolved follow-up instead of
appending another chronological receipt. Do not restore per-file audit logs,
agent ownership rosters or cumulative fix counts here.
