
1.170 and Parc both use Chromium **156.0.8078.48**, so each difference is a

`0xe10f478` (applied at `0x45922b4`, with code overrides at `0x4592384`) and its
engine-flag table at `0xdff3750`. Parc's side comes from
`Engine/source-lock.json` `gn_defines` (dev), `SHIPPING_DEFINES` in
`scripts/engine-source.py` (shipping), generated `buildflags.h` headers and
`Engine/ParcNative/native_startup_policy.h`. Confidence is **D** where a value
was read from the binary and **I** where it is inferred. The full working
report (ignored, local) is `work/cursor-flag-diff/REPORT.md`.

## Decisions (Josh, November 1)

| Change | Decision | State |
|---|---|---|
| DCHECKs and the testing field-trial config off | Adopted (`9080b3f1`) | In the dev engine rebuilt November 1 |
| Proprietary codecs, decoded and encoded by macOS rather than bundled FFmpeg/OpenH264 code | Adopt (November 1) | In the dev engine (overlay 287 and the source-lock defines, built November 1). See [macOS codec route](#macos-codec-route) |
| `enable_hangout_services_extension` | Adopt (November 1) | In the dev engine (source-lock define, built with the codecs) |
| WebAudio `decodeAudioData` of AAC/M4A through the GPU process's AudioToolbox decoder, renderer sandbox unchanged | Adopt (November 1) | In the dev engine (overlay 292). See [WebAudio `decodeAudioData`](#webaudio-decodeaudiodata) |
| `MallocNanoZone=0` on the main app | Adopt | In every package since overlay 282 (`scripts/build.py`) |
| Back/forward cache | Keep on, then measure | Unchanged |
| Official build, LTO, PGO, stripping | Shipping engine only | `SHIPPING_DEFINES` sets `is_official_build=true` (ThinLTO, stripped) with `chrome_pgo_phase=0`: the PGO profile is a separate gclient download the lock doesn't pin. No dSYM yet (`enable_dsyms=false`, workspace symbol level 0). First shipping build November 1–2 |
| Page translation | Exclude: Chrome's translate service needs a Google API key | In the dev engine (overlay 282, `disable-translate-trigger`) ([details](#page-translation)) |
| Safe Browsing without a Google API key | Keep; it is inert without a key | Unchanged |
| On-device search suggestions (`OmniboxOnDeviceHeadProvider*`) | Re-enable: the model comes through the component updater and needs no key | In the dev engine (overlay 282) |
| Web Translator API (`TranslationAPI`) | Keep on: websites call it, it runs on-device models and needs no key | Unchanged |

Parc must not depend on Google API keys or paid Google services, because Josh
intends to open-source it.

Overlay 282 (`ac7a815f`) carried the runtime feature overrides, translation
off, on-device search suggestions and `MallocNanoZone`; every engine built
since includes them.

## Build arguments (GN)

|---|---|---|---|---|---|
| `is_official_build` | Chromium's release recipe on Mac: ThinLTO, PGO, zero-initialised stack variables, message-free CHECKs, stripping | true (D: no function-starts or data-in-code load commands, stripped) | false | true | Shipping only. Never for dev: every rebuild would relink with LTO |
| `use_thin_lto` | Whole-program optimisation at link time | true (I, follows from official) | false | true | Comes with official for shipping |
| `chrome_pgo_phase` | Optimise with Chrome's recorded execution profile | probably 2 (I) | 0 | 0 | Off for now: official builds otherwise require the profile, which needs `checkout_pgo_profiles=True` in the generated `.gclient` (refused by `verify_workspace`) and a download |
| `symbol_level`, `enable_dsyms`, `enable_stripping` | Debug info, dSYM, stripped binary | stripped (D); dSYM kept privately (I) | 0, false, unstripped | 0, false, stripped | Shipping stays at the workspace's symbol level 0 for now; the stripped build leaves `Chromium Embedded Framework.unstripped` beside it as the only symbol source. A level 1 build with a dSYM needs `shipping_build` to accept another symbol level |
| `is_component_build` | ~500 dylibs instead of one framework | false (D) | true | false | No change. Component builds make incremental rebuilds cheap; never measure performance on them |
| `use_partition_alloc_as_malloc`, BackupRefPtr | PartitionAlloc for every allocation, plus dangling-pointer protection | on (D) | off (forced by component builds) | on | No change. Dev memory numbers don't predict shipping |
| `proprietary_codecs`, `ffmpeg_branding`, `enable_ffmpeg_video_decoders`, `media_use_openh264` | H.264/HEVC/AAC in MP4, MSE and HLS, HEVC hardware decode, WebRTC H.264. MP3 already plays without them | on; FFmpeg without its H.264 and AAC decoders but with an AudioToolbox AAC decoder; OpenH264 bundled (D) | off, Chromium, true, false | same | Adopt through macOS's decoders: on, Chromium, false, false. Without it H.264/AAC video fails on many sites. See [macOS codec route](#macos-codec-route) |
| `enable_hangout_services_extension` | Google Meet's private diagnostics extension | on (D) | off | off | Adopt (November 1); rides with the codec rebuild |
| `dcheck_always_on`, `disable_fieldtrial_testing_config` | Debug assertions; Chromium's bundled experiment config | off, off (D) | off, off (since `9080b3f1`) | off, off | Done. This also turns off forced ANGLE validation |

## Packaging

|---|---|---|---|---|
| `LSEnvironment` `MallocNanoZone=0` on the main app | Turns off the nano allocator. Helpers inherit the browser's environment, so only the main app's entry has an effect | set (D) | set on the main app and helpers in `scripts/build.py`; takes effect at the next package | Adopt |

## Runtime features

`parc::ApplyNativeStartupPolicy`. "Parc" is the current state.

|---|---|---|---|---|
| `CertificateTransparencyAskBeforeEnabling` | Turns on Certificate Transparency enforcement, which non-Google-branded builds leave off | on (D) | off | Adopt. Enforcement switches itself off if the log list is 70+ days stale |
| `MacAppCodeSignClone`, `MacAppCodeSignCloneRenameAsBundle` | Clones the app at launch for staged updates and spawns a cleanup helper at quit | off (D) | on | Adopt. Parc has no updater |
| `FedCm` | Browser "Sign in with Google" chooser, drawn as a Views bubble that Parc can't host | off (D) | on | Adopt. Sites fall back to popup or redirect sign-in |
| `AutofillServerCommunication` | Sends form signatures to Google; can't work without an API key | off (D) | on | Adopt. Local autofill is unaffected |
| `ServiceWorkerAutoPreload` | Fetches subresources while a Service Worker starts | off (D) | on | Keep on (upstream performance default) |
| `PreloadMediaEngagementData` | Lets popular sites autoplay with sound in a new profile | off (D) | on | Adopt for parity |
| `BrowsingTopics` | Privacy Sandbox Topics classification of browsing history | off (D) | on | Adopt |
| `EnforcePrivacySandboxAttestations` | Limits Privacy Sandbox APIs to attested sites | off (D) | on | Keep on; it is the safer gate |
| `NetworkTimeServiceQuerying` | Asks Google's time service to detect a wrong clock | off (D) | on | Adopt |
| `Glic` | Gemini in Chrome plumbing | off (D) | on | Adopt (AI group) |
| `LensOverlay` | Google Lens screen search | off (D) | off by pinned CEF in the browser process | Adopt explicitly (AI group) |
| `LiveCaption` | On-device live captions | off (D) | on | Adopt for parity; macOS dictation is unaffected |
| `MerchantTrust`, `PageInfoAboutThisSite`, `PageInfoAboutThisSiteMoreLangs` | Google-backed Page Info panels | off (D) | on, on, off | Adopt |
| `TailoredSecurityIntegration` | Syncs Enhanced Safe Browsing from a Google account | off (D) | on | Adopt. Ordinary Safe Browsing is unaffected |
| `OmniboxOnDeviceHeadProvider*` | On-device search-suggestion model, delivered by the component updater | on (D) | off | Re-enable, and add the provider to Parc's command bar |
| `HistoryEmbeddings` | History embeddings | off (D) | off | Keep Parc's committed exclusion |
| `TranslateRankerQuery`, `TranslateRankerEnforcement` | Downloaded model that decides whether to offer translation | not overridden | on | Turn off with page translation |

## Page translation

Chrome's page translation calls Google's translate service, which needs a Google
API key. Parc ships none and won't pay for one, so translation is excluded.
Chromium already refuses to offer or perform it without a key
(`TranslateManager::CanManuallyTranslate` and `FilterIsTranslatePossible`), but a
key can still arrive at runtime through the `GOOGLE_API_KEY` environment
variable or an Info.plist entry (`google_apis/api_key_cache.cc`). Overlay 282
therefore closes each entry point directly:

| Entry point | Where it starts | Parc |
|---|---|---|
| Automatic offer, including `hrefTranslate`, predefined-target and always-translate | `TranslateManager::ComputePossibleOutcomes` (`translate_manager.cc:870`) | `--disable-translate-trigger` prevents every outcome before the ranker is queried |
| Translate ranker model download | `TranslateRankerImpl` creates its model loader when either ranker feature is on | Both ranker features are product exclusions, so no loader exists |
| `translate.enabled` (`kOfferTranslateEnabled`), default on in `browser_ui_prefs.cc` | Profile preference registry | `OnRegisterCustomPreferences` sets its default to off with CEF's `SetDefaultPreference`; user and managed values still take precedence |
| Page menu **Translate** and **Translate selection** | `RenderViewContextMenu` | Parc's page menu removes both items |
| Translate bubble | `BrowserWindow::ShowTranslateBubble` | `NativeBrowserWindow` refuses it; Parc's translate popover (`native_translate.mm`) is removed |
| `IDC_SHOW_TRANSLATE` | `chrome::ShowTranslateBubble` | Nothing in Parc dispatches it (no Chrome app menu or accelerator), and the bubble is refused |
| Omnibox Translate action | `ChromeAutocompleteProviderClient::PromptPageTranslation` | Parc's command bar never runs a match's actions |
| Settings **Reset Translated-site Prompts** | `SettingsWindow.swift` and `PCNativeBrowserApplication (TranslationPreferences)` | Removed |
| `chrome://settings/languages` **Use Google Translate** | Chrome WebUI | Still shown, off by default. Turning it on can't translate anything. The page fetches the supported-language list from the translate server once |
| `chrome://translate-internals` | Chrome debug WebUI | Shows state only; it can't start a translation |

Page language detection stays: Autofill reads the page language through
`ChromeAutofillClient::GetLanguageState`. The web Translator API
(`TranslationAPI`, stable on Mac) is separate from page translation: websites
call it, and it runs Google's on-device TranslateKit models from the component
updater without an API key. It stays on (Josh, November 1).

## Same in both

DCHECKs and the field-trial testing config (once the November 1 dev engine is
packaged), Widevine through the component updater with host verification
compiled in ([details](#widevine)), PDF, printing, extensions, Safe
Browsing, AV1/VP9, V8 pointer compression and sandbox, no embedded Google API
`LocationProviderManager` and disables `ContextualCueingV2`, `ContextualTasks`,
`Indigo` and `PageContentCache`, all of which already have those defaults in

## macOS codec route

Josh decided on November 1 that Parc plays H.264, HEVC and AAC through macOS's
own decoders and encoders. Parc is to be open source and won't pay codec
licence fees, so it bundles neither FFmpeg's H.264/AAC decoders nor the OpenH264
encoder. The change is overlay 287 (`Engine/ParcHost/integration/platform-codecs.patch`)
plus the source-lock defines `proprietary_codecs=true ffmpeg_branding="Chromium"
enable_ffmpeg_video_decoders=false media_use_openh264=false`. In Chromium builds
`media_use_openh264` also sets `rtc_use_h264`.


(`h264dec.c`, `h264_slice.c`, `h264_refs.c`) or AAC decoder
(`libavcodec/aac/aacdec.c`) appears; their messages are missing too. FFmpeg's
H.264 parser, MP4 demuxer and raw ADTS demuxer are present, as are MP3, FLAC,
Vorbis, Opus and PCM. The earlier "FFmpeg's H.264 decoder is present" reading
came from `non-existing PPS %u referenced`, which `h264_parser.c` also prints.
That the base was Chrome's FFmpeg configuration minus two decoders is
inferred from those parser and demuxer leftovers.

For AAC, `arc/third_party/platform_media/ffmpeg/audiotoolboxdec.c` is FFmpeg's
AudioToolbox decoder registered for AAC only. Its FFCodec at `0xe014ec0` names
`aac_at` ("aac (AudioToolbox)", class `at_aac_dec`, wrapper `at`) with init
`0x8d98b7c`, decode `0x4518e6c`, close `0x8d98c4c` and flush `0x8d98ca4`; the
`ffviv_audio_kit.c` (`0x4519500`, "invalid ADTS header") strips ADTS headers and
builds the AudioSpecificConfig itself. It outputs interleaved integer PCM and
takes its input format from `kAudioFormatProperty_FormatInfo` of an ESDS cookie.
The `ffviv` prefix matches Vivaldi's published platform-media code (inferred).

That decoder runs in the renderer, inside `FFmpegAudioDecoder` and WebAudio's
text at `0xc6d3531`): reads of `/System/Library/Components`, audio plug-in
folders and CoreAudio preferences, the IOAudio user clients, `AudioIO` shared
memory, and mach lookups for `coreaudiod`, `audiohald`, `SystemSoundServer`,
`VDCAssistant`, `AudioComponentRegistrar` and `SandboxHelper`. Its other
embedded profiles match Chromium's apart from one `gpu.sb` rule.

cannot initialise without FFmpeg's H.264 decoder. Apple documents that
`FormatInfo` "will return the base level format", and a probe here confirmed
probably plays HE-AAC at half bandwidth, and HE-AAC v2 in mono. This was not
imports no AudioToolbox reader that could inspect the bitstream (no
`AudioFileStream` and no `AudioFile` reading). Its ADTS config builder
(`0x4519500`) and converter creation (`0x8d98d34`) contain neither of SBR's
sync-extension constants (`0x2b7`, `0x548`). That comes from imports and a
bounded disassembly, so it is inferred.

### Parc's design

`AudioToolboxAudioDecoder` in the GPU process, which upstream uses only for
xHE-AAC. The renderer's `FFmpegAudioDecoder` finds no AAC decoder and declines,
and the decoder selector moves on to `MojoAudioDecoder`. This needs no sandbox
change. `gpu.sb` already allows `AudioComponentRegistrar` for AudioToolbox AAC
encoding and xHE-AAC. With the pinned `common.sb` + `gpu.sb` applied, every AAC
case decodes; under `common.sb` + `renderer.sb`, AudioToolbox refuses the stream
mean adding CoreAudio and device access to the renderer, Chromium's most exposed
process. It would also need FFmpeg build changes. The patch:

- lets `src=` playback build a valid AAC config. FFmpeg fills in an audio
  stream's sample format only by opening its decoder, so without the AAC decoder
  Chromium's AVStream conversion produced `kUnknownSampleFormat`. That
  invalidates the config, and MP4 files would have played without sound.
  `ffmpeg_common.cc` now uses planar float, AudioToolbox's output, when FFmpeg
  left the sample format unset for AAC;
- adds FFmpeg's raw ADTS demuxer to the Chromium-branded macOS arm64
  configuration, so `.aac` files and AAC internet radio reach AudioToolbox
  through `src=`. It also adds the AAC parser and the ADTS-header, APE-tag and
  image-tag helpers the demuxer needs, but no decoder. The files are
  `libavformat/aacdec.c`, `apetag.c` and `img2.c`, and `libavcodec/aac_parser.c`,
  `aac_ac3_parser.c` and `adts_header.c`. They read ADTS frame headers, ID3/APE
  tags and cover-art file names, and do no decoding. They link against
  Chromium's FFmpeg objects, which contain no AAC decoder. Chromium generates
  these configurations from FFmpeg's `configure`, so the patch edits the
  generated `config.h` (`CONFIG_ADTS_HEADER`), `config_components.h`
  (`CONFIG_AAC_PARSER`, `CONFIG_AAC_DEMUXER`), `demuxer_list.c` and
  `parser_list.c` for that one configuration. It adds the sources in
  `third_party/ffmpeg/BUILD.gn` and leaves the generated `ffmpeg_generated.gni`
  alone. FFmpeg's ADTS demuxer leaves the stream's rate, channels and frame size
  to the AAC decoder, because ADTS headers give HE-AAC's core rate. So the
  patched demuxer reads them from the first header. Without the frame size,
  libavformat can't time the packets and `FFmpegDemuxer` stops at the first one
  ("PTS is not defined");
- accepts every AAC profile. It selects the richest layer the stream signals
  (HE-AAC v2, HE-AAC, AAC-LC) with `kAudioFormatProperty_FormatList` and
  `FirstPlayableFormatFromList`, preferring the container's rate. When the
  container runs a plain AAC-LC config at twice its rate (`mp4a.40.5`/`.29` in
  MSE MP4 and MPEG-2 TS), it rewrites the config to signal SBR, adding
  parametric stereo for a mono core;
- finds implicitly signalled HE-AAC (overlay 291), where SBR, and parametric
  stereo for HE-AAC v2, appear only in the bitstream. This applies to a bare
  two-byte AAC-LC config with a core of 24 kHz or less, when nothing already
  doubles it. As in FFmpeg's decoder, the stream's first access unit decides.
  macOS's ADTS parser (`AudioFileStream`) reads SBR from that access unit's raw
  data block. It gets the access unit as repeated ADTS frames, because it
  reports nothing until it has parsed about 128 bytes. Parc feeds it at least
  two frames and 1 KB, as a margin. If the parser lists
  HE-AAC, the decoder swaps its AAC-LC converter, before any output, for
  the SBR config an `mp4a.40.5` hint would give. The output then matches
  FFmpeg's: twice the core rate, and stereo for a mono core whether or not
  parametric stereo data is present. True AAC-LC, configs that signal SBR
  absent and SBR that first appears after the deciding access unit stay
  AAC-LC, as in FFmpeg. An access unit the parser can't judge leaves the
  decision to the next one: an empty, header-only, truncated or damaged one.
  AudioToolbox outputs nothing for those, so nothing has locked the layer yet.
  Once there is output, the layer stays. Parc doesn't parse the bitstream
  itself, because AAC channel elements carry no length. Reaching the fill
  element that holds SBR would mean decoding the full channel syntax with AAC's
  twelve Huffman codebooks. The ADTS parser runs in the GPU process; under
  `renderer.sb` it fails, as the decoder does;
- times HE-AAC as macOS's own decoding does, sample for sample. AudioToolbox
  drops HE-AAC's 962-frame SBR delay from its first output after creation or
  `Reset()`. It returns that many at the end, once the input callback reports
  end of stream with no packets and no error; an error makes it discard them.
  Parc reports it that way for AAC-LC and HE-AAC only. xHE-AAC keeps
  upstream's end of stream, as AC-3 and E-AC-3 would if Parc built them.
  Every later output therefore starts 962 frames before its access unit. The
  decoder holds those frames back, so each buffer, and the discard padding
  that comes with it, covers exactly its own access unit. That matches
  `ExtAudioFile`, which applies an MP4's priming and remainder to the same
  stream. Chrome's FFmpeg decoder keeps the SBR delay, so the same audio
  starts 962 frames (22 ms at 44.1 kHz) later in Chrome. Josh chose macOS's
  alignment. AAC-LC has no delay and is unchanged;
- leaves AAC-LC and HE-AAC samples alone. Upstream's peak limiter stays for
  xHE-AAC, which it was added for, and for the other codecs; HE-AAC v2 peaks
  above 1.0 now pass through, as from FFmpeg's decoder;
- lets `src=` playback take that rate change. Chrome's `src=` never sees one:
  `avformat_find_stream_info` runs FFmpeg's AAC decoder on the first packet and
  copies the doubled rate into the config. `AudioRendererImpl` fails a
  mid-stream rate change unless the stream supports config changes, as Media
  Source streams do. Without FFmpeg's decoder the config keeps the core rate.
  So the patched renderer converts through `AudioBufferConverter`, as it always
  does for Media Source, but only for configs the decoder could double. One
  case is AAC with no config at 24 kHz or less, which raw ADTS gives. The other
  is a bare two-byte AAC-LC config whose rate is its core of 24 kHz or less.
  Other `src=` audio is unchanged, including all AAC at 32 kHz and above and
  configs that already signal SBR;
- strips ADTS headers, which AudioToolbox rejects. MPEG-2 TS (HLS, MSE
  `video/mp2t`), MSE `audio/aac` and WebCodecs without a description deliver
  them. With no description, the first frame's header configures the decoder.
  Parc refuses multi-block ADTS frames, where FFmpeg's decoder warned and
  decoded only the first block. Frames too short to hold a header and payload
  go to AudioToolbox unstripped, or are refused without a description;
- relaxes media's GN assert so macOS may combine proprietary codecs with
  Chromium-branded FFmpeg, but only with `enable_ffmpeg_video_decoders=false`.
  That keeps `IsDecoderBuiltInVideoCodec(H.264)` false, so VideoToolbox, Mojo,
  WebCodecs, Media Capabilities and `canPlayType` stop assuming an FFmpeg
  fallback;
- lets WebRTC use VideoToolbox's H.264 encoder without OpenH264, as Android
  does. Stock desktop Chromium refuses hardware H.264 encoding unless OpenH264
  exists, which would leave H.264 out of every send offer. VideoToolbox also
  takes Constrained Baseline, the profile most peers negotiate, which Chrome on
  Mac encodes with OpenH264. A probe of its hardware Baseline encoder found no
  slice groups or redundant pictures, the tools that profile excludes. The patch
  also drops the assumed software fallback for H.264 receive.

H.264 and HEVC decode through `VideoToolboxVideoDecoder` in the GPU process,
unchanged.

### WebAudio `decodeAudioData`

Overlay 292 (`Engine/ParcHost/integration/webaudio-aac.patch` and
`platform_audio_file_decoder.{h,cc}`) sends WebAudio's AAC to the same GPU
process decoder. Chromium decodes `decodeAudioData` input on a renderer worker
with FFmpeg (`AudioBus::CreateBusFromInMemoryAudioFile`, then
`media::AudioFileReader`). When that fails and FFmpeg's demuxer finds AAC,
`BaseAudioContext` passes the file to `PlatformAudioFileDecoder` on its own
worker sequence. FFmpeg still demuxes in the renderer, and `AudioFileReader`
still gives each packet its timestamps and the container's priming and padding
discards. Each packet then goes to a `MojoAudioDecoder` bound through the
renderer process's media `InterfaceFactory`, the route WebCodecs' `AudioDecoder`
already takes. Eight decodes stay in flight so the IPC round trip doesn't set
the pace: `MojoAudioDecoder` now accepts several, and `MojoAudioDecoderService`
answers them in order, feeding the AudioToolbox decoder one at a time.
Playback sends one at a time, so it is unchanged. The output keeps the
decoder's rate and channel count, which HE-AAC's SBR and parametric stereo
change, and is resampled to the context's rate as before, for `AudioContext`
and `OfflineAudioContext` alike. With overlay 291's decoder that is HE-AAC's
full rate, raw ADTS included, timed as macOS's `ExtAudioFile` decodes it, with
HE-AAC v2 peaks left unlimited. Neither sandbox profile changes.

- A GPU process crash, a GPU process that can't be reached, or a decoder that
  refuses the stream rejects with `EncodingError`. A lost connection never
  returns partial audio; a damaged stream keeps the audio before the damage, as
  Chromium's FFmpeg path does.
- A GPU process that leaves decodes unanswered for 30 seconds rejects instead
  of leaving the promise pending.
- Destroying the document stops the decode before its next packet. `close()`
  alone doesn't, because Chromium still runs the legacy callbacks after it.

and CoreAudio access added to `renderer.sb` (above). Parc rejects that widening.

The [WebAudio check](../tests/NativeWebAudioAAC/README.md) passed against the
built overlay 292 engine on November 1: 53 checks, no failures. Every fixture,
HE-AAC and HE-AAC v2 in MP4 and raw ADTS included, matched macOS's
`ExtAudioFile` decode in rate, channels, frame count and samples, and every
failure case failed cleanly. The Blink half that turns the result into an
`AudioBuffer` needs a renderer and hasn't run.

Speed, from the same check: a 10-minute stereo 44.1 kHz AAC-LC M4A (26,460,000
frames) over Mojo, with the service on another thread of the same process.
Seven runs, on a Mac that was also packaging the app:

| Decodes in flight | Median | Fastest |
|---:|---:|---:|
| 1 | 950 ms | 790 ms |
| 2 | 574 ms | 458 ms |
| 4 | 659 ms | 437 ms |
| 8 (Parc's) | 578 ms | 452 ms |
| 16 | 511 ms | 438 ms |
| 32 | 466 ms | 428 ms |

macOS's `afconvert` took 350–680 ms to decode the same file to disk. Keeping
decodes in flight roughly halves the time, and from two on the runs are within
noise of each other. A real GPU process adds the cost of crossing processes
for each message, which the check can't measure without a browser.

### Trade-offs and gaps

- **No software H.264 decoder.** On Apple Silicon, Chromium requires VideoToolbox
  hardware for H.264 and advertises Baseline to High, 64×64 to 4096×4096. Its
  H.264 path accepts only 4:2:0 and configures 8-bit output, so 4:2:2 and 4:4:4
  streams fail, and High 10 probably does too. Anything else the hardware
  rejects now fails where Chrome would fall back to FFmpeg. If hardware video
  decode is disabled (blocklist, `--disable-accelerated-video-decode`, GPU
  fallback), no H.264 decoder remains. VP9 and AV1 keep libvpx and dav1d. HEVC
  already allows VideoToolbox's software decoder.
- **WebRTC H.264.** If the VideoToolbox encoder can't start (odd frame sizes, for
  example), WebRTC switches to another negotiated codec. A receive stream whose
  hardware decoder fails has no software decoder to fall back to. Chrome would
  also move streams to software when there are many small ones; Parc keeps them
  on VideoToolbox.
- **Implicit HE-AAC detection is Apple's ADTS parser.** Its rules are
  undocumented. It decided correctly on every access unit of the fixtures:
  stereo, mono, 5.1 and v2 HE-AAC, and AAC-LC at 22.05 and 44.1 kHz. Random and
  truncated access units, and damaged AAC-LC ones, fell back to AAC-LC. A later
  macOS could change that, and such streams would quietly play their AAC-LC
  core again. Detection doesn't cover configs longer than two bytes that don't
  signal SBR, 960-sample frames or program-config-element channel layouts. Nor
  does it cover cores above 24 kHz, which FFmpeg would also double.
- **Implicit HE-AAC through `src=` keeps the core rate in its config.** The
  renderer resamples to the output device's rate, as for Media Source, instead
  of passing the stream's rate on. Plain AAC-LC that looks the same, with a
  core of 24 kHz or less and no SBR, takes that path too, though its rate never
  changes. Low-rate speech and old internet radio streams are examples. Where
  the renderer uses the stream's own parameters, HE-AAC is converted back to
  the core rate and channel count, so it sounds as before. That covers a Web
  Audio `MediaElementAudioSourceNode` and playback with no usable output
  device. Code in the renderer that reads FFmpeg's stream parameters also sees
  the core rate and channels. WebAudio `decodeAudioData` takes the decoder's
  rate and channels instead, so it gets full-rate HE-AAC.
- **WebCodecs gets HE-AAC a chunk late.** Holding back each access unit's last
  962 frames means a chunk's output arrives with the next chunk, and `flush()`
  returns the rest. Chrome outputs each chunk as it decodes it. Playback isn't
  affected.
- AAC Main, SSR and LTP don't decode: AudioToolbox rejects their configs (probed
  here). They are rare.
- MP3, FLAC, Opus, Vorbis and PCM are unchanged; Chromium's FFmpeg already
  decodes MP3. AC-3 and E-AC-3 stay off on macOS, as in Chrome.
- ALAC (Apple Lossless) in MP4, which Safari plays: `AudioToolboxAudioDecoder`
  in the GPU process decodes it from its magic cookie (the ALACSpecificConfig
  from Chromium's MP4 parser, or the `alac` atom from FFmpeg's demuxer), and
  `ffmpeg_common.cc` gives `src=` files planar float as for AAC. Pages see it
  only under Safari's identity (`IsParcSafariOnlyAudioCodecs`), and never in
  WebCodecs, which Safari's lacks.
- AMR and AMR-WB audio (`samr`, `sawb`) and H.263 video (`s263`) in 3GPP and
  MP4, which Safari plays: `AudioToolboxAudioDecoder` decodes AMR, one packet
  per frame of each sample, and `ParcVideoToolboxH263Decoder`
  (`media/gpu/mac`) hands H.263 to VideoToolbox's software decoder through
  `VideoToolboxVideoDecoder`, both in the GPU process. `VideoCodec::kH263` is
  Parc's and has no profile. Only Safari-identity pages produce these configs:
  `MP4StreamParser` under Safari's init segment rules (which also require the
  `damr` and `d263` boxes, as `AVStreamDataParser` does) and `FFmpegDemuxer`
  for `src=` (`ParcSetSafariCodecs`). Media Source on those pages takes the
  codec strings `samr`, `sawb` and `s263` (and `name.*`) in every MP4 family
  type, but not `s263` in QuickTime.

