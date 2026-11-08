# Safari-mode media edges: Chromium's decisions against WebKit's

On Safari-identity pages ([fairplay-identity.md](fairplay-identity.md)) Parc
plays media through AVFoundation, but what the page sees is decided by the
Chromium layers above it: the media element, `WebMediaPlayerImpl`, the
pipeline and Media Source. In Safari, WebKit's layers decide. This document
compares the two, decision by decision, for the nine Chromium files below,
read in full at the pinned engine (Chromium 156.0.8078.48, `d0c02bfa`;
pristine line numbers, before Parc's overlay) against WebKit main
`db2d79f4413193cbfa65b50ebddcec39eaba5809` (November 7, 2026).

An **edge** is a point where one of these files decides something a page can
observe (a `readyState` change, an event fired or withheld, when a seek
finishes, when time moves, what is accepted, rejected, waited for or dropped)
differently from WebKit at the same point. Each entry gives the Chromium
`file:line`, the WebKit `file:line`, what the page sees differently, and
Parc's status:

- **handled**: Parc already matches WebKit on Safari-identity pages (the
  overlay hunk or Parc file named).
- **fixed**: fixed by the named commit from this audit.
- **in progress**: a fix agent owns it; the entry names the scope.
- **reason**: left as Chromium decides, with the architectural reason.
- **same**: examined and not an edge (recorded where it was a likely one).

Which Parc path a decision reaches matters. On Safari-identity pages:

- `<video src>` HLS plays through `AVPlayer` in the GPU process
  (`Engine/ParcNative/fairplay/fairplay_hls_player.mm`), behind the
  render-side `NativeHlsDemuxer` and `NativeHlsRenderer` facade
  (`Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md`).
- Media Source with a FairPlay CDM plays through `AVSampleBufferDisplayLayer`
  and `AVSampleBufferAudioRenderer` (`fairplay_renderer.mm`).
- Clear Media Source and other `src=` media play through Chromium's own
  renderer; only the element, player and Media Source decisions here apply
  to them. "AVFoundation path" below means the first two.

Unchecked claims are labelled **unchecked**.

## Scoreboard (13:45, November 7)

Reading: all nine files, 20,592 lines, done (reading log below). Fix jobs on
main: **93**. Being fixed now: **7** (casting follow-ups, moved-video ownership, late
audio track joining the running player, PCM audio in MP4, native HLS key requests, a worker's Media Source dying, rewinding plain files). Queued:
**about 15**. Waiting on Josh: four differences no user can perceive (proposed
leave), two where matching Safari is worse (range-less servers: keep Chrome's;
AV1 without hardware: match Safari). Done when the queue is empty, every
entry here shows its commit, and each fix's follow-ups are fixed. The live
slot list and queue are in `work/safari-media-audit-src/RUNNING_LOG.md`.

### Casting after leaving the page (CAST-4, CAST-5)

A cast still connecting, or of a video played under five seconds, ended when
the page entered the back/forward cache: **fixed** ed1b5e34 (overlay 578).
A progressive file whose data at the paused position wasn't downloaded
showed no picture on the TV while the page was cached and evicted it past
about 1 MB; a background tab frozen outside the cache lost a cast that
connected after freezing: **fixed** b6d0a63e (casting players only). A cast
still connecting 60 s after leaving is lost when Chromium evicts a page with
an unfinished download, and Chrome's own HLS player's data sources aren't
covered, and a 'cast this video' launch that failed outright left its
remoting request set: **fixed** dc01dff2. A TV session that never offers
remoting keeps the request until the page runs (nothing visible): **left**. Two
videos where the other starts casting first, or a backend switch, can drop
a request before it plays, and on `no-store` pages Parc ends the cast where
Safari's TV stays connected with nothing playing: **left** (rare). Media Source past its buffer can't feed a
cast from a frozen page (Safari's AirPlay can't cast plain Media Source
either) and a cast paused while its page is cached can't be resumed from the
TV until the page runs: **left**. An unmeasured paused cast is sized
at 30 fps, so a paused 1080p60 video can start on a TV without 4K support
where Chromium's measurement would refuse it: **left** (no frame rate exists
in the config; the TV's own limit still applies).

### Spotify on Safari identity (AUDIO-ID)

Parc has no Widevine license, so Spotify is learned as Safari and its
player takes its Safari path: legacy `WebKitMediaKeys` with
`com.apple.fps.1_0`, and a page-built HLS playlist (`data:`, or `blob:`)
naming byte ranges of one audio file plus an `skd://` key, played through
native HLS. Parc's native HLS route accepted only http(s) playlists, so no
song played: **fixed** 7419cea8 (nested `data:` playlists too, so video
podcasts; `blob:` playlists AVFoundation itself rejects, and Spotify uses
them only without MediaSource). Spotify's Safari path excludes FLAC in MP4
(lossless): **kept** (Josh, November 7: no Widevine, so Safari identity is
the only way it plays). Apple Music and Apple Podcasts (MusicKit, https
HLS) need no change. Not run against the signed-in service.

### Mini Player cast (MINI-CAST)

The Mini Player's last button is Cast on Chrome-identity media and AirPlay on
Safari-identity media: **fixed** 65c8fd25. Cast SDK pages with a default
presentation request (YouTube-style) got no button, and a cast-menu launch
finishing after navigation could cast the next page's video: **fixed**
2c258379. The row vanishing when the site drops its media session while
casting, and a cast launched just before leaving ending where Chrome's
carries on: **fixed** 5a160e58 (remoting is requested at the pick again, as
Chrome, and withdrawn on a failed launch). Stop casting from the row after the
page navigates away, or when the session is fully gone: **in progress**
(MINI-CAST-4). A second tab of the same site
shows Connecting during another tab's launch, and speaker-only receivers
don't show the button on default-presentation pages: **left** (brief,
cosmetic). Chromium's chooser has no "this Mac" entry, so a cast ends
with Stop casting: **left**.

### Captions in picture in picture (PIP-CAPTIONS)

Captions never showed in Parc's PiP window, where Safari's shows WebVTT,
Media Source, native HLS and FairPlay cues: **fixed** 5a730e1e (cues painted
at PiP size, repainted only when they change; lifted above the scrubber
while the controls show, a Parc choice). A cross-origin iframe player
scrolled out of view keeps updating its PiP captions (the paint runs outside
the throttled lifecycle; guarded by a test in b8cf81a3): no difference.

### Detached CDMs on native HLS (WMPI-5b)

The native HLS player kept every detached CDM until the same one was
reattached, so a page cycling MediaKeys held them all: **fixed** da0ef540
(released once no request or queued SPC needs it; reattaching cancels).

## Reading log

| File | Pristine lines | Read through |
|---|---:|---:|
| `third_party/blink/renderer/core/html/media/html_media_element.cc` | 5,504 | 5,504 |
| `third_party/blink/renderer/platform/media/web_media_player_impl.cc` | 4,242 | 4,242 |
| `media/base/pipeline_impl.cc` | 1,861 | 1,861 |
| `media/filters/pipeline_controller.cc` | 478 | 478 |
| `media/filters/chunk_demuxer.cc` | 1,658 | 1,658 |
| `media/filters/source_buffer_state.cc` | 931 | 931 |
| `media/filters/source_buffer_stream.cc` | 2,029 | 2,029 |
| `third_party/blink/renderer/modules/mediasource/media_source.cc` | 1,652 | 1,652 |
| `third_party/blink/renderer/modules/mediasource/source_buffer.cc` | 2,237 | 2,237 |

## Edges

### `html_media_element.cc`

**HME-1. Moving an element to another document.** Chromium
`html_media_element.cc:506-642, 710-755`: unless the move is into or out of
a same-origin Document Picture-in-Picture window, a loading or loaded
element runs the load algorithm again (`abort`, `emptied`, `loadstart`,
position back to 0) and resumes playing if it was. WebKit
`HTMLMediaElement.cpp:994-1023` (`didMoveToNewDocument`) keeps its player,
position and state and only re-registers with the new document. A page that
adopts a playing video into an iframe or popup sees it restart from 0 in
Parc and carry on in Safari. **Fixed** 47fe80b9 for same-origin moves between
framed Safari-identity documents (the player stays bound to the frame that
made it, as Chromium already does for Document Picture-in-Picture; the
element's event queue moves with it). A video moved into a popup follows the popup's
visibility: **fixed** 16ff69d8. The moved video's Now Playing, media keys,
tab sound icon and picture in picture now belong to the page showing it:
**fixed** cf6e810a. Closing, navigating or removing the opener no longer restarts
it for clear Media Source, plain files and native HLS: **fixed** 2e206083.
A moved video with MediaKeys attached reloaded when its CDM's frame went,
and FairPlay and native HLS tab mute acted from the opener's tab: **fixed**
00634ec8 (CDM ids resolve across frames of the creating renderer process
only; mute follows the new frame with no gap). A mid-segment native HLS load or a non-range plain file failing when the old
frame died, a video moved while in picture in picture staying bound to its
old frame, and MediaStream (WebRTC) videos reloading: **fixed** 5c7cbd9c (an
HLS resource without a strong ETag or Last-Modified isn't resumed, since a
live playlist can change, and fails as before: **left**). The page's own cast button and
Chrome's video remoting went through the opener: **fixed** 17e9e829 (a cast
already running stays with the tab that started it until it ends, as
Chromium ties routes to a tab; whether the TV keeps playing when the
starting frame closes mid-cast is **unchecked**). A move into a document without a browsing context
(`createHTMLDocument`) reloaded and failed where Safari keeps the player:
**fixed** 22ce9758 (it keeps its player: plays on in a `createHTMLDocument`
body, pauses in template content, as WebKit's `pauseAfterDetachedTask`).
Left (rare): a video moved from a popup into the opener's frameless document,
whose popup then closes, reloads and fails; a `preload=none` video first
played while frameless fails. A script-built muted
video moved from a Chrome-identity document already latches Safari's muted
rule at connection (muted state follows the current document, not the
creating one): no difference; guarded by tests in 2d774d1a.

**HME-2. `muted` content attribute set by script.** Chromium
`html_media_element.cc:852-856, 878-886`: the attribute sets `muted` only when
the parser creates it or `cloneNode` copies it
(`MediaElementMutedDefaultState` is experimental, off). WebKit
`HTMLMediaElement.cpp:1188-1192` (`postConnectionSteps`) and `:2199-2203`
(`loadResource`): until script sets `muted`, the attribute decides it at the
first connection or load. A video built by script with
`setAttribute('muted', '')` is muted in Safari, so muted autoplay starts and
it makes no sound; in Parc it was unmuted, so autoplay could be refused or it
played sound. **Fixed** 3b5b12cc (one corner differs: an element never
connected or loaded that moves from a Chrome-identity document into a
Safari-identity one keeps Chromium's value).

**HME-3. `load()` with no source after `play()`.** Chromium
`html_media_element.cc:1182-1239`: with `networkState` `NETWORK_EMPTY`,
`load()` leaves `paused` false. WebKit `HTMLMediaElement.cpp:1823-1826`: an
explicit `load()` sets `paused` true even then. A page that calls `play()`
before any source and then `load()` reads `paused` false in Parc, true in
Safari.

**HME-4. Lazy-loaded media while deferred.** Chromium
`html_media_element.cc:1371-1389`: `loading=lazy` deferral sets
`networkState` to `NETWORK_IDLE` before `loadstart`. WebKit
`HTMLMediaElement.cpp:1963-1964, 1656-1675`: deferral returns before step 7,
so `networkState` stays `NETWORK_NO_SOURCE`.

**HME-5. Nothing to load after a played resource.** Chromium
`html_media_element.cc:1353-1362`: when the source is removed and `load()`
finds nothing, an element whose player had reached `HAVE_FUTURE_DATA` keeps
its previous `networkState`. WebKit `HTMLMediaElement.cpp:1951-1960` always
sets `NETWORK_EMPTY` (and leaves picture in picture).

**HME-6. `preload="none"` on a `blob:` URL.** Chromium
`html_media_element.cc:1611-1618` never defers a `blob:` load, so a blob file
loads its metadata with `preload="none"`. WebKit loads a non-Media-Source
blob through the AVFoundation player, which stays idle under `preload`
none until the page plays (`MediaPlayerPrivateAVFoundation.cpp:191-205`,
`761-768`); Media Source blobs open in both.

HME-3 to HME-6 and HME-17: **fixed** 7000e39a. A resumed lazy load still
restarts resource selection in a microtask where WebKit queues a task, so
`networkState` turned `NETWORK_LOADING` one task early: **fixed** 7d9146e7.

**HME-7. Media Source readyState and seeks.** Chromium
`web_media_player_impl.cc:1123-1125` drops `readyState` to `HAVE_METADATA` at
every seek, `:2345` onward raises it from the renderer's two buffering
states, and `html_media_element.cc:2370-2393, 2379-2380` fires `waiting` and
finishes the seek at `HAVE_CURRENT_DATA`. WebKit sets a Media Source
element's `readyState` from buffered ranges at the playhead or pending seek
target (`MediaSource.cpp:424-498`, `MediaSourcePrivate.cpp:41-121, 160-176,
634-640`), re-checked on appends, duration and source state changes, seeks,
playback ticks and time changes, and finishes a seek when the player's seek
completes (`HTMLMediaElement.cpp:4180-4360`,
`MediaPlayerPrivateMediaSourceAVFObjC.mm:561-700`). A seek into buffered
data while playing fires `waiting`, `canplay`, `playing` and
`canplaythrough` in Parc, nothing beyond `seeking`/`timeupdate`/`seeked` in
Safari; `canplay` and `canplaythrough` never come apart in Parc. Native HLS
**handled** (a13b5579). Media Source **fixed** f50e1aab (readyState from the
buffered ranges around the playhead; a seek into buffered data fires only
`seeking`/`timeupdate`/`seeked`). On macOS 13.0-14.3 the FairPlay
renderer couldn't tell when a frame had decoded, so protected Media Source
said `canplay` before keys and `seeked` before the picture: **fixed** 7597d287
(WebKit's preroll signal, `SourceBufferPrivateAVFObjC.mm:1074-1107`; Parc's
minimum is 13.0). Pre-existing FairPlay renderer gaps a user feels
(`fairplay_chromium/README.md` Known gaps): keys arriving after playback
started, replaced MediaKeys, a switch into Dolby Vision, a protected late
SourceBuffer, and a page switching or turning its video track off cost a
rebuffer or froze the picture: **fixed** e2556dc9 and 098f5290 (renderers
join on the same clock; Chromium's renderer hands off to the FairPlay
renderer at a keyframe; a handoff asked for during a seek waits for it:
ca8b6db6). The handoff holds the picture and pauses the sound for about
40-65 ms where Safari plays straight through: **in progress** (FP-RESTART-3,
preroll the FairPlay renderer and switch on the same clock). Left (rare): a
switch needed while playing backward, mid-resume, after a CDM change or for
codecs the FairPlay renderer can't play still restarts with one rebuffer. Dolby Vision alongside a track the FairPlay
renderer can't play (VP9 before the switch, Vorbis) fails: **in progress**
(FP-DV); `setSinkId` audio output selection wasn't wired:
**fixed** 30970c11 (FairPlay Media Source and native HLS; Chrome-identity
FairPlay pages follow it too, as Chrome moves all of an element's audio).
Unplugging the chosen device stalled protected playback (Safari too) and
'default' pinned the current default on Media Source: **fixed** 7b5f48ab
(audio falls back to the system default and keeps playing; Parc better than
Safari). Following a later default change is checked by reasoning only
(**unchecked** at runtime).

**HME-8. Seek steps run synchronously.** Chromium
`html_media_element.cc:2656-2735` clamps to the duration, the earliest
position and the nearest seekable point and queues `seeking` inside the
`currentTime` setter. WebKit `HTMLMediaElement.cpp:4110-4178` sets
`seeking` and a provisional `min(target, duration)` at once and runs the
remaining steps (earliest position, nearest seekable point, the `seeking`
event) in a queued task (`seekTask`, `:4180-4309`), cancelling a still-queued
earlier one. Reading `currentTime` right after setting it can differ (a live
stream whose seekable range starts after 0).

**HME-9. Seek to the current time.** Chromium always asks the player
(`html_media_element.cc:2730`; `web_media_player_impl.cc:1146-1186` elides
only a paused, fully buffered non-Media-Source seek). WebKit
`HTMLMediaElement.cpp:4227-4256`: a precise seek to the current time outside
poster mode, with no fast seek pending and no open Media Source, fires
`seeking`, `timeupdate` and `seeked` without a player seek.

**HME-10. Seek with no seekable ranges.** Chromium
`html_media_element.cc:2715-2718` clears `seeking` silently. WebKit
`:4228, 4244-4255` fires `seeking`, `timeupdate` and `seeked` when the target
is the current time, else clears silently.

**HME-11. Finishing a seek.** Chromium `html_media_element.cc:2737-2756` fires
`timeupdate` and `seeked`. WebKit `HTMLMediaElement.cpp:4260-4262, 4323-4360`
also re-arms `ended` unless the seek lands in ended playback, fires a pending
`playing` (`maybeFirePendingPlaying`) and resumes an element that was playing
before the seek.

**HME-12. Seeking with `preload` below auto.** Chromium
`html_media_element.cc:2669-2670` lifts only `preload="none"`. WebKit
`HTMLMediaElement.cpp:4126-4128` prepares to play (preload auto) when
`preload` is below auto and `readyState` is below `HAVE_FUTURE_DATA`.

HME-8 to HME-12: **fixed** 0beefdec (with WebKit's once-only `ended` latch and
a `playing` that arrives during a seek held until `seeked`). Chromium's
built-in controls and a `#t=` fragment still seek at once where WebKit's go
through the queued seek; pages can't tell. WebKit's resume after a seek
applies only to macOS Now Playing scrubbing: HME-34.

**HME-34. Now Playing scrubbing.** WebKit pauses an element when a Now
Playing scrub starts and resumes it 500 ms after the last step
(`HTMLMediaElement.cpp:6507-6537, 4357-4359`). Chromium's system-control
seeks (`html_media_element.cc:5365-5379`) don't pause. **Fixed** e425c4db. Picture in picture and toolbar
scrubs use WebKit's playback-controls rule instead (internal pause, no
events): **fixed** b4914f3e.

**HME-35. A new load rejects waiting `play()` promises.** Chromium
`html_media_element.cc:1182-1212` rejects pending play promises only when
`networkState` isn't `NETWORK_EMPTY` and the element isn't paused. WebKit
`HTMLMediaElement.cpp:1766, 3194-3211` rejects them with `AbortError` on
every load, explicit or not, unless an in-flight play admission will settle
them. A page that calls `play()` before any source and then sets `src` sees
its promise rejected in Safari and fulfilled in Parc. **Fixed** b1924e73.
Two timing-only differences remain, which no user can perceive: a promise
sure to resolve settles at load start rather than a task later, and a load in
a document with no browsing context still rejects. **Left** (Josh agreed November 7:
no user can perceive it).

**HME-13. `currentTime` while playing.** Chromium
`html_media_element.cc:2818-2841` holds the official playback position
until the next microtask, and while waiting for data. WebKit
`HTMLMediaElement.cpp:4409-4431` returns the cached position only while
paused and reads the player otherwise, so two reads in one task can differ
while playing, and a stalled element reports the player's time.

**HME-14. Negative and non-finite `currentTime`.** Chromium stores a
negative default start position and throws on non-finite values. WebKit
clamps to [0, max] (`HTMLMediaElement.cpp:4451-4465`). **Handled**:
`setCurrentTimeForBindings` in `fairplay-identity-blink.patch`.

**HME-15. `playbackRate` range.** Chromium `html_media_element.cc:338-341,
2926-2981` throws `NotSupportedError` for a rate outside 1/16 to 16 (negative
included) and ignores such a `defaultPlaybackRate`. WebKit
`HTMLMediaElement.cpp:4525-4596` accepts any rate and hands it to the player.

**HME-16. `ended` at rate 0.** Chromium `html_media_element.cc:2983-2993`:
`ended` is true at the end with `playbackRate` 0 (direction forward means
rate ≥ 0). WebKit `HTMLMediaElement.cpp:4629-4645`: only with a rate above 0.

HME-13, HME-15, HME-16: **fixed** f66198f5. Two parts of HME-15 still
differ: a negative rate leaves the time standing still where Safari's
`src=` player plays backwards (Chromium's pipeline has no reverse playback;
Safari's Media Source player also drops negative rates), and rates outside
1/16 to 16 play at the nearest limit while the page reads its own rate.
Rates outside 1/16 to 16 and native HLS reverse playback: **fixed**
bac07f94. A plain `src=` file stood still at a negative rate: **fixed** 4bc9fab8
(reverse playback in Chromium's pipeline, inline, picture in picture and
background; silent; pauses at 0). Still different: rewinding 4K or
long-keyframe files held between decoded chunks: **fixed** ed3848c9 (time
never stops; frames drop evenly when decoding can't keep up). Still: 4K with
5-10 s keyframe gaps rewinds at an estimated 5-10 frames a second; closing it
needs FFmpeg's disposable-frame skipping, about a day (**left**, Josh agreed
November 7: negative rates on plain 4K files are rare); a rewind can
take up to 2 s longer to start; rewinding holds up to 384 MB (was 192 MB);
dropped rewind frames weren't counted in `getVideoPlaybackQuality`: **fixed**
1e420a54 ( count them as the spec's decoded-but-not-presented frames;
Safari reports AVPlayerLayer's `videoPerformanceMetrics`,
`MediaPlayerPrivateAVFoundationObjC.mm:4039-4059`, so AVFoundation decides
and whether it counts reverse drops is **unchecked**); while casting, Now Playing showed a backward
scrubber over a frozen TV (**fixed** e4ca73cd); whether Safari's
reverse playback is audible is **unchecked** (AVPlayer decides).

**HME-29. Ended at rate 0 inside the element.** Chromium's internal check
(`html_media_element.cc:4223-4245`, used at `:3220-3221, 4041-4087,
4219-4221`) still counts rate 0 at the end as ended, so `play()` there
seeks to the start and `ended` can fire. WebKit's `endedPlayback`
(`HTMLMediaElement.cpp:6902-6928`) is false at rate 0 (`:4785-4787,
6426-6467`). **Fixed** a714681a (and a rate raised above 0 at the end now
pauses or loops a task later, as WebKit's player reports the end). `ended`
firing only once per arrival is part of HME-23.

**HME-17. The last `progress` before `suspend`.** Chromium
`html_media_element.cc:2268-2283` fires it only if the player made progress
since the last check. WebKit `HTMLMediaElement.cpp:3335-3344` always fires
one `progress`, then `suspend`.

**HME-18. `progress` and `stalled` on Media Source.** Chromium
`html_media_element.cc:2530-2585` fires `progress` every 350 ms that data
arrived on a Media Source element. WebKit `HTMLMediaElement.cpp:3962-3994`
asks the player, and Safari's Media Source player doesn't support progress
monitoring (`MediaPlayerPrivateMediaSourceAVFObjC.mm:1594-1598`), so a Media
Source element gets no periodic `progress` (or `stalled`). **Fixed** 7000e39a:
a successful `endOfStream()` makes the element idle with `progress` and
`suspend`, as Safari's player reports Loaded only then. Parc set that idle
state synchronously where Safari's arrives from the player a task later:
**fixed** 7d9146e7. The exact arrival time of Safari's report isn't fixed
(it comes from the GPU process); no user can perceive it. **Left**
(Josh agreed November 7: no user can perceive it).

**HME-19. Default `preload`.** Chromium `html_media_element.cc:3074-3111`
makes a missing or invalid `preload` metadata (and forces metadata on
cellular). WebKit `HTMLMediaElement.cpp:1094-1104` and
`HTMLMediaElement.h:1365` make it auto. A plain `<video src>` reports
`preload` "auto" in Safari and buffers ahead to `canplaythrough` without
`play()`; Parc reported "metadata" and stopped after metadata. Native HLS
already prepared to play as WebKit does; the rest **fixed** f0178670
(an element with `autoplay` now preloads automatically whatever the
autoplay policy, as WebKit's does).

**HME-20. `muted` before script sets it.** WebKit
`HTMLMediaElement.cpp:5102-5111` returns the content attribute itself until
`muted` is set by script or latched at connection or load. **Fixed**
3b5b12cc.

**HME-21. Non-periodic `timeupdate`.** Chromium
`html_media_element.cc:3527-3550` fires every non-periodic `timeupdate`
(pause, waiting, load reset). WebKit `HTMLMediaElement.cpp:5383-5417` fires
any `timeupdate` only when the time differs from the last one's (seek
completion and load reset bypass it), so `pause()` at an unchanged time
fires none. **Fixed** f0178670.

**HME-30. Preload once prepared to play.** WebKit's effective preload stays
auto for every later load once the element was prepared to play
(`HTMLMediaElement.cpp:2084-2101, 4021-4032`; `m_hasEverPreparedToPlay` is
never reset). Parc's fell back to the attribute on the next `src`, so the next video
started slower. **Fixed** c301fd01.

**HME-31. `timeupdate` on time jumps and cue boundaries.** WebKit fires one
when the player reports a time change outside a seek
(`HTMLMediaElement.cpp:6381-6398`) and from cue updates while playing
(`:2423-2432, 2455-2476`). Chromium reports time changes only after seeks and
at the end (`web_media_player_impl.cc:2100-2122, 2399-2403`) and its cue
timer fired no `timeupdate`. **Fixed** da2f002b (cue boundaries, the end
before looping, and native HLS backward jumps, including while paused).
Up to 250 ms difference in an extra `timeupdate` after a seek on caption
pages, and a race-only extra one: no user can perceive either. **Left**
(Josh agreed November 7: no user can perceive it).

**HME-22. Autoplay policy.** Chromium `html_media_element.cc:3161-3196`
asks `AutoplayPolicy::RequestPlay` (Chromium's document user activation,
sticky for the frame, plus media engagement). WebKit
`HTMLMediaElement.cpp:4687-4718` asks `MediaElementSession::playbackStateChangePermitted`
(`MediaElementSession.cpp:463-568`): with Safari's default policy, audible
playback needs a user gesture being processed now, or an element a gesture
already unlocked. **Fixed** 8d00107a (Josh's default: Safari's rule).
Low Power Mode and thermal throttling requiring a gesture even for muted
video, a hidden page needing a gesture to start sound, a camera stream
allowed because the page already plays audio, and an audio track appearing
mid-playback being re-checked: **fixed** acee1d60. Safari's per-site autoplay setting has no Parc equivalent, and site
quirks are excluded (they key on site names).

**HME-23. When playback has ended.** Chromium `html_media_element.cc:4223-4245`
asks the player (`IsEnded()`, after the renderer reports the end). WebKit
`HTMLMediaElement.cpp:6902-6928`: the current position at or past the
duration with a positive rate (or at 0 going backwards). A paused element
seeked to its duration reads `ended` true in Safari, false in Parc until the
renderer ends.

**HME-24. Potentially playing.** Chromium `html_media_element.cc:4213-4221`
counts `HAVE_METADATA` and up. WebKit `HTMLMediaElement.cpp:6863-6875`
requires `HAVE_FUTURE_DATA`, or having reached it and dropped below. An
element that never reached `HAVE_FUTURE_DATA` gets `waiting` from a drop in
Parc and none in Safari.

**HME-25. Removed from the document.** Chromium
`html_media_element.cc:5065-5077` pauses a disconnected element unless it is
in picture in picture, and with `networkState` `NETWORK_EMPTY` that pause
starts resource selection (`:3252-3256`). WebKit
`HTMLMediaElement.cpp:1258-1270, 1323-1334` doesn't pause while seeking, with
`NETWORK_EMPTY`, or after an invisible-autoplay interruption, and leaves
standard fullscreen.

HME-23 to HME-25: **fixed** c63e6291. A seek to the current time at the end was
thought to re-arm the once-only `ended` latch; checked against WebKit
`HTMLMediaElement.cpp:4244-4262`, Parc already matches (0beefdec skips such
seeks before the latch); regression tests added in bd07fa38. **Same.** Fullscreen is left at removal in
Parc and a moment later in WebKit's pause task: no user can perceive it.
**Left** (Josh agreed November 7: no user can perceive it).

**HME-26. Frozen and back/forward cache.** Chromium
`html_media_element.cc:4388-4398` pauses on a frozen frame (`pause` event,
play promise rejected, stays paused when thawed). WebKit
`HTMLMediaElement.cpp:7401-7452, 7336-7366` stops a page entering the
back/forward cache without events and resumes it when the page returns
(`setPausedInternal(false)`), and does nothing for other suspensions. Going
back to a page with a playing video: Safari carries on, Parc shows it paused
after a `pause` event. **Fixed** 8eaa50de: a back/forward-cache freeze holds
playback without events and resumes on return with the same player and
position; other freezes leave media alone (the element's events wait for the
thaw, and Chromium's freezing policy never freezes an audible page,
`freezing_policy.cc:613-617`). WebKit's `userCancelledLoad` changes nothing on
macOS here (`HTMLMediaElement.cpp:7213-7219`). Still different: a page
restored into a background tab resumes at once, where WebKit waits until the
page can start media (`MediaElementSession.cpp:717-730`): **fixed** 7fcc63d0
for background tabs; a restore into a minimised or covered window waited
where Safari plays: **fixed** 54fc1006 (an "in window" signal from the
browser).
With a Cast session active the player restarted on entering the cache, as
stock Chromium does: **fixed** c0f53c09 on every page (Josh's decision), and
Safari-identity pages keep WebKit's 30-minute cache lifetime. A stale session
leaving the TV on a paused video, and the cast ending after 30 minutes where
Safari's TV keeps the frame up to an hour: **fixed** 31735c02. A cast started
a second before leaving showed a blank TV until the user returned: **fixed**
b0a863a1 (casting players only; other cached pages stay frozen). Leaving
before the TV has connected still ends the cast after about 5 seconds, and a
video played less than 5 seconds before casting never starts on the TV:
**in progress** (CAST-4). Between
30 and 60 minutes away Parc now restores the casting page and resumes on the
TV, where Safari reloads the page: Parc is better here: **kept**
(Josh agreed November 7). FairPlay
video can't be cast (Safari uses AirPlay). Native HLS video, FairPlay
included, now AirPlays from the page's button and the Mini Player through the
system route list: **fixed** c3c53b1d (no device picker of Parc's own: listing
devices needs Apple-only entitlements; Josh agreed). Josh approved the Mini
controls, Remote Playback opening AirPlay, and
`webkitWirelessVideoPlaybackDisabled`: **fixed** e82baa07 (Space tint, computed for
the always-dark placard and scrim with at least 4.5:1, recolouring live:
f339440b; the overflow menu item takes the tint for its own surface:
95cdb568). A ManagedMediaSource element didn't switch to its HLS
`<source>` alternative when a target is picked, as Safari does: **fixed**
6bc1c789, with Safari's rule that a managed source stays closed until
`disableRemotePlayback` or a non-blob `<source>` is present (a Safari-identity
site omitting both now never starts, as in Safari). Left: a `load()` after a
switch drops the pending time; WebM doesn't switch; the alternative check
skips WebKit's CSP check (all rare). Clear `src=` files didn't AirPlay (Safari plays them through AVPlayer):
**fixed** 1c03b194 (they move to AVPlayer and back seamlessly; Safari never
AirPlays Media Source, so neither does Parc). The user's chosen audio and video
tracks now carry to the TV, and a live stream's `currentTime` stays
continuous across the switch: **fixed** 0786af49. Left: a live stream
reconnects on the TV (a short gap, restarting at the live point; one
connection would need AVFoundation fed from Chromium's loader), and some
files list more audio tracks to the page than Safari's first-group view. Nothing AirPlayed to a real Apple TV yet. A streaming source's open connection may count against the
cache's limits (**unchecked**).

**HME-27. Error and rejection messages.** Chromium builds `MediaError.message`
as `MEDIA_ELEMENT_ERROR: …` (`html_media_element.cc:262-273`) and
play-promise rejections with its own texts (`:4988-5040, 5301-5310`). WebKit
uses the player's last error message or "Unsupported source type"
(`HTMLMediaElement.cpp:3113-3117`), "Media failed to load"/"decode" with the
player's message (`:3155-3173`), "The operation is not supported." for
`play()` after `MEDIA_ERR_SRC_NOT_SUPPORTED` (`:4701-4705`) and no message
otherwise. **Fixed** 7e747354. Safari's macOS players report no message of
their own (`MediaPlayerPrivate::errorMessage()` is empty for them), so the
native HLS route's AVFoundation error text no longer reaches the page.
Rejections that WebKit makes `NotAllowedError` when playback is refused
after `play()` started stay `AbortError` (part of HME-22).

**HME-32. `MEDIA_ERR_ABORTED`.** Safari on macOS reports it when a worker's
MediaSource is destroyed: `abort`, error 1 "Load was aborted", `emptied`
(`MediaSource.cpp:225-245`, `HTMLMediaElement.cpp:2317-2322, 7208-7262`).
Chromium reported nothing (`media_source.cc:1433-1573`), so the video just
froze. **Fixed** 5f98fd24 (WebKit's `userCancelledLoad` steps; on macOS its
only other caller returns early, `HTMLMediaElement.cpp:7218, 7359`). If it
happens in picture in picture the window stays open, as in WebKit; Parc's
window contents then are **unchecked**. `MEDIA_ERR_ENCRYPTED` is never fired in Safari either (modern
EME is on). **Same.**

**HME-28. `media-playback-while-not-visible`.** Chromium
`html_media_element.cc:702-708, 3139-3145, 5253-5299` honours this
permissions policy (pausing hidden frames, deferring `play()` until
visibility is known). WebKit has no such policy. **Fixed** c63e6291.

### `web_media_player_impl.cc`

**WMPI-1. Seeks on `src=` files.** Chromium `web_media_player_impl.cc:1118-1211`
drops `readyState` to `HAVE_METADATA` at every seek and completes it at the
renderer's next `BUFFERING_HAVE_ENOUGH` (`:1857-1903, 2345-2442`), so a
playing file fires `waiting`, `canplay`, `playing` and `canplaythrough` on
every seek. WebKit's AVFoundation player keeps `readyState` from the item's
status (`MediaPlayerPrivateAVFoundation.cpp`, `updateStates`) and the element
finishes the seek when the player's seek resolves
(`HTMLMediaElement.cpp:4180-4360`). Media Source is HME-7; native HLS
**handled** (a13b5579). **Fixed** a2d41ba1 (plain files keep readyState
through a seek into buffered data).

**WMPI-2. Waiting for a key.** Chromium `web_media_player_impl.cc:2457-2494`
reports block and resume together for every wait and Blink's element never
changes `readyState`. WebKit `HTMLMediaElement.cpp`
(`mediaPlayerWaitingForKeyChanged`) runs Wait for Key once per blocked
episode: `readyState` to `HAVE_CURRENT_DATA` or `HAVE_METADATA`, then
`waitingforkey`, restored when the key arrives; native HLS waits only for a
key request with no CDM attached
(`MediaPlayerPrivateAVFoundationObjC.mm:2210-2235, 3090-3110`). Media Source
key timing **handled** (35589317); the `readyState` drop and the native HLS
rule **fixed** 88efb22f. Still differing: any newly usable key ends the wait
rather than the one playback asked for, and a key event racing the stall
report can leave `readyState` lowered while playing: **fixed** d751d783.
Encrypted `src=` media through Chromium's pipeline waited while a CDM was
attached, Media Source tracked waiting per player rather than per
SourceBuffer, non-usable key status changes weren't rechecked, and a key
check in flight across `setMediaKeys(null)` could end a wait: **fixed**
915d4ee6. Native HLS decided "no CDM attached" when the GPU player accepted the
CDM rather than at the key request, and a CDM offered twice answered
"attached" early: **fixed** bfd29ee0. `setMediaKeys` before the native HLS
player exists resolves before the GPU player takes the keys, so a player that
couldn't take them left a video that never played with no error: **fixed**
c1673012 (refusal now rejects with `NotSupportedError`; WebKit's own refusal
path is a FIXME). A key session that couldn't be created when the native player
started failed silently: **fixed** fe2b500d (`generateRequest()` rejects with
`NotSupportedError`, as WebKit's CDM path does; a fresh request can retry).

**WMPI-3. Hidden pages pause video.** Chromium
`web_media_player_impl.cc:3744-3787, 3825-3870, 3528-3551, 2643-2714` pauses
video without unmuted audio when its page or frame is hidden (the page sees
`pause` and a rejected play promise) and resumes it when shown. WebKit on
macOS pauses nothing for being hidden (`InvisibleAutoplayNotPermitted` and
`RequiresPageVisibilityToPlayAudio` are iOS-only:
`UnifiedWebPreferences.yaml:3348-3365, 5281-5303`;
`HTMLMediaElement.cpp:733-741`). A muted video in a background tab keeps
playing in Safari. **Fixed** dec04e58. Chromium still turns a hidden
audio-and-video player's video track off after 10 s
(`web_media_player_impl.cc:3789-3823`): no event and `currentTime` runs on,
but decoded frame counts stop rising, dropped counts can jump on show
(`video_renderer_impl.cc:1062-1065`), and canvas captures show the last
frame until the stream catches up; returning to the tab can show a frozen
picture for up to half a second (`:3840-3843`). Picture in picture, capture
and casting were already exempt (`:3808-3811`). **Fixed** 5ed9a2e8.

**WMPI-4. Servers without range requests.** Chromium
`web_media_player_impl.cc:1494-1515` plays a file from a server that ignores
range requests and makes it unseekable (seekable `[0, 0]`), and gives live
content no seekable range. Safari loads files through AVFoundation, which
needs range requests for such files, so Safari often won't play them at all.
Matching Safari would stop videos that play today. **Kept** (Safari won't play these at all;
Chrome's plays them).

**WMPI-5. `setMediaKeys(null)`.** Chromium
`web_media_player_impl.cc:1662-1687` refuses to clear a CDM; Parc accepts it
on Safari-identity FairPlay players but keeps decrypting with the old CDM
(14ce748a). WebKit detaches it (`HTMLMediaElement.cpp` `setMediaKeys`,
`MediaPlayerPrivateMediaSourceAVFObjC.mm:1162-1166`,
`MediaPlayerPrivateAVFoundationObjC.mm:3060-3080`), so samples after that
wait for a key. **Fixed** 4f5fe602.

### `pipeline_impl.cc`

**PIPE-1. Encrypted media before MediaKeys.** Chromium `pipeline_impl.cc:1200-1214`
creates no renderer while an encrypted stream has no CDM (`kNoCdm`), so a
Media Source element stays at `HAVE_METADATA` until keys are set. WebKit's
Media Source `readyState` comes from buffered ranges whatever the keys
(`MediaSource.cpp:424-498`), held below `HAVE_CURRENT_DATA` only for video
without a decodable frame (`MediaPlayerPrivateMediaSourceAVFObjC.mm:1229-1235`).
Part of HME-7, **fixed** f50e1aab.

Otherwise the pipeline makes no page-visible decision of its own: it clamps
seeks to the demuxer's start time (`:460, 1150`), never lets media time go
backwards (`:1615-1642`), ignores negative rates (`:1532-1535`, part of
HME-15) and relays the renderer's and demuxer's states. **Same.**

### `pipeline_controller.cc`

**PC-1. Resuming a streaming source.** Chromium `pipeline_controller.cc:249-257`
resumes a suspended pipeline whose source can't seek (a server without
range requests) at time 0 with a time update. Chromium suspends such
players only at the start or when their frame is frozen
(`web_media_player_impl.cc:3160-3166, 3296-3297`), so the page sees
`currentTime` jump to 0 after coming back from the back/forward cache;
WebKit keeps the position. **Fixed** 8eaa50de (the cache freeze no longer
suspends the pipeline).

Seeks during seeks are coalesced (`:65-86, 273-288`), as WebKit queues the
latest (`HTMLMediaElement.cpp:4136-4145`). **Same.**

### `chunk_demuxer.cc`

**CD-1. Adding a SourceBuffer after metadata.** Chromium
`chunk_demuxer.cc:646-718, 1430-1489` accepts `AddId` only until every
SourceBuffer's first init segment has arrived (`kReachedIdLimit` after that),
which Blink turns into `QuotaExceededError`. WebKit's AVFoundation Media
Source adds a SourceBuffer whenever the source is open
(`MediaSource.cpp` `addSourceBuffer`, `MediaSourcePrivateAVFObjC.mm:117-141`).
A player that adds an audio SourceBuffer after the video one started
fails in Parc (`QuotaExceededError`, `media_source.cc:1626-1637`). **Fixed**
b294d1e7. Still differing: Parc restarts the renderer for the new track (an
extra rebuffer, and a blank picture with the FairPlay renderer) where WebKit
adds it to the live renderer, and a late second audio-language SourceBuffer
plays only the original audio where Safari mixes both enabled tracks:
**fixed** 00671621 (late tracks join the playing renderer, FairPlay and
RendererImpl, no restart; a second audio SourceBuffer plays mixed on
FairPlay). Clear Media Source played only the first of two audio SourceBuffers,
`audioTracks` toggles played only one track (`html_media_element.cc:4486`),
and an encrypted late track on RendererImpl restarted (a rebuffer): **fixed**
83554da3 (every enabled track mixed, as Safari); the merged-SourceBuffer race
is closed too. A late track needing the FairPlay renderer while RendererImpl plays
restarted: **fixed** 098f5290; a turned-off first track keeps decoding silently (a
little CPU, no audible effect: **left**); sync at rates other than 1 is
within 30 ms by reasoning only (**unchecked**). Video track switches on FairPlay
froze the picture: **fixed** e2556dc9.
`readyState` returned straight to
`HAVE_ENOUGH_DATA` after the new track's data arrived: **fixed** f50e1aab.

Seeks wait for data at the target (`:512-541, 1017-1022`), end of stream
before any init segment is a format error (`:1305-1312`), buffered ranges
intersect across SourceBuffers with the end extended once ended
(`:1592-1605`, `source_buffer_state.cc:72-122`) and duration follows the
MSE duration change rules (`:1192-1254, 1537-1585`), as in WebKit
(`MediaSource.cpp`, `MediaSourcePrivate.cpp:computeBufferedRanges`).
**Same.** A disabled stream returns end of stream (`:267-282, 315-329`):
a page turning its own video track off is one of Josh's cuts.

### `source_buffer_state.cc`

**SBS-1. Init segments that don't match the declared codecs.** Chromium
`source_buffer_state.cc:533-574, 576-800` fails an append whose init
segment has a codec missing from the type given to `addSourceBuffer` (or
lacks a declared codec's track). WebKit never compares them
(`SourceBuffer.cpp:780-1090`, `SourceBufferPrivate.cpp:910-990`): it fails
only an init segment with no tracks, a later one whose track counts differ,
or unknown ids among several tracks of a type. Sites with loose codec
strings play in Safari and fail in Parc. **Fixed** 165f1260 (also in the MP4
parser, which separately refused undeclared audio codecs). Text-track counts,
which WebKit also compares, never differ: Safari's Media Source reports no
text tracks either (`TextTracksInMSEEnabled` false). On FairPlay players a
later init segment may now switch codec without `changeType()`; a switch to
a codec the FairPlay renderer can't play is a playback error where Safari
plays it (the renderer's known codec gap).

**SBS-2. MPEG-2 TS in Media Source.** Parc's engine builds Chromium's TS
parser and answers `video/mp2t` with H.264, AAC or MP3
(`media_source.cc:66-88, 568-582`), and that parser drops streams the type
didn't declare. Safari takes TS through `AVStreamDataParser`
(`SourceBufferParser.cpp:43-58`, `SourceBufferParserAVFObjC.mm:204-214`,
`AVStreamDataParserMIMETypeCache.mm:55-120`), whose type list on this Mac
includes `video/mp2t`, `video/x-mp2t`, `video/m2ts` and `video/x-m2ts`
(checked with `[AVStreamDataParser audiovisualMIMETypes]`, macOS 27.2), and
parses every stream. **Fixed** a71dff66 (Safari's TS types and codec answers;
AC-3 and E-AC-3 in TS now play with sound; MPEG-1 Layer I/II audio decodes
through Chromium's MP3 decoder; measured against this Mac's
`AVStreamDataParser`, which ignores HEVC in TS). Still different, all
user-felt: several audio streams in one TS showed as one track, so a
language or commentary menu did nothing, and E-AC-3 7.1 frames split across
packets lost their extra channels: **fixed** ffa89f7f. FairPlay SAMPLE-AES
H.264, AAC, AC-3 and E-AC-3 in TS failed to play: **fixed** bea69854 (mpts init data and the single
`TransportStreamIdentifier` key ID as WebKit; AC-3/E-AC-3 decryption
**unchecked**, no licensed content). An HE-AAC stream declared in the PMT but
only implied by its config is named plain AAC (possibly losing the high
band): **fixed** d5889317 (the PMT's declared type is kept, as Apple's
parser). One `encrypted` event for a SourceBuffer
holding video and audio (one key serves both, as WebKit), and rare
descriptor-order and type-mismatch cases: **left**. MPEG-1/2 video in TS played black: **fixed** 9f8ba00d (a TS
elementary-stream parser with Safari's types, key frames, timestamps and pixel
aspect, decoded by VideoToolbox in the GPU process). Left: `videoWidth`/
`videoHeight` for non-square pixels follow Chromium's model for every codec
(720x528 where Safari reports about 655x480; same shape on screen, a
different default element size); plain `.ts`/`.mpg` files are
**unchecked**; no decode with GPU video decoding turned off; which video
track Safari picks when H.264 and MPEG-2 share a TS is **unchecked**.

Clear Dolby Vision in Media Source (`:675-698`) is **handled** on
Safari-identity pages (`ParcSetClearDolbyVisionAllowed`). In-band text
tracks in Media Source are off in Safari too (`TextTracksInMSEEnabled`
defaults false, `UnifiedWebPreferences.yaml:6413-6420`). **Same.**

### `source_buffer_stream.cc`

**SBST-1. Buffer budget and eviction.** Chromium limits each stream
separately (`source_buffer_stream.cc:145-176`, `demuxer_memory_limit*.cc`:
about 12 MB of audio, video by resolution) and garbage-collects GOP by GOP
after the last append, then before the playhead, then from the back
(`:735-1058`). WebKit gives each SourceBuffer one budget, 5% of
`maximumSourceBufferSize` (318,767,104 bytes) plus 95% with video
(`SourceBuffer.cpp:702-731`, `SettingsBase.cpp:104-109`), and evicts 30 s
chunks (halving to 3 s) from the start up to before the playhead, then from
the end back to the playable segment (`SourceBufferPrivate.cpp:703-776,
1747-1830`). `appendBuffer()` throws `QuotaExceededError` at different
points and different ranges disappear. **Fixed** e9a50704. Still differing:
back eviction drops a longer track's tail that WebKit keeps; Parc removes
whole GOPs where WebKit cuts frame by frame; Parc keeps the last appended GOP
as its own range where WebKit removes it; and WebKit's cached evictable-size
shortcut that skips the exception wasn't modelled. **Fixed** 4ba6c7c3 (no
playback-gap risk: back eviction only removes data past the stall point and
front eviction never removes the current group). An append starting
mid-group after a removal drops frames to the next keyframe in Chromium where
Safari keeps them, but neither can show them: no user can perceive it. The
memory-pressure purge dropped a longer audio track's tail Safari keeps (a
possible rebuffer): **fixed** 575b0add.

**SBST-2. Small gaps in `buffered`.** Chromium keeps separate ranges unless
the gap is within twice the largest inter-buffer distance
(`:50-63, 694-725, 1672-1678`). WebKit merges gaps under 2002/24000 s
(`TrackBuffer.cpp:84-87, 197`, `PlatformTimeRanges.cpp:62-66, 205-221`) and
bridges gaps within its gap tolerance during playback. A 70 ms gap in 30 fps
video was one range in Safari, two in Parc. **Fixed** 2d35f28b.

Removal extends to the next keyframe (`:418-455`), a seek near 0 starts at
the first buffered keyframe within 1 s (`:637-644, 1428-1433`; WebKit's
start-gap allowance, `MediaSourcePrivate.cpp:100-111`) and new appends
replace what they overlap (`:1193-1301`), as WebKit's coded frame processing
does. **Same** (the audio splice trim at `:1060-1191` shortens an overlapped
frame where WebKit drops it; the difference stays below the 83 ms gap that
`buffered` merges, so pages don't see it).

### `media_source.cc`

**MS-1. Types without codecs.** Chromium `media_source.cc:530-667` accepts a
type only when it is fully supported (`:658-661`), so
`isTypeSupported('video/mp4')`, `addSourceBuffer('video/mp4')` and
`changeType('audio/mp4')` are refused. WebKit `MediaSource.cpp`
(`isTypeSupported`) accepts a codec-less type the player may support.
**Fixed** 590230f6. Still differing: Safari's type list also has
`video/quicktime`, `audio/x-m4a`, `video/x-m4v`, `audio/3gpp` and
`audio/ogg`, which Parc refuses; init segments on Safari pages accept IAMF,
which Safari doesn't play; and Dolby Vision outside profiles 5 and 8 fails
where Safari plays its HEVC base layer: **fixed** 0095776c (QuickTime,
`x-m4a`/`x-m4v` family, 3GPP, MP3 and AAC aliases accepted; IAMF refused and
dropped from mixed init segments; Dolby Vision 4/7/9 refused in
`addSourceBuffer` and played as their base layer). Still different, each
user-felt and **queued**: Ogg (Opus/Vorbis/FLAC) in Media Source, so a site
fell back or played silent: **fixed** c1371b0e (Safari's accepted types and
0-based packet timing, matched to Safari's parser within 2 µs). Left as
Parc-better or imperceptible (Josh agreed November 7): ambisonic Opus plays
where Safari is silent; headers re-sent after `abort()` aren't decoded as
garbage; a mid-page `abort()` drops the partial page; checksum-failed pages
are skipped; the final FLAC frame's duration follows its header; a mixed
Ogg-plus-video `decodingInfo` query says no;
PCM in MP4 failed: **fixed** bde68ac0 for clear streams (FairPlay-protected PCM
can't play on macOS in Safari either: CoreAudio has no protected PCM decoder,
so it fails with a decode error in both. The real gap, the FairPlay
renderer refusing even clear PCM and EME refusing `ipcm`/`fpcm`, is
**fixed** 49594abf); Dolby Vision 10 (`dav1`), 20, 8.x in `hvc1`
and HLG tagging differed: **fixed** d8f9bace (measured against this Mac's
AVStreamDataParser and AVSampleBufferDisplayLayer). Profiles 4 and 7: Safari
fails to decode them (and refuses them in `isTypeSupported`), Parc plays the
base layer: **kept** (Parc better). `decodingInfo` for `dav1.10`/`dvh1.20`
not matching `isTypeSupported`, and 8.2/10.2 SDR-compatible bases shown as
PQ: **in progress** (MS-4d2). `dav1` on M1/M2 refused by inference
(**unchecked**); real profile 20 content **unchecked**; AMR and H.263 in 3GPP failed: **fixed** 8459d88a (AudioToolbox/VideoToolbox
decoders). Still: `canPlayType` is silent for 3gpp/3gpp2 and samr/sawb/s263
where Safari says maybe or probably; MPEG-4 Part 2 video (`mp4v.20.x`) in
3GPP fails; raw .amr/.awb files don't play: **left**, pending Josh (Safari
identity applies only to learned streaming sites, which don't serve 3GPP). `text/vtt` in `isTypeSupported` differs but no site
appends WebVTT, so no user can perceive it: **left** (Josh agreed November 7: no user can perceive it).
Lowercase `flac`/`opus` in MP4 and Parc's runtime answer for Dolby Vision 8
and `dav1.10` are **unchecked**. AV1 on Macs without hardware AV1 (M1/M2):
Safari refuses it so sites send VP9 or H.264, decoded in hardware; Parc
accepts it and decodes in software: more CPU, battery drain, heat, fan noise
and possibly dropped frames at 1440p60 or 4K, in background tabs and picture
in picture too. **Fixed** 7cd74527 (Josh approved November 7: match Safari; M3 and later
unchanged). A
codec-less TS stream carrying HEVC or AC-3 now gets a SourceBuffer and fails
on append: part of SBS-2.

**MS-2. Duration inside the last frame.** Chromium
`media_source.cc:980-1034` keeps a new duration between the highest
presentation timestamp and the highest buffered end. WebKit
(`setDurationInternal`, step 4.1) raises it to the highest buffered end.
**Fixed** 590230f6.

AC-3/E-AC-3 and Dolby Vision profile 5 answers are **handled**
(`fairplay-identity-blink.patch`). `endOfStream`, `setLiveSeekableRange`,
`seekable` for an infinite duration (`:830-885`), the closed-state and
updating checks and active SourceBuffer ordering follow the MSE spec as
WebKit does. **Same.**

### `source_buffer.cc`

**SB-8. Appending after an element error.** Chromium
`source_buffer.cc:1840-1887` throws `InvalidStateError` from `appendBuffer()`
once the element has an error. WebKit has no such check in
`appendBufferInternal`, but its failed append has already detached the
source, so the next append throws the same error from `isRemoved()`
(`SourceBuffer.cpp:578-581, 600-601, 1092-1113`). **Same** at this point;
the timing difference is MS-3.

**MS-3. A Media Source error closes the source at once.** WebKit's append
error and `endOfStream('decode'|'network')` run the element's failure steps
in the same task (`MediaSource.cpp:609-693, 1338-1344`), which detach the
source: `closed`, `sourceclose`, duration NaN, SourceBuffers removed
(`HTMLMediaElement.cpp:3133-3135, 3177-3179`, `MediaSource.cpp:1052-1106`).
Chromium leaves it `ended` and attached (`media_source.cc:1294-1335`) and
sets `video.error` after a media-thread round trip
(`html_media_element.cc:2115-2140`, which never closes the source;
`pipeline_impl.cc:804-808, 1068-1094`). In its own `error` handler a Safari
page sees `video.error` set and the source closed; a Parc page sees neither,
its next append fails again, and `sourceclose` never fires. **Fixed**
71120cd4.

The init segment checks (`:1472-1763`) are the ones WebKit applies
(`SourceBuffer.cpp:780-1090`) except the codec comparison, which is SBS-1.
`changeType` codecs are MS-1, and Parc's FairPlay codec filter for it is
**handled** (`IsFairPlayChangeTypeSupported`). `abort()`, `remove()`, `mode`,
`timestampOffset` and the append window setters (`:263-585, 761-926`), the
append and remove event sequences (`:2081-2190`) and the append error
algorithm (`:2192-2224`) are WebKit's (`SourceBuffer.cpp` `abort`, `remove`,
`appendError`). **Same.** `appendEncodedChunks`, the `SourceBufferConfig`
`changeType` and `trackDefaults` are behind Chromium flags that are off
(`source_buffer.idl:80-105`), as Safari has none of them. **Same.**
ManagedMediaSource's memory-pressure purge is **handled**
(`fairplay-identity-blink.patch`).
