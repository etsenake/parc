# Native page status preview

Run `bash tests/NativeStatusText/run.sh`. The real AppKit component executes
**60 assertions** for delayed visibility, duplicate handling, expansion,
click-through, page-local geometry, pointer avoidance, narrow-pane overlap,
mouseMoved idle-stop while the pill is hidden, pointer/overlay fingerprint
layout skips, independent pages, expected/unexpected detachment, hiding,
validation at delivery, invalidation during animation and controller release
with pending timers or a live mouse monitor. Tests use offscreen windows and
the main run loop. They do not synthesize user input, load a browser engine or
prove integrated rendering.

## Reference and implementation boundary

main SHA-256 is `4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`;
Core SHA-256 is `97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`.
Retained REA instructions, Swift metadata and Objective-C encodings establish:

- Core `0x68ea1a0` weakly resolves the exact page/delegate and sends
  stream and expands ordinary text after 1.5 seconds. These are not fade times.
  Default compact/expanded line breaks are truncating-middle/truncating-tail.
  zone and retains the current side when the two zones overlap. The local
  from hit testing.

The five retained REA evidence IDs are
`ev_e7d7bd2b11799a3fcfd05de7d70b4e7c2c51282ceebef69483d7fbb0c5b5fbae`,
`ev_a93fd33fbdd1f12ff0706b86bd1bbb66dd29869829312cc6d6881bc3488c6d88`,
`ev_8a2125ce13cff3ad5f7ee969ffba4e51bc36ac1149eeaa3dc9f120a856bebe1a`,
`ev_e5f13e83d935d65ac8ad46e92a67cd130432f3328037bd320e838c01fd39ca29`,
and `ev_f30e12f9758c54e6f048d48b0b33a68dbe27c5fe069225a1c269317cb58b76d8`.
These are static observations, not original source or observed execution.

Parc's actual `CefDisplayHandler::OnStatusMessage` resolves the callback's
original WebContents and its existing NativePageState. Each state owns one
controller inside its unchanged native page host. Explicit native attachment,
main-document navigation, renderer exit, visibility and page destruction gate
the presentation. There is no selected-tab/global status lookup, URL reload or
replacement `StatusBubbleViews`. Chromium's original mouse and exclusive-access
processing remains intact. The page host can be resized inside the DevTools
composition without placing status text over the tools pane.

The v39 overlay passes read-only replay with 118 mapped files and 104 patched
targets. Four isolated compiler checks pass for the presenter, page state,
application callback and platform attachment against the pinned generated
settings. The newly registered presenter uses the existing native-components
settings before generation; the three other units retain their libcef settings.
The active v22 build was not changed. Linking, actual generated membership/header
checks and integrated execution remain pending. No public Swift bridge changed.

## Remaining acceptance checks

The 11 pt font, 6 pt corner radius, native popover material and 8 pt text padding
are provisional styling choices; original metrics, palette, material and corner
treatment are not yet verified. The pipeline's second input, routing-explanation
text/icons and original URL formatting remain unresolved. CEF currently supplies

Exercise real links, long/escaped/international URLs, link leave, page exit,
navigation, windows, splits and document replacement. CEF's delivery of an empty
status on every pointer-exit path is unverified; do not claim that the component
tests resolve it or preemptively bypass Chrome's mouse processing. Compare actual
fade/interruption, pointer monitor delivery, theme, scaling, fullscreen,
reduced-motion and focus behavior. The source enables the recovered avoidance
needs runtime comparison. Explained routing status is not implemented.
