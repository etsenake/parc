# Native page status preview

`bash tests/NativeStatusText/run.sh` exercises the production AppKit controller
using offscreen windows and the main run loop. Inspect the runner and follow
[the working contract](../../AGENTS.md) before running window-based checks.

The suite covers delayed visibility, duplicate handling, expansion,
click-through, page-local geometry, pointer avoidance, narrow-pane overlap,
idle mouse-monitor cleanup, layout skips, independent pages, detachment,
hiding, stale animation delivery and controller release. It also checks URL
formatting, icons, live modifier explanations and preservation of transient text.

## Production path

The status observer resolves the callback's original WebContents and existing
NativePageState. Each state owns a controller inside its native page host.
Attachment, navigation, renderer exit, visibility and page destruction gate the
presentation. Resizing the page within docked DevTools keeps the capsule out of
the tools pane.

The capsule formats actual link URLs and asks the page's outcome callback for
modifier descriptions. It explains background and foreground tabs, Peek and
new windows; local messages such as Reader preparation remain plain text.
Modifier changes update the description immediately. Ordinary text waits half
a second to appear and expands after 1.5 seconds; explained links expand at once.
The controller moves the click-through capsule away from the pointer and rejects
stale animation completions.

Current styling and the two remaining source gaps—split-link descriptions and
continuous Space-theme refresh—are owned by
[web interactions](../../docs/web-interactions.md#hovered-link-status).
