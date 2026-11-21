# Native Find component

`find_bar_view.h/.mm` is a real AppKit Find control: editable single-line field,
results, previous/next/close controls, keyed page/window focus registration and
safe reattachment/teardown. `find_bar.h/.mm` supplies the actual Chromium 157
`FindBar` implementation to its real `FindBarController` and `FindTabHelper`.
It does not simulate search, own WebContents or construct a substitute Browser.

The per-page overlay receives its content/top-bar geometry from the host.
Find presentation and keyboard behavior are documented in
[keyboard navigation](../../docs/keyboard-navigation.md).

## Checks

Read [the working contract](../../AGENTS.md) before running these checks.

```sh
swift test --filter FindBarTests
```

The AppKit suite compiles with ARC and
`-Wall -Wextra -Werror`, then executes real offscreen
NSWindows/NSTextFields, their field editors and the main run loop. It checks
native insertion and marked-text composition, programmatic updates without
query callbacks, result/unknown states, button actions, keyboard command
routing, narrow-pane geometry, keyed focus restoration, preserving unrelated
focus, weak delegate ownership, invalid contexts and reentrant teardown. A
regression reparents the destination pane to another window during focus-loss
callback delivery: attachment rejects that now-invalid context.


`NativeBrowserWindow::CreateFindBar()` delegates to `AppKitBrowserHost`, which
constructs `NativeFindBar`. Chromium's `FindBarController` owns and sets up that
bar. The host supplies:

- `GetFindBarContext(WebContents*)`: the supplied contents' actual per-page
  overlay container, live `PCNativeFocusManager`, unique find/page keys and top
  inset. No frontmost-window lookup. A missing/mismatched context detaches stale
  presentation. A registration token is retained for the context's lifetime.
- `CloseFindOverlappingBubbles()`: the actual shell's applicable bubble closure.

The normal application Find menu uses `BrowserWindowController`'s `PageFindView`
and the selected page's native Find methods. Those methods and the Chromium
bridge both reach the original page's `FindTabHelper`; the shell keeps queries
bound to that page's document revision. [Keyboard navigation](../../docs/keyboard-navigation.md#find-commands-and-original-document-ownership)
owns the application menu, split/Peek geometry and focus behavior.

The Chromium bridge dispatches edits and next/previous through `FindTabHelper`;
Escape/close use controller `EndFindSession(kKeep,kKeep)`. It forwards visibility
changes and actual field-focus state. Query updates from results do not replace
marked IME text. Chromium's Mac helper supplies its global Find pasteboard;
clearing results retains that query, and Mac audible notifications are counted
without playing a sound, matching pinned upstream behavior.

The native view saves an actual keyed responder or weak same-window control,
normalizing shared field editors to their owning field, and uses the explicit
page key as fallback. A hide-induced transition to NSWindow is distinguished
from the user choosing another control.

`GetHostWidget()` is null because the host is AppKit. Fullscreen uses the native
path rather than Views-only immersive reparenting. Show/hide is immediate;
`StopAnimation` has no animation to stop. The source overlay compiles the view
in native_components and the bridge in //parc:browser.
