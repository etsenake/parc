# macOS AAC decoding through AudioToolbox

Parc routes every AAC profile to Chromium's `AudioToolboxAudioDecoder`,
which runs in the GPU process behind `MojoAudioDecoder`. Parc's FFmpeg has no
AAC decoder, so `FFmpegAudioDecoder` declines AAC first. The overlay also gives
FFmpeg-demuxed AAC a sample format and adds FFmpeg's raw ADTS demuxer and AAC
parser (no decoder) for `src=`. The decoder finds implicitly
signalled HE-AAC in the first access unit. See
[the macOS codec route](../../docs/engine-flags.md#macos-codec-route) for the
design.

```sh
python3 tests/NativePlatformCodecs/run.py /absolute/chromium/src --results /absolute/private/results
```

The runner takes the decoder, `ffmpeg_common.cc`, the ADTS demuxer and the
FFmpeg configuration from the reviewed overlay. It works file by file, so the
checkout may mix patched, pristine and earlier-overlay files. It takes each
file's pristine bytes from the checkout when they match the manifest's before-digest. Otherwise it reads them,
read-only, with `git show HEAD:` from the Git checkout that holds the file. It
applies `platform-codecs.patch` to them in memory, and every result must match
the manifest's after-digest.

It compiles, each with the actual flags of its target in the current dev
engine's ninja files:

- the patched decoder;
- `ffmpeg_common.cc`;
- `aac_decoder_test.cc`;
- the FFmpeg units the configuration change adds or alters.

It links them with the rest of the completed FFmpeg objects, as `libffmpeg`
links them, and with the `libmedia` and `libbase` component libraries.
Fixtures come from macOS's `afconvert`: AAC-LC, HE-AAC and HE-AAC v2, each as
MP4 and ADTS, plus mono AAC-LC, mono HE-AAC without parametric stereo, 5.1
HE-AAC, and AAC-LC encoded at 22.05 kHz in stereo and mono. ADTS can't signal SBR, so the
HE-AAC ADTS files are implicitly signalled. afconvert's MP4s signal SBR
explicitly, so `run.py` also writes copies whose esds config is just the
two-byte AAC-LC core. A `free` box absorbs the size change, so the chunk offsets
still hold. afconvert also writes macOS's own decoding of the HE-AAC and
HE-AAC v2 ADTS files and of the HE-AAC, HE-AAC v2 and AAC-LC MP4s, as 32-bit
float WAV. That decoding includes the decoder's tail and each MP4's priming and
remainder, and `run.py` converts it to planar samples. MP4 access units for the
direct cases are extracted in Python so nothing touches AudioToolbox before a
sandbox applies.
Everything is written to the results directory. It never invokes GN or Ninja,
initializes a browser or launches a helper.

The binary feeds the decoder AAC the way each Chromium path delivers it:

- `src=`: FFmpeg demuxes MP4 and raw ADTS with FFmpegGlue's settings, and
  Chromium's AVStream conversion builds the config. With no AAC decoder in
  FFmpeg, the sample format is unset. Every packet must carry a defined,
  increasing PTS, which the decoder receives as `FFmpegDemuxer` would stamp
  it. The output keeps the config's rate, except that implicitly signalled
  HE-AAC doubles a core of 24 kHz or less. The patched renderer accepts that
  change.
- FFmpeg's and Chromium's MP4 parsing: raw access units, the esds
  AudioSpecificConfig, and the SBR rate when the config signals it.
- MPEG-2 TS (HLS, MSE `video/mp2t`) and MSE `audio/aac`: whole ADTS frames and
  the two-byte config. MPEG-2 TS doubles the rate when the codec string names
  SBR; MSE `audio/aac` always takes the header's rate (the "without an SBR
  hint" cases).
- WebCodecs without a description: ADTS chunks and no config.

It checks the output rate, channel count, frame count, timestamps, tone
separation and 12–20 kHz energy (which only SBR restores), plus decoding across
`Reset()`. Implicitly signalled HE-AAC must come out as FFmpeg's decoder gives
it: twice the core rate, and stereo for a mono core, with both channels equal
when there is no parametric stereo data. AAC-LC at the same core rates must stay
AAC-LC, and so must a config that signals SBR absent. HE-AAC frames after an
AAC-LC first frame must not switch the stream. Implicit HE-AAC must decode
exactly as it does with an `mp4a.40.5` hint, start at the first packet's
timestamp and keep its core tones aligned with the AAC-LC core it used to play.
It must decide correctly after `Reset()`, an empty buffer, or end of stream
followed by `Reset()`, with and without a config. AAC-LC first frames must keep
the stream AAC-LC across a later `Reset()`. A first access unit that can't be
judged, one byte, a header-only frame or half an access unit, must leave the
decision to the next, which then finds HE-AAC.

HE-AAC must equal macOS's own decoding sample for sample, and so must AAC-LC.
That covers implicit ADTS with and without a description, including the
decoder's last 962 frames. It covers `src=` MP4s with FFmpegDemuxer's real
priming and remainder, including implicit MP4 against macOS's decoding of the
explicit file. It also covers synthetic padding: 3,000 frames of priming with
500 of remainder, and one whole access unit discarded. HE-AAC v2's decoded
peaks above 1.0 must survive, since AAC-LC and HE-AAC aren't limited. An empty
buffer right after the first access unit mustn't move the first timestamp.
Only AAC-LC and HE-AAC configs may drain AudioToolbox at end of stream;
xHE-AAC and AC-3 configs must keep upstream's end of stream.

Damaged first access units include
random, truncated, bit-damaged and one-byte ones, the longest ADTS payload, and
a raw access unit too long to reframe. Each must decode at one rate, 22.05 kHz
(AAC-LC) or 44.1 kHz (HE-AAC), or fail cleanly, and never crash. Raw AAC without a config must fail, and so must multi-block ADTS
frames, which Parc refuses where FFmpeg's decoder decoded only their first
block. Header-only ADTS frames (7 bytes, or 8 bytes claiming a CRC) must be
refused without a description and must not crash a configured decoder.
`Decode()` after a failed `Initialize()` must fail and `Reset()` must complete,
since Mojo forwards both. It
then runs again after applying Chromium's own `common.sb` + `gpu.sb` seatbelt
profile in-process, with Chromium's helper parameters. It runs once more under
`common.sb` + `renderer.sb`, where AudioToolbox must refuse the stream.

The GPU seatbelt profile permits the native decoder, while the renderer profile
refuses it. Fixture tones distinguish AAC-LC from SBR output and compare the
result with macOS decoding sample for sample; the test is not a listening test.

The [WebAudio fixture](../NativeWebAudioAAC/README.md) covers the Mojo transport,
queueing, cancellation and decoder output across that boundary.
