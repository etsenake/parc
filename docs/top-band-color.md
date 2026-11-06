# Top-band page colour

1Password onboarding page's blue header, ChatGPT's black, YouTube's
`#0F0F0F`. Its engine decides that colour in the renderer from the page's
layout and styles, falls back to copying the composited frame when the styles
cannot tell it, and its app settles and caches the result per site. Parc now
does the same (overlay 294, pending its engine build). The bar's fill, ink and
crossfade are in [split groups](split-groups.md#top-bar-page-colour).

This page records what was recovered, from where, and how Parc maps it.
Recovered pseudocode is evidence, not original source.

## Evidence

  synthesized; the tracker's real entries were found from prologues. Strings
  `../../arc/blink/core/top_band_color_tracker.cc`, `ScheduleDetection`,
  `FireDetection`, `ytd-masthead`, `youtube.com`, `.youtube.com`,
  `arc::TopBandColorTracker::EmitChosenState(blink::LocalFrameView *, ChosenState)`.
  Bounded REA raw-slice decompilations (evidence IDs) of `0x4684838`
  (`ev_07ed6d4b…`), `0x46849d0` (`ev_b930c826…`), `0x4684c40` (`ev_a8069308…`),
  `0x4686a2c` (`ev_3c874a5d…`), `0x4686b58` (`ev_a13c50b7…`), `0x4686cb8`
  (`ev_d5ce8b7f…`), `0x4687028` (`ev_d7400cc9…`), `0x46874c0` (`ev_a4f1143c…`),
  `0x46876a0` (`ev_fe78c7e0…`), `0x18f4550` (`ev_45aced16…`) and `0x23d6c9c`
  (`ev_4d127634…`); the rest is bounded annotated disassembly.
  predates the engine's `shouldCrossfade` callback, so its one consumer was read


**Ownership.** `LocalFrame`'s constructor (`0x2716a30`) creates the tracker
(`0x4684838`, 0x138 bytes) for main frames behind the Blink runtime feature
`TopBandColorSampling` (`enableTopBandColorSampling` web preference) and
stores it at `LocalFrame+0x18c`; `0x46848f0` traces it. It owns a
`HeapTaskRunnerTimer<TopBandColorTracker>` on `TaskType::kInternalDefault`
(23). Everything runs on the renderer main thread.

**When it runs.** Only after lifecycle updates, so any layout, style, scroll,
animation or paint change can trigger it; there is no DOM observer or periodic
timer of its own.

- `LocalFrameView::RunPostLifecycleSteps` ends with `FireDetection`
  (`0x1afc5fc`).
- `FireDetection` (`0x46849d0`): while the 100 ms timer runs, it only marks a
  detection pending (and still detects if a report is waiting for a frame);
  otherwise it restarts the timer and detects. The timer (`0x46847c0`)
  schedules an animation frame for a pending detection
  (`ScheduleAnimation(kOther, 0, "ScheduleDetection")`).
- `Document::FinishedParsing` (`0x18f4550`) marks parsing finished and
  schedules a detection.
- `Document::OnLargestContentfulPaintUpdated` (`0x23d6c9c` → `0x46876a0`) marks
  a contentful paint, forgets the last pixel-sampled element and schedules a
  detection.
- `DocumentLoader::CommitNavigation` (`0x1fecd00` → `0x1fefbd0`) resets every
  field, stops the timer and invalidates pending reports; it reports nothing.
- A missing layout view reports "no colour" once and stops detection until the
  next commit.

**Sample points (`0x4684c40`).** `W` is the layout viewport's visible width
without scrollbars (`0xa9d440`). Four list-based, penetrating hit tests
(`HitTestRequest` `0x1c26`: read-only, active, ignore clipping, ignore
`pointer-events: none`, list-based, penetrating; `HitTestNoLifecycleUpdate`,
`0xce07c0`) at `x = i·⌊W/4⌋` for `i = 0…3` and `y = 1`. Unscrolled, and when
scrolled without a fixed header, points go through `DocumentToFrame`
(`0xa506808`), so the band stays at the document's top while the page
scrolls. When scrolled, the first band element at `x = 0` decides: if it or a
container up to the layout view is fixed or sticky, all four points stay in
the viewport.

**Band elements (`0x4686a2c`).** An element that is visible, displayed and not
fully transparent, whose absolute bounding box is at least 11 px tall and
`⌊W/3⌋` wide, and reaches the viewport's left edge (`x ≤ 0`) or right edge.
covering all three inner columns.) `<video>` and `<canvas>` are never band
elements. On `youtube.com` and its subdomains, an element with class
`ytd-masthead` is skipped, so YouTube's page background shows through.

