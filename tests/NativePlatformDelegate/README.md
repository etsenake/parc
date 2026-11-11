# Native page binding

`Engine/ParcNative/native_page_binding.{h,mm}` connects one real Chromium
WebContents to its stable AppKit page wrapper and page-bound services. The test
directory keeps its historical name; the direct engine uses
`parc::NativePageBinding`.

## Ownership and lifetime

The binding is WebContents user data and observes that same WebContents. The
Browser and its tab model retain ownership of the page. The binding wraps the
existing native content view without creating a tab, reloading a URL or
replacing the window's content view. Its weak Browser reference identifies the
current tab owner and may be empty during insertion, transfer or DevTools
docking. Binding and native-view access belong to the browser UI thread.

When the page is destroyed, the binding closes its attachment gate and cancels
page-bound requests while their services are alive. The invalidated wrapper
stays retained until binding destruction. Weak callbacks protect against
cancellation or native reparenting destroying the binding during delivery.

## Attachment and detachment

Ordinary attachment requires membership in the owning Browser's actual tab
model, the original WebContents content view, and exact equality between the
wrapper's NSWindow and the BrowserWindow's NSWindow. A popup cannot inherit an
attachment merely because its opener has a window.

`PageHostWillDetach()` clears attachment before cancellation callbacks run.
Reattachment during that delivery is rejected. The shell completes the real
Browser/window association and view containment before `PageHostDidAttach()`
can reopen the page's service gates. Unexpected native-window changes cancel
old-window requests and require that explicit attachment step again.

Docked DevTools frontends use a separate auxiliary attachment lease supplied
by their actual pane. It checks the original content view and that pane's exact
NSWindow without inventing a Browser/tab owner. Gaining the lease opens the
folder-upload, HTTP-auth, client-certificate and JavaScript-dialog gates; losing
it closes the JavaScript-dialog gate. Other services observe their captured
leases. Auxiliary attachment changes preserve newer leases established during
an older callback.

## Checks

```sh
python3 -B tests/NativePlatformDelegate/check-chromium.py /absolute/path/to/chromium/src \
```

The selected schema 2 lock determines the source and generated compiler flags.
The checker validates `native_page_binding.mm` against `//parc:browser`'s
`obj/parc/browser.ninja`; other lock schemas are refused. The output name
defaults to the selected lock's build configuration. The checker reads the
canonical lock.

The checker reads the pinned compiler's generated Objective-C++ flags and runs
syntax checks without generating, linking or launching anything. Logs remain
in ignored `build/tests/native-platform-delegate/`. The shell supplies balanced
page-will-detach/page-did-attach calls around actual view and window changes.
