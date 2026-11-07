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

## Reading log

| File | Pristine lines | Read through |
|---|---:|---:|
| `third_party/blink/renderer/core/html/media/html_media_element.cc` | 5,504 | 5,504 |
| `third_party/blink/renderer/platform/media/web_media_player_impl.cc` | 4,242 | 4,242 |
| `media/base/pipeline_impl.cc` | 1,861 | 0 |
| `media/filters/pipeline_controller.cc` | 478 | 0 |
| `media/filters/chunk_demuxer.cc` | 1,658 | 0 |
| `media/filters/source_buffer_state.cc` | 931 | 0 |
| `media/filters/source_buffer_stream.cc` | 2,029 | 0 |
| `third_party/blink/renderer/modules/mediasource/media_source.cc` | 1,652 | 0 |
| `third_party/blink/renderer/modules/mediasource/source_buffer.cc` | 2,237 | 0 |

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
Parc and carry on in Safari. **Open.**

**HME-2. `muted` content attribute set by script.** Chromium
`html_media_element.cc:852-856, 878-886`: the attribute sets `muted` only when
the parser creates it or `cloneNode` copies it
(`MediaElementMutedDefaultState` is experimental, off). WebKit
`HTMLMediaElement.cpp:1188-1192` (`postConnectionSteps`) and `:2199-2203`
(`loadResource`): until script sets `muted`, the attribute decides it at the
first connection or load. A video built by script with
`setAttribute('muted', '')` is muted in Safari, so muted autoplay starts and
it makes no sound; in Parc it was unmuted, so autoplay could be refused or it
played sound. **In progress** (fix agent E1).

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

HME-3 to HME-6 and HME-17: **in progress** (fix agent E2, load algorithm).

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
**handled** (a13b5579). Media Source **in progress** (fix agent MSE-RS).

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

HME-8 to HME-12: **in progress** (fix agent E3, seek algorithm).

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

HME-13, HME-15, HME-16: **in progress** (fix agent E4, time and rate).

**HME-17. The last `progress` before `suspend`.** Chromium
`html_media_element.cc:2268-2283` fires it only if the player made progress
since the last check. WebKit `HTMLMediaElement.cpp:3335-3344` always fires
one `progress`, then `suspend`.

**HME-18. `progress` and `stalled` on Media Source.** Chromium
`html_media_element.cc:2530-2585` fires `progress` every 350 ms that data
arrived on a Media Source element. WebKit `HTMLMediaElement.cpp:3962-3994`
asks the player, and Safari's Media Source player doesn't support progress
monitoring (`MediaPlayerPrivateMediaSourceAVFObjC.mm:1594-1598`), so a Media
Source element gets no periodic `progress` (or `stalled`). **In progress**
(fix agent E2).

**HME-19. Default `preload`.** Chromium `html_media_element.cc:3074-3111`
makes a missing or invalid `preload` metadata (and forces metadata on
cellular). WebKit `HTMLMediaElement.cpp:1094-1104` and
`HTMLMediaElement.h:1365` make it auto. A plain `<video src>` reports
`preload` "auto" in Safari and buffers ahead to `canplaythrough` without
`play()`; Parc reported "metadata" and stopped after metadata. Native HLS
already prepares to play as WebKit does (`ParcPreparesToPlay`); the rest
**in progress** (fix agent E5).

**HME-20. `muted` before script sets it.** WebKit
`HTMLMediaElement.cpp:5102-5111` returns the content attribute itself until
`muted` is set by script or latched at connection or load. Part of HME-2,
**in progress** (fix agent E1).

**HME-21. Non-periodic `timeupdate`.** Chromium
`html_media_element.cc:3527-3550` fires every non-periodic `timeupdate`
(pause, waiting, load reset). WebKit `HTMLMediaElement.cpp:5383-5417` fires
any `timeupdate` only when the time differs from the last one's (seek
completion and load reset bypass it), so `pause()` at an unchanged time
fires none. **In progress** (fix agent E5).

**HME-22. Autoplay policy.** Chromium `html_media_element.cc:3161-3196`
asks `AutoplayPolicy::RequestPlay` (Chromium's document user activation,
sticky for the frame, plus media engagement). WebKit
`HTMLMediaElement.cpp:4687-4718` asks `MediaElementSession::playbackStateChangePermitted`
(`MediaElementSession.cpp:463-568`): with Safari's default policy, audible
playback needs a user gesture being processed now, or an element a gesture
already unlocked. **Open** (with Josh: whether Safari-mode pages take Safari's
stricter rule).

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

HME-23 to HME-25: **in progress** (fix agent E6).