**Each point's vote.** Nodes are taken topmost first:

1. Opaque `background-color`: vote for the element with that colour, with any
   translucent elements above it blended over (`Color::Blend`, `0x1288a1c`);
   the topmost translucent element owns that vote.
2. Fully transparent: next node.
3. Translucent: blended into the overlay; next node.
4. Colour decided by pixels: an `<img>`, `opacity < 1`, or a background image
   that can reach the band. A layer that does not repeat vertically and is
   anchored at the bottom never counts; a non-repeating bitmap shorter than
   half the element leaves the background colour in charge. The tracker
   samples the `<img>`'s decoded bitmap, else the first background layer with
   an image (a generated one, such as a gradient, drawn at the element's size
   up to 800 px a side), and votes only for an opaque result. The same element
   within 1.5 s with an unchanged background and opacity reuses the last
   result (`0x4686b58`).
5. Pixels with no usable colour: the tracker asks the browser to sample the
   composited frame (a frame-sample vote with an id), unless a visible
   `<video>` or `<canvas>` at least `⌊W/3⌋ × 11` covers that point, or the page
   is scrolled and this is not the last frame-sampled element. In the scrolled
   case the report is flagged to reuse the browser's last frame sample.
   Otherwise next node.

Before the document's first largest-contentful-paint update, a translucent or
pixel-coloured element at any point abandons the whole detection, so pages do
not report a colour while still painting their header. A point with no vote
counts for the canvas background when that is opaque (or votes for the
overlay blended over it).

table order). A frame-sample winner always wins; otherwise the canvas
background wins with more votes than the best element. With nothing chosen,
the document background (`LocalFrameView::DocumentBackgroundColor`,
`0x1288750`) is reported once parsing has finished; a translucent one reports
"no colour".

**Pixel sampling (`0x40c05c0`, shared with the browser).** Five samples across
row 0 and five across row `min(8, h) − 1`, at `x = i/4 · (w − 24)`. If the
largest RGB distance (each channel scaled to 0…1, alpha ignored) among the
row-0 samples, or between the outer pairs of the two rows, is 0 the colour is
row 0's first sample; above 0.5 there is no colour; otherwise it is the
rounded average of row 0's five samples.

**Reporting (`0x4687028`, `0x46874c0`).** A report equal to the last sent one
is dropped. Frame-sample and document-background reports wait for the next
presented frame (`ChromeClient::NotifyPresentationTime`, vtable slot
`0x418`), so the browser copies and the bar changes with that frame; a newer
detection replaces or cancels a waiting report. The mojo message (`0x418c740`,
name hash `0x597900bf`) carries an optional `SkColor`, "sample the frame",
the frame-sample id, "reuse the last frame sample" and `shouldCrossfade`.
`shouldCrossfade` is false for reports before the document's first
largest-contentful-paint update and for the first report after it, and true
afterwards; later LCP updates do not reset it.


