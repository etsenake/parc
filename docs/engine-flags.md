# Engine policy, codecs and protected media

The source of truth is `Engine/source-lock.json`, `SHIPPING_DEFINES` in
`scripts/engine-source.py` and `Engine/ParcNative/native_startup_policy.h`.
This guide describes current Parc policy, not a comparison inventory.
Release/build status belongs in [product status](parity.md).

## Decisions

Parc does not depend on Google API keys or paid Google services. Preserve the
committed AI/service exclusions, ordinary password/autofill/security features and
macOS dictation. Generic Chromium/Google networking is not a separate removal
project. Disabled features are not evidence of measured CPU or memory savings.

## Build arguments (GN)

| Setting | Development | Shipping |
|---|---|---|
| Engine configuration | ARM64 component build | ARM64 standalone framework |
| `is_official_build` | false | true; official ThinLTO/stripping policy |
| `chrome_pgo_phase` | upstream development default | 2; pinned Chromium and V8 builtins profiles, checksums verified |
| `dcheck_always_on` | false | false |
| `disable_fieldtrial_testing_config` | true | true |
| `proprietary_codecs` | true | true |
| `ffmpeg_branding` | Chromium | Chromium |
| `enable_ffmpeg_video_decoders` | false | false |
| `media_use_openh264` | false | false |
| `enable_hangout_services_extension` | true | true |
| Platform Dolby Vision, encrypted Dolby Vision, AC-3/E-AC-3 | true | true |
| `enable_dsyms`, `use_remoteexec` | false | false |

