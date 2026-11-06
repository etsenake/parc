# Native renderer-crash presentation


Run the focused component checks with:

```sh
bash tests/RendererCrashPresentation/run.sh
```


The test uses display values and controlled callbacks to exercise the production view; it does not construct a fake Chromium controller or claim that native engine actions executed. Separate full-app Swift and public-ABI Objective-C facade compiler checks passed against the private real native SadTab header. The actual engine producer/controller tests and packaged renderer crash → visible error → Retry → same-page recovery remain separate verification.


The shell reads current native state during adoption, transfer, rendering and metadata callbacks. A new crash invalidates an older navigation error; recovery can still expose a genuinely later navigation failure. Presentation acknowledgment, Retry and explicit focus recheck the real page, snapshot, observer, physical owner, native descendant and attachment record. A departed pane cannot act on a moved page. Metadata alone does not steal address focus; restoration synchronizes renderer visibility before returning focus if the disappearing crash view owned it.

Integrated checks still required include crash while hidden/in a split, transfer with a stale old-pane Retry callback, real keyboard/AX action routing, normal termination without crash UI, renderer relaunch failure, crash during close, and same-page recovery in the packaged Swift application. Component success does not close these runtime gates.
