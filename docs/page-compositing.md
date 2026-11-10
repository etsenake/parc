# Page compositing

Parc gives each native window a recyclable compositor pool. A page acquires a
compositor before it is shown and can retain a compatible last frame while a
new renderer frame arrives. The pool serves tabs, split panes, Peek, live Easel
captures, DevTools, popups and document picture in picture.

## Ownership and attachment

The pool is keyed by `NSWindow`, shared by browser hosts and Profiles in that
window. A page keeps its own compositor when possible, otherwise takes a hidden
idle one or allocates a new one. The previous page detaches before another page
attaches. The renderer's root layer is displayed through `DisplayCALayerTree`
under the parent compositor.

The display view lives immediately above the renderer inside `WebContentsView`,
fills its bounds, and accepts no input, focus or accessibility role. Native
responder traversal skips it. Attachment must precede showing: once the parent
compositor is installed, the renderer's own direct drawing is disabled.

Chromium can remove the display view during detachment. `restoreContentView`
repins the exact hierarchy and hidden state while the host is busy. A busy
handoff returns busy and schedules visibility/layout reconciliation rather than
showing an unattached page. Shell selection and layout run visibility in the
same commit after arrangement; posted reconciliation remains for adoption,
selection and reentrant work.

## Reusing a frame

A retained frame is usable only for the same role, such as page versus docked
DevTools, and when both its layer bounds and page-view dimensions cover at least
90% of the requested size in each dimension. An incompatible frame is cleared
instead of stretching the wrong pane into view.

Candidates rank by fit, overlap, availability and recency. A hidden compositor
retains its frame; drawing stops when an ancestor is hidden or it leaves the
window unless a capture lock requires drawing. In-flight presentation callbacks
do not restart hidden drawing. Showing resumes it, and screen changes refresh
scale, color and HDR properties.

The shell settles dirty page-host geometry before exposing the renderer. This
keeps a newly selected page attached at its current pane size rather than a
stale size from its previous host.

## Retirement and shutdown

The idle sweep runs every two seconds. It marks unused candidates and retires
them on a later pass, keeping one most-recently-used idle spare while a host
exists. A compositor still owned by a hidden or minimized page is not an idle
spare. A window with no host retains none.

Page destruction detaches first. Deferred release cannot destroy the pool in
the middle of its own callback; if the task cannot be posted, the fallback
retains the reference instead of using freed state. Application shutdown calls
`PrepareNativeApplicationShutdown` to detach and destroy pools before
`CefShutdown`, while the required native infrastructure is still available.
Shutdown must not depend on a future task running.

## Remaining boundaries

Retaining a frame cannot manufacture one. Newly allocated compositors, evicted
frames, pages that have never drawn and incompatible pane sizes can show the
normal backing until their first frame. Docked DevTools can also show backing
when its previous compositor was evicted from the single-spare pool.

These are current lifecycle boundaries, not a claim that every visible flash
has been reproduced or that a particular user report has this cause.

## Sources and validation

The implementation is in the native page host/compositor bridge and window
selection/layout integration. Focused checks cover compositor reuse policy,
`NativePageHost`, `NativeFocusManager`, `NativeDevTools` and packaging exports.
Native compiler checks validate bridge integration when run.

This document describes current source. Model checks and compilation do not
prove first-frame smoothness across real windows, GPUs, displays or DevTools
transitions. No application was launched for this documentation cleanup.
