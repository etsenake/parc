# Website top-band color

The renderer samples a page's top band to color Parc's website toolbar. A native
client accepts results only for the current document, displays fresh samples
immediately and maintains a small host cache for future visits. This is separate
from Space themes and does not use the page's advertised theme color alone.

## Renderer sampling

The detector performs four hit tests across the top edge, at one-quarter-width
intervals and y = 1. It normally examines the document top; a fixed or sticky
header uses the visible viewport instead. Candidate bands must be visible,
edge-touching, at least 11 pixels tall and at least one-third of the viewport
wide. Video/canvas elements and the YouTube masthead class are excluded.

Opaque CSS colors can be blended and voted directly. Images, backgrounds and
translucent content may need pixels. Decoded images and gradients use bounded
raster work, capped at 800 pixels, sampling two rows and five horizontal points.
A color distance above 0.5 rejects a nonuniform band; otherwise the samples
produce the candidate average.

Detection runs after lifecycle updates, throttled to 100 ms, and waits for a
clean pre-paint state. Parsing and largest-contentful-paint progress schedule
new attempts. Only the observed outermost document participates; SVG documents
are excluded. A commit resets document state so a prior page cannot report
into its successor.

Before the first largest-contentful-paint result, pixel and translucent-color
paths defer. Votes prefer the strongest element candidate; a usable frame
sample takes precedence, then canvas/document background fallbacks apply under
their parsing and vote conditions. Ties preserve the first candidate.
Frame/background results wait for presentation, and duplicate results are
dropped. Early results do not crossfade; later post-paint changes can.

## Native ownership and cache

The associated observer carries a weak current-document identity. When a frame
copy is needed it reads the top eight device-independent pixels, with one copy
in flight and a queued newer request. Replies must still match their request,
page and document.

The shell keys samples by the real committed HTTP(S) host. Reader presentation,
internal pages and display-only URLs cannot populate a synthetic cache key.
A sample is shown immediately, but persistent convergence waits until its
color is within 0.015 of the previous/cache value or the bounded retry sequence
finishes. Retries are 400 ms apart, at most four. Active tracking can reread at
250 ms and temporarily disable convergence.

The cache keeps the 50 most recently updated hosts and coalesces disk saves for
one second. Regular profiles persist it; private state is memory-only until the
last private window closes. Explicit history deletion by URL host, time range
or all history invalidates matching cache entries. Ordinary history expiration
does not erase them.

## Bounded refresh

Element pixels are sampled at most once per detection. A 1.5-second negative
cache is keyed by image identity/load state, gradient value, raster details,
text color, color scheme and zoom. Image-load changes invalidate it.

An animated image or paint change that keeps those keys unchanged can therefore
leave the chosen band color stale for up to that cache interval. This remains
a performance/refresh tradeoff.

## Sources and checks

The renderer top-band detector, native associated observer and
`TopBarColorClient` feed `BrowserToolbar`. Relevant checks are
`tests/TopBandColor/run.py`, the focused top-band-color script and native/client
component coverage. They exercise candidate decisions, ownership and cache
behavior; syntax/compiler checks cover integration when run.