## Widevine

### What Parc has today

Parc's engine supports Widevine EME, as an unverified host. CEF requires
`enable_widevine`, `enable_cdm_host_verification` and `enable_cdm_storage_id`
(`cef/tools/gn_args.py`), and the generated build flags have library CDMs and
the Widevine component on. Nothing bundles the CDM: `bundle_widevine_cdm` is for
Chrome-branded builds, and the public checkout has no CDM binaries.

- **CDM delivery.** Chrome's startup calls `RegisterComponentsForUpdate()`, which
  registers the Widevine component, unless `--disable-component-update` is
  passed. CEF's Chrome runtime keeps that call and Parc doesn't pass the switch;
  both functions are linked into the framework. Parc's profile on Josh's Mac
  already holds Widevine CDM 4.10.3112.0 for arm64, downloaded October 30. The
  update server needs no API key.
- **Key system.** The renderer registers `com.widevine.alpha` through Chrome's
  key-system code, which CEF's renderer client inherits. On macOS the robustness
  is software only (`SW_SECURE_CRYPTO`, `SW_SECURE_DECODE`), as in Chrome.
  Desktop library CDMs have persistent licenses off
  (`WidevinePersistentLicenseSupport`), so sessions are temporary.
  extension ID, `WidevineCdm`, Google's update URL and `VerifyCdmHost_0`, and

