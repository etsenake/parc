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
Chromium 157 presentation adaptation. Other promotion entrypoints are outside this focused change.

Generation must leave the reviewed overlay output unchanged.

The fixture's intentional non-Views window exposes the original defect. The
overlay registers these cases in the existing macOS `chrome/test:unit_tests`
target, rather than introducing a second fake browser model.

After building the existing upstream `unit_tests` target, execute
`unit_tests --gtest_filter=NativeWindowLookupTest.*` on this macOS build.
