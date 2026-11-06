# Native Find component

`find_bar_view.h/.mm` is a real AppKit Find control: editable single-line field,
results, previous/next/close controls, keyed page/window focus registration and
safe reattachment/teardown. `find_bar.h/.mm` supplies the actual Chromium 156
`FindBar` implementation to its real `FindBarController` and `FindTabHelper`.
It does not simulate search, own WebContents or construct a substitute Browser.

SHA-256 `4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`:

  page chrome. The caller supplies real container/top-panel geometry.
- REA command evidence `ev_8d02b876bf43898b3acedc88639235899e476e8bd4a4994b3d7b65803f3cd44e`;
  presentation evidence `ev_cf965b6659e91a32f3869900a47f50f7b7461828e27b028fd491e63cdd5d3831`.

The complete bounded report is retained in the task outputs as
`arc-native-find-ui-contract.md`. Exact colors, inner spacing, font tokens,
animations and split-pane simultaneous Find presentation are not established.
Current system styling and synchronous show/hide are explicitly unfinished

## Checks actually run

```sh
bash tests/NativeFindBar/run.sh
python3 tests/NativeFindBar/check-chromium.py /path/to/chromium/src
```

The standalone AppKit suite passed **79 assertions across 6 groups**. It compiles
NSWindows/NSTextFields, their field editors and the main run loop. It checks
native insertion and marked-text composition, programmatic updates without
query callbacks, result/unknown states, button actions, keyboard command
routing, narrow-pane geometry, keyed focus restoration, preserving unrelated
focus, weak delegate ownership, invalid contexts and reentrant teardown. A
regression reparents the destination pane to another window during focus-loss
callback delivery: attachment rejects that now-invalid context.

The separate checker reads the actual generated `obj/cef/libcef_static.ninja`
Objective-C++ settings and uses the pinned Chromium compiler, without modifying
the checkout or invoking GN/Ninja. With the real upstream generated prerequisites
present, **both the AppKit view and the Chromium bridge pass syntax checking**
with warnings treated as errors. This does not link or execute the bridge in a
browser. Logs/argv/dependencies are ignored under `build/tests/native-find-bar/`.

## Integration and lifetime

`NativeBrowserWindowHost::CreateFindBar()` should return
`std::make_unique<parc::NativeFindBar>(find_host)`. `FindBarController` owns and
sets up the bar; do not instantiate a second controller or manually duplicate
its tab observation. Its host must outlive the bar and implement:

- `GetFindBarContext(WebContents*)`: the supplied contents' actual per-page
  overlay container, live `PCNativeFocusManager`, unique find/page keys and top
  inset. No frontmost-window lookup. A missing/mismatched context detaches stale
  presentation. A registration token is retained for the context's lifetime.
- `CloseFindOverlappingBubbles()`: the actual shell's applicable bubble closure.

The bridge dispatches edits and next/previous through the real FindTabHelper;
Escape/close use controller `EndFindSession(kKeep,kKeep)`. It forwards visibility
changes and actual field-focus state. Query updates from results do not replace
marked IME text. Chromium's Mac helper supplies its global Find pasteboard;
clearing results retains that query, and Mac audible notifications are counted
without playing a sound, matching pinned upstream behavior. These are explicit
were not established by this bounded trace.

The native view saves an actual keyed responder or weak same-window control,
normalizing shared field editors to their owning field, and uses the explicit
page key as fallback. A hide-induced transition to NSWindow is distinguished
from the user choosing another control. The Find-specific restoration caller in
mechanism is separately recovered and tested. Full keyboard traversal among
Find buttons and exact focus behavior across split/profile switches remain
browser acceptance work.

`GetHostWidget()` is null because the actual host is AppKit. Integration must
retain the native fullscreen path rather than calling Views-only immersive
reparenting. Show/hide currently has no animation; `StopAnimation` therefore has
no work. Real Browser/Find command routing, navigation/tab-switch behavior,
renderer matches/highlights, profile/pasteboard boundaries, actual accessibility
and visual/motion comparison remain integration gates. The v5 reviewed source
overlay compiles the view in native_components and the bridge in libcef_static.
The current application backend and production native host remain unchanged.
