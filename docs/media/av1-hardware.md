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

## Source contract

The capability fact comes from VideoToolbox before renderer sandboxing, and is
shared with workers. The implementation gates API queries, parser admission and
later player configuration changes; checking only `isTypeSupported` would miss
undeclared media. WebKit's AV1/WebM and platform media capability paths provide
the platform-facing contract. MP4 file playback also depends on AVFoundation
rather than Chromium's software AV1 decoder.

Hardware-present profile/level/chroma/depth checks retain their existing owners.
This gate is not a processor-name heuristic and does not depend on tab visibility,
PiP, casting or capture state.

## Checks

The API matrix covers both hardware states, both identities, MP4/WebM,
canPlayType and all three MSE entry points. A decodingInfo matrix covers both
identities/hardware states for file and MediaSource. Player tests cover
undeclared AV1 refusal and the Chrome bypass. The injected hardware result
uses a scoped process command line, restored after each test.

These regressions live in the Blink/player changes in
`Engine/ParcHost/integration/fairplay-identity-blink-direct.patch` and
`fairplay-media.patch`. `tests/FairPlayIdentity` also covers the renderer gate.
