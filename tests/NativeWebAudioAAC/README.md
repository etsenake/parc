# WebAudio AAC through the GPU process

Overlay 292 lets WebAudio's `decodeAudioData` decode AAC and M4A. Parc's FFmpeg
has no AAC decoder, so when the renderer's FFmpeg decode fails on AAC,
`blink::PlatformAudioFileDecoder` keeps FFmpeg's demuxing and
`media::AudioFileReader`'s trimming in the renderer and sends each packet to the
GPU process's `AudioToolboxAudioDecoder` through `MojoAudioDecoder`, eight at a
time; `MojoAudioDecoderService` queues them for the decoder. See
[WebAudio `decodeAudioData`](../../docs/engine-flags.md#webaudio-decodeaudiodata).

```sh
python3 tests/NativeWebAudioAAC/run.py /absolute/chromium/src --results /absolute/private/results
python3 tests/NativeWebAudioAAC/run.py /absolute/chromium/src --results /absolute/private/results --compile-only
```

The runner takes `platform-codecs.patch`, `webaudio-aac.patch` and the new
files from the reviewed overlay. Patches the checkout doesn't have yet are
applied in memory; either way the bytes must match the manifest. It compiles
each of these with the actual flags of its target in the engine's ninja files:

- `audio_toolbox_audio_decoder.cc`, `audio_file_reader.cc`, `ffmpeg_common.cc`,
  `mojo_audio_decoder.cc` and `mojo_audio_decoder_service.cc`;
- `platform_audio_file_decoder.cc` and `base_audio_context.cc`, with WebAudio's
  Blink flags. `base_audio_context.cc` is only compiled; turning the result
  into an `AudioBuffer` needs a renderer;
- `webaudio_aac_test.cc`, with `media/mojo/services` flags.

`--compile-only` stops there, which is all that is safe while an engine build
rewrites objects. Otherwise it links the test, with Chromium's own `ld64.lld`
because its static libraries are thin archives, from every input of
`libmedia_mojo_services.dylib` (the patched service in place of the built one),
the patched `MojoAudioDecoder`, Chromium's Mojo media-log object and the
engine's component libraries, including its FFmpeg. Fixtures come from macOS's
`afconvert`: AAC-LC (stereo, mono, 60 s and 10 minutes), HE-AAC and HE-AAC v2
in MP4, and AAC-LC and HE-AAC as raw ADTS. It never invokes GN or Ninja,
starts a browser or launches a helper.

The test checks:

- that FFmpeg still decodes WAV through the reader's synchronous path, and has
  no decoder for AAC, which is what sends AAC to the GPU process;
- each file decoded with the decoder in-process, one decode at a time, and
  behind a real `MojoAudioDecoder` and `MojoAudioDecoderService` on another
  thread with eight in flight, which must return identical audio;
- that the Mojo decode matches macOS's `ExtAudioFile` decode in rate, channels,
  frame count and samples for every file, HE-AAC and HE-AAC v2 included. That
  takes overlay 291's decoder: HE-AAC's last 962 frames, its peaks above 1.0
  and raw ADTS HE-AAC at 44.1 kHz;
- a raw ADTS file cut in half keeps the audio before the cut;
- WAV and random bytes are declined without creating a decoder;
- a GPU process that closes the pipe after 50 packets, one that is never
  reachable, and one that stops answering (with a 2 s watchdog) all fail the
  decode without hanging, and a crash returns no partial audio;
- cancelling stops the decode, with no more than the decodes already in flight
  reaching the GPU process;
- a reset sent straight after ten decodes gets all ten answers, in order,
  before its own, and decoding works afterwards;
- over the service's raw interface: decodes whose data arrives after a failed
  `Initialize()` are each answered `kNotInitialized`, in order, and a read
  that fails behind a decode still in the decoder is answered after it;
- the 10-minute file with 1, 2, 4, 8, 16 and 32 decodes in flight: each
  returns the same audio, at macOS's length, and its time is printed as a
  `TIME` line.

Status, November 1: passed against the built overlay 292 engine, 53 checks and
no failures. The `TIME` results are in
[WebAudio `decodeAudioData`](../../docs/engine-flags.md#webaudio-decodeaudiodata).

Before overlay 291, an AudioToolbox-only probe of the same fixtures showed the
decoder losing HE-AAC's last 962 frames, limiting HE-AAC v2's peaks (1.026
from a source peaking at 0.6) and decoding raw ADTS HE-AAC at its 22,050 Hz
core. Overlay 291 fixed all three, so this check treats any of them as a
failure.
