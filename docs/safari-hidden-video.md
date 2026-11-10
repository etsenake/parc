# Safari identity and hidden playing video

Safari-identity pages keep their selected video track while playing in the
background. This applies to clear URL and Media Source playback. Autoplay,
media-session interruptions and protected-canvas policy remain separate owners.

## Playback ownership

Chromium's `WebMediaPlayerImpl::UpdateBackgroundVideoOptimizationState` schedules
a ten-second task. Ordinarily `DisableVideoTrackIfNeeded` can deselect video
while audio continues, and foregrounding reselects it through
`EnableVideoTrackIfNeeded`.

Parc's Safari-identity check in `ShouldDisableVideoWhenHidden` prevents that
track-disable/reselect cycle. Chrome-identity pages retain Chromium's existing
streaming, picture-in-picture, capture, flinging and keyframe eligibility rules.
The implementation and paired identity regressions live in
`Engine/ParcHost/integration/fairplay-media.patch`.

FairPlay Media Source and native HLS already have renderer-specific exemptions.
FairPlay uses the sample-buffer renderer; native HLS uses AVPlayer, which owns its
media streams. They do not enter Chromium's hidden-track disabling path.

## Presentation and cost

WebKit's macOS players can detach their presentation layer or switch eligible
Media Source playback to a renderless decoder while hidden. They keep the
selected video track; their private AVFoundation scheduling is separate from
that visible source behavior.

Parc's Chromium clear renderer keeps decoding instead of reproducing WebKit's
AVFoundation-specific presentation teardown. This uses more decoder/GPU work
and frame-buffer bandwidth than audio-only playback. Hardware acceleration,
resolution, codec and frame rate determine the cost. The identity exemption
does not change the FairPlay, HLS or Chrome-identity paths.

## Checks

The Blink player regressions cover Safari and Chrome identities with URL and
Media Source playback, varying keyframe distances, picture in picture, capture
and feature flags. Safari cases reject hidden-track disabling; Chrome cases
retain the original eligibility expression. `tests/EngineSource/test_overlays.py`
checks the source overlay structure.
