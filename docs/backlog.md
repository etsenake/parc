# Product backlog

This is the bounded list of unfinished product work carried forward from the
old ledger and reconciled on November 10, 2026. It is not a new authorization to
start every task. [Product status](parity.md) describes what exists; subsystem
guides own technical details. Legacy IDs keep unresolved obligations traceable
without preserving thousands of completed rows or percentage tables.

Keep only concrete missing behavior, explicit deferrals and product decisions.
Completed fixes do not wait for user confirmation or another browser test.

Keep the existing requested order for otherwise unassigned work: Routing,
Windows, Data, Performance, then Folders, Archive, Command bar, Tab switcher,
Peek and Onboarding. Product quality applies throughout. Finish assigned work
first; scripting and the specifically deferred items below stay deferred.

## Reported behavior

- **What's New address leakage:** native History can retain its local file URL,
  and engine copy paths can expose the committed file address while a new typed
  destination is loading. These need engine history/copy handling, beyond the
  current shell's address masking. [Software updates](software-update.md).

## Sidebar accessibility

- Outline/row accessibility selection is read-only; press/custom actions can
  select items. Control-Space highlight movement has no dedicated announcement,
  although scope changes do. Decide and verify the intended assistive-technology
  behavior before treating the broader accessibility requirement as complete.
  [Sidebar accessibility](sidebar-accessibility.md).
- Forced-appearance floating-sidebar contrast and uncolored/colored swipe
  material changes remain documented presentation risks. Resize frame holds,
  transfer subscriptions and fallback frame restoration have specific boundary
  semantics, not newly reproduced bugs. Keep their focused checks and limits in
  [sidebar motion](sidebar-motion.md) and [resizing](sidebar-resize.md).

## Routing

- **ROUTE12 — reconcile:** disposition and unavailable-destination fallback
  behavior remains the single carried routing requirement. Audit current
  external/internal routing and exact destination ownership before defining the
  remaining change, including shared Profile reservation during overlapping
  private-window creation. The Links editor and close-commit handoff are implemented.
  [Settings](settings.md), [routing interaction](routing-interaction.md).

## Windows and lifecycle

- **WIN11 — reconcile:** remaining private Library, document-modal,
  capture-to-Easel and cross-window retirement cases. Private Downloads, Media
  catalog access and explicit capture-to-Library already exist; do not present
  the whole private experience as missing. [Private lifecycle](private-route-lifecycle.md),
  [capture Library](capture-library.md).
- **WIN12 — reconcile:** Dock/logout and restoration across window states,
  window-local folder disclosure, pinned-section interaction and nested Peek
  behavior. Dock reopen, window identity, Stay on Top and session records are
  implemented. [Windows](windows-lifecycle.md).
- **WIN13 — reconcile:** remaining focus/activation, auxiliary-window and modal
  interruption cases, including popup handoffs. Existing command admission and
  owner-validation work must stay intact. Native command-window and hidden-page
  destination queries exist; remaining shell consumers still need integration.
  [Window activation](window-activation.md).
- **WIN15 — reconcile:** remaining private/popup/standard-window appearance and
  transitions; existing private indicators and popup controls are implemented.
  [Window appearance](window-appearance.md).

## Data and credentials

- **DATA13 — acceptance:** stable Developer ID signing and Parc Safe Storage
  migration are implemented. Actual encrypted restart and upgrade/authorization
  continuity still lack acceptance; preserve old keys and ciphertext and normal
  macOS consent. [Keychain contract](../tests/KeychainNamespace/README.md),
  [release operations](master-release.md).
- **DATA14, DATA16 — reconcile:** source-specific discovery/access/recovery,
  keyboard/accessibility and presentation. Import now processes all readable
  source Profiles into their intended destinations; the old destination/profile
  chooser is not current UI. Recent onboarding completion supersedes broad
  “missing import UI” statements.
- **DATA15 — capability boundary:** unsupported source credential/encryption
  formats must be reported honestly, with supported file-import alternatives.
  Determine which additional sources are feasible before promising support.
  [Browser import](browser-import.md).

