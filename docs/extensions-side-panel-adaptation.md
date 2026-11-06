# Extension side-panel compatibility boundary

This document closes the reference dependency shared by EXT12 and EXT14. Parc
continues to support genuine Chromium extension side panels. Their native host
geometry and immediate layout changes are an explicit compatibility adaptation,

## Positive original configuration and construction evidence

image SHA-256 is
`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`.
The main ARM64 image SHA-256 is
`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The recovered-component/type/function helpers and retained panel contract were
previous Core index covered a different version. Bounded annotated disassembly
answered the remaining question; no decompilation, target execution or
second-version comparison was needed.

| Boundary | Positive original evidence |
| --- | --- |
| Native feature identity | Static table entry `0xc1d9cd0` contains integer key 14 and initializer `0x781790c`. The table constructor `0x781736c` invokes these initializers and stores their tagged values. |
| Default and local override | `0x781790c` constructs Boolean false, then passes the exact preference key `ExtensionSidePanelEnabled` to `0x7819140`. The latter calls `CFPreferencesCopyAppValue`; `0x7819350` accepts only a CFBoolean for a Boolean entry. Missing or differently typed values leave the default. |
| Presentation gate | Global extension-panel helper `0x5fbef80` calls Boolean lookup `0x25b5318` with key 14. Its false branch returns at `0x5fbefbc`, before obtaining the panel UI or requesting presentation. The corresponding contextual helper retains the same gate. |
| Native browser construction | Browser constructor `0x315d588`, instructions `0x315dd38–0x315dd60`, allocates and zeroes a 544-byte features object, stores it at Browser `+0x478`, then initializes it through `0x315f02c`. Native post-window setup is `0x315e340`. Those two initializers leave panel UI slot `+0xa8` zero. |
| Exact consumer of that slot | The global helper obtains features through BrowserWindowInterface virtual slot `+0xc0` and reads features `+0xa8` at `0x5fbefd0`; the later Show calls use that pointer. The native BrowserWindowInterface subobject has vtable `0xbef73d0`; its `+0xc0` entry is adjusted features getter `0xa502f64`. |

The native API also exposes `setFeatureEnabled:enabled:` (`0x68bbbd0`), so the
compiled default is not a claim about every possible override or remote rollout.
The separately generated Swift flag `extension-side-panel-enabled` is **not**
used as proof of a binding to native key 14. Nor do the earlier negative type,
keypath or getter searches prove that all possible presentation code is absent.
The positive boundary is narrower and sufficient: ordinary native initialization
starts with the actual extension-panel presentation gate off and no panel UI in
the exact slot the enabled helper would use. There is no recovered visible
baseline whose pixel dimensions or animation curve Parc can truthfully copy.

## Why the current engine needs an adaptation

Side-panel support is explicitly included in Parc (P0-15 and EXT08). Disabling
Chromium 156's real side-panel service and extension host remain authoritative
for permissions, Profile/window/tab identity, options, loading and extension
unload. Its standard presentation delegate is based on Views; Parc's native
AppKit window needs the typed `NativeSidePanelHost` and native presentation
registration already implemented in `extension_side_panel.mm`.

The adaptation therefore preserves the original recoverable boundary—one
Browser-owned panel using supplied genuine extension WebContents—while giving
that content a real native container. It deliberately defines the missing
visible baseline in Parc-owned code:

- A trailing container shares the page's top and bottom. Its preferred width is
  30% of window width, bounded to 240–360 points and clamped to
  the actual remaining width for narrow or zero-sized hosts. EXT12 owns those
- A 32-point native header identifies the surface generically as Extension and
  provides a 32-by-24-point xmark close control. This is explicit compatibility
  artwork remains the genuine rendered page in the separate body container.
  The close button uses `closeExtensionSidePanel()` on the exact native binding.
- Chromium's extension host closes Escape automatically only for popup hosts.
  Parc therefore handles an unhandled plain Escape after the panel session's
  exact-owner checks, requiring the original key NSWindow and native key-down
  event. Modified keys, another window and a non-key original window cannot
  dismiss it. Both the header and keyboard route use the real service's close
  and asynchronous drain; they do not merely hide a Swift view.
- Showing waits for real host load and a valid, visible original window and
  container. Shown notification and focus reach the actual coordinator only
  after attachment and visibility succeed.
- Replacement and contextual switching detach synchronously, retain eligible
  real hosts in their original coordinator caches, and reuse or transfer the
  actual session on tab moves. Generation checks refuse stale presentation.
- Close, disable, unload and shutdown detach immediately. Actual host deletion
  and manager draining wait for callbacks to unwind before Browser/Profile
  deletion. No animation timer extends the lifetime of a terminal page.
- A close restores the saved responder only in the exact original window, when
  the panel still owned focus and no newer responder took over. An explicit
  panel-only focus scope includes the native header and body; the service
  remembers it weakly at show and validates that it still contains the actual
  page in that window. Clients without the optional scope use the body alone.
  It never infers the app root from a generic superview. Hidden views
  and disabled controls are refused. This bounded AppKit admission rule is not
  the separate Swift offscreen-sidebar policy.

The existing immediate panel layout and native detachment are the deliberate
motion adaptation. The recovered reducer's immediate close acknowledgement is
preserved, but it is not presented as proof of an original visible transition.
Popup motion remains separately recovered native AppKit behavior.

## Verification and evidence

Durable raw evidence remains outside Git at
`work/extensions-checks/ext14/panel-gate/receipt.json` and its hashed assembly
files. Earlier original bridge provenance remains in
`outputs/parc/arc-extension-side-panel-contract.md`; the new findings refine its
unresolved native gate rather than rewriting its old investigation result.
The read-only index is `work/extensions-checks/ext14/arccore-1.122.db`.

The final native panel and AppKit host source passed the pinned Chromium compiler
(`work/extensions-checks/ext14/panel-final-native.json`). The production event
and focus helpers pass 23 inert AppKit assertions (`panel-input.log`), and the
finished bridge passes whole-module Swift SIL (`ext14-panel-final.json`). The
published popup handoff also retains its inert native-close checks; EXT13
independently reviewed and checked the integrated picker and lifecycle seams.
EXT12's final consumer passes 10 inert header assertions, 104 production-frame
layout assertions and its final whole-module SIL check.

Fresh reviewer `ext14_lifecycle/ext14_completion_review` cleared the exact
native completion source and original lifecycle integration without findings.
The original ownership and reentrant teardown boundaries are part of that
review. EXT12 separately reviews its header and body consumer. These are
source/compiler/inert checks; no functional browser test or runtime acceptance
is claimed or required by the current instruction.
