# Safari identity: waiting for protected media keys

These rules apply to documents presenting Safari identity and follow WebKit's
media-key waiting behavior. Chromium identity keeps its original event path.

- `MediaPlayerPrivateAVFoundationObjC::shouldWaitForLoadingOfResource`,
  lines 2218–2230: a src= key request with a CDM attached finishes loading;
  without one it records the skd identifier and signals waiting. Chromium's
  src= decryptor and Parc's FairPlay Renderer therefore do not turn a stall
  into an element key wait with a CDM attached. Decoder buffering still stalls
  playback when it cannot decrypt; this does not manufacture usable keys.
- `MediaPlayerPrivateAVFoundationObjC::attemptToDecryptWithInstance`,
  lines 3081–3100: an existing native-HLS wait ends only when the attached
  instance has a session for its recorded key identifier (WMPI-2b).
- `CDMInstanceSessionFairPlayStreamingAVFObjC::updateKeyStatuses`, around
  line 1652, notifies the instance for every status change.
  `CDMInstanceFairPlayStreamingAVFObjC::sessionKeyStatusesChanged`, lines
  714–718, calls every status observer. `AudioVideoRendererAVFObjC`'s observer,
  lines 121–124, retries blocked samples. Its `attemptToDecrypt` and
  `canEnqueueSample` also check session and sample keys. Parc's core FairPlay
  renderer already observes every key change; the adapter and Mojo CDM now
  also notify the element for changes with no newly usable key. No fake
  additional-usable-key event is sent to Chromium decryptors.
- `SourceBufferPrivateAVFObjC::didProvideContentKeyRequestInitializationDataForTrackID`,
  lines 358–409, records the result of the renderer's setInitData lookup per
  SourceBuffer. `MediaSourcePrivateAVFObjC::waitingForKey`, lines 206–211,
  returns any-of over all SourceBuffers, including inactive buffers. One
  SourceBuffer finding a session must not restore an element while another
  still waits. This is observable in waitingforkey and readyState, and can
  affect a page that gates play on those events. Parc preserves SourceBuffer
  IDs through the demuxer, aggregates their waits, and removes their state
  with removeSourceBuffer. Playback itself still requires usable sample keys.

Checks carry monotonically increasing tokens. New init data, removal, CDM
detach, successful replacement and failed attachment invalidate old answers.
Invalidation precedes releasing a CDM, whose destruction can answer queries
synchronously. Detach retains established waiting state. Only a new init-data
request may emit encrypted or start a SourceBuffer wait; status rechecks can
end an existing wait but cannot replay encrypted for resolved init data.

The same policy applies in picture in picture, background tabs, and fullscreen;
no presentation path bypasses the element's aggregate. Native HLS and FairPlay
remain gated to Safari identity. This change does not modify casting, Now
Playing, output protection policy, or renderer/sample scheduling.

## Verification

The owned `ParcWebMediaPlayerImplTest` suite covers attached src= stalls,
two independently blocked SourceBuffers, status updates with no additional
usable keys, removal with a check pending, successful and failed replacement,
detach with a success in flight, and suppression of delayed encrypted events.
The owned media-element suite covers waiting and ready-state behavior through
the Parc supplement, and the owned chunk-demuxer suite covers buffer identity
on removal. These suites install beside their Blink and media layers and run
through those layers' normal test binaries.

The overlay source checks run with:

```sh
PYTHONPATH=tests/EngineSource python3 -m unittest tests.EngineSource.test_overlays
```

Compile the affected Chromium test targets with the pinned generated headers
and target flags. Keep execution receipts in ignored check output.