**HME-26. Frozen and back/forward cache.** Chromium
`html_media_element.cc:4388-4398` pauses on a frozen frame (`pause` event,
play promise rejected, stays paused when thawed). WebKit
`HTMLMediaElement.cpp:7401-7452, 7336-7366` stops a page entering the
back/forward cache without events and resumes it when the page returns
(`setPausedInternal(false)`), and does nothing for other suspensions. Going
back to a page with a playing video: Safari carries on, Parc shows it paused
after a `pause` event. **In progress** (fix agent E7).

**HME-27. Error and rejection messages.** Chromium builds `MediaError.message`
as `MEDIA_ELEMENT_ERROR: …` (`html_media_element.cc:262-273`) and
play-promise rejections with its own texts (`:4988-5040, 5301-5310`). WebKit
uses the player's last error message or "Unsupported source type"
(`HTMLMediaElement.cpp:3113-3117`), "Media failed to load"/"decode" with the
player's message (`:3155-3173`), "The operation is not supported." for
`play()` after `MEDIA_ERR_SRC_NOT_SUPPORTED` (`:4701-4705`) and no message
otherwise. **In progress** (fix agent E8).

**HME-28. `media-playback-while-not-visible`.** Chromium
`html_media_element.cc:702-708, 3139-3145, 5253-5299` honours this
permissions policy (pausing hidden frames, deferring `play()` until
visibility is known). WebKit has no such policy. **In progress** (fix agent
E6).

### `web_media_player_impl.cc`

**WMPI-1. Seeks on `src=` files.** Chromium `web_media_player_impl.cc:1118-1211`
drops `readyState` to `HAVE_METADATA` at every seek and completes it at the
renderer's next `BUFFERING_HAVE_ENOUGH` (`:1857-1903, 2345-2442`), so a
playing file fires `waiting`, `canplay`, `playing` and `canplaythrough` on
every seek. WebKit's AVFoundation player keeps `readyState` from the item's
status (`MediaPlayerPrivateAVFoundation.cpp`, `updateStates`) and the element
finishes the seek when the player's seek resolves
(`HTMLMediaElement.cpp:4180-4360`). Media Source is HME-7; native HLS
**handled** (a13b5579). **In progress** (fix agent WMPI-1).

**WMPI-2. Waiting for a key.** Chromium `web_media_player_impl.cc:2457-2494`
reports block and resume together for every wait and Blink's element never
changes `readyState`. WebKit `HTMLMediaElement.cpp`
(`mediaPlayerWaitingForKeyChanged`) runs Wait for Key once per blocked
episode: `readyState` to `HAVE_CURRENT_DATA` or `HAVE_METADATA`, then
`waitingforkey`, restored when the key arrives; native HLS waits only for a
key request with no CDM attached
(`MediaPlayerPrivateAVFoundationObjC.mm:2210-2235, 3090-3110`). Media Source
key timing **handled** (35589317); the `readyState` drop and the native HLS
rule **in progress** (fix agent WMPI-2).

**WMPI-3. Hidden pages pause video.** Chromium
`web_media_player_impl.cc:3744-3787, 3825-3870, 3528-3551, 2643-2714` pauses
video without unmuted audio when its page or frame is hidden (the page sees
`pause` and a rejected play promise) and resumes it when shown. WebKit on
macOS pauses nothing for being hidden (`InvisibleAutoplayNotPermitted` and
`RequiresPageVisibilityToPlayAudio` are iOS-only:
`UnifiedWebPreferences.yaml:3348-3365, 5281-5303`;
`HTMLMediaElement.cpp:733-741`). A muted video in a background tab keeps
playing in Safari. **In progress** (fix agent WMPI-3).

**WMPI-4. Servers without range requests.** Chromium
`web_media_player_impl.cc:1494-1515` plays a file from a server that ignores
range requests and makes it unseekable (seekable `[0, 0]`), and gives live
content no seekable range. Safari loads files through AVFoundation, which
needs range requests for such files. **Open** (with Josh).

**WMPI-5. `setMediaKeys(null)`.** Chromium
`web_media_player_impl.cc:1662-1687` refuses to clear a CDM; Parc accepts it
on Safari-identity FairPlay players but keeps decrypting with the old CDM
(14ce748a). WebKit detaches it (`HTMLMediaElement.cpp` `setMediaKeys`,
`MediaPlayerPrivateMediaSourceAVFObjC.mm:1162-1166`,
`MediaPlayerPrivateAVFoundationObjC.mm:3060-3080`), so samples after that
wait for a key. **In progress** (fix agent WMPI-5).