The frame host (`0x1e3ad9c`) forwards the outermost frame's message to
`0x40c0094`. A colour report clears any pending frame sample and is delivered
(replaced by the last frame sample's colour when asked to reuse it). A
frame-sample report is answered from the cached sample with the same id, or
by copying the view's top 8 DIP (`CopyFromSurface`, `0x40c0230`) and sampling
it with 8 × scale rows and a 24 × scale right margin (`0x40c04bc`), which skips
overlay scrollbars. Only one copy runs at a time; a newer id waits for it.
Deliveries happen only when the colour changes (`0x40c0124`) and reach the app
as `webContents:didSampleTopBandColor:shouldCrossfade:` through


- **State per page** (`TopBarColorState`): `colorToDisplay`,
  `currentColorSample`, `numConvergenceAttempts`, `requireConvergence`
  displayed at once. It is written to the domain cache when convergence is not
  400 ms, at most four times, so a colour that holds still gets cached.
  convergence off and re-reads its sample after 250 ms.
- **Cache** (`domainCache`): keyed by URL host (`NullString` without one,
  `TopBarColorCache` default as `{host: {Color: hex, LastUsed: time}}`
- **Consumers.** Only `TopBarPanelContainerView` conforms to
  `TopBarColorListener`: the top bars of split panes and of the Toolbar
  preference. A bar newly showing a page starts, without animation

## In Parc

- **Renderer.** `TopBandColorTracker`
  (`Engine/ParcRenderer/top_band_color_tracker.{h,cc}` →
  `third_party/blink/renderer/core/frame/parc_top_band_color_tracker.*`) is
  created for an ordinary page's outermost main frame in `LocalFrame`'s
  constructor (not for SVG-image pages) and hooked into the same four places
  by `Engine/ParcHost/integration/top-band-color.patch`. It detects only while
  the browser observes it. The pure rules (pixel sampling, band geometry, the
  vote table and choice, pixel memory and the browser's delivery state) live in
  `Engine/ParcRenderer/top_band_color_sampling.h`
  (`third_party/blink/public/common/parc/`), shared by both processes.
- **Channel.** `parc.mojom.TopBandColorAgent`/`TopBandColorObserver`
  (`Engine/ParcRenderer/top_band_color.mojom`, in `mojom_core`). Following
  Parc's website-theme agent, the browser binds the renderer's agent on the
  frame's associated channel and passes its observer; when it arrives the
  tracker resends its last report and schedules a detection, and a
  disconnected observer stops detection.
- **Browser.** `TopBandColorSampler` in `native_appkit_page.mm` copies and
  samples frames and publishes `PCNativePage (TopBandColor)`
  (`hasTopBandColorSample`, `topBandColor`, `topBandColorHost`,
  `topBandColorCrossfades`); its deliveries pass the page's shell-notify
  filter. A new document forgets the delivered colour and drops any copy still
  in flight. `topBandColorHost` is the host of the committed website (http or
  https) document that sent the colour, never the visible or Reader display
  URL; Reader, extension and internal pages report none, so their colour is
  shown but not cached.
- **App.** `TopBarColorClient.swift` ports the client. A colour is cached only
  under the host it was sampled from, and a previous host's sample never
  counts as convergence for the next one. `PaneTopBarPageColor.swift` feeds
  each delivery to it and shows its colour (looking the cache up by the page's
  a change animates. A bar takes its window's private state from the window
  controller (private when it has none). Engines before overlay 294 keep the
  overlay 293 stand-in: the declared theme colour, then the composited
  background.
- **Forgetting.** Private windows keep their cache in memory until the last
  open one, counted from the app delegate's browser windows, closes. A
  profile's history deletion in the engine (Clear Browsing Data, history
  removal, but not old history expiring) posts
  `PCNativeHistoryDidDeleteNotification`; the client forgets the deleted URLs'
  hosts and the colours cached during a deleted time range, or everything for
  all history, and writes the cache at once. The Library's Remove and Clear
  History do the same for Parc's own history.
- **Checks.** `tests/TopBandColor/run.py` syntax-checks the tracker, the four
  patched Blink files and `native_appkit_page.mm` with their targets' actual
  flags; `scripts/test-top-band-color.sh`, `tests/TopBarColorClient` and
  `tests/BrowserToolbar` cover the rules, the client and the bar.

its hash order. Detection is skipped when the lifecycle is not at least
image or gradient again for every sample point and detection. Parc reads it
once per detection and remembers an element whose pixels gave no colour for
1.5 s, keyed by what decides its pixels: each image's identity and whether it
has finished loading, and for a gradient its value, raster size, text colour,
colour scheme and zoom. A restyle that changes none of these reads nothing;
animated image whose current frame gave no colour, a CSS Paint API
(`paint()`) background whose output changed while its value did not, and an
element whose image is replaced by a new one at the same address. Parc draws
under its URL's host, hostless ones under one `NullString` entry; Parc caches
only http and https websites. There is no
be in a particular state before delivering (`0x40c0178`–`0x40c01d0`, not
identified) and has a "copy again" flag (`+0x40`) with no setter found; Parc
their alphabetical order among Blink's HTML element classes (`'!'` is
`HTMLImageElement`, confirmed by the LCP code that sets its LCP flag); the
"visible" style test, the same-element style comparison and the image-height
test are read from field layouts and approximated with Blink's public
accessors.
