# Native LocationBar compatibility service

`Engine/ParcNative/location_bar.{h,cc}` implements the non-rendering service
owned by the native BrowserWindow. It is not the visible Parc command
bar, a Chrome toolbar, or a browser-window adapter.

## Current interface

The owning native BrowserWindow contains `NativeLocationBar`, the real
`OmniboxController` and `ChromeOmniboxClient`, and a non-rendering view.
`GetWebContents()` queries that Browser's active tab; `LocationBarModel::From`
requires the Browser's model to have been registered first. The controller uses
a 1.5-second stop-duration override. Inherited edit-model methods remain live;
this service does not supply the visible command field or suggestion popup.

Absent visual widgets yield false, empty or null only for their UI queries.
Fullscreen queries the actual window; editing queries the real OmniboxView.
Permission and accessible command-bar presentations are separate services.

The view dies before the controller/client and clears its edit-model pointer.
Construct after Browser features and destroy before Browser/Profile teardown.
The client binds the actual BrowserCommandController and validates its presence.

## Narrow AI policy prerequisite

Set supported startup features **before** constructing any such service:
disable `HistoryEmbeddings`. The constructor checks that feature's explicit
disabled override before allocating the controller. That override also
prevents Chrome's separate country/locale launch fallback. It does not alter
the global FeatureList or install a testing controller.

On-device search suggestions are included. Their
model arrives through the component updater, which needs no Google API key, so
`DefaultOmniboxProviders()` includes the on-device head provider here and the
browser test expects it.

At this pin, `DefaultOmniboxProviders()` still selects an inert
HistoryEmbeddingsProvider with its feature disabled. Its `Start()` exits through
the client's feature check before querying history-embedding services; the
object's presence is not falsely reported as absence. See
`components/omnibox/browser/autocomplete_classifier.cc`,
`history_embeddings_provider.cc`, and
`chrome/browser/history_embeddings/history_embeddings_utils.cc` in the pin.
This guard covers these specific paths only, not engine-wide absence. The
broader AI audit is closed; preserve existing exclusions and investigate
concrete contrary evidence.
No general Google-networking removal is implied.

## Production integration and checks

`NativeBrowserWindow::Impl` constructs this service after the browser's models
are initialized and exposes it through `GetLocationBar()`. Teardown releases it
before the native host and Browser. Visible command UI remains in Parc's Swift
command bar, while native permissions use their own page-bound presenter.

```sh
python3 tests/NativeLocationBar/check-chromium.py /absolute/path/to/chromium/src
```

The selected source lock chooses the implementation flags: `browser.ninja`
from the canonical source lock.

`location_bar_browsertest.cc` contains Chromium browser tests for
Browser/Profile/model/active-tab identity, command enablement, the inherited
edit model and destruction ordering. The filter is
`NativeLocationBarBrowserTest.*`; execution requires the browser-testing
authorization described in [the working contract](../../AGENTS.md).