## Performance

- **PERF04–PERF08 — acceptance and measured fixes:** navigation/page loads;
  input, scroll and sidebar frame pacing; sustained media/long sessions;
  memory/CPU; cold/warm startup in the shipping configuration. Existing targeted
  fixes do not constitute a representative benchmark. Keep measurement and
  regression fixes separate from merely stabilizing a test.
  [Navigation performance](performance-navigation.md).
- **PERF09 / DL-PERF-01** remains deferred until after the product polish pass;
  see [deferred work](#deferred).

## Folders

These older obligations need a focused source reconciliation against the
implemented collection transactions before choosing another implementation:

- **FOLD16–FOLD18:** cross-Profile collection moves; external/copy dragging and
  spring-loaded expansion; remaining Favorite/selection modifier cases. Mixed
  ordinary-tab/folder-plus-split Option-copy remains unsupported; whole splits
  copy. Note/Easel splits cannot copy across Profiles, and documents still
  referenced by the source Profile cannot move across it.
- **FOLD19–FOLD20:** group opening and included archive/restoration cases.
- **FOLD21–FOLD22:** move feedback, menus, disclosure/ancestor highlighting,
  drag geometry/motion and haptics. Inline folder-title editing remains separate
  from the split New Folder command's guarded rename prompt.
- **FOLD23:** decide whether another Duplicate entry should support Undo from
  actual current ownership. The existing context command has none; this is not
  an instruction to invent a duplicate-Undo feature.

[Folder moves](folder-moves.md), [folder commands](folder-commands.md).

## Archive and history

- **HIST13:** row-click preview/Expand is implemented. A persisted close-time
  snapshot cache remains separate from that live preview. The current shell
  accepts one HTTP(S) web record only; document/group preview promotion still
  lacks its complete shell transaction despite an existing document owner.
- **HIST14 — reconcile:** nested archived-root reconstruction and broader
  restoration cases.
- **HIST15–HIST17 — reconcile:** search/filter/selection presentation,
  Library/preview transitions, keyboard/accessibility/focus and action ownership.

[Archive](archive.md), [archive preview](archive-preview.md),
[document previews](archive-preview-documents.md).

## Command bar

- **CMD25 — source gaps:** Task Manager requires a native page, so Notes,
  Easels and empty windows need a window-level engine route. Restore Data lacks
  a sidebar-backup producer. Expand/Collapse Pinned Section lacks its sidebar
  implementation. Keep unsupported actions honest until their dependencies exist.
- **CMD24, CMD26–CMD28 — reconcile:** remaining ranking/preview decisions,
  geometry/theme treatment, pointer/motion/haptics and IME/keyboard/accessibility
  interruption cases. In-window hosting, live commands and recent editing/ranking
  corrections already exist. Toolbar/pane/split/extension controls covered by
  the command bar still lack the sidebar's hover-suppression admission.
- **Related hover status:** Option-click and Option-Command-click already open
  links in splits; hovered-link outcome text still lacks their split variants.
  This is a label gap, not missing split navigation.

[Command bar](command-bar.md), [web interactions](web-interactions.md).

## Other input and surface limits

- Generic Edit → Format → Font menu integration is absent; existing Note/Easel
  formatting works. Shortcut storage still conflates keypad Clear with Escape
  and keypad multiply with `*`. [Keyboard](keyboard-navigation.md).
- Blocked popups have no chooser/release UI. The hovered-link capsule updates
  its theme on presentation/appearance changes, not continuously while editing
  a Space theme. [Web interactions](web-interactions.md).
- Download-arrival motion has no Reduce Motion gate. Filesystem Documents,
  Desktop and Screenshots have flyout sources, not dedicated Library pages;
  Library Documents means Notes/Easels. [Downloads](download-library.md).

## Tab switcher

- **MRU10–MRU13 — reconcile:** remaining card geometry/type/material, replacement
  and selection motion, refusal/interruption, keyboard/accessibility and
  hover/pressed/haptic cases. The working switcher and navigation stay supported.

[Tab switcher](tab-switcher.md).

## Peek

- **PEEK15 — product decision:** retain the explicit local link policy until
  its intended factory defaults are settled.
- **PEEK16–PEEK19 — reconcile:** geometry/states; Tab/Shift-Tab/accessibility
  edges; continuous swipe reversal/cancellation; snapshots, promotion/reveal and
  haptics. Open in Current Space and live Expand bindings are already implemented.
- **PEEK20–PEEK21 — reconcile:** parent physical-window transfer, missing-parent
  handling and remaining promotion/cross-window creation provenance.

[Peek](peek.md).

## Onboarding

- **OB17 — ordering decision:** Favorites currently follows the whole import.
  Keep that default pending a decision on moving it immediately after source
  selection. The other 35 original onboarding requirements are implemented;
  old “75% complete” and already-closed theme/extension/reveal/traversal gaps
  were stale. [Onboarding](onboarding.md).
- Actual VoiceOver, Full Keyboard Access, default-browser consent and complete
  first-launch/replay behavior have separate acceptance limits; do not turn
  passing model or compiler checks into a real-user acceptance claim.

## Media capability and acceptance

- The FairPlay decoder still lacks VP8/MP3 support; transitions into unsupported
  codecs need truthful failure/recovery. VP9/Vorbis remain restricted to the
  Safari-identity route. [FairPlay integration](../Engine/ParcNative/fairplay_chromium/README.md).
- Media playback grants have a remaining multi-player association concern;
  document-move preservation exists, but no current two-player reproduction
  establishes a user-visible failure. Add a focused ownership regression before
  selecting a correction. The same integration guide owns this detail.
- Protected-service playback, output protection/privacy, physical AirPlay
  receivers and system caption styling have device/runtime acceptance limits.
  Built engine artifacts do not resolve those limits. Preserve the supported
  native-HLS route and the MSE route's lack of AirPlay rather than promising
  unsupported casting. [FairPlay identity](fairplay-identity.md),
  [native HLS](../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md).

## Product quality

**POL01–POL12** now describe product quality, not a mandate to copy another
browser. Preserve coverage of the complete interaction/state inventory; icon
optics; typography/spacing/material; light/dark/themes and window sizes; menus
and modals; hover/pressed/disabled/selected states; animation/frame pacing;
interruption/reversal; keyboard/gestures/focus; accessibility/contrast/Reduce
Motion; sound/haptics; and integrated journeys. Fix concrete defects as they
are found. Sampled flows cannot establish exhaustive coverage.

## Deferred

- **SCRIPT10–SCRIPT13:** additional quit/command/error behavior, collection order
  and properties, window/sidebar mutation and scripting failure contexts remain
  deferred by the current product scope. Preserve existing scripting. [Scripting](scripting.md).
- **PERF09 / DL-PERF-01:** after polish, investigate large-Downloads-folder
  stalls. This began as reported feedback about another browser, not a
  reproduced Parc defect. Establish the original report and reproduction;
  distinguish filesystem size, history size, transfer throughput and UI stalls
  before choosing a fix. [Downloads](download-library.md).
- **Cross-window limitations accepted for deferral on November 2:** a frozen
  placeholder can be blank after automatic return to a non-key window; a close
  that cannot begin after transfer can leave the tab selected; foreign-window
  split close eligibility is restricted; Close-Peek Undo is unavailable while
  its parent is elsewhere, though Reopen works. Reconcile current source before
  reopening these explicitly skipped cases. [Windows](windows-lifecycle.md).

## Keeping this useful

No completed-row history, percentage denominator, obsolete agent reservation or
raw test transcript belongs here. Each active item needs a concrete next step
and an owner only while ownership is current. Update or remove the item when
its source change lands; retain lasting behavior in the subsystem guide.
Keep this backlog below 400 lines, and follow [AGENTS.md](../AGENTS.md).
