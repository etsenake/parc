# Chromium hooks and kept patches

This reference is the one home for every hook Parc has inside Chromium and every Chromium patch the
overlay still carries. [How Parc changes Chromium](chromium-seams.md) explains the architecture,
the extension points Parc uses first and the hook pattern; this reference lists what exists today.

## What counts as a hook

A hook is a setter that a Chromium `.cc` declares and defines so Parc can install a function,
callback or handler that Chromium calls at one exact point. Unhooked Chromium keeps its original
path. Hooks are declared in one of two places:

- [`parc/chromium_hooks.h`](../Engine/ParcChromium/chromium_hooks.h) declares every browser-side
  `parc_hooks::Set...` setter, grouped by the Chromium file that defines it. Chromium never
  includes it, so a signature that drifts fails at link time.
- Renderer, media, Blink and content hooks are declared in a Parc header installed inside the layer
  that owns the hook point: `content/browser/media/parc_fairplay_hooks.h`,
  `content/public/browser/parc_worker_identity.h`, `content/public/browser/parc_playback_target.h`
  and `third_party/blink/renderer/core/html/media/parc_media_player_move.h`.

A few functions run the other way: Parc calls them to act on Chromium state the hook owns, such as
releasing a deferred private profile or starting picture-in-picture scrubbing. They are listed
beside the hook they belong to as call-ins.

