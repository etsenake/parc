# Product backlog

This is an index of concrete unfinished behavior and explicit product decisions,
checked against the implementation on November 10, 2026. Subsystem guides own the
details. [Product status](parity.md) describes what exists; this list does not
authorize starting every task.

Completed fixes stay done. Missing test receipts, browser access, user confirmation
and routine release timing are not backlog work. Update or remove an item when
its implementation lands; do not preserve completed rows or percentage tables.

For otherwise unassigned work, retain the requested order: Routing, Windows,
Data, Performance, Folders, Archive, Command bar, Tab switcher, Peek and Onboarding.
Finish assigned work first; explicit deferrals remain deferred.

## Sidebar accessibility and presentation

- Add direct accessibility row-selection setters and spoken Control-Space
  highlight changes. Existing press/custom selection actions work.
  [Sidebar accessibility](sidebar-accessibility.md).
- Honor Reduce Motion in preview-card and Library-width transitions. Restore
  New Tab's pressed scale after a cancelled click, and prevent long Space drags
  from exposing blank strip content. [Sidebar motion](sidebar-motion.md),
  [previews](sidebar-previews.md), [theme rendering](space-theme-rendering.md).
- Finish the documented theme-control hover/dot/tooltip details and floating
  material transitions. Refresh visible tooltips when their palette changes.
  [Theme editor](space-theme-editor.md), [sidebar motion](sidebar-motion.md).
- Keep fallback window geometry and sidebar width associated with the same saved
  window. Refresh open Library width after Space-count changes and enlarge the
  empty card's Pinned drop target during drag. [Resizing](sidebar-resize.md),
  [Space management](space-management.md).

## Routing

- **ROUTE12:** overlapping private-window creation lacks a shared Profile-lifetime
  reservation. Failed creation or last-window teardown can retire a context while
  another creator still needs it. Add shared claims through creation and teardown.
  Ordinary disposition and missing-destination fallback are implemented.
  [Private lifecycle](private-route-lifecycle.md).

## Windows and lifecycle

- **WIN11:** private windows cannot create/open Notes or Easels, browse document
  Library, or send captures to Easels. Private Media and explicit capture saves
  to the parent Profile's Library work. [Capture Library](capture-library.md).
- **WIN12:** folder disclosure is shared across windows; move it into window
  presentation state. Whole pinned-section collapse also needs implementation.
  [Windows](windows-lifecycle.md), [sidebar resizing](sidebar-resize.md).
- **WIN13:** wire shortcut-education Copy availability to native admission, and
  retain/revalidate the original page and hidden destination before popup handoff.
  [Window activation](window-activation.md).

## Data and credentials

