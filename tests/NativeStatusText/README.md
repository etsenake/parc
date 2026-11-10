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

## Implementation boundary

Content updates independently of visibility, which waits 0.5 seconds; ordinary
text expands after 1.5 seconds. The page-local pill uses 10 pt side/bottom insets,
24 pt height and compact width up to 400 pt. It moves away from the pointer,
preserving the current side when avoidance zones overlap, and is click-through.
Animation completion rejects stale identities.

Parc's actual `CefDisplayHandler::OnStatusMessage` resolves the callback's
original WebContents and its existing NativePageState. Each state owns one
controller inside its unchanged native page host. Explicit native attachment,
main-document navigation, renderer exit, visibility and page destruction gate
the presentation. There is no selected-tab/global status lookup, URL reload or
replacement `StatusBubbleViews`. Chromium's original mouse and exclusive-access
processing remains intact. The page host can be resized inside the DevTools
composition without placing status text over the tools pane.

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
reduced-motion and focus behavior. The source enables the avoidance
algorithm for ordinary pages; higher-level routing and pointer behavior require integrated validation. Explained routing status is not implemented.
