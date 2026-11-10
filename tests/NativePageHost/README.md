# Native page-host component

`Engine/ParcNative/page_host.h/.mm` implements native containment of a supplied
WebContents NSView. It does not create or own Chromium WebContents, a Browser,
a profile or an NSWindow. The engine adapter must retain the returned stable
host, supply the actual WebContents native container and coordinate engine
ownership/close consent separately.

Run the focused native suite on macOS with Xcode command-line tools:

```sh
bash tests/NativePageHost/run.sh
```

The script compiles the production component and tests with ARC and warnings
treated as errors, then executes the standalone test binary. It links AppKit
ignored `build/tests/native-page-host/`. Test NSWindows stay offscreen; the suite
uses their real view hierarchies, Auto Layout, first-responder mechanism and a
running main queue. It does not verify visible key-window keyboard delivery,
renderer accessibility, GPU rendering or actual Chromium integration.

The suite passes **214 assertions across fourteen groups** and runs in
`scripts/test.sh`: containment/reuse, replacement/external removal, deferred
renderer focus/replacement, window move and detach, invalidation/weak lifetime,
reentrant replacement teardown, hidden queued-focus refusal, initially-hidden
content visibility, reentrant visibility ownership, the pane compositor view
(never the renderer responder, events pass through, on-screen state, screen
callbacks for hiding, a hidden ancestor, parking in a hidden container and
leaving the window, and geometry callbacks) and content restoration after a
Chromium-style detach
([page compositing](../../docs/page-compositing.md)). The background-visibility
regression against the earlier component exits 1 at “selected initially-hidden
native content and its renderer are actually unhidden”.

The November 10 fresh-tab regressions never run a window event between native
attachment and show. Both initially visible and initially hidden new pages,
their renderer fixtures and the compositor display must have the host's size
when show returns. They also cover changed pane/infobar geometry, replacement
content, clean repeated shows without subtree walks, and transfer, hide or
invalidation callbacks during layout. Against the preceding production host,
the new foreground-page regression fails with a 0×0 page and renderer. These
checks establish the geometry defect and correction, not the reported live
load time or a GPU-rendering result.

From October 26 (`90578fb5`, Peek focus routing) to November 1 the suite failed:
that change made a queued focus request belong to the renderer and window it
was made for, and to a host the window had actually made first responder, but
three groups still expected the request to follow a replacement renderer or a
move to another window, and called `becomeFirstResponder` directly. They now
check the current contract, including that a request made after a replacement
focuses the new renderer. These are component checks, not proof of live
renderer focus or rendering.


| Source file | Recovered contract and implementation boundary |
|---|---|
| `page_host.h` | A retained page wrapper with weak observer, actual native-window attachment notification and focus-attempt notification. Browser/window ownership stays outside the wrapper. |

`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`.
Retained REA records: construction
`ev_03415e0bfcecc8bf308ec08a3994cbc2ea13bf9436acbca12a6c3b46beb0e321`,
focus `ev_d0cc5cf70459e756fc7a84eb89ad4b19df0124300ed772d1b263b19481351afc`,
focus block `ev_db0739f98e30b1c03b571b09bc8c3069960937d6f4ac80892e4b19c8daef673d`,
attachment `ev_219c8c676dbc0dc3e76e60081e62481fe7a9440abca3eb6b250388f061e7fad3`,
replacement `ev_2d2a3c10c652c7376f328760b574e1f44a0f709cfaf858c6ab909bda72a9f415`.
The source uses none of the original private addresses at runtime.

`invalidate` is an explicit Parc lifetime safeguard, not a recovered original
destructor API. The owner calls it before destroying the page/window: it cancels
pending focus/callbacks, clears constraints, and detaches the supplied view and
host. It is terminal and idempotent. Ordinary host detachment preserves the page
and still reports the actual window change. Neither operation closes a browser
tab or grants consent to unload.

## Chromium 156 parent-view visibility adaptation

actual window; it does not establish a hidden-state policy. Pinned Chromium
156.0.8078.48, commit `d0c02bfad08ec92a6ffcf989e53cd995e6381a4c`, separately
requires the host to show the native WebContents container, in addition to the
renderer visibility notifications:

| Pinned source evidence | Established behavior |
|---|---|
| `chrome/browser/extensions/open_tab_helper.cc:183–198` | `active:false` selects `NEW_BACKGROUND_TAB`. |
| `chrome/browser/ui/navigator/browser_navigator.cc:539–540` | Background creation sets `initially_hidden`. |
| `content/browser/web_contents/web_contents_view_mac.mm:434–440,861–866` | Creation hides the native container; the host-visible setter forwards to its native bridge. |
| `content/app_shim_remote_cocoa/web_contents_ns_view_bridge.mm:91–115` | The bridge sets the actual container NSView's hidden flag. |
| `ui/views/controls/native/native_view_host_mac.mm:287–318` | The normal native host explicitly shows/hides that container. |
| `content/browser/web_contents/web_contents_impl.cc:3179–3182,5436–5465` | `WasShown()` updates page/renderer visibility; showing the renderer child does not clear its container parent's hidden flag. |

The native adapter now applies the existing shell-visible-page decision to that
exact managed container before `WasShown()`/`WasHidden()`. It revalidates the
Browser, page binding, pane, view, supplied window and CEF attachment around the
native callback, then checks the latest reconciliation generation and actual
visible-page set before the engine notification. Superseded work cannot change a
later owner's visibility. This adds no page, selection, navigation or focus
operation and does not recreate the renderer.

Frozen evidence: ignored
`work/native-background-page-visibility-fix/source-handoff.json`, SHA256
`9c2c031bd32d2bbd4cae706585c3509ffc3fc5e3c4f0638d5f939815ef367c2e`,
binds all six source files, the old-fail/new-pass logs and generated-owner checks.
The failing v70 GUI run did **not** inspect B's live native hidden flag. The source
path and AppKit regression establish the missing host operation; rebuilt
background-created-page rendering, accessibility, repeated selection and
side-panel lifecycle remain runtime acceptance gates.

complete fullscreen detach/reattach notification policy and native occlusion
classification. Browser/profile activation, keyboard dispatch and accessibility,
color-provider and compositor integration belong to the surrounding engine
adapter. The traced observer callbacks are no-ops in one original construction
path, which does not prove these responsibilities unnecessary elsewhere. The
wrapper does not infer visibility from attachment or successful focus from a
processed request.
