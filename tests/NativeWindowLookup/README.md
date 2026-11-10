# Native browser-window lookup

Chromium's generic `BrowserWindow::FindBrowserWindowWithWebContents` found a real
tab's owning browser, then reduced the result to a `BrowserView`. That discarded
Parc's actual native `BrowserWindow`, which intentionally has no Chrome view.
Address-save prompts are one caller affected by this lookup.

The reviewed overlay preserves successful Widget/BrowserView lookup, including
non-tab contents. If that path cannot provide a window, it resolves the actual
tab owner through `GlobalBrowserCollection` and returns `BrowserWindow::FromBrowser`.
It never substitutes the last-active browser, another profile or a fake view.
The helper uses the pinned Chromium interfaces and actual native ownership.

Four regression cases use `BrowserWithTestWindowTest` and the real tab model:

- Active and background tabs resolve the same non-Views window.
- Unattached WebContents do not borrow the current window.
- Detaching a tab removes its association; inserting that same tab in another
  browser resolves the destination window.
- A real local `SaveAddressBubbleController` accepting a synthetic address
  reaches its real parent controller without requiring a Chrome promotion view.

That last case exposed a connected defect: the post-save iOS promotion
unconditionally dereferenced `AsBrowserView` before checking eligibility. The
patch checks for the real Views presentation capability before starting that
optional promotion. Its eligibility callback ultimately creates a Views bubble
anchored to Chrome's toolbar. The native save result remains intact; this is a
promotion. Other promotion entrypoints are outside this focused change.

CEF rechecks its own source patches during project generation. The native
continuation overlaps its existing Autofill hunk, so the overlay updates
that patch definition to recognize the same reviewed result. All other CEF
hunks remain intact. The checker repeats CEF's actual read-only reverse check
before compilation; it does not skip or disable the patcher.

The fixture's intentional non-Views window exposes the original defect. The
overlay registers these cases in the existing macOS `chrome/test:unit_tests`
target, rather than introducing a second fake browser model.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/NativeWindowLookup/check-chromium.py /absolute/chromium/src
```

The script validates the applied implementation hash and uses the actual
generated target compiler flags. It never runs GN/Ninja or writes
to the external source tree. `--tests-only` permits checking the four test
cases before the overlay is applied. Logs stay in ignored `build/tests/`.

After building the existing upstream `unit_tests` target, execute
`unit_tests --gtest_filter=NativeWindowLookupTest.*` on this macOS build.
