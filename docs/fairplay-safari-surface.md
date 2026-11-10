# FairPlay web surface

Safari-identity documents expose the media interfaces below, including dedicated
workers where supported. Identity is context-scoped; ordinary Chromium pages
retain their own API and policy behavior. See [identity](fairplay-identity.md),
[FairPlay core](../Engine/ParcNative/fairplay/README.md) and
[native HLS](../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md).

## Modern EME (`com.apple.fps`, `com.apple.fps.N_x`)

`IsFairPlayKeySystem` accepts case-sensitive `com.apple.fps` and names beginning
`com.apple.fps.`. The core supports `cenc`, `sinf`, `skd`, `mpts` and the Parc
`keyids` extension. Init-data naming is distinct from the encryption scheme:
FairPlay capability selection accepts absent/`cbcs` schemes, not `cenc` encryption.

Protected Media Source tracks report `sinf` init data. An attached MediaKeys
session already holding the corresponding request suppresses a duplicate event.
MPEG-TS SAMPLE-AES uses `mpts` and `TransportStreamIdentifier`; native HLS `skd`
requests use the real AVFoundation asset/key-loader path.

A server certificate precedes `generateRequest`. Key status maps usable,
pending, released, internal error and output restriction. Renewal, remove,
load and acknowledgment operate on the actual key session; callbacks are not
failed by an arbitrary license-response timeout. Raw responses follow message
order. Key statuses update immediately while their event waits for the
outstanding update promise to settle.

Temporary and persistent-usage-record sessions follow the configured persistence
policy. Secure-stop reports are origin/top-origin partitioned below the Profile's
FairPlay storage. Private or opaque-origin contexts create no persistent reports.
Persistent-license combinations retain the macOS capability/createMediaKeys
rejection rules rather than promising usable persistent licenses.

`load()` keeps Blink's printable ASCII/512-character session-ID validation.
`closed` retains Chromium's reason-bearing promise; `expiration` is NaN. Main-world
Safari identity hides `getStatusForPolicy`. Empty robustness is supported.
Device-identifier salts follow site-data lifetime and stay in memory privately.

## Capability answers

The browser queries AVFoundation/VideoToolbox instead of trusting a fixed machine
snapshot. HLS capabilities use AVFoundation's actual types; MP4 additionally
requires a supported FairPlay renderer path. Malformed enum values reject the
configuration; malformed individual content capabilities are skipped.

`decodingInfo` uses the Safari result shape, including its echoed configuration,
and ignores `keySystemConfiguration`. Supported codec paths apply native
hardware/HDR/level policy. Spatial audio queries inspect the current output
device. AV1 and `dav1` are refused on Macs without hardware AV1 under Safari
identity, allowing services to choose a hardware-decoded alternative.

Clear and protected FLAC/ALAC and clear Opus/PCM routes are implemented where
the relevant native decoder supports them. Protected Opus and protected PCM
have no corresponding CoreAudio decoder. An EME answer cannot distinguish a
clear sample from a protected sample of the same codec. Current format details
belong to the renderer documentation, not a duplicated codec matrix here.

## Media element timing (native HLS live and DVR)

Native HLS provides live/DVR duration, seekable window, start dates and changes
through `fairplay_hls_timeline` and `NativeHlsDemuxer`. Live duration is infinite
until an actual transition changes it. `getStartDate()` uses the supplied wall
clock date; media without a date returns Invalid Date.

Under Safari identity, assigning positive infinity seeks to the live end;
negative infinity and NaN target zero. `fastSeek` follows keyframe/native
AVPlayer tolerance where available. `preservesPitch`, including false, reaches
both native HLS and the FairPlay renderer; rate zero and non-unit rates retain
their appropriate audio algorithm.

## Legacy prefixed EME (`WebKitMediaKeys`)

The main-world compatibility layer exposes legacy constructor/session methods,
`webkitneedkey`, key message/added/error events and media-key attachment.
Version 2/3 Media Source protocols use the underlying modern FairPlay core;
legacy HLS systems resolve the actual held asset request. Legacy clear key is
limited to its HLS route.

Each legacy Media Source session owns its own modern MediaKeys and secure-stop
lifetime. The latest attached renderer session owns decryption. New loads clear
old init data and held requests. Protocol versions travel with sinf requests;
init-data forms rebuilt by Blink cannot preserve those extra fields.

`webkitneedkey` is raised through the native element bridge. Other compatibility
layer events created by script remain untrusted. Safari-identity EME exposure
and permissions-policy behavior are scoped separately from ordinary Chromium
pages. No service login or subscription access is implied by API availability.

## ManagedMediaSource

ManagedMediaSource includes worker handles, managed buffers, streaming/quality
state and `bufferedchange` timing. Native buffering/eviction drives the real
state rather than a timer pretending that data arrived.

Opening requires `disableRemotePlayback` or an eligible non-blob HLS alternative.
Selecting AirPlay can switch to that alternative. Subsequent loading/CSP and
format edge cases remain in [media follow-ups](safari-media-edges.md).

## Presentation and fullscreen

Presentation APIs bridge the real inline, fullscreen and picture-in-picture
owners, including protected native layers. Frame counters report actual native
statistics. AirPlay uses the system route picker; clear file switching and
selected-track propagation are implemented alongside native HLS.

Picture in picture is user-accepted as complete and is not reopened by this
inventory. Physical Apple TV and licensed-service acceptance must not be inferred
from API, compiler or component checks.

## Native HLS audio and text tracks

Native audio, video and text selection, metadata/DataCue and chapter information
travel through the real HLS player bridge. Blink continues loading out-of-band
`<track>` children itself; they are not installed as AVFoundation alternate
tracks. That integration remains an explicit limitation.

Native asset parsing uses sandboxed parsing and the owning browser loader.
Private assets suppress persistent caching and URL logging. Metadata preload,
readiness and errors follow actual asset/item state.

## Formats and routing

HLS uses GPU-process AVPlayer behind `NativeHlsDemuxer`/`NativeHlsRenderer`.
FairPlay Media Source uses AVSampleBufferDisplayLayer and
AVSampleBufferAudioRenderer. Clear Media Source and ordinary files normally
use Chromium's renderer; a supported late protected/Dolby Vision transition
prerolls the native renderer and hands over on the existing clock.

MediaKeys replacement and clearing are implemented. Detachment holds new
protected samples/requests while already enqueued samples retain their keys.
Reattachment releases held work; retired key sessions live only while a request
or queued SPC still needs them. Unsupported/fallback handoffs remain covered
by the separate follow-up list.

## Departures and validation limits

The following are retained limits, not new runtime findings:

- Output protection rechecks display changes when AVFoundation reports them;
  there is no explicit UI-display-change signal to the GPU key session.
- Native HLS out-of-band tracks remain Blink-owned, as described above.
- Legacy script-generated events are untrusted; Blink session-ID validation and
  the documented init-data extensions remain deliberate API adaptations.
- Renewal uses the last answered key and rejects an SPC failure; that differs
  from an indefinitely unsettled native renewal request.
- Decoder-reset recovery lacks a public trigger for
  `requiresFlushToResumeDecoding`; that path has no live acceptance result.
- Capability coverage for non-FairPlay video and physical output-device changes
  still needs targeted verification; supported-codec results are not a blanket
  assertion about every `decodingInfo` combination.

Tests in `tests/FairPlayIdentity` and native FairPlay components check protocols,
validation, lifetime and fixtures. Compiled Chromium test objects are not executed
Chromium suites. Preserve the [media follow-ups](safari-media-edges.md) and
[backlog](backlog.md) when changing these boundaries.
