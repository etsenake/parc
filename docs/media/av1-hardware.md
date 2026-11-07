# AV1 under Safari's identity

Safari-identity documents require VideoToolbox hardware AV1 support. The
browser asks `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` once and
passes the result on the renderer command line before sandboxing. Renderers
share that immutable machine fact with their workers. No processor names or
site names participate. Chrome-identity documents retain Chromium's answers.

Without hardware, `canPlayType` returns empty, `MediaSource.isTypeSupported`
returns false, `addSourceBuffer` and `changeType` reject AV1, and
`MediaCapabilities.decodingInfo` returns unsupported, not smooth and not power
efficient. Codec negotiation can choose VP9 or H.264. Undeclared AV1 in a file
or MediaSource is stopped when metadata identifies it; a later AV1 video
configuration is stopped too. These checks do not depend on visibility,
background state, picture in picture or remote-rendering state. Hardware AV1
keeps the previous paths. FairPlay's existing codec restrictions remain.

## WebKit evidence

Reference: WebKit main `db2d79f4`, retained sparse checkout
`work/safari-media-audit-src/webkit-main`. Paths below are relative to
`Source/WebCore`.

- `platform/graphics/cocoa/AV1UtilitiesCocoa.mm:230-235` implements
  `av1HardwareDecoderAvailableInProcess`: a soft-link availability check and
  `VTIsHardwareDecodeSupported('av01')`. Lines 188-227 cache/deliver the
  browser/GPU process fact with a test override.
- `platform/graphics/cocoa/SourceBufferParserWebM.cpp:1546-1555` accepts an
  `av01.` codec only with that hardware fact. Lines 838-854 construct AV1
  track data only with hardware; otherwise the track is unsupported, and
  lines 977-987 skip its blocks rather than decoding them in software.
- `Modules/mediasource/MediaSource.cpp:696-719,963-1018` uses type support for
  `isTypeSupported` and `addSourceBuffer`.
  `Modules/mediasource/SourceBuffer.cpp:470-499` checks parser switch support
  for `changeType`.
- `html/HTMLMediaElement.cpp:1587-1616` delegates `canPlayType` to the selected
  media engine. `platform/graphics/avfoundation/objc/MediaPlayerPrivateMediaSourceAVFObjC.mm:207-222`
  delegates MSE types to SourceBufferParser.
- MP4 does not contain an additional explicit AV1 hardware predicate in these
  WebKit entry points. `platform/graphics/avfoundation/objc/SourceBufferParserAVFObjC.mm:204-213`
  uses AVStreamDataParserMIMETypeCache; that cache's lines 67-114 consult the
  asset cache. `AVAssetMIMETypeCache.mm:canDecodeExtendedType` asks
  `AVURLAsset.isPlayableExtendedMIMEType`.
  `MediaPlayerPrivateAVFoundationObjC.mm:2112-2146` selects file playback using
  that asset cache and AVFoundation. WebKit does not install Chromium's
  software AV1 decoder on this file path. The no-hardware MP4 platform answer
  is Josh's supplied Safari observation; it was not remeasured on an M1/M2.
- `platform/graphics/cocoa/PlatformMediaEngineConfigurationFactoryCocoa.cpp:63-88,138-145`
  first requires media-engine support, then validates AV1 parameters through
  `AV1UtilitiesCocoa.mm:72-180`, including the platform's profiles, levels,
  chroma and color-depth capabilities. This edge adds the missing hardware
  refusal; existing hardware-present profile/performance answers are unchanged.

## Validation boundary

The API matrix covers both hardware states, both identities, MP4/WebM,
canPlayType and all three MSE entry points. A decodingInfo matrix covers both
identities/hardware states for file and MediaSource. Player tests cover
undeclared AV1 refusal and the Chrome bypass. The injected hardware result
uses a scoped process command line, restored after each test.

All modified translation units and tests are compiled with compile_copy.sh
and shipping engine flags. Chromium test executables are unavailable here:
tests are not linked or run. Scratch generated playback-controls enum/interface
stand-ins cover the existing generated-header lag and are not in the overlay.
An inert AVFoundation probe on this hardware-capable Mac returned hardware=1,
MP4 AV1 playable=1, WebM AVURLAsset playable=0 (WebKit supplies its WebM parser).
No browser, PiP, casting, FairPlay playback, battery or frame-drop measurement
was run. This source change requires the next engine build to reach users.