Some patches also give a Chromium class a per-object setter, such as a validator Parc attaches to
one dialog. Those are part of their patch and are listed in the patch's entry, not as hooks. Direct
calls from patched Chromium files into Parc-owned files installed inside a layer, such as the media
element supplement, are described in the [seams guide](chromium-seams.md#parc-state-in-parc-owned-objects).

Each hook entry says what it does for people using Parc, the Chromium file that holds the hook
point, why an extension point could not serve, where Parc installs it and which Parc code answers.
Each patch entry says what it changes, which files it touches and why it must stay a patch.

## Counts

The reference covers 66 hooks and 73 patches:

- 61 setters in `parc/chromium_hooks.h`, plus its one call-in, `DestroyUnusedOTRProfile`.
- 5 setters in layer headers: the Widevine request observer, the Safari-identity query, worker
  identity, the AirPlay playback-target handler and Blink's player move. Their 5 call-ins are the
  Safari-identity check, the three AirPlay answers and picture-in-picture scrubbing. One more
  call-in, `content::NotifyNativeDeferredOpenURL`, lives in `content/public/browser/parc_native_links.h`.
- 73 patches in [`overlay.json`](../Engine/ParcHost/overlay.json): 72 in
  `Engine/ParcHost/integration/` and `extension_context_menu_native` in `Engine/ParcNative/`.

To recheck the counts after a change, compare the setters the header declares with the ones the
patches define, list the layer headers' setters, and count the manifest's patches:

```sh
rg -o 'Set[A-Z]\w*\(' Engine/ParcChromium/chromium_hooks.h | sort -u | wc -l
rg -oN --no-filename '^\+(?:[A-Z_]+ )?void (?:parc_hooks::)?(Set[A-Z]\w*)\(' -r '$1' Engine/ParcHost/integration Engine/ParcNative/*.patch | sort -u
rg -n 'EXPORT .*Set\w+\(' Engine/ParcHost/integration/*.h Engine/ParcNative/fairplay_chromium/parc_fairplay_hooks.h Engine/ParcRenderer/parc_media_player_move.h
python3 -c "import json; print(len(json.load(open('Engine/ParcHost/overlay.json'))['patches']))"
```

The second command lists the 59 header setters plus the four layer setters and three AirPlay
call-ins the patches define; per-object member setters are indented and left out. Blink's
player-move setter is defined in Parc's own `parc_media_element.cc`, so only the third finds it.

## The areas

| Area | Hooks | Patches | Reference |
|---|---|---|---|
| Browser and startup | 23 | 14 | [browser, pages and windows](chromium-hooks-browser.md#browser-and-startup-hooks) |
| Page and window | 17 | 9 | [browser, pages and windows](chromium-hooks-browser.md#page-and-window-hooks) |
| Interface routing and prompts | 15 | 26 | [interface and prompts](chromium-hooks-interface.md) |
| Media and FairPlay | 8 | 16 | [media and Blink](chromium-hooks-media.md#media-and-fairplay-hooks) |
| Blink and renderer | 1 | 5 | [media and Blink](chromium-hooks-media.md#blink-and-renderer-hooks) |
| Build and tests | 0 | 4 | [below](#build-and-test-patches) |

Patches by area:

- Browser and startup: `chromium-direct-startup`, `native-browser-overlay`, `native-page-retirement`,
  `native-embedded-pages`, `native-host-direct`, `native-session-cookies-direct`,
  `native-signin-disabled-direct`, `internal-extension`, `native-web-push-direct`,
  `native-atomic-import`, `native-reader-direct`, `native-internal-urls-direct-overlay`,
  `native-license-host` and `native-applescript-lifecycle`.
- Page and window: `native-host-route-direct-overlay`, `native-window-lookup-direct`,
  `native-views-bubble-guards`, `native-fullscreen-window`, `native-history-swipe-direct`,
  `native-input-diagnostics-direct`, `native-external-split-drop`,
  `color-provider-manager-observer` and `native-side-panel`.
- Interface routing and prompts: `native-site-permissions-direct`, `native-sad-tab`,
  `native-server-certificate-viewer-direct`, `native-http-auth`, `native-tab-sharing-direct`,
  `extension_context_menu_native`, `native-page-context-menu-direct-overlay`,
  `native-password-prompt-direct`, `chromium-direct-shared`, `native-devtools-auxiliary`,
  `native-devtools-direct-overlay`, `native-developer-panels`, `native-intent-picker-direct-overlay`,
  `native-client-certificates`, `native-external-protocol`, `native-folder-upload-direct-overlay`,
  `native-extension-install`, `native-webauthn`, `native-autofill-capabilities-direct`,
  `native-autofill-controllers-direct`, `native-address-editor`, `native-address-account`,
  `native-protocol-handler-request`, `native-current-tab-picker`, `native-delegated-picker` and
  `native-file-dialogs-direct-overlay`.
- Media and FairPlay: `cdm-helper`, `fairplay-media`, `fairplay-compositing-direct`,
  `fairplay-identity-workers`, `fairplay-playback-controls`, `native-media-controls`, `native-cast`,
  `native-presentation`, `native-gmc-presentation`, `platform-codecs`, `webaudio-aac`,
  `native-viz-capture-direct`, `native-video-pip-direct`, `native-auto-pip-host-occlusion-direct`,
  `document-pip-minimum-size` and `native-document-pip-content-settings`.
- Blink and renderer: `fairplay-identity-blink-direct`, `fairplay-tracks`, `top-band-color` and
  `blink-overlay-scrollbar-fade`.

## Build and test patches

- **`parc-owned-tests`** adds Parc's owned test targets to Chromium's test binaries, so
  `unit_tests`, `components_unittests` and `blink_unittests` run them. It touches ten BUILD files:
  `chrome/browser`, `chrome/browser/media`, `chrome/browser/ui/autofill/payments`,
  `chrome/browser/ui/media_router`, `chrome/browser/ui/views/global_media_controls`,
  `components/global_media_controls` and Blink's `controller`, `core`, `platform` and
  `platform/loader`. A test binary's dependency list lives only in its Chromium BUILD file.
- **`product-name`** sends each message grit's extension-message formatter writes through Parc's
  owned `tools/grit/grit/parc_branding.py`, so built-in extension strings name Parc. It touches
  `tools/grit/grit/format/chrome_messages_json.py` and `tools/grit/grit.pydeps`; the formatter is a
  build tool with no embedder input.
- **`native-safe-browsing-direct`** adds two direct dependencies, the permissions proto and the GCM
  build flags, to `chrome/browser/safe_browsing/BUILD.gn`, which only that file can declare.
- **`native-extensions-background-mode`** makes the background-extension dependency follow
  `enable_background_mode` and gives the extensions target Parc's window-state API, which the tabs
  API's window update uses, in `chrome/browser/extensions/BUILD.gn`.

## Parc headers kept patches include

A few kept patches still include a narrow Parc API header from an `//parc/native:*_api` target or
`parc/features.h`: the context menu, internal URLs, tabs API window state, intent picker, tab
previews, download picker, browser delegate, autofill and the Mac framework path. Each is the
smallest include that preserves its behaviour.

## Keeping this reference current

Every change that adds, changes, moves or removes a hook or a patch updates this reference in the
same change: the entry, its area's count and the totals above. Reviewers treat a missing update as a
blocking finding ([Chromium boundary](../AGENTS.md#chromium-boundary)). A new hook or patch still
needs the user's approval first, with the alternatives tried and why each fails.
