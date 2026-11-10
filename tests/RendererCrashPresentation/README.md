# Native renderer-crash presentation

`PageFailureView.swift` is the actual Swift/AppKit component used by each browser pane and Peek for ordinary navigation errors and the separate native renderer-crash snapshot. A crash shows the SadTab surface (`SadTabContent.swift`; see [failure and recovery](../../docs/web-interactions.md)). The snapshot's presence, identity, error code and action come from the real Chromium SadTab instance; the component does not classify termination codes. The reload link invokes that exact native action and leaves the presentation intact until the native helper clears it.

Run the focused component checks with:

```sh
bash tests/RendererCrashPresentation/run.sh
```


The test uses display values and controlled callbacks to exercise the production view; it does not construct a fake Chromium controller or claim that native engine actions executed.


The shell reads current native state during adoption, transfer, rendering and metadata callbacks. A new crash invalidates an older navigation error; recovery can still expose a genuinely later navigation failure. Presentation acknowledgment, Retry and explicit focus recheck the real page, snapshot, observer, physical owner, native descendant and attachment record. A departed pane cannot act on a moved page. Metadata alone does not steal address focus; restoration synchronizes renderer visibility before returning focus if the disappearing crash view owned it.