### Host verification

The CDM runs in a sandboxed utility process. Upstream starts it from the default
helper; from overlay 289 Parc starts it from `Parc Helper (CDM)` (see
[library validation](#library-validation)). When the signature files exist, CEF
(`cdm_host_file_path.cc`) gives the CDM two host files:

| Binary | Signature | Flags |
|---|---|---|
| `Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework` | `…/Versions/A/Resources/Chromium Embedded Framework.sig` | 1 |
| `Contents/Frameworks/Parc Helper (CDM).app/Contents/MacOS/Parc Helper (CDM)` | `Contents/Resources/Parc Helper (CDM).sig` | 0 |

CEF names the second signature after the CDM process's own executable. Parc
passes `main_bundle_path` and `framework_dir_path`, which CEF forwards to child
processes, so both paths resolve inside `Parc.app`, which `cdm.sb` can read; the
signature lookup itself needed no engine change. Chrome signs only its framework, with flag 1
both files on macOS ([CEF issue 3404](https://github.com/chromiumembedded/cef/issues/3404)),
because a CEF helper is the client's own code. The helper's flag 0 is inferred.

Missing signatures don't stop the CDM from loading: `CdmModule::Initialize`
only records the result. The CDM reports the host's status in license requests,
and each service's license server decides what to do with it.

The signature format was read from castlabs' public
[`vmp-resign.py`](https://github.com/castlabs/electron-releases/blob/master/vmp-resign.py)
against the shipped, Apple-signed universal binary, and the downloaded CDM's own
signature. A file is version byte 0, then tagged entries with LEB128 lengths: 1
the certificate, 2 an RSA-PSS signature (SHA-1, 20-byte salt) of SHA-512(body)
followed by the flags byte, and 3 the flags. The body runs, for each
architecture, from the first `__TEXT` section to the end of the string table. It
leaves out the header, load commands and Apple's signature, so VMP signing
happens before Apple signing seals the bundle. Chrome's own generator,
`third_party/widevine/scripts/signature_generator.py`, lives in a Google-internal
repository; the public checkout's `scripts` directory is empty.

### Packaging

`scripts/build.py build` signs the two host files when given either
`--widevine-certificate` with `--widevine-private-key`, or
`--widevine-sign-command`, an external service run as `COMMAND BINARY SIGNATURE
FLAGS`. The key's passphrase comes only from `PARC_WIDEVINE_KEY_PASSPHRASE`, which
the tool takes out of its environment and passes to the `openssl` call alone.
`openssl` and the signing service run without a terminal, so a missing passphrase
fails rather than prompting. A key inside any Git checkout, `.git` directory,
worktree or submodule is refused. Each signature is verified when written
and again after Apple signing. Component engines are refused, because their media
code, which loads the CDM, lives outside the signed framework. Without a signer
the package report's `widevine` entry says `unsigned` and why. The certificate's
chain to Google's root isn't checked locally. Commands are in
[packaging](../tests/Packaging/README.md#widevine-host-signatures).

### What plays without a signature

Widevine content plays when its license server doesn't require a verified host.
CEF's maintainers test Widevine with Shaka's demo streams, which probably
qualify; so do services with relaxed policies. A service that requires a verified
host refuses the license, so nothing plays; there's no lower-resolution
fallback. castlabs names Netflix, Prime Video, Disney+, Apple
TV+, Hulu and Crunchyroll among services that often check
([castlabs](https://castlabs.com/security/widevine-certification/)), and
describes the statuses a server sees
([VMP status reference](https://github.com/castlabs/electron-releases/wiki/VMP)).
Which status unsigned Parc reports, `PLATFORM_UNVERIFIED` or `PLATFORM_TAMPERED`,
hasn't been observed. Signed or not, no Chromium host on macOS gets
hardware-secure Widevine, so any resolution limit beyond that is the service's
own policy.

### The external dependency

A production VMP certificate comes only from Google Widevine. A browser maker
asks through [widevine.com](https://www.widevine.com/) for a license agreement,
signs it, then sends certificate signing requests for a development and a
production certificate, which Google signs
([castlabs, quoted here](https://blog.samuelmaddock.com/posts/the-end-of-indie-web-browsers/)).
Google charges nothing: "Widevine does not assess any fee for use of its
products and services"
([Widevine overview](https://developers.google.com/widevine/drm/overview)). But
approval is Google's choice. In 2019 Widevine refused the open-source Electron
browser Metastream: "I'm sorry but we're not supporting an open source solution
like this"
([The Register](https://www.theregister.com/2019/04/03/googles_widevine_drm)),
and other small browsers waited months without an answer.

castlabs' free EVS service signs only apps built from castlabs' own Electron
releases. Custom Chromium builds need its commercial Widevine 3PL audit
([EVS](https://github.com/castlabs/electron-releases/wiki/EVS)), so it doesn't
fit a free Parc. Open source itself doesn't conflict with the signatures: the
key stays outside the repository, and only official builds would be signed.
Anyone else's build of Parc would be an unsigned host.

### Apple FairPlay inside Chromium (decision, November 6)

Waiting on Google's certificate isn't acceptable (above), so Josh chose to play
protected video through Apple's FairPlay while the page stays in Chromium. A
first attempt that moved whole DRM sites into a WebKit view was discarded: it
needed a second engine's worth of parity work (extensions, passwords, cookies,
DevTools, capture) for one feature.

**What the services do.** A throwaway WKWebView app with Safari's user agent
(`work/drm-webkit-test`, not committed) logged both services' media calls on
this Mac, signed in:

- **Netflix** (watch page, 3840x2160 Dolby Vision): standard EME,
  `requestMediaKeySystemAccess("com.apple.fps.3_0")` with `initDataTypes:
  ["cenc"]` and temporary sessions; `generateRequest("cenc", …)`; license
  accepted and three keys usable; media through MSE (`blob:` URLs). It offers
  avc1, hev1, dvhe (Dolby Vision profile 5) and av01 video, mp4a.40.5 (HE-AAC)
  audio, and probes mp4a.40.42 (xHE-AAC).
- **Apple TV+** (signed-in titles): the same EME shape (`com.apple.fps.3_0`,
  `cenc`), media through `ManagedMediaSource`, dvh1.05.01 video with ac-3 /
  ec-3 audio. License requests go to `play-edge.itunes.apple.com/…/fpsRequest`.
  Signed-out preview tiles use native HLS (`video.src` = `.m3u8`), titles don't.
  The site's store must match the account's: tv.apple.com (US) on a Canadian
  account gets `"status": -1002` for every key, in Safari too; tv.apple.com/ca
  gets `"status": 0`.

Both services granted keys to an app that is not Safari, so presenting
Safari's identity is enough; neither checked for Safari itself. A WKWebView
has WebKit's legacy `WebKitMediaKeys`, which Netflix's UI also requires
before it plays, so Parc adds it to Safari-identity pages (see
[fairplay-identity.md](fairplay-identity.md#webkitmediakeys)).

**Design.** The page never leaves Chromium. Chromium gains a FairPlay key system
(`com.apple.fps` and its versioned names), registered the way Windows registers
PlayReady (`components/cdm/renderer/playready_key_system_info.*`), and a
renderer selected for it, as `RendererType::kMediaFoundation` is on Windows.
Chromium's MSE demuxer keeps parsing the page's chunks; instead of decoding,
the renderer hands the still-encrypted samples and their DecryptConfig to
Apple's public sample-buffer playback: an `AVContentKeySession` (FairPlay
Streaming) for the license exchange, which passes through the page like any
EME exchange, then client-built CMSampleBuffers carrying
`kCMFormatDescriptionExtension_ProtectedContentOriginalFormat`,
`kCMSampleAttachmentKey_CryptorSubsampleAuxiliaryData` and an attached
`AVContentKey` (`AVSampleBufferAttachContentKey`), enqueued to
`AVSampleBufferDisplayLayer` and `AVSampleBufferAudioRenderer` under an
`AVSampleBufferRenderSynchronizer`. Apple documents this use. The display layer
takes the video quad's place in Chromium's CoreAnimation tree
(`ui/accelerated_widget_mac/ca_renderer_layer_tree.mm` already draws video
through AVSampleBufferDisplayLayer and marks protected video
`preventsCapture`), so page content drawn over the video (controls,
subtitles) stays on top. Sites offer FairPlay only to Safari, so Parc presents
Safari's identity (user agent and key-system support) only to sites that need
it, learned when a page asks for Widevine; there is no built-in site list.
Extensions, passwords, cookies, history, DevTools, Peek and capture are
unaffected, since the page is an ordinary Chromium page.

**Milestones.** M0: the engine-independent FairPlay core
(`Engine/ParcNative/fairplay/`) plays Axinom's public FairPlay test vectors
from parsed fMP4 chunks on a Mac, standalone. M1: the key system, renderer and
compositing in the engine; proof is the same stream in a normal Parc tab. M2:
Safari identity for DRM sites; Netflix and Apple TV+. M3: Picture in Picture in
Parc's own window (the display layer can move there), fullscreen, and codecs.

**Known open points.** Chromium has no `ManagedMediaSource`; Apple TV+'s
player must fall back to `MediaSource` (checked in M2). Dolby Vision and
AC-3 / E-AC-3 need `enable_platform_dolby_vision` and
`enable_platform_ac3_eac3_audio`; without them Parc doesn't report those codecs
and services fall back to HEVC HDR / AAC. Screenshots of protected video are
black, as in Safari. Every engine step needs a build on Josh's other Mac.

### Library validation

Google signs the downloaded CDM with its own team ID (`EQHXZ8M8AV`). A
hardened-runtime helper signed with Parc's Developer ID can't load it without
`com.apple.security.cs.disable-library-validation`. Chrome doesn't need that:
Google signs both, so Chrome's default helper keeps library validation
Helper` the entitlement, which also covers the network, storage and audio
processes that helper runs.

Parc takes the narrow route instead (coordinator for Josh, November 1, who said
not to weaken existing security boundaries). Only the CDM process runs in a helper
without library validation.

Nothing upstream routes the CDM anywhere else. In Chromium 156,
`content/browser/media/service_factory.cc` launches the CDM service with no
child flags, so it gets the default helper. macOS content knows only the
default, Renderer and GPU helpers. Chromium removed its old Plugin helper, and
CEF's CMake still lists a `(Plugin)` suffix, but no code starts it. Content
already lets the embedder choose a helper for flags it defines
(`ContentBrowserClient::GetChildProcessPath`); CEF does that for Alerts.

Overlay 289 adds the missing request with the smallest rebuild:

- `cdm-helper.patch` adds `SetCdmServiceChildFlags` to the internal
  `content/browser/media/service_factory.h`, which has four includers. On macOS,
  the CDM launch passes the flags it holds, `CHILD_NORMAL` by default, so other
  embedders are unchanged. It also adds `kChildProcessHelperCdm` next to Chrome's
  Alerts flag in `chrome/browser/child_process_host_flags.h`, which has three.
  Content's public headers, which most of the engine includes, are untouched.
- `native-internal-urls.patch`, which already owns CEF's browser client, sets
  that flag when the browser's main parts are created, and resolves it to
  `Parc Helper (CDM)`. It sets the flag only if the bundle contains that helper;
  otherwise the CDM stays in the default helper. A package without it can load
  the CDM only under ad-hoc signing, where the default helper also lacks library
  validation. The check runs once at startup, before the UI thread
  disallows blocking work.

The CDM keeps its `kCdm` sandbox. Seatbelt parameters come from the launched
program's path and the main bundle, and `Parc Helper (CDM)` lives inside
`Parc.app`.

`scripts/build.py` packages `Parc Helper (CDM).app`, bundle ID
`org.parc.Browser.helper.cdm`, from the same helper binary. With a certificate it
is signed with only `disable-library-validation`. The default and Alerts helpers
get no entitlements, Renderer and GPU keep only `allow-jit`, and the main app
keeps Chromium's list. Ad-hoc development signing still disables library
validation on every helper, because component libraries have no team ID.
Packaging also refuses an engine whose CEF client doesn't route the CDM to that
helper name.


free, 60 s and 600 s cooldowns), HEIF decoding, an AudioToolbox AAC decoder in
the renderer (see [macOS codec route](#macos-codec-route)) and a Google
Meet-only automatic picture in picture. The low-RAM policy is a PERF07
investigation, not a switch.

## Not determined

