# Native extension side-panel chrome

Run `bash tests/NativeExtensionSidePanelChrome/run.sh` for inert AppKit checks of
`ExtensionSidePanelView` and the production `SplitPaneControl`. The fixture
never opens a browser or profile and uses an unshown window with an explicit
inert key-state override. It checks genuine content-child ownership, header/close
fit, retained child identity and autoresizing, panel-specific accessibility,
native close dispatch, Escape and refusal from hidden chrome.

The panel is an explicit current-Chromium adaptation, explained in
[`docs/extensions-geometry.md`](../../docs/extensions-geometry.md) and the shared
[`native boundary`](../../docs/extensions-side-panel-adaptation.md). The shell
supplies native geometry and header controls around the real engine page.

`python3 tests/SidebarMotion/check.py` additionally exercises the production
outer panel frames, including ordinary, popup, Library, narrow and initial
zero-sized layout. The final application receives the standard whole-module
Swift SIL check. The native close/ownership/renderer lifetime checks belong to
[the side-panel service](../NativeExtensionSidePanel/README.md); the shell never
substitutes a URL-loaded tab or synthetic close model.