- **DATA15:** Safari's own browsing-data export file, a Firefox step for an
  exported password file, Safari's separate Profile stores and other import
  formats need reader support before being offered.
  [Import capabilities](../Engine/ParcImport/README.md#reader-and-writer-boundary).

## Performance

The specifically deferred Downloads investigation is [below](#deferred).
New performance work needs a concrete delay or resource problem; a missing
benchmark is not a defect. [Current implementation](performance-navigation.md).

## Folders

- Ordinary-tab, folder and mixed-selection Option-drag copies are absent; whole
  splits copy. Note/Easel splits cannot copy across Profiles, and document moves
  refuse while source aliases still reference the document. These need explicit
  copy/relocation transactions. [Folder moves](folder-moves.md).
- Close does not handle selections containing only empty saved folders. Favorite
  tiles do not join range/multi-selection. [Sidebar selection](sidebar-selection.md).

## Archive and history

- **HIST13:** live previews support one web tab. Connect document/group preview,
  close consent and promotion to their existing owners; add persisted close-time
  images if previews must show the page as it was when closed.
  [Archive preview](archive-preview.md), [document owners](archive-preview-documents.md).
- **HIST14:** Library Put Back cannot reconstruct deleted nested folder roots.
  Existing window Undo restores the tree; persisted Archive restoration needs
  folder provenance. [Archive](archive.md).

## Command bar

- **CMD25:** Task Manager needs a window-level route for Notes/Easels/empty
  windows; Restore Data needs a backup producer and restore flow; Pinned
  expand/collapse needs sidebar state and commands. [Command bar](command-bar.md).
- Controls covered by the command bar can still show hover feedback. Some
  extension-popup, site-bubble and accessibility focus states also lack sidebar
  button-reveal ownership. [Command bar](command-bar.md), [navigation](navigation.md).
- Clicking the address in a page toolbar, on a single page or a split pane,
  opens the 350-point compact editor under the toolbar. It should open the full
  command bar in the middle of the window, like Command-T, with that pane's
  address selected so submitting navigates that pane. The compact editor belongs
  to the sidebar's address field only; popup windows keep it because they can be
  narrower than the full bar. [Entry points](command-bar.md#entry-points-and-source-owners).
- The sidebar's compact editor feels cramped. At 350 points wide, titles
  truncate early, and its address row's icon and text sit left of the result
  rows' icon and title columns. Widen it to about 450 points and line the address
  row up with the result columns.
  [Appearance](command-bar.md#appearance-and-theme).

## Other input and surface limits

- Add the generic Edit → Format → Font menu route, distinct keypad identities
  and recording mappings beyond F20. Existing document formatting works.
  [Keyboard](keyboard-navigation.md).
- Split dividers lack keyboard/accessibility resizing. Pane-handle drag,
  double-click separation, Option-close unsplit and sidebar drop-to-combine are
  absent. [Split groups](split-groups.md).
- Share Split View… in the split pane menu doesn't work. Remove the item, its
  share action and its menu artwork. [Split groups](split-groups.md),
  [menu artwork](../Resources/SplitPaneMenu/README.md).
- Add split outcomes to hover text, refresh a visible status capsule during
  Space-theme edits, and provide blocked-popup chooser/release UI.
  [Web interactions](web-interactions.md).
- Tooltip shortcut feedback needs the same shifted-symbol matching as command
  dispatch. [Tooltips](tooltips.md).
- Download arrival needs a Reduce Motion path. [Downloads](download-library.md).
- Extension context-menu side-panel toggle is unavailable even though toolbar
  side-panel presentation works. [Extension interaction](extensions-interaction.md).

## Planned interface work

Visual work in each item follows the [interface review](visual-review.md)
workflow, renders first.

- Closing the last tab removes its page at once instead of fading it out
  before the start page fades in. [Start page](start-page.md#transitions).

## Peek

- Continuous swipe tracking, reversal/cancellation, exit fade/snapshots and
  haptics are absent; dismissal currently handles completed right swipes.
- Nested Peek needs parent-chain ownership. Existing parent transfer, orphan
  promotion, Tab/Shift-Tab and live Expand are implemented.
- The Peek card should be measured from the window edge, with the parent page
  shrinking by 9 points per side as it fades. Parc's Peek sits inside the page
  card's clip, so its card is measured from the page card and the parent only
  fades. This needs a Peek host above the page card that keeps window dragging in
  the margins.

## Media

Casting continuity across navigation and picture in picture are implemented.
The remaining work is specific to these paths:

- Correct competing-player cast selection, capture the route's original document
  before navigation, and narrow same-source Connecting labels and speaker-only
  discovery. Media Source on a frozen page cannot append beyond its buffered
  range. [Casting and media boundaries](safari-media-edges.md).
- FairPlay needs MSE pitch-policy forwarding. VP8/MP3 and protected Opus/PCM
  remain unsupported; codec eligibility and fallback behavior belong in
  [FairPlay integration](../Engine/ParcNative/fairplay_chromium/README.md).
- Protected playback also retains reused-context start-date, nested translucent
  video-layer and encrypted AC-3/E-AC-3 channel-layout limits.
  [Native HLS](../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md),
  [composition](../Engine/ParcNative/fairplay_chromium/COMPOSITING.md),
  [native audio](../Engine/ParcNative/fairplay/README.md).
- Native-HLS alternative availability must respect CSP; transport-stream parsing
  still stops at the first matching descriptor. See
  [media boundaries](safari-media-edges.md) for the exact cases and retained scope.
- Worker ManagedMediaSource lacks playback-position feedback for its high-water
  stop. Existing shared workers keep their old identity until they end. The
  [web surface](fairplay-safari-surface.md) and [identity](fairplay-identity.md)
  guides own these limits and the output-protection/codec details.

## Engine architecture

These shrink what each Chromium upgrade must refit, or what an engine build costs. None changes
what users see or hear today, and each must keep it that way.
[How Parc changes Chromium](chromium-seams.md) owns the details.

- Reverse playback's window planning and Safari's multi-track audio mixing still sit inside
  Chromium's renderers, so every upgrade must refit them there. Moving them into Parc files ships
  only with a real playback check that backward playback still shows frames and Safari-identity
  pages with two audio tracks still mix them.
- The AAC `decodeAudioData` path could become a hook. If the hook lost today's pipelined decoding,
  pages decoding AAC audio could wait roughly a second longer per three-minute track, so measure
  decode throughput in a running browser before switching.
- Optional experiments that could remove more patched media code, each needing its own measurement
  and approval because a regression would show as stalled or mis-composited protected video: the
  wait-for-key latch inside the player, `SetOutputIsSecure` in place of the parked-compositor flag,
  a composite renderer and a separate FairPlay process with `CALayerHost`.

## Deferred

- **SCRIPT10–SCRIPT13:** broader scripting commands, error contexts, collection
  properties and window/sidebar mutation remain deferred. Existing automation
  works. [Scripting](scripting.md).
- **PERF09 / DL-PERF-01:** investigate large-Downloads-folder stalls after polish.
  The original report concerned another browser; establish a repeatable Parc
  delay and distinguish filesystem size, history size, throughput and UI work
  before choosing a fix. [Downloads](download-library.md).
- **Cross-window cases explicitly deferred:** automatic return to a non-key
  window can leave a blank placeholder; failed close after transfer can leave
  the tab selected; foreign-window split closing is restricted; Close-Peek Undo
  requires the local parent, though Reopen works. [Windows](windows-lifecycle.md).
- Rare reverse-playback optimization and additional 3GPP/AMR formats retain their
  existing scope decisions. [Media boundaries](safari-media-edges.md).

Keep details in the linked guide and current ownership only while a task is
active. Follow [the documentation policy](documentation.md); this index should
stay below 400 lines.
