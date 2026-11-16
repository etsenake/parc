# Native renderer-crash presentation

`PageFailureView.swift` is the actual Swift/AppKit component used by each browser pane and Peek for ordinary navigation errors and the separate native renderer-crash snapshot. A crash shows the SadTab surface (`SadTabContent.swift`; see [failure and recovery](../../docs/web-interactions.md)). The snapshot's presence, identity, error code and action come from the real Chromium SadTab instance; the component does not classify termination codes. The reload link invokes that exact native action and leaves the presentation intact until the native helper clears it.

Run the focused component checks with:

```sh
bash tests/RendererCrashPresentation/run.sh
```

This opens and closes one test-owned AppKit window. The 67 checks cover the sentence split, error code, colours and artwork loaded from the binary's own `SadTab` and `PageFailure` resources; the composition's geometry (96-point artwork, the 96-point square paper plane for an ordinary failure, 64-point spacing, centred column, 20-point corner inset, link-only hit testing, narrow wrapping) and light/dark backing; and the behaviour: actual visible drawing and focus, once-only snapshot acknowledgment, no acknowledgment while hidden, no optimistic clear after the link's action (click, Space or AX press), exact snapshot replacement and teardown during a drawing callback, ordinary error separation, retained page/window containment, pointer exclusion and explicit accessibility-hidden preservation/restoration. A replacement during drawing must receive a later real draw before it can act. The tests never call `draw` directly to fabricate presentation; the light/dark backing is drawn by a window-less copy, which cannot acknowledge.

The test uses display values and controlled callbacks to exercise the production view; it does not construct a fake Chromium controller or claim that native engine actions executed.

Parc keeps its registered native hierarchy attached to the same NSWindow, hides it (including its AX subtree), and displays the per-pane error sibling instead. Physical removal would break the current exact native page/container security relationship. This is a current-engine containment adaptation.

The shell reads current native state during adoption, transfer, rendering and metadata callbacks. A new crash invalidates an older navigation error; recovery can still expose a genuinely later navigation failure. Presentation acknowledgment, Retry and explicit focus recheck the real page, snapshot, observer, physical owner, native descendant and attachment record. A departed pane cannot act on a moved page. Metadata alone does not steal address focus; restoration synchronizes renderer visibility before returning focus if the disappearing crash view owned it.