The lock permits symbol levels 0 and 1, default 0. Distributed dSYM delivery is not
part of the release recipe. The [engine guide](../Engine/README.md#build-configuration)
describes the shipping build's pinned PGO profile. Component engines change linking
and allocator behavior; their memory/startup measurements do not predict shipping
performance. Keep dependencies pinned and preserve compiled objects/caches.

## Packaging

The main app and helpers receive `MallocNanoZone=0`; helpers inherit the browser
process environment. Production signing limits disabled library validation to
`Parc Helper (CDM)`, which loads the independently signed Widevine CDM. Default
and Alerts helpers have no extra entitlement; the Renderer and GPU helpers,
classic and Aperitif alike, retain `allow-jit`.
Ad-hoc component development needs broader library-validation exceptions because
its libraries lack a team ID; that is not the shipping entitlement policy.

## Runtime features

`ApplyNativeStartupPolicy` always adds `disable-field-trial-config`. Product
exclusions override an explicit enable: `HistoryEmbeddings`, `Glic`,
`GlicActorUi`, `AutofillActorMode`, `LensOverlay`, `TranslateRankerQuery`,
`TranslateRankerEnforcement`, `CentralizedInfoBarFramework` and
`TranslateTrigger`. `TranslateTrigger` replaced Chromium's
`disable-translate-trigger` switch in 157; with it off, Chromium never offers or
starts page translation on its own.

Defaults applied only when the command line has not explicitly named a feature:

- Enabled: `CertificateTransparencyAskBeforeEnabling` and `WebContentsDiscard`.
  The latter preserves the same WebContents during idle-tab discard.
- Disabled: `MacAppCodeSignClone`, `MacAppCodeSignCloneRenameAsBundle`, `FedCm`,
  `AutofillServerCommunication`, `PreloadMediaEngagementData`, `BrowsingTopics`,
  `NetworkTimeServiceQuerying`, `LiveCaption`, `MerchantTrust`,
  `PageInfoAboutThisSite`, `PageInfoAboutThisSiteMoreLangs`,
  `TailoredSecurityIntegration`, `CredentialManagementUnifiedUi` and
  `ExtensionsPinnedByDefault`. The last two keep automatic sign-in on Parc's
  password prompt instead of Chromium's toast, and keep newly installed
  extensions unpinned.

Back/forward cache, ServiceWorkerAutoPreload and Privacy Sandbox attestation
retain upstream defaults. On-device omnibox suggestions and the web Translator
API remain available without a Google API key. Safe Browsing remains included
without a configured key. Its local database, service startup and warning paths
are not disabled merely by the missing key; request construction omits an absent
key rather than refusing every request. The app's actual updater is Sparkle;
Chromium's app-clone mechanism is not its update owner.

## Page translation

Google page translation is excluded. Startup prevents offers before the ranker;
both ranker features are off; the profile preference defaults off. Page-menu
Translate and Translate Selection, the app translate popover and translated-site
reset setting are absent. `NativeBrowserWindow` refuses the bubble, and the
command bar does not dispatch autocomplete-match translation actions.

`chrome://settings/languages` may still show the default-off Google Translate
switch and fetch its supported-language list. Turning it on does not bypass the
blocked entry points. Translate internals displays state only. Page language
detection remains for Autofill and other consumers. The on-device web Translator
API is separate and intentionally remains available.

## macOS codec route

H.264, HEVC and AAC use macOS codecs. Parc does not bundle FFmpeg's H.264/AAC
decoders or OpenH264. `platform-codecs.patch` connects Chromium's
`AudioToolboxAudioDecoder` in the GPU process; the renderer's existing sandbox
is not expanded for audio decoding.

AAC `src=` configurations receive a usable planar-float sample format when
FFmpeg cannot supply one. Chromium-branded FFmpeg includes AAC/ADTS parsers and
the raw ADTS demuxer, including packet timing from the first header, but no AAC
decoder. Profile selection uses AudioToolbox's format list and the container rate
to choose AAC-LC, HE-AAC or HE-AAC v2. The implementation also detects eligible
implicitly signalled SBR/parametric stereo through Apple's ADTS parser.

### WebAudio `decodeAudioData`

The renderer parses the encoded file and sends AAC packets to the GPU process's
AudioToolbox decoder through Mojo. Returned PCM produces the AudioBuffer without
changing the renderer sandbox. Concurrent decode requests and failure cleanup
are bounded; [native WebAudio checks](../tests/NativeWebAudioAAC/README.md)
exercise the service. Standalone service timing is not end-to-end renderer or
GPU-process performance evidence.

### Codec boundaries

- H.264 has no FFmpeg software fallback. Hardware-decoder disablement/failure or
  unsupported 4:2:2/4:4:4 streams cannot fall back; High 10 support is not claimed.
  WebRTC similarly relies on VideoToolbox or another negotiated codec. VP9 and
  AV1 retain their normal software paths outside Safari-identity restrictions.
- Implicit HE-AAC detection relies on platform parser behavior. Configurations
  longer than two bytes without explicit SBR, 960-sample frames, program-config
  layouts and cores above 24 kHz are not covered by that detector.
- `src=` implicit HE-AAC retains core rate/channels in its stream configuration.
  Ordinary output resamples, but MediaElementAudioSourceNode or playback without
  a usable output device can observe/convert to the core parameters.
  `decodeAudioData` uses the decoder's full output parameters.
- WebCodecs HE-AAC output is delayed by the held tail until the next chunk or
  `flush()`. AAC Main, SSR and LTP are rejected by the tested platform decoder.
- ALAC, AMR/AMR-WB and H.263 use the platform paths only on Safari-identity pages.
  ALAC is not exposed through WebCodecs. Their container/configuration checks
  remain in the native codec implementation.

AC-3/E-AC-3 and Dolby Vision are implemented and gated by the media identity
contract below; old claims that their build flags are off are obsolete.

## Widevine

### What Parc has today

The pinned Chromium build enables Widevine, host verification and storage IDs.
The component updater supplies the CDM; Parc does not bundle its binary or
turn off component updates. The renderer registers `com.widevine.alpha`.
macOS Widevine uses software robustness and temporary licenses. Parc remains an
unverified host unless official host signing is separately provisioned.

### Host verification

The CDM runs in its sandboxed utility process, routed to `Parc Helper (CDM)`.
Chromium supplies the framework and helper host files when their signatures exist:

| Host | Signature |
|---|---|
| Engine framework binary | framework `Versions/A/Resources/Chromium Embedded Framework.sig` |
| Parc Helper (CDM) executable | helper `Contents/Resources/Parc Helper (CDM).sig` |

Missing signatures do not stop loading; the service's license server decides
whether to accept the reported host status. An unsigned host may therefore play
some protected streams and be refused by others. There is no guaranteed
lower-resolution fallback for a refused license. A valid signing certificate
requires external Widevine approval, not an Apple Developer ID certificate.

### Packaging

`scripts/build.py build` accepts either `--widevine-certificate` plus
`--widevine-private-key`, or `--widevine-sign-command` receiving
`BINARY SIGNATURE FLAGS`. The key passphrase is passed only to the openssl child
through its private environment. Signers run without a terminal and fail on
missing input rather than prompting. Keys inside Git checkouts/worktrees or
submodules are refused.

Signatures are checked when written and after Apple signing. Component engines
are refused because relevant media code lives outside the signed framework.
Without a signer, the package report records unsigned status and its reason.
Local verification does not validate the certificate chain to Google's root.
See [packaging](../tests/Packaging/README.md#widevine-host-signatures).

### Apple FairPlay inside Chromium

Protected-media pages stay in Chromium. FairPlay exchanges travel through the
page's normal EME request, then `AVContentKeySession` supplies content keys to
Apple sample-buffer playback. Chromium's MSE demuxer parses encrypted samples;
the FairPlay renderer provides protected CoreAnimation video and synchronized
audio while page controls/subtitles remain above it. There is no separate
WebKit browser for DRM sites.

Parc learns sites needing Safari identity from a Widevine request instead of a
hardcoded site list. Its identity layer includes ManagedMediaSource, legacy
WebKitMediaKeys and presentation/fullscreen APIs. Native HLS, Dolby codecs,
PiP and fullscreen are implemented. See [Safari identity](fairplay-identity.md),
[FairPlay core](../Engine/ParcNative/fairplay/README.md) and
[Chromium integration](../Engine/ParcNative/fairplay_chromium/README.md).

Protected video is not capturable as ordinary pixels.

### Library validation

Only the CDM helper weakens library validation. `cdm-helper.patch` supplies the
`parc_hooks::SetCdmServiceChildFlags` hook; Parc's browser client selects the dedicated helper
only when it exists in the bundle. The process retains the CDM sandbox and all
bundle path restrictions. Packaging refuses an engine that cannot route the
CDM to the expected helper. No default network/storage/audio helper receives
this production exception.

Parc selects its web-push client through the GCM factory before profile services
start. It declines legacy sender-ID registrations immediately, while Instance ID
registrations and the GCM transport keep Chromium's implementation.
