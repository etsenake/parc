# Experience parity ledger

## Family completion

| Priority | Family | Done | Left | Latest change | Owner |
|---|---|---:|---:|---:|---|
| Complete | [Keyboard shortcuts and keyboard gestures](#keyboard-shortcuts-and-gestures) | 100.0% | 0.0% | +2.6 pp | Completed recovery; original `claude-kbd-*` owners retired |
| Complete | [Downloads](#downloads) | 100.0% | 0.0% | +3.0 pp | Claude `claude/downloads` |
| 1 · Complete | [Sidebar](#sidebar) | 100.0% | 0.0% | +5.9 pp | Claude `claude/sidebar` |
| 2 · Complete | [Today / pinned tabs / favorites](#today--pinned-tabs--favorites) | 100.0% | 0.0% | +4.5 pp | Claude `claude/today-favorites` |
| 3 · Complete | [Automatic archive](#automatic-archive) | 100.0% | 0.0% | +16.7 pp | Completed AUTO09–AUTO12 owners; retired after publication |
| 4 · Complete | [General navigation and gestures](#general-navigation-and-gestures) | 100.0% | 0.0% | +6.2 pp | Claude `claude/navigation` |
| 5 · Complete | [Split views](#split-views) | 100.0% | 0.0% | +3.0 pp | Codex `recover_sp33`; recovered Claude work in original `claude-split-sp33` |
| 6 · Complete | [Web interactions](#web-interactions) | 100.0% | 0.0% | +5.3 pp | Claude `claude/web-interactions` |
| 7 · Complete | [Extensions](#extensions) | 100.0% | 0.0% | +7.1 pp | Completed EXT11–EXT14 owners; retired after publication |
| 8 · Complete | [Spaces and profiles](#spaces-and-profiles) | 100.0% | 0.0% | +5.6 pp | Complete; SPACE18 independently reviewed and delivered |
| 9 · Complete | [App identity and icon variants](#app-identity-and-icon-variants) | 100.0% | 0.0% | +9.1 pp | Completed ICON08–ICON11 authors and independent reviewers; retire after publication |
| 10 · Complete | [Settings](#settings) | 100.0% | 0.0% | +3.7 pp | SET01–SET27 independently reviewed and delivered; authors/reviewers retire after publication |
| 11 · Complete | [Screenshots and recordings](#screenshots-and-recordings) | 100.0% | 0.0% | +4.2 pp | CAP01–CAP24 independently reviewed and delivered; authors/reviewers retire after publication |
| 12 · Complete | [Easels](#easels) | 100.0% | 0.0% | +3.4 pp | EASEL01–EASEL29 independently reviewed and delivered; original authors/reviewers retire after publication |
| 13 · Complete | [Notes — local restoration](#notes--local-restoration) | 100.0% | 0.0% | +3.8 pp | Cursor `cursor/notes` (claimed October 29) |
| 14 · Complete | [Page tools](#page-tools) | 100.0% | 0.0% | +5.9 pp | Cursor `cursor/page-tools` (claimed October 29) |
| Complete | [Media](#media) | 100.0% | 0.0% | +5.9 pp | Cursor `cursor/media12` (MEDIA12); prior Codex `codex/media-family` retired |
| 16 | [Routing](#routing) | 92.3% | 7.7% | +7.7 pp | Codex `codex/routing-family` (claimed October 29) |
| 17 | [Windows and lifecycle](#windows-and-lifecycle) | 71.4% | 28.6% | +4.8 pp (scope) | Codex `codex/windows-lifecycle` (claimed October 29) |
| 18 | [Data and credentials](#data-and-credentials) | 75.0% | 25.0% | — | Available |
| 19 | [Performance](#performance) | 40.0% | 60.0% | +10.0 pp | Codex `codex/perf04` (claimed October 29) |
| After listed | [Folders](#folders) | 65.2% | 34.8% | — | Available |
| After listed | [Archive and history](#archive-and-history) | 70.6% | 29.4% | — | Available |
| After listed | [Command bar](#command-bar) | 82.8% | 17.2% | +0.7 pp | Codex `codex/command-bar-polish` (reported command failures and appearance) |
| After listed | [Tab switcher](#tab-switcher) | 69.2% | 30.8% | — | Available |
| After listed | [Peek](#peek) | 66.7% | 33.3% | — | Available |
| Before polish | [Onboarding / complete first launch](#onboarding-and-complete-first-launch) | 75.0% | 25.0% | +2.8 pp | Cursor `cursor/document-close` (claimed October 31) |
| After listed | [Whole-product polish](#whole-product-polish) | 0.0% | 100.0% | — | Available |
| Complete | [Standalone Chromium architecture](#arccore-replacement-work-map) | 100.0% | 0.0% | — | Complete |
| Excluded | Live integrations | Excluded | Excluded | — | Excluded |
| Deferred | [Automation and scripting](#automation-and-scripting) | 69.2% | 30.8% | — | Deferred by Josh October 29 |

Percentages count the fixed DONE/LEFT requirements linked above; partial work stays LEFT. Latest change is the percentage-point movement from the preceding delivery for that family, calculated before rounding. — means its first counted baseline or excluded scope. Appearance and interaction requirements are included; these are requirement counts, not estimates of remaining engineering hours.

**Five-minute updates — corrected user direction, October 28:** report each active row's estimated completion and movement, concrete changes and actual current step, in Claude's plain wording. These per-row updates do not replace the fixed delivery counts above or grant partial DONE credit. Do not repeat estimate disclaimers or revisit completed rows because their old names remain on reused worktree folders. Initial active-row estimates: EXT11 95%, EXT12 70%, EXT13 90%, EXT14 80%, SPACE13 65%; subsequent updates report movement from the preceding estimate.

**Whole-product polish and runtime checks — user direction, October 29:** begin
whole-product polish immediately. Josh explicitly reauthorized running and using
investigation. This supersedes the earlier browser-test prohibition and the
older order that placed polish after the listed families. Preserve current
ownership and unfinished rows while pursuing the requested comparisons and fixes.

**Swift SIL clarification — October 29:** Josh clarified that the whole-module SIL pass is for closing complete rows, not every partial increment. Partial increments still receive appropriate checks and independent review before publication; authors continue their rows through completion.

**Review scope clarification — October 29:** when every increment has been independently reviewed, do not repeat a complete historical diff review at row completion. Review new and materially changed code and its integration with earlier reviewed increments; previously cleared, unchanged code need not be reviewed again.

**Parallel work within rows — October 29:** Josh directs each row owner to actively assign independent research, implementation and dependencies to fresh focused agents while other increments are being built, checked or reviewed. The owner coordinates and integrates their work and remains responsible for the whole fixed row. See [the working contract](../AGENTS.md) and [collaboration guide](collaboration.md).

**Independent delivery — October 29:** completed, checked and reviewed rows publish without waiting for a separately owned consumer to integrate them. The consuming owner takes the integration and records the interface and handoff; unowned required work and an author's own unfinished requirements remain that author's responsibility. ROUTE14 delivers independently; ROUTE13 owns integrating it into its editor.


**Stop after Easels — user direction, October 29:** finish only the final Easels app package, input/resource/export/signing verification and receipt publication, then stop. All 29 Easel rows are independently reviewed and published at `e82e4f5e`. After successful final delivery, disable the five-minute progress heartbeat. Do not claim or start Notes or any later family without a new request from Josh. This supersedes the earlier automatic-continuation authorization.

**Notes continuation — user direction, October 29:** Josh requested the next remaining family after that Easels stop. Notes is the active family in the table above. Other later families stay unclaimed. The five-minute heartbeat applies to this family's active rows.

**Page tools — user direction, October 29:** Josh requested Page tools next and moved it from priority 17 to 14. Notes remains 13 with its existing owner. Media and Routing follow as 15–16; the later Windows and lifecycle priority change is recorded below. The Easels stop is superseded for this family. Josh later the same day: remaining LEFT rows run in parallel (multitask). Active rows: TOOLS16 and TOOLS17 concurrently. The five-minute heartbeat applies to this family's active rows.

**Windows and lifecycle priority — user direction, October 29:** move Windows and lifecycle immediately below Routing, ahead of Data and credentials, and pick up that family next. Existing Media and Routing assignments continue.

**Remaining priority order:** preserve the numbered families and then the remaining families in their displayed order. Onboarding remains immediately before Whole-product polish; its existing work and fixed counts remain intact. Automation and scripting is deferred to the bottom of the table.

**Automation and scripting deferred — user direction, October 29:** prioritize a working browser first. Defer all remaining scripting and automation beyond what is already implemented until later; preserve the existing implementation and its DONE/LEFT counts. Do not claim or start the remaining scripting rows while deferred.


**Historical stop — October 27 (user report):** Codex's Onboarding, Keyboard shortcuts/gestures, Downloads and Split views assignments stopped, and engine ownership transferred to Claude. Later recovery and ownership transfers supersede that snapshot; the current family table and [shared engine ownership](#shared-engine-ownership) are authoritative. Onboarding's retained work remains available at its newly deferred place in the priority order.

**Owner rule:** update this single table and the affected requirement rows in the same delivery. Record scope changes explicitly. Keep detailed evidence below; do not add separate percentage tables. Read [the collaboration guide](collaboration.md) for claims, repo-only communication, direct publication and shared-engine rules. Every owner ships directly to main; root integration is not a gate.

## Current ownership and handoffs

- **Cursor `cursor/cb-site-search` — website scope colour, pill glow and Tab hint (November 1).**
  Checkout `work/cursor-cb-site-search`; asked for directly by Josh while the
  Command bar family stays Codex's. Partial CMD26/CMD27 work; it changes no
  DONE/LEFT counts. Adds `CommandBarSiteColor.swift` (bundled brand colours,
  and the pill's `focusColor` glow in `CommandBarScopeEditing.swift`, wired in
  `CommandBar.swift`
  (`refreshScopeColor`, `siteVisit`, `selectedScopeOffer`, `siteScopes`). Engine
  overlay 299 adds new fields to `PCNativeOmniboxScope` (`templateURL`,
  `searchHost`, `prepopulated`, set in `initWithTemplate:`) and
  `PCNativeOmniboxSnapshot.siteScopes`. In `native_search.mm` it adds
  `SiteScopes()`, which builds active engines and caches them per
  search-preferences revision in `site_scopes_`, and three lines at the top of
  `Publish()`, which append them to `offers_` and hand them to the snapshot.
  `Enter()`'s revision check also accepts a cached site scope still in
  `offers_`. Rebased onto cb-stability (`b6000e1c`); re-hash after any further
  `native_search.mm` change. The overlay is pending an
  engine build; `native_search.mm` compiled with its real `siso` command. The app
  reads the fields only when the engine responds to them.
  The site colour reaches cb-look's row and cell `selectedColor` and the pill's
  `focusColor` through `CommandBar.selectedRowColor` and `applyPalette()`, so
  the hint use `CommandBarTypography.label` (FontSet `label` at weight 7, 13
  so Parc's Actions label shares the font and insets. The pill's built-in colour is the colourless
  palette's `scopePill`, so no accent default remains. Tests: `command-bar-site-color`. [Contract](command-bar.md#website-scope-colour-pill-and-tab-hint).

- **Cursor `cursor/tab-switch-flash` — no white flash on tab switches (November 1).**
  Checkout `work/cursor-tab-switch-flash`. Josh's report: every tab switch in a
  changes no family's DONE/LEFT counts. Cause: without a Views window
  compositor each page drew through its own, which hiding destroyed and showing
  rebuilt, so a re-shown page showed the pane's white backing until a new
  compositor's first frame; that has been so since October 24, not a November
  `attachWebContentsHostView:` `0x4737eb4`) keeps one compositor per pane and
  parents each page into it through `ViewsHostable`/`SetParentUiLayer`. Parc
  now does the same per window (`native_pane_compositor`): a page about to be
  shown takes the compositor of the page it replaces, which still holds that
  page's last frame, and keeps showing it only when it was the same pane's
  (same role, each place covering 90% of the other), otherwise starting from
  the pane backing; a compositor stops drawing the moment its pane is parked,
  so the held frame doesn't depend on timing; docked DevTools, Peek and Easel
  pages use the same path; idle compositors are retired after two sweeps, one
  spare per window; every compositor is destroyed before `CefShutdown`
  ([page compositing](page-compositing.md)). Engine overlay 297. Josh still
  saw the flash in overlay 301's build. The cause was that the shell puts the
  incoming pane on screen synchronously, but the page inside it stayed hidden
  until a posted task, so an intervening commit showed the white backing.
  Overlay 302, pending build, runs that visibility pass synchronously from the
  shell's layout and selection calls. Still white, as before: a page's first frame in a brand-new
  compositor; a page whose saved frame Chromium evicted; a page replacing
  another pane's frame (where a split was, a Peek, a tab replacing one that
  docked DevTools had narrowed). Gap: docked DevTools can still flash after
  its window used more compositors than its one spare. Also fixed:
  `tests/NativePageHost` had failed since `90578fb5` because three groups
  expected the old queued-focus contract; it now checks the current one. It,
  `tests/NativeFocusManager` and `tests/NativeExtensionPopup`, which all build
  the page host on its own, now run in `scripts/test.sh`. Checks:
  `scripts/test-pane-compositor-policy.sh`, those three suites,
  `tests/Packaging/test_native_page_host_exports.py`, real-command compiles of
  every changed engine source. Shared paths: `native_appkit_host.mm`
  (visibility pass, window claim), `native_appkit_application.mm` (shutdown),
  `devtools_pane.mm`, `page_host.{h,mm}`, `Engine/ParcNative/BUILD.gn`.

- **Cursor `cursor/easel-export-image` — Easel Export as Image (November 1).**
  on completed Easels; it changes no family's DONE/LEFT counts. Shared paths:
  `EaselCanvasView.swift` (`exportImage(backingScale:)`, `onExportImage`,
  Command-Shift-S, strip renderer), `EaselEditorViewController.swift` (Share
  button), `CaptureImageEditor.swift` (fixed-canvas export),
  `EaselImageExport.swift` (panel, encoder, `EaselImageExporting`),
  `BrowserWindowController.swift` (Save Page As), `tests/MenuImages/check.py`
  and `scripts/test-easels.sh`. Engine overlay 296 (`native_page_capture.mm`,
  `native_appkit_bridge.h`: `PCNativePage.snapshotEmbeddedPage(completion:)`)
  is pending an engine build; compiled with real flags by
  `tests/EaselEmbeddedSnapshot/run.py`. [Contract](easels.md#export-as-image).
- **Cursor `cursor/cb-commands` — command bar command coverage (November 1).**
  Checkout `work/cursor-cb-commands`; delivers CMD29. **Engine overlay 300**
  (`native_appkit_bridge.h`, `native_appkit_page.mm`: `PCNativePageToolTaskManager`
  → `IDC_TASK_MANAGER_MAIN_MENU`, without requiring a live renderer) is pending
  an engine build. Its units compile with real flags
  (`tests/EaselEmbeddedSnapshot/run.py`). The number is main's 299 plus one at
  the time of writing; it is renumbered at publish. On an older engine the
  Open Task Manager row is simply not offered. **Ranking (consumed from
  `cursor/cb-stability`'s handoff):** `CommandBarRanking.commandCandidate`
  trigger phrases as separate texts (`CommandBarTypedCommand.rankingPhrases` /
  `rankingTexts`) and passes `CommandBarMenuItemInfo.rankingBump`, the bump
  weight was not recovered; 0.06 keeps the largest bump (Export Notes, 1.5)
  at 0.94, under an exact tab's 0.95. A bump never admits an unmatched action.
  [Evidence](command-bar.md#mainmenu-type-travel-data).

- **Cursor `cursor/incognito-hint` — toasts and the Press Again cue in private windows (November 1).**
  Checkout `work/cursor-incognito-hint`. Whole-product polish; it changes no
  context, so in an incognito window every toast and the cue take the static
  per-colour adjustment turns into a blue card tint, P3 (0.159, 0.277,
  0.570), with white text. Parc's private windows now pass that colour to
  private popups and ordinary windows keep their Space's.
  [Evidence](window-appearance.md#private-window-theme).
    cue in ordinary windows whose Space colour has HSL lightness 0.8–0.95:
    very pale themes, and an uncoloured Space in light mode on macOS 13–15,
    where `NSColor.windowBackgroundColor` is about `#ECECEC` (lightness
    macOS 27 that colour is white (lightness 1, a −0.05 step), and dark mode
    and darker or more saturated themes are unaffected.
    The drag-into-split insertion border in a private window now takes the
    incognito palette's maxContrast, sRGB (236, 237, 255) in Dark Aqua, as
  - **Semantic palette.** The projection also hands toasts the window's
    tracing view, which Parc does not draw; the label, keycap and share button
    use the background-based white or black. No change was needed.
    the blue tint rests on the recovered code. The offscreen renders cannot
    draw the card's native material.
  - **Checks.** `scripts/test-toasts.sh`, `scripts/test-shortcut-hint-presentation.sh`,
    `scripts/test-shortcut-cue.sh`, `scripts/test-live-bindings.sh`,
    `scripts/test-split-drop-card.sh`, `tests/IncognitoWindowTheme`, the
    whole-module typecheck and SIL.
  Checkout `work/cursor-toasts-2`. Whole-product polish; it changes no family's
  "Copied Image" after capture Copy, the zoom percentage, "To exit full screen,
  press [Exit binding]." on entering full screen, "Archive Cleared", "Tab
  restored to [Space]. Click to view." after Put Back, "Copied File" for Library
  copies (including a media file's image), "Copied Current URL" for Copy Download
  background-tab affordance ("New Tab Created", "… in [Space]", "New Document
  label at NSFontManager weight 8 in the inherited primary colour; its sub-label
  is FontSet.subLabel, system 11 semibold. A Peek's toasts sit below Parc's
  five seconds through key loss, Space creation and its item's removal. The
  full-screen hint names Toggle Full Screen when Exit is unbound and never shows
  for page full screen. [Evidence and inventory](toasts.md).
  - **Recorded gaps.** The card tint and native material behind it are not
    height from the pane; Parc has none. Pin/unpin and "Auto archived N tabs"
    producers were not found. (Clear Today's undo toast was closed by
    `cursor/clear-today-undo`.) Parc's local Notes and
    Easels have no shareable link, so "Copied Note/Easel URL" don't apply. A
    Library capture copy has no share button (no file URL). The sidebar link
    of the background-tab and unarchive toasts, are inferred; with Exit unbound
    link-copy producer, so Copy Download Link's toast is Parc's choice. "New
    Document Created" cannot appear yet (separating needs a live page). Parc's failure
    recovered.

  Checkout `work/cursor-toasts`. Whole-product polish; it changes no family's
  `ShinyToastDropdown` card in a passive child window. Content toasts sit 8
  points in from the focused (or named) pane's top-right corner, over its header,
  new toast replaces the old, the Press Again cue included. Toasts are framed
  Copy Link, sidebar link copy, Super Copy, Cannot Add New Pane, the
  click-to-reveal move notice, New Tab Created and Parc's failure notices all
  moved onto it; the Press Again cue draws the same card. [Evidence and inventory](toasts.md).
  - **Recorded gaps.** Superseded by `cursor/toasts-2` above.
- **Cursor `cursor/incognito-look` — private window theme (November 1).**
  Checkout `work/cursor-incognito-look`. Whole-product polish; it changes no
  family's DONE/LEFT counts. Josh reported Parc's private window lighter and
  [Evidence](window-appearance.md#private-window-theme).
    its Space's translucent `#202020`: an opaque Display P3 (0.054, 0.06,
    0.075) window and floating sidebar with no material, BrandBlue's palette
    in Dark Aqua (sidebar text, rings, plus HUD, history chooser, recent-tab
    switcher, tooltips, website stylesheet), the same surface on its download
    review panel, and the URL bar's `CommandBarPlaceholderIncognitoBackground`
    (P3 white 0.15) resting fill. Private popups keep their previous look,
    Ordinary windows are unchanged.
  - **Toolbar.** Not a private-window difference: Josh's Parc had Show Toolbar
    preference in every window; View → Hide Toolbar restores the URL bar and
    navigation buttons. No code change.
    BrandBlue's extended-sRGB blue (1.024) is clamped to 1. The incognito
    confirm it. (The empty URL bar's text and magnifier were closed by the
    split chrome work, and the Press Again cue's `#202020` card by
    `cursor/incognito-hint`.)
  - **Checks.** New `tests/IncognitoWindowTheme`; `tests/FloatingSidebarSurface`,
    `tests/SidebarHeaderGlyphs`, `tests/SidebarPlusMenu`, `tests/Tooltip`,
    `tests/WebsiteTheme`, `tests/SpaceManager`, `scripts/test-theme-rendering.sh`,
    `scripts/test-recent-switcher-presentation.sh`, `RecentTabSwitcherTests`
    and the whole-module typecheck. SIL waits for the engine build.

- **Cursor `cursor/close-undo` — Undo for every close (November 1).**
  Checkout `work/cursor-close-undo`. Whole-product polish; it changes no
  family's DONE/LEFT counts. Every close that takes tabs out of the sidebar now
  goes on the window's Undo, so ⌘Z undoes the latest close first: ⌘W, a row's
  close or Archive Tab, a pane's close, Archive Tabs Below/Above, the folder
  preview's Archive, the switcher's close and AppleScript close read Undo/Redo
  Archive Tab(s); Clear keeps Clear Tab(s) and its toast; a dismissed Peek reads
  Undo/Redo Close Peek. Unloading a pinned tab, pinned Note or Easel, or
  it in place instead of archiving it. Undo selects the tab that was focused
  when it closed and leaves selection alone otherwise (this corrects Clear,
  which never reselected). Undo Close Peek doesn't change selection: the Peek
  shows if its parent is in view, waits behind it otherwise, and, for a parent
  with no live page, opens once the parent loads; Redo closes exactly the Peek
  Undo opened. Tabs Undo or Reopen restore, and Peeks they reopen, come back
  with their back/forward entries. Private windows get the same Undo, history
  (memory only) and Clear's toast. A close finishing while an Undo/Redo waits
  on a leave-page dialog joins the stack afterwards, in commit order. Closing
  the pane a split is filed under no longer moves the split to the bottom of
  Today, in view or not. [Evidence and behaviour](reopen-closed-tabs.md#close-undo).
  - **Engine handoff, overlay 301.** `native_appkit_page.mm` adds
    `-[PCNativePage captureNavigationState]` and the engine-internal
    `PCNativeNavigationState` (opaque `NSObject` to the app);
    `native_appkit_application.mm` adds
    `-[PCNativeBrowserWindow openNavigationState:profilePath:container:background:completion:]`;
    `native_link_routing.mm` adds `-[PCNativePage openPeekWithURL:navigationState:]`.
    Bridge and `native_appkit_page.h` declarations; overlay digests updated
    for those five files only, on main's 300. Main's 296 and 298 also edit
    `native_appkit_bridge.h` and `native_appkit_application.mm`, 299 the
    bridge, and 300 the bridge and `native_appkit_page.mm`; all merged
    without conflict and their digests come from the merged files.
    Each translation unit compiled with its real siso command against the
    295 tree with every 296–301 engine file mapped over it (output in `/tmp`);
    not applied or built here. The app checks `responds(to:)`, so an older engine opens addresses
    without history.
  - **Recorded gaps.** The Library card Clear split case is closed by
    `cursor/multiwindow-tabs` (below): Undo puts the pane back into its split.
  - **Checks.** `scripts/test.sh` (with `scripts/test-close-undo.sh`;
    BrowserStore's split-slot test failed before the fix), `test-toasts`,
    `test-private-browsing`, `test-notes`, `test-window-presentation`, the
    FolderUndoManager dependents, the Peek static checks, `ParcEngine.m` with
    the packaging flags, the three engine translation units and the
    whole-module typecheck and SIL. No browser was launched.
    `tests/DownloadLibrary/check-view.py` and `tests/LibraryWidth/check.py`
    now compile `TopBarColorClient.swift`, which `LibraryView.swift` uses since
    e2522c28; both failed on main without it.

- **Cursor `cursor/meet-pip` — Document Picture-in-Picture and the capture strip
  (November 2).** Josh found Google Meet's PiP failing with “The application
  declined the new native window” and the Meet tab replaced by “This page
  couldn't open”. The shell declined every `PCNativeWindowKindPictureInPicture`
  request (“as-yet-unimplemented”); it now gives Chromium's PiP browser the
  title-less floating panel of Parc's video PiP (`PictureInPictureWindowController`:
  one page, Chromium-owned bounds and close, every Space; hover chips Return to
  Tab, hidden when the page sets `disallowReturnToOpener`, and Close, plus a
  centred drag grip, with the rest of the strip reaching the page; non-activating
  and key only once clicked, so auto-PiP opened from another app cannot take its
  typing; ⌘W closes it). Return to Tab is Chrome's back-to-tab
  (`-[PCNativeBrowserWindow returnPictureInPictureToOpener]`). Leaving Parc now
  enters a call's auto-PiP as it does video: Parc's shell reports occlusion to
  Chromium's `AutoPictureInPictureTabHelper`
  (`native-auto-pip-host-occlusion.patch`), whose own entry is the only one the
  pop-up blocker admits; returning closes it. Chromium's content-settings icon
  refresh dereferenced a missing Views frame for this PiP browser and crashed
  Parc (`native-document-pip-content-settings.patch`). Separately, a failed new
  window (`CreationFailed`, the only browser-level `didFailWithError`) was
  written as the current tab's page failure in every window of that Profile;
  it is now only logged. The window capture strip (“Camera is on, Microphone is
  badge and a capturing Favorite's tile menu opens the same Stop menu, which covers
  the Favorite's page, its Peeks and its Easel pages. Also fixed: the passkey
  (`webauthn.mm`) and external-protocol prompt guards read a starting
  navigation's RenderFrameHost, a CHECK in every build, which crashed Parc on
  1Password's pages; they now compare frame tree nodes. A crash audit also
  found that the page menu's Copy Link Address, Copy Image, Copy Video Frame
  and Copy Link to Highlight crashed Parc (Chromium's confirmation toast CHECKs
  without a Views anchor), as did a look-alike domain's Safety Tip (null
  BrowserView in the page-info anchor), as did a site's “restore file access”
  prompt; `native-views-bubble-guards.patch` drops all three. Gaps: those
  copies show no “copied” confirmation, look-alike domains get no Safety Tip
  warning, a site restoring remembered file access is declined without a
  prompt (it must ask again), a page requesting a USB/HID/serial device still
  crashes Parc (same missing anchor, left out as rare), the PiP window
  shows no camera/microphone icons (Chrome's frame does), auto-PiP at a site's
  default “ask” setting opens without Chrome's Allow/Don't allow overlay (so it
  acts as allow, for tab and app switching alike), and minimising the
  call's window does not enter auto-PiP (Chromium leaves a hidden window alone;
  Parc's video rule does enter). Whole-product fix; it changes no family's
  DONE/LEFT counts.
- **Cursor `cursor/multiwindow-tabs` — the same tab in two windows (November 1).**
  Checkout `work/cursor-multiwindow-tabs`. Fixes Josh's report that a second
  window's sidebar showed the first window's tabs but wouldn't open them, and
  removes Parc's invented “This tab is open in another window / Move Tab Here”
  tab whose page another window holds moves the live page here with no prompt,
  from every selection route, splits and Favorites included. Notes and Easels
  move with their editor, and a Peek travels with its parent. The window it
  left keeps the pane frozen and dimmed to 0.6 over its theme, with no
  the row brings the page back. The page also returns when its new window
  stops showing it or closes. Reopen and Close Undo regroup whole splits across
  windows, which closes the Library card split gap. Every row action works in
  every window; a row's Close moves the page here first and closes it here,
  so its leave-page prompt and its Undo and Reopen belong to the window whose
  row was used. The frozen picture is copied once as the page leaves and never
  [Evidence and behaviour](windows-lifecycle.md#the-same-tab-in-two-windows).
  Whole-product fix; it changes no family's DONE/LEFT counts.
  - **Recorded limits.** A Note, an Easel or a page with an open Peek moves only
    while both windows are visible, unminimized and free of sheets (the
    window-move transaction); a plain page moves from a minimized window too.
    The frozen frame is copied after the move, so for about a frame the pane
    shows its white backing at 0.6; a page copied at a different window size
    is scaled to fill. The recent-tab switcher's close of another window's
    tab moves it here and closes it here as a row's Close does, but ends the
    switcher while the page moves.
  - **Recorded gaps (skipped by Josh, November 2: not breaking).**
    - The frozen copy is taken in the window the page moved to, which must be
      key. On an automatic return to a window that isn't key, a placeholder
      that window keeps in another Space stays a dimmed blank pane; clicking
      it still pulls the page back.
    - If a moved tab's close can't start when the page arrives (another page
      still opening, a Note failing to prepare), `placeArrival` selects the
      page here instead of closing it.
    - `sidebarRootsCloseAvailable` still requires `switcherCanUse`, so the
      split cell's Close and keyboard Close of selected roots stay disabled
      for a split another window shows.
    - Undo of Close Peek isn't offered when the Peek's parent tab is in
      another window; Reopen still moves the parent here and reopens it.
      code.
  - **Checks.** `scripts/test-window-presentation.sh`, `ClosedItemsTests`,
    `scripts/test-close-undo.sh`, `scripts/test-page-placeholder.sh`
    (against Josh's screenshot: mean error 4.37 of 255), `scripts/test.sh`,
    `scripts/test-private-browsing.sh` and the whole-module typecheck and SIL.
    No browser was launched. `tests/DownloadLibrary/check-view.py`, broken on
    main since `e2522c28` (it didn't compile `TopBarColorClient.swift`), now
    compiles it, so `scripts/test.sh` runs to the end again.

- **Cursor `cursor/clear-today-undo` — Undo for Clear Today (November 1).**
  Checkout `work/cursor-clear-today-undo`. Whole-product polish; it changes no
  family's DONE/LEFT counts. After Clear, the window's Edit menu reads Undo Clear
  Tabs, ⌘Z puts the cleared tabs back where they were (whole splits included)
  “Cleared Tabs! Use ⌘Z to undo.” at the top right.
  [Evidence and behaviour](reopen-closed-tabs.md#close-undo).
  - **Recorded gaps.** None left: the Library card Clear split case was
    closed by `cursor/multiwindow-tabs` (Undo puts the pane back into its
    split), and Undo for every other close, a Clear finishing during a pending Undo/Redo,
    private windows, the split jumping to the bottom and Clear's reselection
    of the focused tab were closed by `cursor/close-undo`.

- **Cursor `cursor/pinned-extension-icons` — pinned extension badges top right (November 1).**
  Checkout `work/cursor-pinned-extension-icons`. Whole-product polish; it changes
  no family's DONE/LEFT counts. Pinned toolbar and sidebar actions draw their
  badge as an iPhone-style pill over the icon's top-right corner, in the
  extension's colours, per Josh's direction above. [Evidence](extensions-geometry.md#reference-and-finite-comparison).
  - **Engine handoff, overlay 290.** `native-extension-action-icon.patch` adds
    `ExtensionActionViewModel::GetIconWithoutBadge`, which builds the icon
    source without ever setting a badge (`GetIconImageSource`'s new
    `include_badge`); the snapshot gains `iconWithoutBadge` and resolved badge
    colours. Not applied or built here; the engine owner applies and builds
    it. Until then the app shows Chromium's baked bottom-right badge, which is
    the fallback for any older engine. VoiceOver reads the badge text as the button's value on either.
  - **Recorded gaps.** The Site Control Center's tiles now draw the same
    top-right badge from the unbadged canvas (closed, `cursor/scc-look`, see
    [WEB14](web-interactions.md#site-control-center--web14)). Badge text wider
    than the 26-point pill is clipped: four digits fit, `WWWW` does not. The
    new engine tests were only syntax-checked against shadowed headers, not
    built or run.

- **Cursor `cursor/loading-contrast` — page-loading indicator colour and contrast (November 1).**
  Checkout `work/cursor-loading-contrast`. Whole-product polish; it changes no
  family's DONE/LEFT counts. Josh found the loading pill above the page barely
  are BaseAssets `ForegroundPrimary` (near-black at 0.9 on a light Space, white
  at 0.8 on a dark one), resolved under the Space's content appearance. Parc had
  that springs to 128 points for the sweep. Mid-sweep contrast against the band
  rises from 1.12:1 to 8.83:1 on Josh's Space.
  [Evidence](navigation.md#loading-stop-and-refresh-feedback).
    never assigns the view model colour that would select 0.46), not on a
    pixels from his capture; the other Spaces used flat colours, because the
    Metal gradient, grain and behind-window material do not render offscreen.
    former opaque near-white, so the bar measures about 4.6:1 to 9.8:1 against
    a dark band instead of 5.3:1 to 12.3:1. It is still clearly visible, and
  - **End of a sweep.** When a load ends mid-sweep, the track fill jumps in
    one frame from 0.276 to 0.92 × pulse and stays darker than during the
    Parc keeps it.
  - **Checks.** `tests/NavigationLoading` (84) and `tests/SidebarPacing` (146
    plus both negative controls) pass, as does the whole-module typecheck.

- **Cursor `cursor/ext-store-identity` — Web Store identity, recorded page-background gap (November 1).**
  Checkout `work/cursor-ext-store-identity`. Whole-product polish; it changes
  no family's DONE/LEFT counts. Parc's internal component extension names Parc
  on the Chrome Web Store and removes its switch-to-Chrome prompts.
  [Evidence](extensions.md#chrome-web-store-identity).
    resource 14558, service worker 14901, registered at `0x4311964`) also sets
    page background colours on Slack and Notion; Parc does not yet. Its tab
    listener runs the script on `loading` and `complete` when the URL contains
    `app.slack.com` or `notion.so` (host permissions `https://app.slack.com/*`
    and `https://www.notion.so/*`). Each script returns at once if
    `window.bcnySyncThemeBackgroundColor` is set, stores its updater there,
    runs it once the body exists (after `DOMContentLoaded` while loading) and
    reruns it on every `class` attribute change of `body`. Slack: set
    `body.style.backgroundColor` to `#0D0F0E` when the body's computed
    `color-scheme` is `dark`, otherwise `#F6F6F5`. Notion: while `body` has
    class `dark` and no inline background, set `#191919`; once `dark` goes,
    own page-colour sampling) is not established.

- **Cursor `cursor/sidebar-state-gaps` — New Tab placeholder look, Add Split floating sidebar (November 1).**
  Checkout `work/cursor-sidebar-state-gaps`. Whole-product polish; it changes
  no family's DONE/LEFT counts. It closes two gaps recorded on October 31.
  - **New Tab while a new-tab bar is open.** Command-T, the New Tab row and
    Add Split make New Tab the current item: the current plate and shadow,
    the title and plus in the palette's title colour, no transition. No tab
    row or split is current meanwhile, and split children lose their plate;
    Favorites are unchanged. The sidebar keyboard search does not count.
    [Evidence](#today-divider-clear-and-new-tab).
  - **Add Split's pending pane.** While it is pending, a hidden sidebar
    floats and every hide floats, as with no tab; filling or cancelling the
    pane hands it back to the hover rule. This rests on an inference: that
    [Evidence](sidebar-motion.md#add-splits-pending-pane).
    dismissing because a new tab was chosen; the writer of that flag was not
    found, so Parc's New Tab can return to idle while a typed result resolves.
    The flag is `WindowState.isDismissingCommandBarViaNewTabSelection` (field
    decompilation.
  - **Checks.** `tests/SpaceManager` and `tests/EmptyWindow` (new pending-pane
    negative control), plus the whole-module typecheck and SIL.

- **Cursor `cursor/empty-state` — window with no tab, page card shadow (October 31).**
  Checkout `work/cursor-empty-state` (`cursor/empty-state`). Whole-product
  polish increment; it changes no family's DONE/LEFT counts.
  - **Empty window.** The Parc start page is removed. A window with no tab
    0.1 in Dark Aqua, following the window's appearance) in the page host's
    6-point clip over a clear backing, so the translucent theme backdrop and
    the windows behind it show through. Its accessibility label "No tab open"
    is Parc-chosen. A blank tab shows plain white, in private windows too, and
    selecting it gives focus to the window.
    [Evidence](window-appearance.md#a-window-with-no-tab).
  - **No-tab sidebar.** With no tab, every hide (⌘S, drag collapse, click
    outside, hover dismissal, resignation) floats the sidebar instead, and a
    hidden sidebar floats when the window loses its last tab; the first tab
    hands it back to the hover rule. [Evidence](sidebar-motion.md#a-window-with-no-tab-keeps-its-sidebar).
  - **Page card shadow.** Every page card, empty content and split panes
    1 point down, outside only) from one stretchable image.
    [Evidence](window-appearance.md#page-card-shadow).
    was not decoded. The Add Split pending pane gap is closed by
    `cursor/sidebar-state-gaps` above.
  - **Not here.** The floating sidebar's own surface belongs to
    `work/cursor-floating-sidebar`; sidebar rows to `work/cursor-today-rows`.
  - **Checks.** `tests/EmptyWindow` (new, four negative controls),
    `tests/ContentFocusRequest`, `tests/SidebarMotion`, `tests/SidebarPacing`,
    the split scripts, `tests/NativeContentDrop` (its local-editor source list
    is brought up to date) and the whole-module typecheck and SIL. `scripts/test-split-dividers.sh` and `tests/SidebarAccessibility`
    already fail on `origin/main` at assertions this increment does not touch.

- **Cursor `cursor/library-shell` — Library shell, rail and Archive page (October 31).**
  Checkout `work/cursor-library-shell` (`cursor/library-shell`). This is the
  shared Library shell used by Archive, History, Media, Downloads, Easels &
  Notes and Spaces. It does not take the Archive and history family, and
  HIST13–HIST17 stay LEFT. Delivered here: the depth layer, rail tiles with
  the wrapped “Easels & Notes” label and no History or Boosts tile, Archive
  rows without a footer, hover trash and Put Back on the live record, Clear
  Archive / Clear History in the context menu, GrayA11 and secondary ink,
  dimmed Library traffic lights with the system lights hidden (a popup keeps
  the system lights; expanded full screen hides the in-chrome group), and the
  page card at the Library's edge with a 6-point continuous corner (the width
  rule is corrected by `cursor/spaces-width` below). Split
  panes are unchanged. Archive’s header now uses the shared header components
  (`cursor/library-archive-header` below).

- **Cursor `cursor/library-archive-header` — Archived Tabs header and Downloads rail progress (October 31).**
  Checkout `work/cursor-library-archive-header` (`cursor/library-archive-header`).
  This is a Library-shell polish increment. It does not take the Archive and
  history family, and HIST13–HIST17 stay LEFT.
  - **Header.** Archived Tabs and History use the Downloads page header:
    `DownloadSearchField` in `DownloadSearchBackdrop`, the `.header` Filter
    sized by `fittingSize.width`, and `LibraryPageHeader` geometry.
  - **Rail progress.** The Downloads rail tile shows `DownloadActivityBadge`
    (`DownloadActivity.active`; `DownloadActivity.inFlight` since
    `cursor/library-rail-gaps`) with the sidebar entry's feed and window gate
    from `BrowserWindowController.refreshDownloads`, not the entry's
    visible-item lifecycle or Downloads preference. The 24-point badge stays
    at full opacity, and the label rises 2.5 points while it shows (2 points
    since `cursor/library-rail-gaps`).
    Whether it reports progress 1 before clearing is unconfirmed; Parc keeps
    DL27's 1.45-second completion checkmark. Whether a pending (not started)
    download badges the rail is unconfirmed; Parc badges it with the partial
    (`LibraryRailTile.iconSize`); this is not changed here.
    `cursor/library-rail-gaps` below traces the writer, closes the
    not-started and icon-size gaps, and narrows the first: the rail's
    checkmark now needs progress 1 while still in progress, and whether
  - **Shared paths.** `LibraryView.swift`, `LibraryRailTile.swift`,
    `DownloadLibraryView.swift` (`DownloadFilterButton`) and
    `BrowserWindowController.swift` (`refreshDownloads`).
  - **Evidence.** [Archived Tabs page header](archive.md#archived-tabs-page-header--october-31)
    and the [Library entry rail item](download-library.md#original-library-entry).

- **Cursor `cursor/rail-anim` — Library rail selection playback (October 31).**
  Checkout `work/cursor-rail-anim` (`cursor/rail-anim`). This is a
  Library-shell polish increment. It does not take the Archive and history
  family, and HIST13–HIST17 stay LEFT.
  - **Playback.** A tile selected in a window plays `hover-start` (frame 1)
    Deselection no longer stops a running play, and a finished play now parks
    has not played shows the composition's start frame (`ip`).
  - **Verification.** Offscreen strips of the real tile, compared with rlottie
    renders of the same files, match the segment, timing (frame 11 at about
    168 ms, 35 at about 568 ms) and shapes. `tests/LibraryRail/check.py`
    covers playback on selection, deselection and reselection mid-play,
    parking on `selection-end`, leaving the window and Reduce Motion. It does
    not cover the never-played start frame, because frame 0 and frame 1 are
    visually indistinguishable (identical in four files; Archived Tabs differs
    only by a sub-pixel mask edge).
  - **Recorded gaps.** Icons draw at 29 points rather than 28 (closed by
    `cursor/library-rail-gaps` below). Parc redraws on
    (inferred, not traced). Parc skips the 12 Offset Path items in the Easels,
    inferred to skip them too. If it applies them, Parc's shapes draw about
    0.1 point fuller per edge.
  - **Shared paths.** `LibraryRailTile.swift`, `LibraryRailIcon.swift` and
    `Resources/Library/README.md`.

- **Cursor `cursor/library-rail-gaps` — Library rail icon size and Downloads ring (November 1).**
  Checkout `work/cursor-library-rail-gaps` (`cursor/library-rail-gaps`). This
  is a Library-shell polish increment. It does not take the Archive and
  history family, and HIST13–HIST17 stay LEFT.
  - **Icon size.** `_AnimatedPageSidebarItemView` constrains itself to
    icon centres are unchanged, playback is untouched, and the badge's label
    to within its 0.8-point pixel pitch.
    `DownloadActivity.inFlight`: paused and not-started downloads never badge
    it. `DownloadProgressBadge` completes on `onChange(of: progress)` at 1 or
    while still in flight. The badge leaves, and the icon returns at once,
    when nothing is in flight; the rail no longer holds a finished download's
    checkmark. One renderer persists while anything is in flight; a played
    checkmark keeps DL27's 1.45-second deadline, after which the renderer is
    dropped and the empty slot stays, under Reduce Motion and after an
    accessibility rebuild too. Colours and widths were already DL27's
    recovered renderer.
    executable and is not recovered, so its value at the last byte (and so
    are open; Parc keeps the static 0.2 ring for an unknown total. Live
    snapshots map Chromium's `IN_PROGRESS` to `downloading` (or `paused`)
    whatever the byte count, so a running download shows its ring from the
    first snapshot; `.pending` comes only from `BrowserDownloadStatus.inferred`
    (`receivedBytes == 0`) for a record without a status. Which state, if any,
    a change of in-flight download is inferred from SwiftUI identity, not observed. The rail body has no
    screenshot for comparison.
  - **Shared paths.** `LibraryRailTile.swift`, `LibraryRailIcon.swift`,
    `DownloadActivityBadge.swift` (`DownloadActivity.inFlight`,
    `DownloadActivityBadge.updateInFlight`) and `LibraryView.swift`.
  - **Evidence.** [Library entry rail item](download-library.md#original-library-entry).
  - **Checks.** `tests/LibraryRail`, `tests/LibraryWidth`, `tests/SpaceManager`
    and the whole-module typecheck and SIL. `tests/DownloadLibrary/check-view.py`
    passed before the review fix to the completion deadline and was not re-run
    after it, because it activates the app.

  Checkout `work/cursor-arc-tooltip` (`cursor/arc-tooltip`). A cross-cutting
  polish component. It takes no family credit, and the Whole-product polish
  rows stay LEFT.
  - **Component.** `view.parcTooltip = TooltipConfiguration(label, shortcut:
    corners 14 with 3 facing the anchor, ⌃⌥⇧⌘ keycaps that follow held keys,
    fallback, idle and warm-handoff timing, and dismissal. Keycaps show the
    command's live binding. Browser windows colour it from the Space theme;
    title and background follow light/dark, and the key colours come from the
    light palette.
  - **Pilot.** Only the sidebar toggle is converted (Hide sidebar / Lock
    sidebar, its live ⌘S binding, bottom-trailing, 0.45 s). Its AppKit help
    tag is replaced, and the tag's text stays as live accessibility help; the
    tooltip window is hidden from accessibility. The app-wide adoption
    (`cursor/tooltip-adoption`, below) converted the other controls.
    BasePrimaryDark and BasePrimaryLight are static white and black in
    `Assets.car`. The tooltip follows the app's appearance. The user's capture
    fits the unchanged mapping for a Display P3 blue theme.
  - **Shared paths.** `Tooltip.swift`, `TooltipView.swift`,
    `TooltipController.swift`, `SidebarView.swift` (`setFloating`),
    `BrowserWindowController.swift` (`onPaletteChange`) and `AppDelegate.swift`
    (launch resolvers). Checks: `tests/Tooltip/check.py`; `tests/SpaceManager`
    compiles the new files.
  - **Evidence.** [Tooltips](tooltips.md).

  Checkout `work/cursor-shortcut-glyphs` (`cursor/shortcut-glyphs`). A
  cross-cutting polish increment. It takes no family credit, and the KB rows
  are unchanged.
    Settings detail keycaps keep ⇥ for Tab; Essentials keycaps spell TAB, as
    Storage and matching are unchanged.
  - **Recorded gaps.** Keypad Clear is stored as Escape and keypad × as `*`
    (which French-PC and Turkish-QWERTY-PC also type on a main key), so they
    read ⎋ and `*`, not ⌧ and 𝗑; both need a storage change. The command bar
    12-point medium inside 4/4/4/2-point insets ([command bar](command-bar.md)).
  - **Shared paths.** `KeyboardShortcuts.swift`, `ShortcutKeycapView.swift`,
    `ShortcutEssentialsWindow.swift`, `ShortcutsSettingsView.swift` and
    `ShortcutRecorderView.swift`. Checks:
    `scripts/test-keyboard-navigation.sh` (`KeyLabelTests`),
    `scripts/test-shortcut-detail.sh`, `scripts/test-shortcut-essentials.sh`,
    `scripts/test-shortcut-recorder.sh`.
  - **Evidence.** [Keyboard navigation](keyboard-navigation.md#shortcut-key-text).

- **Cursor `cursor/window-background-paging` — window background through a Space swipe (November 1).**
  Checkout `work/cursor-window-background-paging` (`cursor/window-background-paging`).
  This is a polish increment in the completed Sidebar family. It changes no
  DONE/LEFT counts.
    library because 1.122's is not retained).
      progress is the strip's position between the left and right pages, to
      the window's `backgroundView` and the floating container's theme view
      in every sidebar mode. While tracking, the pair is the pages at the
      the strip is.
      (`gradientFragment`) and their strength-scaled textures
      (`overlayFragment`) by that progress. It ignores `shouldCrossfade`
      (`sidebarMode == .noChrome`), which only the SwiftUI renderer's
      stacked fade reads.
    - The window's translucency shows the `from` style's material, with the
      `to` style's over it at alpha = progress when the two differ
  - **Delivered.**
    - The window's surface now blends through the swipe and commits with no
      jump, locked or floating. Measured offscreen across a commit at 40 %:
      the margins went from a 169-level jump to 0.
    - The floating surface and the window share the renderer's new mixed
      transition pass, replacing the premultiplied crossfade it drew before.
    - A light ↔ dark swipe fades the window's second behind-window material
      in at the swipe's progress.
    - Every swipe sends the pages either side of the strip's position, so a
      drag past one page, a second page during a spring and the commit all
      stay continuous (`SidebarSpacePagingModel.themePages`).
    - The locked sidebar no longer stacks the neighbour's own surface. The
      neighbouring page takes its palette directly and builds no renderer.
      `SidebarView.isOnFloatingSurface` is removed.
  - **Unresolved.**
      runtime flag; Parc follows the Metal one it already re-expresses.
      the coloured theme as a whole.
    - The floating blur's tint at the commit belongs to
      `cursor/floating-swipe-material`.
      unrecovered. Past one page Parc's strip draws only one neighbouring
      page.
  - **Shared paths.**
    - `ThemeRenderer.swift`: `pagingTransition`, `ThemePagingTransition`
      (whose `from`, the left page, is required), `pagingMaterial` and the
      transition pass.
    - `SidebarView.swift`: Space paging.
    - `SidebarSpacePaging.swift`: `SidebarSpacePagingModel.themePages`.
    - `BrowserWindowController.swift`: `onPagingTheme`.
    - `docs/navigation.md`: the paging row.

    Checked by `tests/FloatingSidebarSurface`,
    `scripts/test-theme-rendering.sh`, `tests/SidebarPacing`,
    `tests/SidebarMotion` and `tests/SidebarSpacePaging`.
  - **Evidence.** [Space paging](space-theme-rendering.md#space-paging).

- **Cursor `cursor/floating-sidebar` — floating sidebar surface (October 31).**
  Checkout `work/cursor-floating-sidebar` (`cursor/floating-sidebar`). This is
  a polish increment in the completed Sidebar family (Claude `claude/sidebar`).
  It changes no DONE/LEFT counts.
    1.122's `FloatingSidebarBackgroundView`:
    - a 1-point `SidebarBorderColor` edge (white at 0.3);
    - an 8-point corner, previously 10;
    - a within-window popover blur under the theme, previously the window's
      behind-window material.

    Inside the floating → locked group the shadow fades with the slide, and
    mid-slide keeps the dock. A floating Space swipe draws both themes in the
    no longer jumps.
  - **Recorded gaps** ([floating surface](sidebar-motion.md#floating-surface)):
    - Off-screen renders only approximate the live blur, so the fill must be
      judged in the app.
      `cursor/docking-blur` below closes this.
    - A swipe to or from a Space with a stored forced Light or Dark
      appearance changed the floating material's tint at the commit.
      `cursor/floating-swipe-material` below closes this for coloured
      not to follow the Space's appearance [I].
  - **Shared paths.**
    - `ThemeRenderer.swift`: `ThemeRendererView.floatingCornerRadius`,
      `docksFloatingSurface`, `pagingTransition`, the renderer's two-theme
      pass and `FloatingSidebarSurface`.
    - `BrowserWindowController.swift`: the floating pass, the docking branch of
      the geometry pass, the sidebar's floating clip and flag, and
      `onPagingTheme`.
    - `SidebarView.swift`: `isOnFloatingSurface` and `onPagingTheme` in Space
      paging.
    - `docs/navigation.md`: the paging row's theme evidence (corrected).
    - `Resources/FloatingSidebar`.

    Checked by `tests/FloatingSidebarSurface` and `tests/SidebarPacing`.
  - **Coordination with `cursor/empty-state`.** That increment floats the
    sidebar when no tab is open, through `setSidebarPresentation(.floating)`.
    This one owns only the surface, which follows the presentation, so the
    empty state needs no call of its own.

- **Cursor `cursor/floating-swipe-material` — floating blur through a light ↔ dark Space swipe (November 1).**
  Checkout `work/cursor-floating-swipe-material` (`cursor/floating-swipe-material`).
  This is a polish increment in the completed Sidebar family. It changes no
  DONE/LEFT counts.
    when it differs from the `from` style. The floating container hides that
    `blurView` keeps the popover material from its factory and is never given
    an appearance. The traced Space-appearance sinks target the sidebar above
    have untraced targets, so a view between the window's content and the
    floating container is not ruled out.
  - **Scope.** The old jump came only from Spaces with a stored forced Light
    or Dark appearance. Editor themes are automatic, and their side already
    matched the window's appearance, though not its Increase Contrast
    variant. So the change mostly affects those forced Spaces and the
    Increase Contrast variant.
  - **Delivered.** While the canvas draws a theme's colour, the floating
    popover material takes the window's effective appearance instead of its
    theme's light or dark side. A swipe between coloured Spaces, commit
    included, leaves it unchanged, with no extra view or per-frame work.
    Where the blur is the whole backdrop (an uncoloured Space, or no Metal),
    it keeps the theme's side, which the palette's text was chosen for. It
    takes the window's own appearance whenever the window is on that side,
    so automatic Spaces keep the Increase Contrast variant, coloured or not.
    Locked surfaces behave as before.
  - **Recorded gaps.**
    - Under a forced coloured Space, the floating blur follows the window
      while the text keeps the forced side. A forced-Dark Space's light text
      in an Aqua window sits mostly on a light popover. Review estimated
      that its contrast falls from about 10:1 to about 4:1 at intensity
      0.8, and under 2:1 at intensity 0. This legibility trade-off matches
      the window, while its text follows the colour's contrast.
    - A swipe between an uncoloured forced Space and a coloured one still
      changes the blur at the commit when the forced Space's stored side
      differs from the window's.
  - **Window surface.** The window's own surface pages through a swipe, its
    second material included, since `cursor/window-background-paging`
    (`2ee38837`). There `updatePagingMaterial` writes the base material
    after `updateMaterialAppearance`, and at rest both write the same style.
  - **Shared paths.** `ThemeRenderer.swift` (`updateMaterialAppearance`).
    Checked by `tests/FloatingSidebarSurface`, `tests/SidebarPacing`,
    `tests/SidebarMotion`, `tests/SidebarSpacePaging` and
    `scripts/test-theme-rendering.sh`.
  - **Evidence.** [Floating surface](sidebar-motion.md#floating-surface).

- **Cursor `cursor/docking-blur` — floating sidebar dock material cross-fade (November 1).**
  Checkout `work/cursor-docking-blur` (`cursor/docking-blur`). This is a
  polish increment in the completed Sidebar family. It changes no DONE/LEFT
  counts.
    `blurView` (within-window popover) and `behindWindowBlurView`
    fades `blurView` and the shadow to 0 and `behindWindowBlurView` to 1.
    completion, restores the floating style. Both blur views are reached
    the style setter, whose one caller is the floating → locked transition
    call. So undocking has no material fade.
  - **Delivered.**
    - `ThemeRendererView` has a second, lazily made material over the blur:
      behind-window, emphasized, masked to 8, in the window surface's own
      style. The dock's preparation pass shows it at 0
      (`preparesFloatingDock`, from `SidebarTransition.docksFloatingSurface`).
    - Inside the group the blur and shadow fade out and it fades in, so the
      dock ends on the surface it settles onto. The settled pass restores
      the blur's alpha and hides it.
    - A reversed or superseded dock floats again at once, with its fades
      removed.
    - Its layer exists from creation, so the first dock fades too.
  - **Adaptations.**
      `.duringViewResize`, which would re-render the pinned theme canvas
      every frame.
      only 1 and 2.
  - **Shared paths.**
    - `ThemeRenderer.swift`: `docksFloatingSurface`, `preparesFloatingDock`
      and `dockMaterial`.
    - `SidebarMotionController.swift`: `SidebarTransition.docksFloatingSurface`.
    - `BrowserWindowController.swift`: the dock's preparation and the full
      pass.

    Checked by `tests/FloatingSidebarSurface`, `tests/SidebarPacing`,
    `tests/SidebarMotion` and `scripts/test-theme-rendering.sh`. The live
    fill still needs judging in the running app.
  - **Evidence.** [Floating surface](sidebar-motion.md#floating-surface).

  Checkout `work/cursor-tooltip-adoption` (`cursor/tooltip-adoption`). A
  cross-cutting polish component. It takes no family credit, and the
  Whole-product polish rows stay LEFT.
    `View.help` and `setToolTip:` sites
    (`work/cursor-tooltip-research/adoption-map.md`). 57 controls now show
    Library, compact rail tiles, the theme editor's appearance and noise
    Tab row, which had none, gains New Tab's binding as accessibility help;
    text.
    over "Double-click to rename" until the tab has a custom title, at the
    11-point subtitle at 0.66). SwiftUI's spacing and line heights for that
    layout were measured with `NSHostingView`. A plain double-click on a
    renameable row's body begins its rename through the existing rename
    row's tooltip during a rename; its tooltip model ignores
    `TabCellState.isEditing`, so Parc keeps it ([tooltips](tooltips.md#tab-rows)).
  - **Accessibility.** `LiveShortcutToolTip` keeps each former help tag's text
    as accessibility help on the live binding (`KeyboardShortcuts.bindHelp`).
  - **Component additions.** `style: .label(subtitle:)`, `requiresShortcut`
    (Reset Tab) and `anchorRect` (the Library entry's drawn button, cells and
    cancel buttons); entered views are recorded without the hit test, which
    scheduling still applies. The Library entry's own system-material panel
    is removed.
  - **Custom contents and SwiftUI.** `style: .dockItem(profileName:)` is
    Profile in the full-size indicator capsule in the keycap colours while
    there is more than one Profile, and its numbered Space binding's keycaps,
    above. Quote mode's copy buttons show `CopyQuoteTooltip`'s "Copy Quote as
    excluded. `.parcTooltip(_:)` on a SwiftUI view overlays a
    hit test except the controller's own (`hitTestingView`), so Site Control
    tooltip in the neutral palette in place of `.help`
    ([tooltips](tooltips.md#the-dock-item-style)). The dock tooltip uses the
    window's palette; the producer of `SidebarDockItemTooltipView`'s palette
    argument was not traced. A long Profile name truncates in a capsule
    capped at half the row's room. The Space-switch binding and Profile rule
    are inferred.
  - **Theme editor.** Its tooltips leave `palette` nil and take the
    popover's palette from the edited theme; "Noise" sits below the dial's
    40-point knob (`knobRect`), though the whole dial triggers it.
  - **Shared paths.** The tooltip sources, `SidebarView.swift` (tooltip lines
    and the row double-click), `SidebarTabTitle.isRenameable`
    (`BrowserStore.swift`, shared with the rename lease),
    `KeyboardShortcuts.swift`, `AppDelegate.swift`, `SidebarLibraryEntry.swift`,
    `SiteControlCenter.swift` and the converted views. Checks:
    `tests/Tooltip/check.py` and `tests/SiteControlCenter/check.py`; adopting
    views' component checks take the tooltip sources from
    `tests/Tooltip/support.py`.
  - **Evidence.** [Tooltips](tooltips.md#adoption).

- **Cursor `cursor/perf-row-fill` — sidebar row fill/ring layout paint (October 31).**
  Checkout `cursor-perf-row-fill` (`cursor/perf-row-fill`). Helper increment;
  does not take Performance family ownership and does not mark PERF rows DONE.
  `SidebarRowBackgroundView.layout` no longer sets `needsDisplay` on every
  metadata-driven sidebar layout. Appearance `didSet` still dirties when
  `appearanceState`, `dark` or `ringColor` actually change, and a real bounds
  change still refreshes fill/ring frames and the shadow path. Selected/hover/
  drop/pinned/unread fills, rings, opacity, 1pt shadow spill, dimming-does-not-
  fade-the-ring, flipped-row geometry and clips/masks/group-opacity stay the
  same. Do not edit `SidebarView.swift`; `cursor/perf-chrome-fanout` owns that
  worktree. Shared: `SidebarRowAppearance.swift`,
  `tests/SidebarRows/SidebarRowAppearanceTests.swift`. Family owner remains
  `codex/perf04`.

- **Cursor `cursor/perf-easel-canvas` — incremental Easel canvas display (October 31).**
  Checkout `cursor-perf-easel-canvas` (`cursor/perf-easel-canvas`). Codex
  `codex/perf04` retains the Performance family. This increment owns the Easel
  CPU-draw path that marked every object dirty on layout. Compositing,
  hit-testing and drawing stay as they were: ordinary objects still CPU-draw
  into the canvas dirty rect; per-object surfaces remain only for embedded
  pages. Invalidation dirties the union of frames whose pixels change, including
  overflow of content-hugging fills and arrow heads. Note typing layout was
  published by `cursor/perf-notes-typing` and is not part of this increment.
  `ThemeRendererView.layout` on current main already skips Metal when the
  canvas frame is unchanged; this increment does not retouch those lines.
  PERF05 stays LEFT. Shared paths: `EaselCanvasView.swift`,
  `EaselEditorViewController.swift`, `EaselTextStyle.swift`. Do not
  fast-forward `/Users/josh/Parc`.

- **Cursor `cursor/perf-notes-typing` — Notes typing latency (October 31).**
  Checkout `cursor-perf-notes-typing` (`cursor/perf-notes-typing`). This is a
  bounded typing-path fix on completed Notes, not a claim of the Performance
  family or PERF05. `NoteEditorViewController.textDidChange` remasures the
  edited field and skips footer/format/key-loop layout unless chrome geometry
  changed. In-memory publication validates field limits only; sorted-key JSON
  encoding runs once at the recovered delayed disk persist. Body-only drafts
  do not publish `NoteStore.changes`; title/deletion notify immediately without
  a second persist reload. IME, revision checks and no-torn-write persist stay
  the same. Do not edit `DocumentsLibraryView.swift`; `cursor-perf-library`
  owns that worktree.
  Shared: `NoteEditorViewController.swift`, `NoteDocumentPresentation.swift`,
  `NoteStore.swift`, `docs/notes.md`. PERF04 retains navigation ownership.

- **Cursor `cursor/document-close` — Onboarding / complete first launch (October 31).**
  Checkout `cursor-document-close` (`cursor/document-close`). Chrome import
  (OB18/OB24 defect) is published: restricted Chromium sources use Full Disk
  Access, snapshots retry then refuse a still-changing DB/WAL, and Restart
  resumes the original source bundle. Overlay v270 is applied and built (in the November 1 overlay 286 engine). OB11 is published. Ready-step, Back/Next motion, focus and audio
  increment is published. Theme-step editor chrome (0.83 scale, first-appear,
  Reduce Motion) is published. Conditional ad-blocker setup (tag 7) and
  1–4 / 1–5 of N progress is published; independent review CLEAR; import
  coordinator 163 assertions, onboarding model tests, and 285-source
  whole-module typecheck pass. OB17/OB22 stay LEFT until remaining
  presentation comparison is closed. OB20 wrap/pad/empty-state/hit-region
  and wrap-material increments are owned by Cursor `cursor/onboarding-ob20-rest`
  in `cursor-onboarding-ob20-rest`; family ownership stays here. OB20 stays
  LEFT for remaining theme presentation. Counts 27/36. Active IDs: OB17,
  OB20, OB22, OB23, OB32–OB36. Shared paths: `OnboardingWindow.swift`,
  `OnboardingSetupCard.swift`, `OnboardingArtwork.swift`, `docs/onboarding.md`.
  OB16 published from `cursor/onboarding-ob16-rest`. Overlay v270 remains
  engine_owner apply. Do not fast-forward `/Users/josh/Parc`.

- **Cursor `cursor/onboarding-ob20-rest` — OB20 theme/customization step (October 31).**
  Row owner in `cursor-onboarding-ob20-rest` (`cursor/onboarding-ob20-rest`).
  Family owner remains Cursor `cursor/document-close`; this is not a family
  claim. This worktree owns the complete fixed OB20 row through DONE, not
  leftover-helper work. Wrap/pad/empty-state/hit-region increment is
  independently CLEARED. Wrap-material increment is independently CLEARED:
  blending 1 / emphasized false); setup hides the stock editor’s own
  popover material; sidebar stays 356×508 / corner 12 / visible popover
  material. 0.83 visual scale stays on composition, not Favorites.
  `OnboardingWindow.swift` was not touched. Author check
  `bash scripts/test-onboarding-theme.sh` PASS 119 assertions.
  Parc theme-step appearance comparison; PopoverBackgroundView inner/outer
  DecorationView and washLayerAlpha 0.7 only if helpers recover paint
  color/width; empty-state typography only if recovered. Shared:
  `OnboardingThemeEditor.swift`, `SpaceThemeEditorView.swift`,
  `tests/OnboardingThemeStepTests.swift`, [onboarding evidence](onboarding.md).
  Do not edit `OnboardingWindow.swift` without preserving
  `resumeSafariImport(destination:sourceBundleID:)`, `themeChrome`, ready-step
  confetti/focus/Tab loop, grain card chrome, and the published ad-blocker
  stage.

  Checkout `work/cursor-split-menu-icons`. Josh's screenshot showed the split
  item images unless `NSMenuItem.preferredImageVisibility` is `.visible`, and
  Parc builds against the 27.2 SDK; the SF Symbols were set but never shown.
  dark renditions, copied into `Resources/SplitPaneMenu` with provenance),
  chosen by the split's orientation as `SplitScreenButtonMenu.swift` does
  ([evidence](split-groups.md#split-menu-artwork)). Parc's other menu item
  images are handled by `cursor/menu-icons` below. Shared paths:
  `SplitPaneMenu.swift`, `scripts/test-split-pane-controls.sh`. Does not change
  SP01–SP33 counts.

  Checkout `work/cursor-top-band-color`; builds on the pane-bar colour work
  `TopBarColorClient`, and implemented all three
  ([top-band colour](top-band-color.md)): four list-based hit tests along the
  viewport's top edge vote for band-spanning elements, coloured by their
  background (translucent layers blended), their pixels (images, gradients) or
  a copy of the composited frame's top 8 DIP; YouTube's masthead is skipped;
  the first contentful paint. The app shows each sample, caches settled
  colours per host of the http or https document they came from (50,
  persisted under `TopBarColorCache`; private windows keep theirs in memory
  until the last one closes), forgets hosts and time ranges whose history is
  deleted (Clear Browsing Data in the engine, the Library's Remove and Clear
  History), and starts a newly shown page with its site's colour, else white.
  Engine overlay 295, pending build; until then bars keep the overlay 293
  theme-colour stand-in. Shared paths:
  Blink `local_frame.{h,cc}`, `local_frame_view.cc`, `document.cc`,
  `document_loader.cc`, `core/frame/build.gni`, `public/mojom/BUILD.gn`,
  Engine `native_appkit_page.mm`, `native_appkit_bridge.h`,
  `native_page_shell_notify.h`, `ParcEngine.m`, `BrowserToolbar.swift`,
  `PaneTopBarPageColor.swift`, `BrowserWindowController.swift` (a protocol
  conformance), `AppDelegate.swift` (last private window closing),
  `LibraryView.swift` (history removal).
  Does not change SP01–SP33 counts.

  Checkout `work/cursor-menu-icons`. Follows the split menu finding: every
  service's `image`, and SF Symbols on Copy as… rows) and Easel's Export as
  image) and the extension rows of its main-menu Extensions menu
  Download Location picker labels the folder `.titleAndIcon`. So
  `MenuAction.item` no longer takes a symbol: the tab, folder, selection,
  Move to, preview card, page, Peek, split layout, capture-indicator,
  developer split and payment menus are title only. The share submenu's
  service icons, Open in [Space], the Download Location folder row and the
  split menu show their images through `NSMenuItem.showImage(_:)`
  (`MenuItemImage.swift`), which sets `.visible` on macOS 27. Pop-up button
  menus already showed images, so the picker row was not hidden before.
  Chromium's own Cocoa menus already set `.visible` upstream. Titles now use
  only Copy URL, Open in Split View, Duplicate and Archive). Recent-pages rows
  Issue URL for a Linear ticket, none for a recognized Notion page, Copy URL
  otherwise. Gaps: a recent page on a GitHub, Google or Zoom host (only
  possible when its address also contains a provider string) gets Copy URL
  menu-bar Extensions menu lists each installed
  extension with a 16-point icon, while Parc's has only Manage Extensions…
  and Add Extension…; Easel has no Export as Image row yet; and which menu
  ([open question](sidebar-previews.md)): Parc shows the folder menu, while
  SwiftUI usually lets the row's inner URL menu win. The engine's own
  Extensions pop-up (`native_appkit_host.mm:708`) shows its icons on macOS 27
  from overlay 294, once an engine build includes it. Checks: `tests/MenuImages/check.py` (in
  `scripts/test.sh`), `tests/BrowserToolbar/check.py`,
  `tests/DownloadLocation/check-picker.py`, `tests/EmptyWindow/check.py`,
  `scripts/test-split-pane-controls.sh`, `scripts/test-split-context.sh`.
  Shared paths: `SidebarView.swift`
  (`MenuAction` and its callers), `BrowserWindowController.swift`,
  `SidebarPreviewCard.swift`, `PaneTitleControl.swift`,
  `DownloadLocationPicker.swift`, `SplitPaneMenu.swift`.

- **Cursor `cursor/split-chrome` — sidebar URL bar in splits and page-coloured pane bars (November 1).**
  Checkout `work/cursor-split-chrome`. Josh reported the sidebar URL bar gone
  in split view and pane bars ignoring light/dark and page colours. Commit
  `aabe63c5` (October 30, "Keep live split pages attached when adding a pane",
  `cursor/split-pane-chrome`) made splits always show pane bars; the sidebar
  keeps the URL bar beside split bars, so Parc follows the installed app: only
  the Toolbar preference hides it, it shows and acts on the focused pane, and
  Back/Forward/Reload move to the pane bars (`PaneTopBarAdmission
  .sidebarAddressBarShown`, `SidebarView.navigationInContentToolbar`). The
  "/ Google Calendar" row in Josh's Parc screenshot is a pinned tab that left
  content backing without a colour ([evidence](split-groups.md#top-bar-page-colour)).
  Colour-only changes reach the bar alone through
  `browserViewDidChangePageColor:`; a loading page keeps its last colour, so
  navigations do not blink. Engine overlay `PCNativePage (PageBackgroundColor)`
  and page-colour notify filtering (overlay 293, pending build); shipped
  engines use the declared theme colour only. Every pane shows Copy, extension
  and "Search or Enter URL…", and the split menu takes the bar's scheme. Gaps:
  `TopBandColorTracker`, being built on this path by `cursor/top-band-color`),
  so until then pages are coloured by declared theme colour, then the
  composited background (white for a page declaring neither);
  `TopBarColorClient`'s convergence, timings and per-domain cache are not
  reproduced; the colourless bar's ink follows the backing over the Space
  `webContentTintColor` was not traced. Shared paths:
  `BrowserWindowController.swift` (sidebar ownership, page colour delivery,
  pane backing, Copy, menu scheme), `SidebarView.swift` (two properties, the
  empty-state icon), `PeekController.swift`, `ParcEngine.{h,m}`,
  `BrowserToolbar.swift`, `PaneTopBarColor.swift`, `PaneTopBarPageColor.swift`,
  `SidebarAddressPill.swift`, `SplitPaneControl.swift`, Engine
  `native_appkit_*` and `native_page_shell_notify.h`. Does not change SP01–SP33
  counts.

- **Cursor `cursor/split-pane-chrome` — missing split pane top bar and live-page rebuild (October 30).**
  Checkout `cursor-split-pane-chrome`. Josh reported the compact per-pane bar
  (URL, pinned extensions, Site Control Center, Move/Add/Separate/Convert/Share
  menu, Close) as missing on splits that had been marked done. The bar was
  gated on Show Toolbar (default off) and a recovered flag with no Settings
  row. Splits now always show that bar; the populated menu matches the
  installed list including Share Split View….   Command-bar Add Split no longer
  detaches surviving pages (`pageWillDetach` / compositor teardown); the
  sidebar size changes now push `NSView.layout` into the hosted Chromium view
  in the same pass; a parent frame change was leaving that child dirty-off
  so the compositor kept the old surface for seconds. The pane chrome X now
  closes only that original page, the same as sidebar child Close and Close
  this Split Pane; it no longer focuses the pane first (that posted native
  selection of one page and unloaded the rest of the split). Add Split’s
  command bar now fills its blank pane with New Note / New Easel or an
  existing Today Note or Easel at the drafted slot and orientation; those
  commands no longer replace the first tab. File → New Easel outside Add Split still replaces,
  or clip their own layer: TabCellBackgroundCurrent plus TabCellShadowSelected,
  SidebarItemBackground hover, and selected-split TabCellChildBackground pills
  HighlightRingView instead of a 1-point accent border that flattened those
  cards. Does not change SP01–SP33 counts. Shared paths:
  `BrowserWindowController.swift`, `CommandBar.swift`, `BrowserStore.swift`,
  `ParcSplitView.swift`, `PageContentResizer.swift`, `SplitPaneMenu.swift`,
  `SplitPaneControl.swift`, `SidebarView.swift`, `SplitDragView.swift`,
  `SidebarRowAppearance.swift`, `docs/split-groups.md`. Coordinate with
  `codex/split-recovery` on other reported split interaction failures.

- **Development portability — October 30, requested by Josh.** Codex's bounded
  app plus retained version-specific analysis in a private release asset. See
  [setup](development-setup.md) and [reference contents](../References/README.md).
  Josh also requested publishing the existing incremental Chromium workspace
  and last completed development package, with verified restore commands for
  new-machine onboarding. He clarified that this is a transfer of the retained
  build, not a request to rebuild or update the SDK. Dedicated `engine_owner`
  owns the snapshot, release artifacts and validation.
  `engine_portability_tools` owns archive and restore support; root owns
  onboarding documentation.
  This does not change feature-family counts. Engine stage results and the
  snapshot's exact source identity are recorded with the artifact manifest.

- **Codex `codex/split-recovery` — reported split interaction failures (October 29).**
  Checkout `codex-split-recovery`; investigate and repair actual split interactions
  beyond command-bar invocation, which remains with `codex/command-bar-polish`.
  root and existing session data must be preserved. The original SP01–SP33 counts
  are unchanged while reported failures are investigated. Likely shared paths:
  `ParcSplitView.swift`, split controls and browser window/model integration.
  1.170 in separate windows with newly created public pages. In Parc the direct
  Control–Shift–Equals shortcut opened the split chooser and a URL produced two
  rendered pages; numbered focus, the group’s vertical conversion, separating an
  unfocused child while retaining the focused page, and rejoining that existing
  tab also produced the expected state. Closing the focused disposable pane
  retained its surviving page; cancelling a new split draft restored that page
  without a saved placeholder. The command-bar owner independently
  reproduced its selected Add Split View action failing in the same window.
  CUA pointer drag returned `noWindowsAvailable`, leaving divider resizing
  unverified; continue the remaining interactions against current source. These
  bounded observations do not establish whole-family runtime or motion parity.

- **Codex `codex/sidebar-visual-polish` — reported sidebar defects (October 29).**
  Checkout `/Users/josh/.codex/worktrees/sidebar-visual-polish/Parc`; bounded
  scope: floating Reload text, New Tab theme contrast and the single-Space dock
  `SidebarView.swift`, `SidebarDockStrip.swift` and focused checks/docs. Existing
  family and POL row counts remain unchanged; investigate and publish reviewed fixes.
  Reload's wrapped visible title is removed while its accessible label and live
  shortcut tooltip remain; the native toolbar component check and independent
  review pass. **Engine owner handoff:** produce a GUI-verifiable Parc.app from
  source containing `5c82ccf8` or a later descendant, with exact source SHA,
  artifact path and package-stage receipt. Sidebar owner will inspect Reload,
  New Tab and the Space dock in that package; this verification remains open.
  WIN13's window-command work is separate; preserve its original-window guards.
  component checks and independent review pass. The next package must also
  contain this correction. Iconless default and staged Spaces use the recovered
  8-point secondary foreground dot while keeping their original action owner.
  A lone iconless Space is omitted from the dock collection (Library and + only),
  Create Space keep the switcher. The next package must also contain this
  correction.

Paths below are relative to `/Users/josh/Documents/Codex/2026-10-23/re/work`.
The Owner cells above are authoritative. Update these next-step notes when
publishing; cross-Claude decisions must be committed here or in a linked
subsystem document, not left only in Codex messages.

- **Codex `codex/command-bar-polish` — Command bar (October 29).** Checkout
  `codex-command-bar-polish`; investigate reported horizontal scrolling and Easel
  with retained `command-bar.md` and original action and panel owners; coordinate
  GUI use and preserve WIN13 command-window lifetime guards. The reviewed
  viewport correction fits the whole AppKit table to its clip width and preserves
  vertical scrolling; a 288-assertion component check and whole-module
  typecheck passed. Live gesture comparison is not established. The reported
  Easel and Add Split View selections dismissed without action in v240; their
  direct shortcuts worked in the same active session. macOS denied debugger
  attachment, so the exact rejection boundary and current-source runtime remain
  unobserved. Source identifies a conditional shared registry-revision rejection
  during key restoration; the activation's Space-menu refresh now waits until
  dismissal and selected-action dispatch settle, without weakening original
  item or window validation. Current-package behavior remains unverified.
  [Evidence](command-bar.md#reported-command-dispatch-failure--october-29).
  CMD24–CMD28 remain LEFT; this focused polish increment does not complete them.
  A separately delegated empty-field icon correction keeps the magnifying glass
  when a selected recent tab's favicon arrives; the Cmd-L empty-field path shares
  that rule. See `command-bar.md` for the observed v240 mismatch and its limits.

- **Cursor `cursor/cb-look` — command bar look (November 1, Josh's request).**
  Checkout `work/cursor-cb-look`. Helper increment; the family stays with
  `codex/command-bar-polish` and CMD26/CMD27 stay LEFT. Josh said the bar was
  decorative rings and 0.5/48/24 shadow (drawn in a mouse-transparent child
  window, so presses outside the bar reach the page). It follows the Space's
  own light/dark appearance instead of forced dark. The selected row takes the Space theme's semantic
  0.25 s fade on every selection move. The field is one line, with PopoverInputText
  text, a `maxContrastColor` icon and `subtitle` text selection; a one-pixel
  and the type is FontSet `label` at weight 7 (13) and 18 for the field.
  Coordinator approved the v2 renders while Josh was away. Shared API for
  `cursor/cb-results` and `cursor/cb-site-search` (who rebase over the
  `CommandResultCell`/`CommandBar` changes): `CommandBarPalette`,
  `CommandBarTypography`, `CommandBarSurface`, `CommandBarShadowWindow`,
  `CommandBarHairline` in `CommandBarAppearance.swift`. Open: the bar's corner
  selection for a Space without a colour, an inferred neutral grey palette
  panel's lightness over a light page, which needs a running build
  ([what to check](command-bar.md#checking-appearance-in-a-running-build)).
  Shared paths: `CommandBar.swift`, `CommandBarAppearance.swift`,
  `CommandResultCell.swift`, `CommandResultRowView.swift`, `CommandBarScopeEditing.swift`,
  `BrowserWindowController.swift` (passes the theme and appearance), `tests/CommandBar/AppearanceTests.swift`,
  [command bar](command-bar.md#appearance-and-theme).
- **Cursor `cursor/cb-results` — command-bar row content (November 1).** Josh
  asked directly; the Command bar family stays with Codex (inactive) and this
  entry does not change CMD counts. Checkout `cursor-cb-results`. Owns what rows
  say and show: titles, the em-dash URL subtitle, truncation, Switch to Tab
  captions and command icons; siblings `cursor/cb-look` (panel/row metrics,
  fonts, colours, selection), `cursor/cb-site-search` and `cursor/cb-stability`
  [result row content](command-bar.md#result-row-content). Consumes
  `cursor/cb-stability`'s `PCNativeSearchNavigation.matchType` exactly as that
  handoff names it (`NSString`, `AutocompleteMatchTypeToString`), guarded by
  `responds(to: #selector(getter: PCNativeSearchNavigation.matchType))`; without it rows fall back to
  the search flag and description. Merged over `cursor/cb-look` and `cursor/cb-stability`: the
  show it, colours and the selected colour come from `CommandBarPalette`, rows
  keep `cursor/cb-stability`'s identities and ranking, and the calculator reads
  the input its snapshot answered. Shared paths:
  `CommandBar.swift`, `CommandResultCell.swift`, `BrowserWindowController.swift`.
  being on.

- **Cursor `cursor/perf-shortcut-scan` — renderer key-down shortcut scan (October 31).**
  Checkout `cursor-perf-shortcut-scan` (`cursor/perf-shortcut-scan`). Does not
  take Performance family ownership and does not mark PERF04 or PERF05 DONE.
  `KeyboardShortcuts.nativeCommand` looks up a revision-invalidated index of
  live chords instead of walking every menu reference and re-checking conflicts
  on each renderer key-down. Unmodified letters skip physical capture. Who
  wins, IME (`hasMarkedText`), PreferParc versus renderer ACK, Window Undo,
  keyboard-lock and which menu item fires stay the same. Shared path:
  `KeyboardShortcuts.swift`. Family owner remains `codex/perf04`.

- **Cursor `cursor/perf-hosted-layout` — skip no-op Chromium hosted layout (October 31).**
  Checkout `cursor-perf-hosted-layout` (`cursor/perf-hosted-layout`). PERF05
  remains LEFT; `codex/perf04` keeps PERF04. `PageContentResizer.place` still
  applies throttle/hold/lock frames. It skips the recursive hosted dirty plus
  `layoutSubtreeIfNeeded` when this page frame was already flushed and hosted
  children (stopping at `PCNativeDevToolsPaneView`) already fill it. Intrinsic
  autoresizing that wrote the page/pane frames before `place` still flushes,
  because the inspected Chromium host does not autoresize. A new page size,
  or a hosted child that does not yet fill the page, still flushes so
  Chromium adopts it in the same pass. Does not edit
  `BrowserWindowController.swift` (`cursor/perf-chrome-fanout`). Shared paths:
  `PageContentResizer.swift`, `tests/SidebarResize/`,
  [sidebar resize](sidebar-resize.md).

- **Cursor `cursor/perf-tab-switcher` — held ⌘-Tab overlay hitch (October 31).**
  Checkout `cursor-perf-tab-switcher` (`cursor/perf-tab-switcher`). Helper
  increment; does not take Performance or Tab switcher family ownership and
  does not mark PERF05/PERF rows DONE. `codex/perf04` keeps PERF04. Identical
  items, palette colors and PreferenceKey frames are not republished; focus
  lives on a separate object so a held-key step updates the fill, caption
  and scroll without rebuilding the hosted card stack. Cycling, selection,
  appearance and motion stay the same. Shared paths:
  `RecentTabSwitcher.swift`, `RecentTabSwitcherView.swift`,
  `tests/KeyboardNavigation/RecentSwitcherPresentationTests.swift`.

- **Cursor `cursor/perf-hover` — pointer-driven sidebar hover cost (October 31).**
  Checkout `cursor-perf-hover` (`cursor/perf-hover`). PERF05 remains LEFT;
  `codex/perf04` keeps PERF04. `SidebarHoverTracker` still evaluates every
  reuses converted screen rects while hover info and window/view geometry are
  unchanged, skips extra settle passes once `tracking.info` is stable, and
  keeps one 0.08 s stop work item per `lastMove` instead of enqueueing a new
  one on every event. Does not edit `layoutChrome` / store-driven reconstruct
  (`cursor/perf-chrome-fanout`). Shared paths: `SidebarHoverTracker.swift`,
  `tests/SidebarHover/SidebarHoverTrackerTests.swift`,
  [sidebar motion](sidebar-motion.md). Cmd-S completion still runs a full
  `layoutChrome` plus `layoutSubtreeIfNeeded`; leftover for the theme/layout
  owner.

- **Cursor `cursor/perf-command-bar` — command-bar history scan (October 31).**
  Helper increment in `cursor-perf-command-bar`; does not claim Performance or
  Command bar family ownership and does not change CMD/PERF counts. Empty-query
  recents and Library History reuse oldest-first visit order when timestamps
  strictly increase, otherwise the same `visitedAt` descending sort as before,
  including same-second ties. Matching, ranking versus live tabs, empty-query
  contents and Return behavior stay the same. Shared paths: `BrowserStore.swift`,
  `CommandBar.swift`, `LibraryView.swift`, `BrowserWindowController.swift`.

- **Cursor `cursor/cb-stability` — command-bar typing stability and feature
  inventory (November 1).** Josh asked directly; the Command bar family stays
  with Codex (inactive), and this entry does not change CMD counts until rows
  close. Checkout `cursor-cb-stability`. Owns result ordering, update mechanics
  and missing functionality; siblings `cursor/cb-look`, `cursor/cb-site-search`
  and `cursor/cb-results` own panel/row look, the site-search hint and row
  rows stay until an output for the current query arrives (`updateQuery`
  engine restarts Chromium per keystroke without clobbering its cached
  suggestions (overlay change in `native_search.mm`). Shared paths:
  `CommandBar.swift`, `CommandBarRowDiff.swift`, `native_search.mm`,
  `overlay.json`. **Handoff to `cursor/cb-results`:** each native result now
  exposes `PCNativeSearchNavigation.matchType` (`NSString`, Chromium's
  `omnibox::AutocompleteMatchTypeToString` name: `search-what-you-typed`,
  `search-suggest`, `search-suggest-entity`, `search-history`,
  `url-what-you-typed`, `history-url`, `history-title`, `navsuggest`,
  `bookmark-title`, `search-calculator-answer`, …) and `relevance`
  (`NSInteger`). Until the engine with this overlay ships, check
  `responds(to: NSSelectorFromString("matchType"))` before reading it.
  Ordinary queries now rank every source together (`CommandBarRanking.swift`,
  [typing stability and ranking](command-bar.md#typing-stability-and-ranking)):
  actions, Chromium rows, tabs, Notes/Easels without a sidebar tab and
  recoverable, so the weights are Parc's. **Handoff to `cursor/cb-commands`:**
  an action's placement uses `CommandBarRanking.match` over the texts built in
  `CommandBar.rankedResults` (title, Space/folder target, title plus group);
  add trigger phrases to that `texts` array rather than reordering rows, and
  pass a command's bump as `CommandBarRanking.Candidate.bump` (for example
  `bump: CommandBarMenuItemInfo.candidateBump(forMenuCommand:) ?? 0` in the
  `.typeTravel` candidate built there); a bump never admits an unmatched action.

  (November 1).** Josh asked directly; the Command bar family stays with Codex
  and CMD counts don't change. Checkout `cursor-cb-extras`. Done: the
  colours, kept inside scopes, Search Settings… → Settings → Profiles), and the
  sidebar's empty list area dragging the window on a press and opening the
  new-tab bar on a double-click below the last row
  ([command bar](command-bar.md#search-suggestion-privacy-banner)). Excluded: ⌥⌘G
  produced in 1.122, and `addSearchEngine` is a reducer action that adds to the
  bar's engine list, which Parc's native keyword session already covers. Left:
  the in-bar default-browser prompt (a `DefaultBrowserPrompts` campaign behind
  Shared paths: `CommandBar.swift`, `CommandBarSearchPrivacyBanner.swift`,
  `SidebarView.swift`, `SidebarTablistBackground.swift`,
  `BrowserWindowController.swift`.

- **Cursor `cursor/perf-session-save` — session-save hitch (October 31).**
  Checkout `cursor-perf-session-save` (`cursor/perf-session-save`). Does not
  take Performance family ownership and does not mark PERF08 DONE.
  `BrowserStore.save()` / `scheduleSave()` encoded the pretty-printed session
  on the main thread 0.25s after each `changed()`. Encode/write now run on
  `org.parc.session-save`; JSON schema, pretty-printed sorted keys, 0o600,
  atomic replace, debounce and ephemeral skip are unchanged. Shared path:
  `Sources/ParcCore/BrowserStore.swift`. Family owner remains `codex/perf04`.

- **Cursor `cursor/perf-loading-timers` — loading chrome display-link ticks (October 31).**
  Helper increment in `cursor-perf-loading-timers` (`cursor/perf-loading-timers`).
  Does not claim Performance family ownership; PERF04 stays with `codex/perf04`
  and PERF rows remain LEFT. While a page is loading, `ReloadGlyph` and
  `PageLoadingIndicator` sampled their recovered springs from `Timer` on
  `.common` (120 Hz + 60 Hz), including during scroll and mouse tracking.
  CVDisplayLink adaptation already used for download arrival; 60 Hz elapsed
  timer only before macOS 14) and stop when idle: the reload glyph after its
  load/spin springs settle, the pill after a hidden rest or Reduce Motion's
  static track. Appearance, delays, curves and when the spinner/bar appear or
  hide are unchanged. Shared paths: `ReloadControl.swift`,
  `PageLoadingIndicator.swift`, `tests/NavigationLoading`.

- **Cursor `cursor/perf-loading-pill-pulse` — identical pulse/sweep presentation skip (October 31).**
  Helper leftover on `223c4d6f` in `cursor-perf-loading-pill-pulse`
  (`cursor/perf-loading-pill-pulse`). Does not claim Performance family
  ownership; PERF04 stays with `codex/perf04` and PERF rows remain LEFT. While
  the pill's display link still samples during recovered loading pulse/sweep,
  ticks whose scale/opacity/stroke fingerprint already matches the last apply
  skip the CALayer transaction; a changed frame still presents. Shared paths:
  `PageLoadingIndicator.swift`, `tests/NavigationLoading`.

- **Codex `codex/perf04` — Performance (claimed October 29).** Josh requested
  reauthorized functional browser checks and performance measurements for this
  polish pass. PERF04 is active and remains LEFT. Checkout `codex-perf04` owns
  controlled representative real-HTTPS comparison, causal investigation and
  fixes. GUI access is coordinated with the root owner; the dedicated engine
  owner retains shared engine build, seal and package ownership. Likely shared
  paths include the navigation bridge, native engine overlays and this ledger.
  Exploratory private-window timings and their workload/viewport limits are
  recorded in [navigation performance](performance-navigation.md). A reviewed
  metadata transaction reduces queued state publications and passes the model
  check. Favicon eligibility avoids building a full visible-tab array per request;
  its whole-module typecheck and independent review pass. These performance
  effects remain unmeasured. Native callback fanout has
  further redundant refresh work, but ownership and reentrancy make blanket
  notification coalescing unsafe. The sidebar now shares the same pure split
  projection within each render and hierarchy-container build, eliminating
  repeated calculations without caching across callbacks; its effect is also
  unmeasured. Continue with narrower source investigation
  and ordinary browser observation as GUI access permits. Other Performance
  requirements are not claimed as completed. Cursor `cursor/perf-navigation`
  (helper, October 31) does not take this family: `DidFinishNavigation` in
  `native_appkit_page.mm` still `Notify()`s primary cross-document loads, and
  skips subframe/iframe and primary same-document only when URL/title/loading/
  back/forward and favicon observation are already current. Overlay v271 is applied and built (in the November 1 overlay 286 engine). PERF04 remains LEFT.

- **Cursor `cursor/perf-library` — Library reload/flush freeze (October 31).**
  Checkout `cursor-perf-library` (`cursor/perf-library`). Does not take the
  Performance family or mark PERF09 DONE; `codex/perf04` remains Performance
  owner. Production Library keeps origin History `historyRevision` /
  `BrowserHistoryOrder.newestFirst`, skips Archive grouping when archived tabs
  and space names did not change, skips no-op Downloads/Documents/Media table
  rebuilds, and no longer `CATransaction.flush()` on filter expansion. Visible
  rows, selection, IME, download progress and newly persisted notes still
  update. Shared paths: `LibraryView.swift`, `DownloadLibraryView.swift`,
  `DocumentsLibraryView.swift`, `CaptureLibraryView.swift`. Coordinate with
  `codex/library-polish` on LibraryView. Leftover: `PeekHostView`
  (`PeekController.swift` ~324) still calls `layoutSubtreeIfNeeded` on Peek
  confirmation title changes; not changed here. Next: remaining Library hot
  paths after this increment. Do not fast-forward `/Users/josh/Parc`.

- **Cursor `cursor/perf-chrome-fanout` — idle metadata fanout (October 31).**
  Checkout `/Users/josh/Documents/Codex/2026-10-23/re/work/cursor-perf-chrome-fanout`.
  Does not take the Performance family or the `codex/perf04` owner cell. Shared
  files: `BrowserWindowController.swift`, `SidebarView.swift`, `BrowserStore.swift`,
  `ParcEngine.m`. Josh lock: skip reconstruct only when membership/selection/structure
  match; apply a distinct title/URL/loading/favicon/capture onto existing cells
  immediately. Custom-info split capture badges (named or custom-icon) and
  speaker-host appearance still reconstruct. Identical title/URL writes do not
  publish. Distinct engine notifications are not coalesced. PERF rows stay LEFT.

- **Cursor `cursor/library-spaces` — Library Spaces page (October 31).** Checkout
  `work/cursor-library-spaces`. It does not take a family, and the Library shell's
  owner keeps LibraryView. It changes the Spaces page cards
  (`SpaceManagerView.swift`), the card-only sidebar branches (`SidebarView.swift`),
  `ThemeRendererView.drawsMaterial` and the card Clear wiring
  (`BrowserWindowController.swift`). Visuals were approved by the coordinator.
  Its follow-ups for the sidebar owner (row title padding and truncation, the
  row × tint, and the window sidebar's divider/Clear row) are closed by
  `cursor/sidebar-followups` below.
  [Presentation](space-management.md#library-spaces-page-presentation).

- **Cursor `cursor/spaces-width` — Library grows on the Spaces page (October 31).**
  Checkout `work/cursor-spaces-width`. It takes no family; the Library shell's
  owner keeps LibraryView. The Library was 417 points on every page, so the
  `homeWidth`: max(min(window width − 56, the page's width), 417), with 417 a
  floor rather than the cap the earlier comment and docs described. Spaces is
  216 + 264 × the number of Spaces, and every other page 417. A page change
  window resize settles it. The coordinator approved the renders. Choices
  recorded with the evidence: the screenshot's 4-point strip inset (its owner
  1.122 evidence in [Library width](space-management.md#library-width-on-the-spaces-page)
  settles the other two. Opening on Spaces
  `setHomeWidth` skips the group while that runs. A Space count change on the
  `SpaceManagerView.swift` (`SpaceManagementLayout`), `SidebarMotionController.swift`
  (`SidebarChromeFrames`, the `libraryWidth` style, the layout fingerprint) and
  `BrowserWindowController.swift` (open, change, close and resize).
  [Library width](space-management.md#library-width-on-the-spaces-page).

- **Cursor `cursor/sidebar-followups` — sidebar row, divider and dock polish (October 31).**
  Checkout `work/cursor-sidebar-followups`; it takes no family and closes the
  with the cards' "arrow.down" Clear, ForegroundPrimary while hovered;
  `cursor/today-rows` below corrects when Clear shows, the border and the New
  Tab row. Tab-row and named-split title text runs from the 36-point
  neutral close glyph ([TAB19](#ordinary-row-presentation--tab19),
  [split groups](split-groups.md)).
  A press dragged off the dock + clears its plate
  ([dock plus](sidebar-motion.md#dock-plus-button)). A card's More has a 6-point keyboard ring,
  and a card's Clear is disabled when another window owns every Today page
  ([cards](space-management.md#library-spaces-page-presentation)). Visuals were
  approved by the coordinator.

- **Cursor `cursor/theme-picker-drag` — theme picker knob drag and cursors (October 31).**
  Checkout `work/cursor-theme-picker-drag`. It takes no family and adds no
  credit to SPACE15. The colour pad's knob container no longer flips its
  geometry a second time, so a grabbed knob stays under the pointer at the
  grab offset and holds the 0.99 rim beyond it. Saved colours now draw where
  arrow over the pad, open hand over knobs, closed hand while dragging, and a
  pointing hand on the appearance buttons, − and + and the preset chevrons.
  There is no crosshair, and swatches keep the arrow. A press on a disabled
  pad button no longer grabs the knob beneath it. One adaptation: a release
  outside the pad restores the arrow. Shared with
  `cursor/theme-picker-look`: `SpaceThemeEditorView.swift`, where this
  increment touches only the knob container flip, hit-testing and cursor code.
  Visuals were approved by the coordinator.
  [Contract and checks](space-theme-input.md#drawn-knob-position-and-cursors-october-31).

- **Cursor `cursor/today-rows` — Today divider, Clear and New Tab (October 31).**
  Checkout `work/cursor-today-rows`; it takes no family and adds no credit. The
  window sidebar hides Clear at rest and fades it in while the pointer is over
  the sidebar; the divider row, and so Clear, exists only while Today has items.
  column, the 14-point title at the tab title's inset, the hover plate, the
  press bounce and no tooltip. Library cards with Today items keep showing
  Clear without hover.
  Visuals were approved by the user and coordinator
  ([Today divider, Clear and New Tab](#today-divider-clear-and-new-tab)).

- **Codex `codex/library-polish` — Library appearance and interaction pass (October 29).**
  Checkout `codex-library-polish`; the scope is the shared regular Library and
  its Archive, History, Media, Downloads and Easels & Notes presentation, with
  This is a bounded polish assignment, not a claim that the separate Archive and
  history family or its fixed requirements are complete. WIN11 retains private
  Library ownership; changes to its behavior require coordination with that owner.
  Likely shared source is `LibraryView.swift` and Library category views. Begin
  with retained Home header and category evidence, then compare actual views.
  Cursor `cursor/document-close` (worktree
  `/Users/josh/Documents/Codex/2026-10-23/re/work/cursor-document-close`) does
  not take this family. It is a defect fix on completed Notes/Easels: Cmd+W /
  title cards instead of stock footer bezels; and open Easel paper must follow
  the Space `contentOverBackgroundAppearance` the same way Notes already do,
  instead of staying locked to Aqua.   A further defect on that same checkout:
  the Library hover flyout must list Documents/Desktop/Screenshots folder files
  on window ready instead of wiping the catalog against an empty GUID set.
  (select, image, text, circle, square, arrow, scribble) rather than the
  labelled 36-point caption strip. The sidebar Mini Player must compact to the
  33-point transport when idle, expand title/close chrome on hover, and keep
  the volume slider inside that hovered card instead of a menu that vanishes.
  disclosure tail is aligned over the dock + near the card's trailing edge,
  outside-click/Escape/row choice and parent lifecycle close it, and while it
  is open it defers floating-sidebar dismissal. Its `onVisibilityChange` is
  the open/close hook: true as the HUD opens, false as closing starts.
  Its colours come from the window's live Space theme palette, resolved by the
  window, and shared with the history chooser: `backgroundExtra` over black or
  white for the card and tail, `hover` for the highlight and separators, `subtitle` for
  13-point medium and shortcuts 13-point regular kerned 2, in a 290-point card
  (sidebar-motion.md "Colours and type").
  GrayA11 that turn π/4 into an × while the HUD is open, on
  spring(0.2, 0.5) (Reduce Motion switches it), with GrayA4 hover and
  GrayA5 pressed plates, a GrayA12 pressed glyph, radius 6 and the 0.95
  press scale on spring(0.3, 0.6) (sidebar-motion.md "Dock plus button").
  `TranslucentButtonFace` for the header's toggle, Back, Forward and Reload,
  and SwiftUI `SidebarPlusButtonFace` for the dock +. Both use
  `TranslucentButtonColors`, the continuous 6-point plate, the 0.95 press on
  spring(0.3, 0.6) and the 0.1 s ease-in hover. Merging them into one
  implementation is a consolidation candidate, not yet done.
  Chrome Web Store “Add to Chrome” must install into the Site Control Center’s
  48×32 tiles (16-point icon, pin badge) instead of publishing a CRX as a
  smaller Library download.
  The Settings membership card must keep one masked blob (no stacked copy on
  hover or while the window is key), settle to that same silhouette when
  unfocused, and Randomize must replace the palette and interior blob
  configuration.
  `_32`, 14 points at the narrow row's `_28`; force-reload artwork in Developer
  Mode), crossfade to `xmark` while loading, and spin 2π on press; Clear is
  black/white, not the theme subtitle fill. Corrected October 31 with REA:
  ForegroundPrimary while hovered, in the window sidebar and Library cards
  alike. The window sidebar shows it only while the sidebar is hovered, so 0.3
  is not a resting state there ([Today divider](#today-divider-clear-and-new-tab)).
  Tab-row titles and still glyphs (Easel `square.on.square`, Note `note.text`,
  web `globe`) paint `SemanticColorPalette.title` without vibrancy, matching
  mini player, instead of light-mode ink / `subtitle` on a dark Space.
  Shared files are
  `BrowserStore.swift` (`openNote` / `openEasel` / `finishClosingTabs`),
  `DocumentsLibraryView.swift`, `EaselEditorViewController.swift` /
  `EaselAppearance.swift` / `EaselCanvasView.swift`,
  `BrowserWindowController.swift` (`inheritNoteCanvasTheme`, download refresh,
  flyout file query), `LibraryFlyout.swift` / `SidebarLibraryEntry.swift`,
  `Engine/ParcNative/downloads.cc`, `SiteControlCenter.swift`,
  `MembershipCardView.swift`, `ReloadControl.swift`, `MiniPlayerView.swift`, `SidebarPlusMenu.swift`,
  and a one-line
  `LibraryView.swift` `onClose` wire. Remaining Library categories stay with
  this Codex owner. Contract:
  [Easels & Notes Library cards](documents-library-grid.md), [Easel appearance](easel-appearance.md), [local Notes](notes.md), [Library flyout](download-library.md#original-library-flyout).

- **Codex `codex/windows-lifecycle` — Windows and lifecycle (claimed October 29).**
  Family checkout `codex-windows-lifecycle`; 10/14 DONE and 4/14 LEFT.
  Row owners `win11`, `win12`, `win13`, and `win15` use worktrees
  `codex-win11`, `codex-windows-lifecycle`, `codex-win13`, and `codex-win15`,
  respectively. WIN14 is closed by Josh and removed from active scope. WIN12's reviewed increments preserve
  subsecond per-window recency, identity and local presentation in session
  records and add Dock reopen/menu handling. AppKit restoration now returns
  original regular-window IDs without forcing their frame or focus; startup
  requests wait for restoration and retain original ownership. Unrestored
  records are preserved; the author continues stored window state and logout policy.
  WIN12 retains integration ownership of the unowned pinned-section interaction;
  its implementation draft is in `/Users/josh/.codex/worktrees/win12-pinned-section/Parc`,
  with the live peek's nested membership and clear paths still under trace.
  Per-window folder disclosure is a separate WIN12 dependency draft in
  `/Users/josh/.codex/worktrees/win12-folder-expansion/Parc`; it must migrate
  the original window's disclosure consumers, transactional hierarchy updates
  and Undo/Reopen without changing other windows. Nested peek behavior remains open.
  Stay on Top is integrated for regular and private standard windows; popup
  windows are excluded and private state stays ephemeral. It preserves each
  original native window level and regular window's identity-matched setting.
  Per-window item-creation date production and logout routing remain under investigation.
  Reference and checks are in [Windows and lifecycle](windows-lifecycle.md).
  precede its incognito Spaces guard. Capture admits original OTR pages;
  private Media opens the exact parent
  profile catalog while source navigation stays in the original private window.
  Private Media folder and hidden-file preferences are isolated in memory per
  physical window. Explicit private capture-to-Library uses the original parent
  catalog. Document modal routing, capture-to-Easel and cross-window retirement
  remain in progress.
  Owners coordinate shared window, private-context, focus and lifecycle interfaces
  directly. WIN11, WIN12, WIN13 and WIN15 remain LEFT
  through implementation, dependencies, permitted checks and independent review.
  Likely shared files include `AppDelegate.swift`, `BrowserWindowController.swift`,
  `WindowPresentation.swift` and the parity ledger; changes will be bounded and
  reconciled with active owners. Do not advance shared engine inputs or run
  functional browser tests.
  WIN13's reviewed partial increment gives Import and Settings their own Close
  Tab/key-context handling, refuses New Tab in Import, and prevents importer
  cleanup from raising a browser after focus has moved. The original browser
  Close Tab fallback now requires that browser's key context. Browser navigation,
  sidebar and zoom menu commands likewise require the actual key browser and
  refuse an attached sheet, with zoom retaining its original-page eligibility.
  Reopen, Pin and Duplicate now retain the original window and native security
  admission; command-bar cleanup revalidates the original window and profile
  after callbacks, including owned-panel and history-chooser return. The shared
  focused-window and non-key security properties are available to WIN11. Copy
  and Space menu actions now use their original eligible window; education Copy
  checks the available page state; exact renderer admission is now exposed by
  the reviewed native command-window query, pending engine integration. Share, Extensions and Cast menu
  commands now require their original key browser; extension destination
  resolution rechecks the original window, Space and Profile through cleanup.
  Site Control Center delays retain the original window, anchor and page; normal
  footer actions revalidate after dismissal. The reviewed hidden-destination
  admission query is also available in source, pending engine integration;
  the popup footer handoff and consuming integration remain open.
  are in [window activation](window-activation.md). WIN13 stays LEFT while its
  owner continues the broader modal/auxiliary comparison and coordinates WIN11
  and WIN12 dependencies.

- **Codex `codex/routing-family` — Routing (claimed October 29).** Josh
  requested the next available family while Media continues independently.
  Current count 12/13 DONE, 1/13 LEFT. ROUTE12 stays LEFT until its full
  implementation, required dependencies, permitted checks and independent
  review are complete and published. The coordinating checkout is
  `codex-routing-family`; row owners use separate worktrees. Start with
  `settings.md` Links and internal original-request routing, the native routing
  advance shared engine inputs. Functional browser tests remain prohibited.
  Active row owner `route12` uses `codex-route12` for disposition and
  unavailable-destination policy. ROUTE13 covered editor layout, controls and
  commit/cancel; ROUTE14 covered feedback, focus, keyboard/AX and transition
  motion. The ledger and
  `settings.md` are reconcile-only, with each author updating their own row.
  ROUTE13 is complete: the inline editor and guarded close handoffs are
  independently reviewed and published at `e2108c07`; its finished whole-module
  the unestablished add-control presentation and additional-condition label are
  documented as Parc adaptations in [Links](settings.md#links-and-air-traffic-control).
  **ROUTE14 complete; ROUTE13 integration:** the inline editor
  connects rule/condition-keyed text focus and selection, surviving-control
  focus with a disabled-control fallback, ordered key views, repeated failure
  announcements and selectable full error details. Destination refresh waits
  for active editing, tracked menus and nested sheets. A new inline rule uses
  the recovered 0.3-second top-anchored scroll with Reduce Motion support;
  timing follows inline insertion. ROUTE13 owns this consumer integration.
  ROUTE14's isolated Swift check and whole-module SIL passed and its interaction
  source was independently reviewed. Browser input and VoiceOver acceptance
  were not run. [Interaction evidence](routing-interaction.md). Routing is
  11/14 DONE and 3/14 LEFT at the time, moving by 1/14 (7.1 percentage points).
  Each author retains the complete row through checks, fresh independent
  same-worktree review and direct verified publication.
  ROUTE11 is stopped and removed from the fixed requirements by Josh. Its
  [reference investigation](settings.md#internal-original-request-routing)
  behavior. No created page or original request was replaced.
  **ROUTE13 → Windows and lifecycle owners:** the close-committed
  Links editor needs native and programmatic Settings close to prepare its live
  sheet before `windowWillClose` cancels attached sheets. Interface:
  `LinksSettingsView.prepareForParentClose() -> Bool` finishes field editing
  and atomically commits; success dismisses the sheet, while write failure,
  conflict or an active nested alert keeps Settings open. Explicit discard
  remains available after failure. `SettingsWindow.attemptClose() -> Bool`
  performs the same preparation before `super.close()`; `windowShouldClose(_:)`
  performs preparation for native close. Guard programmatic Settings closes in `AppDelegate`
  and `BrowserWindowController`, including onboarding replay: no ownership
  transition occurs when preparation fails. ROUTE13 owns routing source and
  bounded Settings/caller hooks; Windows owners should preserve the interface
  and record competing close ownership here. The native empty-binding callback
  keeps its owner alive while Settings is visible; its stale empty guarantee is
  not replayed after a delayed sheet. Termination also requires preparing the app's
  Settings and each browser-owned Settings before `terminationInProgress` in
  `AppDelegate.continueApplicationTermination`, aborting quit/restart on a
  failed commit or active nested alert. Browser preparation uses
  `prepareSettingsForTermination() -> Bool`, followed by guarded Settings close.
  Windows lifecycle owners: preserve existing termination/close consent and
  coordinate any competing lifecycle changes here. These boundaries are Parc

- **Cursor `cursor/media12` — Media (MEDIA12 complete October 31).** Prior Codex
  `codex/media-family` retired after idle handoff. Checkout `work/cursor-media12`
  (`cursor/media12`). MEDIA12 wires recovered presentation-set producers beyond
  Separate (ItemSelection mirrors, tab-fullscreen enter, Space switch, non-split
  Peek Expand) onto the shared lease/fence path; host eligibility and privacy
  pools retain their earlier adaptations. Retire the MEDIA12 author after
  confirmed publication and independent review clearance.

- **Cursor `cursor/notes` — Notes local restoration, active family (claimed
  October 29).** Josh requested this next family after the Easels stop.
  Family-owner checkout `cursor-notes` (branch `cursor/notes`) under
  `/Users/josh/Documents/Codex/2026-10-23/re/work`. Active requirement IDs
  NOTE22–NOTE26 now run in parallel row worktrees from current origin/main.
  NOTE21 historical import and local save-effect stays published; do not
  reopen it. Row checkouts: `cursor-notes-note22` (`cursor/notes-note22`),
  `cursor-notes-note23` (`cursor/notes-note23`), `cursor-notes-note24`
  (`cursor/notes-note24`), `cursor-notes-note25` (`cursor/notes-note25`),
  `cursor-notes-note26` (`cursor/notes-note26`), all under
  `/Users/josh/Documents/Codex/2026-10-23/re/work`. Family orchestrator is
  Cursor `cursor/notes`. Row authors own implementation, author checks,
  same-worktree independent review, rebase and `git push origin HEAD:main`.
  Exclusive production scope (bounded wiring only in shared files;
  fetch/rebase origin/main before publish; never overwrite a peer Notes
  row or the Page tools family/TOOLS16/TOOLS17 cells):
  - NOTE22 (`cursor-notes-note22`): remaining historical editor/menu/keyboard
    command discovery and recovered command wiring. Prefer new focused files.
    Bounded dispatch only in `NoteEditorViewController.swift` /
    `NoteKeyboardEditing.swift` for newly recovered selectors. Do not take
    appearance, pressed/glyph drawing, AX presentation, or motion.
  - NOTE23 (`cursor-notes-note23`): exclusive `NoteDocumentPresentation.swift`;
    remaining outer compositing, Space-theme inheritance and remaining
    document typography/layout. Bounded pane-backing only around
    `setNoteCanvasBacking` in `BrowserWindowController.swift`. Do not take
    gutter/menu/link pressed-state drawing, remaining commands, AX, or motion.
  - NOTE24 (`cursor-notes-note24`): exclusive `NoteFormatting.swift` and
    `NoteSelectionFormatting.swift` for selection/gutter/link/menu pressed
    states and historical glyph appearance. Do not take outer canvas/theme,
    remaining commands, AX, or motion springs.
  - NOTE25 (`cursor-notes-note25`): full keyboard/accessibility/viewport-focus
    presentation of existing Notes surfaces. Prefer a new focused AX/focus
    file. Bounded first-responder/AX hooks only. Do not recover new editor
    commands, change drawing, or add motion.
  - NOTE26 (`cursor-notes-note26`): original transition motion and any
    attributable haptics. Prefer a new focused motion file. Bounded
    presentation/dismissal hooks only. Do not invent unattributed haptics.
    Do not change static appearance, remaining commands, or AX.
  Reconcile-only shared: `docs/parity.md` (own NOTE row + family Done/Left/
  Latest change on publication), `docs/notes.md` (own section), focused tests
  and `scripts/test-notes.sh` source lists. Do not apply/build the shared
  engine. Preserve Page tools ownership. Evidence: [local Notes](notes.md).
  Next step: NOTE25 independently reviewed CLEAR and published; Notes family
  26/26. Family owner credits DONE and retires.

- **Cursor `cursor/page-tools` — Page tools (claimed October 29).** Josh
  requested this family and moved it from priority 17 to 14. Family checkout
  `cursor-page-tools` (branch `cursor/page-tools`) under
  `/Users/josh/Documents/Codex/2026-10-23/re/work`. Remaining LEFT rows run
  concurrently (Josh, October 29, multitask). Per-row worktrees from
  origin/main: `cursor-page-tools-tools16` (branch `cursor/page-tools-tools16`)
  and `cursor-page-tools-tools17` (branch `cursor/page-tools-tools17`). Active
  requirement IDs: TOOLS16 and TOOLS17 at the same time. TOOLS14–TOOLS15 remain
  DONE; do not reopen them. Notes owner (`cursor/notes`, 13) and checkout
  remain intact. Evidence: [Developer Mode](developer-mode.md),
  [internal addresses](internal-addresses.md). TOOLS15 independently reviewed
  CLEAR: first-edit `selectAll:` on the next main-queue turn, recovered −45°
  15/15 stripes with page tint on the view layer, 8/5 insets, 28-point
  controls, Capture/Console divider and inside-first trailing collapse.
  TOOLS14 ParcNative `devtools_pane*.mm` focus-on-appear and TOOLS16 overlay
  248 (`native_popover_prompt*`, `native_page_tool_appearance.h`, translate/
  reader/exclusive-access/file-dialog hashes) are applied and built in v240.
  Neither row applies or builds the shared engine.

  Shared-file scope (exclusive unless noted). Reconcile peer publications;
  never overwrite Notes or the other Page tools row.
  - TOOLS16 (reader/translation/print/save/data-dialog appearance):
    `Engine/ParcNative/native_translate.mm`, `native_translate.h`,
    `native_reader.cc`, `native_reader.h`, `native_exclusive_access.mm` and
    `native_exclusive_access.h` (private-profile data-dialog chrome only),
    `file_dialog.mm` print/save presentation, new isolated appearance files
    and tests named for those surfaces. May add `native_popover_prompt.mm/.h`
    if sharing recovered PopoverPromptView chrome; do not rewrite
    `site_permission_presenter.mm` behavior. Documented Chromium viewer
    adaptations stay explicit.
  - TOOLS17 (page-tool keyboard/AX/hover/disabled/motion): `PageFindView.swift`,
    bounded page-tool keyboard/AX/hover/disabled/motion in
    `BrowserWindowController.swift` and `AppDelegate.swift`,
    `BrowserToolbar.swift` page-tool controls, new AX/keyboard/motion tests.
    Do not reopen TOOLS15 `DeveloperToolbarLayout.swift` geometry.
  - Reconcile-only: `docs/parity.md` — each row updates only its own
    requirement row and, on publication, the family Done/Left/Latest change.
    Never overwrite Notes 13, the other Page tools row, or unrelated family
    cells. `Engine/ParcNative/BUILD.gn` only if TOOLS16 adds a source.
    Avoid `SettingsWindow.swift` and `SidebarView.swift`.

  Next step: TOOLS16 independently reviewed and published (reader/translation/
  print/save/data-dialog appearance). TOOLS17 stays DONE. Overlay 248 with
  TOOLS14 `devtools_pane` focus-on-appear is in v240. Fixed family count
  17/17 DONE (100.0%), 0/17 LEFT (0.0%), +1/17×100 = +5.9 pp before rounding;
  denominator unchanged.

- **Easels — October 29, complete.** The nine remaining fixed rows were
  completed without reopening EASEL01–EASEL20. Denominator remains 29:
  29 DONE/0 LEFT (100.0%/0.0%) after reviewed EASEL27 delivery. Original
  assignments and publication ownership:
  - `easel21_attachments`: EASEL21 delivered from `claude-kbd-kb04`; author and
    independent reviewer permanently retired after verified `8cbb6418` publication. The recovered
    non-image boundary and external URL/native clipboard contract are complete.
  - `easel22_text_metrics`: EASEL22 delivered from `claude-kbd-kb21`; author and
    independent reviewer permanently retired after verified `a60c0157` publication. Content-hugging
    fill, actual native metrics and shared native/document history are complete.
  - `easel23_live_capture`: EASEL23 delivered from `claude-kbd-kb17`; exact source
    `18b4012f` is independently CLEAR and v239/overlay247 engine/app integration
    is confirmed. Original author and reviewer permanently retire after closure
    publication; the real region source/lifetime contract is complete.
  - `easel24_defaults`: EASEL24 delivered from `claude-kbd-kb22`; author and
    independent reviewer retire after confirmed publication. See the contract below.
  - `easel29_profile_transfer`: EASEL29 delivered from `claude-kbd-kb38`;
    original author and fresh independent reviewer retire after confirmed
    publication. The exact editor/session/native retirement boundary is complete.
  - `easel25_guides`: EASEL25 delivered from `claude-kbd-kb22`; author and
    independent reviewer permanently retired after verified `3eceb4dd` publication. Endpoint feedback,
    exact-only endpoint guides, recovered guide paths and link/card intrinsic
    guide sizing are complete. EASEL22 text/undo and EASEL23 live-page owners
    are preserved; EASEL26 has the scale-aware endpoint control handoff.
  - `easel26_accessibility`: EASEL26 delivered from `claude-kbd-kb04`; original
    author and fresh independent reviewer retire after confirmed publication.
    Native object selection/focus/actions, geometry controls and original embedded
    page entry/return are complete. EASEL22 text/IME/history, EASEL23 live pages,
    EASEL25 endpoints and EASEL29 session retirement remain integrated. EASEL27
    propagated its generic handle screen-scale API to the AX frame producer and retained actions;
    EASEL28 preserves the published native focus/gesture callbacks.
  - `easel27_appearance`: EASEL27 delivered from `claude-kbd-kb21`; original
    author and fresh independent reviewer retire after confirmed publication.
    Native canvas/selection, scale-correct handle eligibility, compact text rail,
    control states and owner-bound URL editors are checked and independently
    CLEAR. Native rich-format adaptations are documented; EASEL26 focus/AX,
    EASEL28 motion and CAP21 memory-only editing remain integrated.
  - `easel28_motion`: EASEL28 delivered from `claude-kbd-kb22`; original author
    and fresh independent reviewer retire after verified publication. Native
    pinch feedback and annotation visibility share original document/gesture/
    window ownership. EASEL27 consumes the reviewed visibility callback and
    handle-eligibility predicates across drawing, hits, cursors and AX actions.
    Those predicates are preserved in the finished EASEL27 static presentation.
  All 29 fixed Easel rows are complete. Original author/reviewer pairs retire
  after confirmed publication; no research children or nested reviewers. Active authors
  coordinate directly before overlapping `EaselCanvasView`, `EaselStore`, rich
  text or `EaselBrowserObjects` edits, record concrete interfaces here or in
  focused Easel docs, and preserve CAP21's shared memory-only image editor.
  Start with `docs/easels.md`, `docs/easel-embedded-pages.md`, retained reference
  helpers and `docs/capture-editing.md`; do not redo recovered evidence. Each
  owner completes its whole row, checks the actual integrated tree, obtains fresh
  independent code review in the same checkout, then publishes one-line commits
  immediately to main and verifies remote. Partial publication retains the author
  and LEFT status through full completion. Initial estimate/current-step reports
  are requested from each owner; root does not invent percentages.
  Capture source `0889e4a5` is packaged and fully verified using the unchanged
  v238/overlay246 seal; completion publication `5b131df0` released the canonical
  freeze. The same dedicated `engine_owner` delivered reviewed EASEL23
  overlay247 from `18b4012f` and retains family packaging; actual pipeline stages
  and source freezes are recorded under Shared engine ownership. Engine operations
  and canonical source advances remain solely owned by that agent.

  **EASEL27 delivered — October 29:** content-specific selection contours,
  recovered blue/circle marks, screen-scale targets, white paper, compact 50×88
  text rail, native disclosure/control states and owner-bound link popovers
  share the existing document/text/page owners. Independent review fixed retained
  AX edge admission after zoom and narrow toolbar clipping under legacy scrollbar
  preferences; exact finished source is CLEAR. Final whole-module SIL covers 259
  Swift inputs in 34 seconds with zero diagnostics. Checks pass 314 model, 547
  text/appearance, 203 native canvas, 51 capture destination, 14 native URL,
  26+12 motion and 25 memory-only capture assertions. Shared Notes store 32,
  editor 378, retirement 8 and tab 23 checks pass; the tab script's stale source
  list was repaired. Light/dark inert control renders were inspected. No functional
  browser, installed visual, FKA or VoiceOver acceptance is claimed. Native
  presentation adaptations and reference addresses are explicit in the
  [appearance contract](easel-appearance.md). EASEL27 is DONE: 29/29 DONE
  (100.0%), 0/29 LEFT (0.0%), +1/29×100= +3.4 pp before rounding; fixed denominator
  unchanged. Receipts and review hashes are under `easel-coordination/easel27`.
  No engine changes; the dedicated engine owner alone handles app packaging.

  **EASEL28 delivered — October 29:** recovered continuous native canvas zoom,
  directional 100% pinch haptics and immediate annotation visibility use the
  original scroll/window/document lease. The 0.1-second implicit annotation
  context admits current transitions, while cancellation, retirement and live
  Reduce Motion settle owned layers. Shared handle predicates withdraw hidden
  pointer/cursor/AX affordances and refuse retained actions. Logical viewport
  sizing is idempotent; fixed capture dimensions, bytes, native text/history
  and real embedded-page owners remain unchanged. Independent review is CLEAR
  after these integration fixes. Finished checks pass 26 motion policy/owner,
  10 actual canvas, 25 capture-editor and 88 native pool/session assertions;
  whole-module SIL covers 258 Swift inputs in 31 seconds with zero diagnostics.
  Receipts and exact review inventory are under `easel-coordination/easel28`.
  No functional browser or installed-motion acceptance is claimed. EASEL28 is
  DONE: 28/29 DONE (96.6%), 1/29 LEFT (3.4%), +3.4 pp before rounding; denominator
  unchanged. EASEL27 completion is recorded above. [Contract](easel-motion.md).

  **EASEL26 delivered — October 29:** stable native object focus and AX children,
  selected/focused state, original context/actions and visible geometry controls
  now share the durable canvas owners. Native page entry/recovery/return keeps
  exact window/Profile/page identity; transfer, retirement, changed content and
  detached actions refuse. Selection revokes page interaction synchronously.
  Independent review fixed object key-loop restoration after drawing/drag and
  recovery entry for crashed pages. Finished checks pass 203 native canvas and
  88 actual pool/session assertions, plus whole-module SIL in 66 seconds with
  zero diagnostics; all 264 recorded inputs are unchanged. Exact source review
  is CLEAR. No browser, Tab walk, FKA or VoiceOver driving occurred. EASEL26 is
  DONE: 27/29 DONE (93.1%), 2/29 LEFT (6.9%), +3.4 pp before rounding; denominator
  unchanged. [Contract](easels.md#canvas-keyboard-and-accessibility-ownership--easel26).

  **EASEL22 delivered — October 29:** content-hugging black fill with temporary
  white ink follows native glyph/attachment geometry, three synchronous edge
  passes and a rounded union. Editor, canvas and CAP21 memory rendering share
  actual TextKit layout; original colors/fonts/images remain intact. The older
  secondary metric table is resolved from its sole indexed caller, which drops
  that return value; no invented line heights are applied. Mixed/on/off fill
  control, persistence, clipboard and native/document history are implemented.
  Independent review fixed native checkbox cycling, smoothing pass comparison
  and fill inverses crossing document history. One durable editor-lifetime group
  preserves native per-action Undo; an exact history anchor refuses interposed
  shared-owner edits. EASEL21/EASEL24 and reviewed EASEL23 source are integrated;
  EASEL25/EASEL26 claims and all live-page ownership remain intact.
  Finished whole-module SIL: 257 Swift sources, 51 seconds, zero diagnostics;
  isolated checks: 283 model, 531 rich-text, 165 hidden canvas, 51 capture
  destinations, 10 native input and 25 CAP21 assertions. Fresh independent
  exact-source review is CLEAR. Receipts/hashes: `easel-coordination/easel22`;
  compiler: `claude-split-checks/easel22-reviewed-final.json`. EASEL22 is DONE;
  fixed denominator remains 29, now 23 DONE/6 LEFT (79.3%/20.7%), +3.4 pp.
  At that delivery EASEL23 remained LEFT through its required engine integration. No functional
  browser checks. [Contract](easels.md#content-hugging-text-fill-and-native-metrics).

  **EASEL29 delivered — October 29:** included cross-Profile Easel moves now
  retain and revalidate the exact source editors, finish durable edits, retire
  all actual child pages, then explicitly revoke retained source sessions before
  moving the document. Destination browser/live-capture content uses fresh pages
  in the destination Profile; paused captures stay paused. Document/object IDs,
  URLs, capture geometry/provenance and original image bytes survive unchanged.
  Mixed Note/Easel collections receive the same source-session revocation after
  their existing draft flush. Failed moves restore source editor presentation.
  Independent review fixed shared-asset rollback: every document reverse is
  attempted before cleanup, and any failure preserves all copied assets.
  Final checks pass 114 inter-Profile, 310 EaselStore and 76 hidden page-pool
  assertions; whole-module SIL passes 61s with zero diagnostics. Fresh exact-source
  review is CLEAR after EASEL21/22/23/24/25 integration. Contract:
  [cross-Profile relocation](easel-embedded-pages.md#cross-profile-relocation--easel29).
  Receipts/hashes: `easel-coordination/easel29`; final compiler:
  `claude-split-checks/easel29-rebased`. No new engine overlay or functional
  browser tests. The engine owner receives the reviewed app source for its next
  coherent package after the current freeze; no runtime/visual acceptance is
  inferred. EASEL29 is DONE; author/reviewer permanently retire after publication.

  **EASEL21 delivered — October 29:** external HTTP(S) URL paste links the
  actual selected words, replaces self-labelled URLs and supports URL-only
  canvas paste with CAP21's memory-only text adaptation. Generic non-image
  file data is refused without mutation, with explicit plain-word fallback.
  The independent review's paragraph-normalization finding is fixed before
  native delegate/undo commit; EASEL24's insertion-result API is integrated.
  Final SIL passes in 30 seconds with zero diagnostics; focused checks pass
  340 rich-text, 139 canvas, 378 shared Notes, 43 capture-destination and 10
  native web-input assertions. Fresh exact-source independent review is CLEAR.
  EASEL21 is DONE; fixed count is 22/29 DONE (75.9%) and 7/29 LEFT (24.1%),
  +1/29 × 100 = +3.4 percentage points before rounding. No denominator change
  or functional browser test. [Contract](easels.md#external-clipboard-and-non-image-boundary--easel21).

  **EASEL24 delivered — October 29:** `easel24_defaults` and fresh independent
  `easel24_defaults/review_easel24` completed [default text, selection and empty
  editing](easels.md#default-text-selection-and-empty-object-retirement--easel24).
  Add Text and blank-canvas double click create/select the recovered prompt;
  existing text entry keeps native selection/spelling. Escape and final focus
  dismissal retire editing; whitespace cleanup persists with typing Undo and
  refuses failed saves or stale original content. Shown range popovers keep
  their editor; closed ones cannot suppress cleanup. Replacement drops report
  actual insertion success even when empty cleanup keeps item count unchanged.
  EASEL29 consumes `canFinishEditingForTransfer` / `finishEditingForTransfer()`
  and owns its closed-session guard plus all-window page retirement. EASEL21
  preserves the new `insert(...) -> Bool` result in its clipboard integration.
  Checks: Store 283 / text 310 / canvas 130 / capture destinations 43 / native
  input 10 / capture editor 25 assertions; finished whole-module SIL 59 seconds,
  zero diagnostics. Exact corrected source is independently CLEAR. Receipts and
  source hashes: `easel-coordination/easel24`; final compiler receipt:
  `claude-split-checks/easel24-review-final.json`. The shared capture memory
  editor remains intact; no functional browser checks or engine changes.
  Fixed family denominator remains 29: 21 DONE/8 LEFT, +1 row (+3.4 pp).

- **EASEL23 delivered — October 29.** `easel23_live_capture` completed the row
  in `claude-kbd-kb17`, retaining ownership through required engine integration.
  [Live captured regions](easel-live-captures.md) connect original renderer
  viewport/scroll/region metadata to real Profile/window-owned auxiliary pages,
  immutable capture PNG/provenance, first-use education and actual close consent
  before returning to Snapshot. The original pool includes those children in
  deletion, Undo, physical-window transfer and EASEL29 cross-Profile retirement.
  Exact source `18b4012f` passed independent review after final whole-module SIL
  (33 seconds, zero diagnostics), pinned native compilation and 57 injected pool
  assertions. Integrated Easel checks passed 283 Store, 340 text, 139 canvas,
  51 capture-destination and 10 native-input assertions. EASEL29's reviewed
  `e9221af7` integration adds browser/live/paused cross-Profile cases, bringing
  the pool to 76 assertions without changing this row's pool implementation.
  The dedicated `engine_owner` delivered **v239/overlay247** and release app
  source `a60c0157` in `build/independent-v239/development-app-a60c015` on
  canonical. Apply, real build, seal and package all exited 0; the new native
  exports, unchanged inputs and strict signatures are verified in
  `work/integrated-engine239`. Engine completion publication is `11019b6f`.
  EASEL23 is **DONE**: fixed denominator 29, now 26 DONE/3 LEFT
  (89.7%/10.3%), +1/29 × 100 = +3.4 percentage points before rounding.
  The original author and independent reviewer permanently retire after
  verified closure publication. No functional browser test or runtime acceptance
  is claimed; later family app packaging remains with the dedicated engine owner.

- **Screenshots and recordings — October 29, complete.** CAP01–CAP24 are
  delivered: fixed denominator 24, 24 DONE/0 LEFT. CAP24 integrates the reviewed
  CAP17 entry, CAP18 geometry, CAP19 Portrait, CAP20 destinations, CAP21 editing
  and CAP23 media ownership without changing their output/lease contracts.
  All row authors and independent reviewers retire after confirmed publication.
  The reference recording-capability exclusion remains documented below.
  No engine overlay changed; dedicated `engine_owner` retains canonical source
  advance and packaging. The source/component completion rule does not claim
  functional browser, VoiceOver/FKA, or final whole-product polish acceptance.

  **CAP19 delivered — October 29:** `cap19_portrait` and fresh independent
  `cap19_portrait/review_cap19` completed [Portrait fidelity](portrait-capture-fidelity.md)
  in `claude-kbd-kb21`. Controls use the recovered preview/watermark/gradient/
  Website/Desktop structure within the user-requested unified frame editor.
  Source logical dimensions, original-window backing density, PNG DPI, source
  RGB profile and recovered watermark contrast now remain explicit through
  reversible crop/frame/output. Dynamic desktop pixels come only from the
  actual same-display system wallpaper window, with permission preflight,
  PID/frame validation and canceled/stale-result refusal; no static-file or
  full-display fallback. A missing saved Desktop choice keeps Apply blocked
  until a genuine image or explicit alternative, fixing review's P2 finding.
  Isolated compositor/native-control/failure checks and actual light/dark inert
  windows pass; real existing-permission desktop provider returned 1470×956 points
  and 2940×1912 pixels. Finished SIL passes 31s/zero diagnostics; exact source and
  clean CAP20/CAP23 reconciliation are independently CLEAR. Receipts are in
  `capture-coordination/cap19` and `claude-split-checks/cap19-review-fix`.
  No functional browser tests, OS approval bypass or engine overlay changed.
  CAP21 owns the agreed full-resolution annotated-original layer/crop integration
  and retains `CapturedImage.backingScale`; CAP24 retains broader motion/focus,
  with native Portrait focus entering Apply and cancel returning to preview.
  CAP19 closes at 22/24 DONE, 2 LEFT (91.7%/8.3%); author/reviewer retire after
  confirmed publication. This tree is not available for reuse before retirement.

  **CAP17 delivered — October 29:** `cap17_entry` and fresh independent
  `cap17_entry/review_cap17` completed original capture entry in `claude-kbd-kb04`.
  Native Command–Shift drag admits the actual renderer/split pane into the same
  capture lease; Capture Portion's Shortcuts detail independently controls the
  persisted gesture. The established configurable Command–Shift–2 registry is
  preserved. File/page/pane entry and Site Control Center now expose the unified
  acquisition flow, with ordinary Visible Area in the excluded Boosts slot.
  Review's delayed-popover owner finding is fixed: all three capture actions
  revalidate their original page/document/window/Profile/Space after dismissal.
  Source-only whole-module SIL passes in 31 seconds with zero diagnostics; inert checks pass
  ShortcutDetail 108, SiteControlCenter 63 and gesture admission/lifetime 14.
  Independent exact-source review is CLEAR. Contract:
  [capture entry](page-capture.md#capture-entry-and-drag-admission--cap17);
  receipts/hashes: `capture-coordination/cap17`, final compiler
  `claude-split-checks/cap17-final5`. No engine changes, functional browser tests,
  runtime gesture or accessibility acceptance are claimed. CAP18 preserves the
  new `handleCaptureGesture`/shared `updateDrag(to:)` API when applying its
  recovered selection-layer geometry; CAP20 destinations remain separate.
  CAP17 closes at 18/24 DONE, 6 LEFT; its author/reviewer retire after confirmed
  publication, without repurposing.

  **CAP18 delivered — October 29:** `cap18_geometry` and fresh independent
  `cap18_geometry/cap18_review` completed selection/crop/preview/palette geometry
  in `claude-kbd-kb22`. The retained 1.122 helpers recover source-rectangle image
  framing, four-point borders, seven-point corners, 273-point palette anchors,
  32-point rows, named state colors and grayscale/dark live selection layers.
  Original nonbrand cursor representations ship with resource provenance.
  Exact original pixels, native target tokens and output callback ownership
  remain intact. Compact-pane fitting, native instruction-card drawing and the
  shared reversible crop editor are explicit adaptations. CAP17's delivered
  recognizer forwarding uses the same selection geometry; CAP19 controls,
  CAP20 destination ordering/payload, CAP21 editing semantics and CAP24 motion/
  focus retain separate bounded ownership. The complete contract and interfaces
  are in [capture presentation](capture-presentation.md).
  Source/component checks pass: source anchoring, pixel-crop mapping, 30 fitted
  layouts, state colors/cursor representations and inert light/dark/compact/
  crop/busy/empty/saved-state renders. Final whole-module SIL after CAP17
  integration passes in 30 seconds with zero diagnostics; exact-source
  independent review is CLEAR after correcting saved-toggle checkmark contrast.
  Receipts/hashes/renders: `cap18-geometry-evidence`; final compiler receipt:
  `claude-split-checks/cap18-geometry-final3`. No engine changes, functional
  browser tests or whole-browser/runtime parity acceptance are claimed.
  CAP18 closes at 19/24 DONE, 5 LEFT; author/reviewer retire after confirmed
  publication, without repurposing.

  **CAP23 delivered — October 29:** `cap23_discovery` and fresh
  `review_cap23` completed the [OS media source](capture-library.md#os-media-discovery-and-access--cap23).
  The real Media grid combines current-profile captures with direct image/movie
  references in Desktop, Downloads, Documents and the configured screenshot
  folder. Native folder selection, read-only bookmarks, actual availability,
  source disable/re-enable and privacy Settings preserve OS consent. Original
  files stay in place; Quick Look, open/reveal/copy/export/hide use exact source
  ownership and revision guards. Review fixed mixed preview navigation, live
  neighbor updates, asynchronous clipboard generation and thumbnail cancellation.
  Generated-file/model checks include real denied sources, bookmark reopening,
  vnode arrival/removal, final-client shutdown, original-byte export and stale
  source refusal; saved-capture persistence and ten offline packaging checks
  pass. Exact-source independent review is CLEAR, and final whole-module SIL
  passes in 32 seconds with zero diagnostics. Receipts/hashes are in
  `capture-coordination/cap23-*` and `claude-split-checks/cap23-source-final`.
  OS prompt acceptance, Quick Look playback, cloud downloads and browser runtime
  were not exercised. This closes one fixed row: 19/24 → 20/24 DONE,
  79.2% → 83.3% (+4.2 pp), four LEFT; no denominator change.
  CAP21 retains richer captured-item editing/context, and CAP24 owns common
  motion/focus/AX, preserving the root mixed-order/action/cancellation helpers.
  **Engine-owner handoff:** this is Swift/source and package metadata only;
  no engine overlay or Chromium rebuild is required. The next ordinary app
  package must include the new media sources and Desktop/Documents/Downloads
  privacy usage descriptions from `scripts/build.py`, with the existing engine
  seal only if its actual input match permits. Only `engine_owner` advances the
  canonical package input. Author/reviewer retire after confirmed publication.

  **CAP20 delivered — October 29:** `cap20_destinations` and fresh independent
  `cap20_destinations/review_cap20` completed destination ordering, expansion,
  search, stable action/UUID selection and original-source Messages payloads in
  descending optional Sidebar activity, two initially visible destinations and
  lowercase current-label search through all expandable items. The capture
  caller supplies genuine original URL plus current image with optional text
  explicitly nil; no title/branding attribution is invented. Missing-URL
  image-only output, equal-date UUID ordering and profile-local catalog ownership
  are explicit adaptations. Existing PNG persistence/Undo, Library revision,
  native save and truthful service outcomes remain intact. CAP17/CAP18 source is
  integrated; CAP21 owns genuine canvas Edit/separate Crop and CAP24 the remaining
  motion/focus/AX. Contracts and concrete interfaces:
  [capture destinations](capture-destinations.md).
  Focused production checks pass43 assertions. Finished whole-module SIL after
  CAP17/CAP18 integration passes29 seconds with zero diagnostics; fresh exact-source
  independent review is CLEAR. Reviewed CAP23 then fast-forwards without changing
  any CAP20 source. Receipts and cleared hashes: `capture-coordination/cap20`;
  final compiler receipt: `claude-split-checks/cap20-destinations-final-2`.
  No Messages composer, communication, live sharing or functional browser test
  was invoked; no runtime/AX acceptance is claimed. CAP20 closes at21/24 DONE,
  3 LEFT; author/reviewer retire after confirmed publication.

  **CAP19/CAP20 activated — October 29:** after CAP22 publication and retirement,
  fresh `cap19_portrait` owns complete Portrait popover, backing-scale and dynamic
  desktop fidelity in its verified clean published `claude-kbd-kb21` tree.
  Fresh `cap20_destinations` owns complete destination ranking and optional
  message attribution in verified clean published `claude-kbd-kb38`, whose
  SET25 author/reviewer are retired. Preserve user-requested unified reversible
  framing and genuine output transactions. CAP19 owns Portrait controls/compositor
  and captured desktop pixels; CAP20 owns action ordering/payloads and destination
  acceptance. Coordinate bounded PageCaptureController edits directly with CAP17
  and CAP18; CAP18 owns the private overlay's geometry. CAP23 retains external
  media discovery/permissions/Quick Look ownership. CAP21 editing/context and
  CAP24 motion/focus remain queued, with reviewer capacity preserved. Same
  helper-first, full-row, check/review-before-publication rules apply. No new
  worktree, functional browser test or synthetic success path. Settings packaging
  has completed; the dedicated engine owner is retained idle for actual next
  engine/package work.

  **CAP21 delivered — October 29:** `cap21_editing` in
  Move/Image/Text/Circle/Rectangle/Arrow/Freehand tool inventory through retained
  helpers. The shared Easel canvas now edits an isolated capture draft, preserving
  immutable original pixels, accepted source objects, crop, Portrait density and
  real output transactions. Distinct captured-Library Messages (image+source text)
  and AirDrop (image) contexts retain exact revision/view-generation guards.
  CAP18/19/20/23 deliveries are integrated without replacing their geometry,
  compositor, destination ranking or external-file owners. Contract and exact
  shared boundaries: [capture editing](capture-editing.md). Component checks pass:
  editing/payload25, shared EaselStore283/TextStyle310/Canvas102/destinations43/
  input10, and extended Portrait reversible-edit checks. Final whole-module SIL
  `claude-split-checks/cap21-final3` passes in29s with zero diagnostics; fresh
  independent `cap21_editing/review_cap21` clears the exact complete source.
  Review fixes cover rich-text color/undo, idle Escape and original RGB profile
  preservation. Receipts and exact checked hashes: `capture-coordination/cap21-*`.
  CAP21 closes at23/24 DONE,1 LEFT; author/reviewer retire after publication.
  CAP24 retains common capture/Library motion/focus/AX; the editor exposes
  native labeled controls, an explicit key loop, Apply/Cancel and owner-bound
  completion. No engine work, functional browser test or outgoing share is used.

  **CAP24 delivered — October 29:** `cap24_motion` in `claude-kbd-kb22`
  completes capture/Library/share-composer motion, focus, keyboard/accessibility
  and haptic attribution. Arc1.122 retained helpers establish the lens's 90 ms
  latest-target throttle and 0.35/0.87 spring, one-second image reveal,
  0.2-second instruction easing and Portrait 0.5/0.7 spring. Saved/external Media
  previews share actual aspect-fitted thumbnail anchors and recovered open/close
  transitions. Interruption, dynamic Reduce Motion and owner retirement settle
  or close once. Native key loops preserve reciprocal traversal and enabled
  controls; focus bookmarks bind the original window and actual field-editor
  owner, preserving valid search selection and refusing intervening focus.
  CAP21's editor completion and genuine Library sharing callbacks are integrated;
  native sharing owns its composer motion/outcomes. No capture haptic is invented
  from the unrelated Easel scale feedback call site. [Contract](capture-motion.md).
  Author checks: 44 inert native/model assertions, integrated Portrait compositor/
  reversible-edit checks, static light/dark/compact toolbar inspection, and final
  whole-module SIL 29s/zero diagnostics (`claude-split-checks/cap24-final2`).
  Fresh independent `cap24_motion/review_cap24` clears the exact complete source
  and all four reported focus/thumbnail/Reduce Motion fixes; 257 source hashes
  match `capture-coordination/cap24/checked-final2.json`. CAP24 closes 24/24 DONE,
  0 LEFT (95.8% → 100.0%, +4.2 pp). No functional browser, FKA/VoiceOver driving or
  outgoing sharing action was used. Author/reviewer retire after publication.

  **CAP22 capability reconciliation:** `cap22_recording` completed the bounded
  [recording capability investigation](capture-capabilities.md) in
  `claude-kbd-kb21`. The original CAP-06 asked for a shipped recording producer
  **if present**; the fixed CAP22 wording had prematurely presumed one. The
  corrected requirement preserves CAP22 and denominator24, closing discovery
  with an explicit supported capability contract rather than adding a recorder
  without reference evidence. The complete retained menu inventory, image-only
  Capture actions/client, website camera/microphone state, positively identified
  filesystem movie query and separately owned diagnostic trace/developer actions
  establish no standalone recording entry/session/output contract. This bounded
  conclusion does not claim absence from all dynamic code or other versions.
  The current Parc PNG and exact-stream Stop owners already respect those
  boundaries; no production source change or engine work was needed. CAP23
  retains the actual external-file discovery, permissions and movie consumer;
  CAP22 claims none of that delivery. Helper/source receipts and document checks
  are in `capture-coordination/cap22`. Fresh `cap22_review` independently cleared
  the complete reconciliation after correcting filesystem media-source wording;
  it does not attribute the movie bytes to a known producer. No compiler rerun
  or functional browser test was needed for this documentation-only change.
  CAP22 is DONE, giving 17/24 DONE and 7/24 LEFT;
  the original author/reviewer retire after publication confirmation.

- **Settings complete — October 28.** SET01–SET27 are DONE. The following
  assignment and delivery notes retain the reviewed ownership boundaries;
  historical counts describe their individual delivery points.

  **SET27 delivered:** `set27_membership_card` and fresh
  `review_membership_card` completed the
  [local membership card](settings-membership-card.md). The first personal-name
  Settings pane contains the recovered portrait card, original non-brand masks
  and artwork, name-derived shape, generated two-word title, persistent palette
  and blob configuration, pointer tilt/highlight and bounded background motion.
  Native Edit Name, Share, Download and Randomize controls retain original-owner
  sheet/save lifetimes and the integrated SET26 focus policy. Local card creation
  replaces account tenure, and Parc branding replaces company marks; no account,
  cloud/referral, telemetry or AI service was restored. Review's Unicode line
  separator validation finding is fixed and covered. File-backed model/inert
  native rendering checks pass, final whole-module SIL passes in 31 seconds with
  zero diagnostics, and exact-source independent review is CLEAR. Receipts and
  hashes are in `settings-coordination/set27` and
  `claude-split-checks/set27-review-final`; generated-content preview images are
  in `settings-coordination/set27/generated-previews`. These checks do not claim
  browser-runtime, active motion interruption, VoiceOver/FKA or native share
  destination acceptance. SET27 closes the family at 27/27 DONE (100.0%); its
  author/reviewer retire only after confirmed publication.

  **Original Settings assignments — October 28, automatic continuation after App identity completion.**
  Fresh `set21_commands` owns SET21 remaining General/Profiles commands and
  preferences in existing `claude-kbd-kb03`; `set22_themes` owns SET22 remaining
  theme preferences and actual consumers in `claude-kbd-kb17`; `set23_removal`
  owns SET23 profile removal/cleanup sheets and feedback in `claude-kbd-kb21`;
  `set24_presentation` owns SET24 pane colors, selection, geometry and icons in
  `claude-kbd-kb22`; `set25_motion` owns SET25 pane/modal transitions, hover,
  pressed states and haptics in `claude-kbd-kb38`; `set26_accessibility` owns
  SET26 Settings-wide keyboard, accessibility, focus and interruption in
  `claude-kbd-kb04`. Each reuses a verified clean published worktree after its
  previous author/reviewer retired. SET01–SET20 remain DONE; the SET27 inclusion
  below expands the current denominator to 27.
  Read `docs/settings.md` and current source before identifying remaining work;
  retain the completed Space Profile transaction, Icon picker and Shortcuts
  owners rather than rebuilding them. Coordinate shared `SettingsWindow.swift`
  sections directly before edits: SET21 owns General/Profiles command wiring,
  SET22 preference data/consumers, SET23 removal sheet-specific composition,
  SET24 shared pane appearance/layout, SET25 presentation/motion callbacks and
  SET26 responder/AX/interruption integration. Agree concrete interfaces with
  the relevant owner and retain responsibility through integration. Begin with
  no functional browser tests. Every row receives a fresh same-worktree reviewer
  after finished checks; direct findings/fix/re-review precedes publication.
  No research children; report reviewer capacity conflicts to root without
  bypassing review or duplicating work. Partial reviewed increments may publish,
  but authors continue full rows. One-line commits are immediately pushed and
  remote-verified. The dedicated engine owner handles final identity packaging
  separately while these owners continue independent source publication.

  **SET26 delivered:** `set26_accessibility` and its fresh `set26_review`
  completed [Settings responder ownership](settings.md#settings-responder-ownership-and-interruption--set26).
  Native toolbar selection and same-pane focus, static-pane key chains, weak
  pane/Profile/field-editor bookmarks, native sheet return and nested cancellation,
  closed/reopened creation/assignment refusal and translation interruption now
  share the original Settings owner. Review's surviving-Profile bookmark finding
  was fixed with a native-table regression. Twenty-one inert native assertions
  and final whole-module SIL (48 seconds, zero diagnostics) pass; exact-source
  independent review cleared integrated SET21, SET23 and SET24 source. Receipts
  and hashes are in `settings-coordination/set26` and
  `claude-split-checks/set26-final4`. The unshown test field reports `AXUnknown`;
  no screen-reader, Full Keyboard Access or functional browser acceptance is
  claimed. SET23/SET25 may close their unchanged sheet/motion handoffs after
  reconciling this publication. SET27 retains its separate card internals and
  uses native persistent controls/native sheets through the documented shell
  interface. SET26 is complete and its author/reviewer retire after publication
  confirmation; the Settings family is 24/27 DONE (88.9%).

  **Local membership card — explicit user inclusion, October 28.** Josh requests
  the full personalized card on the first Settings page, including its
  pointer-responsive motion, regenerated card designs, names and associated
  not exclude this local experience. The previous whole-account-pane omission
  was too broad; it supplied no card-specific reason to omit these behaviors.
  Fresh `set27_membership_card` owns new SET27 in existing `claude-kbd-kb17`,
  after the completed SET22 author/reviewer retired. Recover the card's complete
  appearance, generation/configuration, names, persistence and local actions
  before implementing them. Preserve Parc branding; explain any account-derived
  cloud/referral services or telemetry. SET27 owns the card end to end, including
  its motion and accessibility; coordinate its host/layout interface with SET24,
  shared motion primitives with SET25 and shell focus/interruption with SET26.
  Those owners keep their existing scopes; do not duplicate card implementation.
  This explicit addition expands the fixed denominator from 26 to 27: 22 DONE
  and 5 LEFT (81.5% / 18.5%). The last completed-row delivery remains +3.8 pp;
  adding the requirement changes the count percentage by −3.1 pp. No completed
  row is reopened. SET27 remains LEFT through full implementation, checks,
  independent review and confirmed publication.

  **SET23 delivered:** `set23_removal` completed the
  [removal-sheet composition and feedback](settings-profile-removal.md): recovered
  450-point geometry, selectable emphasized warning/confirmation content,
  light/dark palette and native press/hover/disabled treatment. Real partial
  results, original-target Retry, irreversible-operation Close and actual
  completion/Done remain above the unchanged controller and atomic model path.
  Fresh `set23_removal/set23_review` identified legacy-scrollbar clipping; the
  failing inert check and measured-viewport correction cleared exact-source
  re-review. Fresh `set23_removal/set23_hover_review` cleared shared modal hover
  ownership, preserving palette/native press behavior while retiring stale
  original-window state. Both reviewers independently verified their published
  source and retired. The final sheet cohort passes 36 assertions; model 37 and
  controller 17 pass; final SIL passes in 37 seconds with zero diagnostics.
  SET26 publication `b036bb9b` is reconciled: both removal callback groups are
  byte-identical, original-context return and removed-profile list fallback are
  integrated, and closed parents cannot restore focus. Its 21 native assertions
  and 48-second final SIL receipt were inspected without duplicate checks.
  Receipts/hashes live in `settings-coordination/set23` and
  `claude-split-checks/set23-hover-final`. SET23 is DONE; no native browser or
  real-profile deletion tests were run. SET27 retains its independent card scope.

  **SET21 delivered:** `set21_commands` and fresh `set21_review` completed the
  [General/Profiles command inventory](settings.md#general-and-profiles-command-inventory--set21).
  Search Settings and Privacy/Security, Passwords, Credit Cards, Notifications
  and Clear Browsing Data use the real selected Profile and original browser
  admission, preserve existing credential details or exact subpages, and report
  refusal without closing Settings. Accepted page commands dismiss the original
  Library overlay before presenting their target; independent review found and
  cleared that correction. Explicit restore/sidebar preferences atomically save
  before publishing, and the recovered quit-warning factory default is true
  without overwriting saved choices. External document-provider routing and
  unavailable native adblock controls retain the confirmed exclusions/capability
  boundary; local Notes and existing profile assignment/removal remain intact.
  Thirty-seven production model and eighteen inert quit-warning assertions pass;
  final whole-module SIL after review correction passes in 45 seconds with zero
  diagnostics. Review cleared exact source; receipts/hashes are in
  `settings-coordination/set21` and `claude-split-checks/set21-commands-review-fix`.
  No functional browser tests ran. SET24 owns the final native command-row
  presentation through the agreed factory/control interface, SET25 its motion
  and SET26 common focus/interruption; their rows remain active. SET21 is DONE;
  its author/reviewer retire only after confirmed publication.

  **SET22 delivered:** `set22_themes` and fresh `set22_review` completed the
  [Settings theme inventory/default reconciliation](settings.md#settings-theme-inventory-and-default).
  theme preference, and its startup registration proves the existing true
  default. Existing shared persistence, original regular/private window palette
  publication and native attachment/document CSS consumers already implement
  that contract. View/editor appearance, renderer, Undo and haptics retain their
  completed owners; no extra preference or engine interface was introduced.
  Fifty-six isolated preference/color assertions and finished whole-module SIL
  pass with zero diagnostics. Independent review cleared the complete diff;
  no functional browser tests ran. SET22 is DONE; the remaining Settings owners
  retain their exact rows and shared-source responsibilities. Author/reviewer
  retire after confirmed publication.

  **SET24 delivered:** `set24_presentation` and fresh independent
  `set24_presentation/set24_review` completed the [shared pane presentation](settings-presentation.md).
  Helpers recover the actual native quinary fill/continuous clipped separator
  border, General/Profile row composition, colored profile command/Advanced
  glyphs, and non-brand native General/Links toolbar assets. The original
  selected-Profile dispatcher and reviewed SET25 hover owner are integrated;
  native values/selection, approved Parc icons and completed Shortcuts stay with
  their existing owners. Forty-eight inert native presentation assertions and
  33 actual Download Location assertions pass; finished whole-module SIL passes
  in 31 seconds with zero diagnostics. Light/dark components and configured
  source-extracted General/Profiles/Advanced/Links layouts were inspected;
  offscreen table backing is not active-window selection acceptance. Independent
  review and the resource audit cleared the exact source. Receipts/hashes are
  in `settings-set24-evidence` and `claude-split-checks/set24-finished`.
  No functional browser or live FKA/VoiceOver tests ran. SET24 advances Settings
  from 22/27 to 23/27 DONE; SET23/25/26 and the added SET27 remain LEFT.
  SET26 consumes the existing native controls through its actual-frame focus
  traversal; SET27 owns a dedicated personal-name first pane/card and minimal
  toolbar insertion, retaining this General layout. Author/reviewer retire after
  confirmed publication; those owners retain their separate complete rows.

  **SET25 delivered:** `set25_motion` completed the
  Settings factory disables optional animated pane transitions; immediate swaps
  and repeated-pane responder preservation are integrated with SET26. The native
  hover owner suppresses inactive, covered, disabled, hidden, sheet-interrupted
  and former-window controls. SET24's command rows and SET23's modal controls
  consume it while retaining their own recovered palette, actual native press
  tracking and accepted-action callbacks. Completed Icon/Shortcuts behavior,
  actual preference haptic producers and native sheet motion remain intact.
  Twenty-eight inert native base assertions and final whole-module SIL pass;
  fresh review cleared the stale former-window/tracking-area event correction
  before publication. Reviewed consumer publications `c5824901`, `52a2be48` and
  `b036bb9b` were reconciled with unchanged source hashes and their own focused
  checks/SIL receipts. Final documentation closure introduces no new source.
  No functional browser tests or hardware haptic acceptance is claimed. SET25
  advances Settings from 25/27 to 26/27 DONE (+3.7 pp); the explicitly added
  membership card remains SET27's complete separate requirement. Author retires
  after confirmed publication; the finished independent reviewer is retired.

- **App identity and icon variants — October 28, automatic continuation authorized
  by Josh after Extensions and Spaces/Profile completion.** Fresh `icon08_artwork`
  owns ICON08 borderless/monochrome marks and alpha cleanup in existing
  `claude-kbd-kb03`; `icon09_optical` owns ICON09 optical bounds and actual small-size
  appearance in existing `claude-kbd-kb04`; `icon10_picker` owns ICON10 selection,
  hover, pressed and transition behavior in existing `claude-kbd-kb17`; and
  `icon11_discovery` owns ICON11 included unlock/discovery behavior in existing
  `claude-kbd-kb21`. These clean, published worktrees are reused after their prior
  owners retired. ICON01–ICON07 remain DONE; the denominator stays eleven.
  Start with `Resources/AppIcons/README.md`, `docs/settings.md` App icon,
  `AppIconController.swift`, `IconSettingsView.swift`, `scripts/app_icons.py`,
  `tests/AppIcons` and retained helper evidence. Preserve all ten approved P
  variants and Original as the default; do not replace the approved master or
  introduce excluded service/account gates. ICON08 and ICON09 agree asset/export
  ownership before shared edits; ICON09 owns small-size/export adjustments, and
  ICON08 owns master cleanup and derived marks. ICON10 and ICON11 agree any
  shared picker/catalog interface directly. Each owner completes its full row,
  including dependencies, permitted checks, fresh independent review in the
  same worktree and immediate one-line commit/push with remote verification.
  Review findings/fixes go directly between each pair. Preserve the helper-first,
  Root coordinates and reports. The retained engine owner packages the reviewed
  final Spaces source separately without blocking this family's publication.

  **ICON11 delivered:** `icon11_discovery` and fresh read-only reviewer
  `icon11_discovery/icon11_review` completed the
  account-date/referral decision and reward banner are resolved from retained
  helpers; Parc's explicit all-ten offline catalog remains immediately available
  with Original as default. No account gate, false unlock state or new artwork.
  By agreement with ICON09, the unchanged `Variant.image` interface now loads
  packaged ICNS representations for picker and live native identity consumers,
  falling back to PNG only when ICNS is absent. Corrupt native artwork reports
  failure. ICON09 retains export/optical ownership and ICON10 retains picker
  interaction/motion ownership. All 50 inert controller assertions and strict
  whole-module typecheck/final SIL pass with zero diagnostics; independent
  clearance and exact source hashes are in `app-icons-checks/icon11` alongside
  the helper/check receipts. No functional browser tests or system icon changes
  ran. ICON11 advances this family from 7/11 to 8/11 DONE; ICON08–ICON10 stay LEFT.
  Author and reviewer retire after confirmed publication.

  **ICON10 delivered:** `icon10_picker` and fresh read-only reviewer
  `icon10_picker/icon10_review` completed the [picker interaction
  contract](app-icon-picker.md). The recovered plain radio treatment disables
  hover enlargement, uses 64-point proportional previews and keeps titles fixed
  beside the current marker. One native radio control per row owns completed
  mouse/keyboard/AX activation, drag-out/Escape cancellation, arrow focus,
  authoritative saved state and original-window/app lifetime. Failed saves keep
  the old selection. Focus rings redraw only for the active app's key window.
  ICON11's native image loader is integrated; ICON09 retains shared optical
  export ownership with the 64-point frame agreed directly. All 45 inert native
  component assertions and final whole-module SIL pass with zero diagnostics;
  light/dark component renders were inspected. Independent review cleared the
  exact finished source after the inactive-window focus-ring correction.
  Receipts, source hashes and review clearance are in `app-icon-checks/icon10`
  and `claude-split-checks/icon10-picker-review-fix`. No functional browser test,
  live VoiceOver/FKA acceptance or real system-identity mutation is claimed.
  ICON10 advances this family from 8/11 to 9/11 DONE; ICON08–ICON09 stay LEFT.
  Author and reviewer retire after confirmed publication.

  **ICON08 delivered:** `icon08_artwork` and fresh read-only reviewer
  `icon08_artwork/icon08_review` completed [UI marks and alpha cleanup](app-icon-marks.md).
  Josh explicitly authorized deterministic processing preserving the artwork.
  All ten 1254 × 1254 masters retain every original RGB byte and every pixel with
  alpha at least 128; 248,811 outer low-alpha debris pixels are cleared. The
  borderless and monochrome marks derive directly from the approved Original P,
  share one exact silhouette, and serve the real welcome/import and portrait
  compositor consumers. The full tile remains the installed-system illustration
  and selected Dock/Finder identity. The mark resources travel through the
  is shipped. Both asset integrity tests, inert bundled mark/light-dark tint
  checks, the real portrait compositor checks and final whole-module SIL pass
  (45 seconds, zero diagnostics). Independent review cleared the exact complete
  source/assets. Evidence and fingerprints are in `work/icon08-artwork-evidence`
  and `claude-split-checks/icon08-marks-final`; the checked-in provenance manifest
  records approved-pixel preservation. ICON09 received these exact cleaned inputs
  directly and passed all 100 native representation checks against them; it keeps
  ownership of optical/export completion. No functional browser tests ran.
  ICON08 advances this family from 9/11 to 10/11 DONE; ICON09 remains LEFT.
  Author and reviewer retire after confirmed publication.

  **ICON09 delivered:** `icon09_optical` and fresh read-only reviewer
  `icon09_optical/icon09_review` completed [optical bounds and small-size export](app-icon-optical.md).
  Josh explicitly authorized deterministic processing preserving the artwork.
  Each native size now uniformly fits the unchanged approved master to the
  retained reference envelope, using software Lanczos downsampling and a
  transparent guard pixel. All ten published ICON08 master hashes match the
  inspected candidate. ICON10's 64-point proportional picker and ICON11's native
  ICNS loader consume the same corrected family. All 100 representation checks,
  ten isolated production packaging cases, 80 inert native controller/compositing
  assertions and the finished renderer/component SIL checks pass. Actual native
  16-, 32-, 64- and 128-pixel light/dark comparisons were inspected. Independent
  review is CLEAR on the complete source; receipts, source/master hashes and
  appearance evidence are in `app-icons-checks/icon09`. Original remains the
  shared default, and no master was redrawn. No functional browser tests or real
  system-identity mutations ran. ICON09 advances this family from 10/11 to
  11/11 DONE (100% / 0%, +9.1 percentage points). Author and reviewer retire after
  confirmed publication; whole-product polish remains separate.

- **Spaces and profiles — October 28, background work explicitly authorized by
  Josh while Extensions proceeds.** Extensions implementation and independent
  review always receive agent capacity first. Root coordinates SPACE17–SPACE18.
  SPACE13 is delivered from `claude-kbd-kb17`: Automatic clears the application
  appearance override and saved preference through the original parent, while
  preserving the Space theme, pad state, local Undo and preset page. Light/Dark
  sibling controls and selected-state feedback use that same parent. Replay
  refuses app-wide appearance changes. The [reference contract](space-theme-appearance.md)
  distinguishes this from palette Undo and the separately recovered forced-color
  action. Author `space13_theme_parent` and independent reviewer `space13_review`
  retire after confirmed publication. The exact source is independently CLEAR;
  72 inert AppKit assertions, 60 model assertions and zero-diagnostic whole-module
  typecheck/SIL passes support the implementation. No browser tests ran.
  SPACE14 is delivered from `claude-kbd-kb22`: original-window **Update Theme**
  Undo/Redo survives popover disposal and reopening, restores open editor state,
  and commits complete themes atomically against original Space/Profile values.
  Competing edits and disk failures preserve authoritative state; inherited
  rotation/scroll/momentum cannot overwrite a parent inverse or clear Redo.
  Setup and creation drafts retain local history. The global appearance Undo
  remains separate. Fresh independent `space14_review` cleared the finished
  source after its physical-gesture cancellation finding was fixed. All 40
  focused inert assertions, 72 appearance assertions and 796 BrowserStore
  assertions pass; final warnings-as-errors whole-module SIL has zero diagnostics.
  [Contract/adaptations](space-theme-undo.md); receipts and clearance:
  `spaces-profiles-checks/space14`. Author `space14_theme_undo` and reviewer retire
  after confirmed publication. No engine change or functional browser test.
  SPACE15 is delivered from `claude-kbd-kb03`: zero-distance pad/intensity
  input, companion-handle promotion and relative drag, ten-point dial drag,
  one-degree continuous rotation, and 200 ms latest-direction wheel input use
  the recovered mappings. Wheel ticks keep independent Undo; stale physical
  input cannot enter a new control or keyboard/AX transaction. Commit rejection
  preserves the new input's authoritative baseline and lifetime. Independent
  `space15_review` is CLEAR after interruption findings were corrected; 79 input,
  60 model, 72 appearance and 40 original-window Undo assertions pass, with a
  zero-diagnostic final whole-module SIL check. [Contract/adaptations](space-theme-input.md);
  local receipts and clearance: `spaces-profiles-checks/space15`. Author
  `space15_theme_input` and reviewer retire after confirmed publication.
  SPACE16 is delivered from `claude-kbd-kb17`: intensity fifth-step and noise
  rotation/drag tenth-step detents emit one native generic/now haptic per accepted
  change, with inclusive endpoints and silent repeated/clamped values. Slider,
  dial-click and wheel noise input, palette/texture/appearance actions, parent
  updates, Undo and commit do not add feedback. Fresh AppKit performers retain
  the original device and system-preference gates. Independent `space16_review`
  is CLEAR on the integrated SPACE15 corrections; 42 haptic, 79 input, 72
  appearance and 40 Undo assertions pass, with a zero-diagnostic final
  whole-module SIL check. [Contract/adaptations](space-theme-haptics.md);
  receipts and clearance: `spaces-profiles-checks/space16`. Author
  `space16_theme_haptics` and reviewer retire after confirmed publication.
  No physical-device feel comparison or functional browser test is claimed.
  The typed `SpaceThemeNoiseGesture` callback distinguishes slider, rotation,
  dial click, scroll wheel and drag; feedback runs after accepted model mutation.
  SPACE14's parent-Undo physical-stream barriers remain independent of commit
  grouping. SPACE17 preserves the pad's immediate refresh at admitted drag start
  and model-center capture while owning rendering/animation. Active owners
  integrate these exact published boundaries through full-row completion.
  SPACE17 is delivered from `claude-kbd-kb21`: the real window's native backing,
  recovered translucency material and contrast-selected content appearance
  have separate owners. Native text and neighbor previews follow their own
  palettes; key/main/parent activity controls texture strength. Theme edits
  publish immediately, while the existing paging owner retains its transition.
  Recovered pad springs now retire on direct input, layout, Reduce Motion and
  detachment without restarting unchanged targets. SPACE15's admitted-start
  cancellation and SPACE16's accepted feedback hooks remain integrated.
  Independent `space17_review` is CLEAR after the Metal-unavailable material
  fallback was made coherent with text contrast. All 68 focused rendering,
  79 input and 40 Undo assertions pass; compatibility receipts retain 72
  appearance and 53 WebsiteTheme assertions. Final whole-module SIL has zero
  diagnostics. [Contract/adaptations](space-theme-rendering.md); receipts and
  clearance: `spaces-profiles-checks/space17`. Author `space17_theme_rendering`
  and reviewer retire after confirmed publication. No functional browser test
  or integrated visual acceptance is claimed. `space18_management` completed SPACE18 in
  `claude-kbd-kb22`. Its first reviewed increment supplied optional authored titles,
  atomic original-target title/icon writes, inline/background rename, real icon
  selection and assigned-Profile menus. The complete row adds the Library Spaces
  category with retained themed sidebar cards, original-order drag/menu/AX moves,
  actual tab/folder actions and keyboard contexts; confirmed atomic Space deletion
  with native consent, typed archival, preserved Profile Favorites and original-window
  Undo/Redo; and same-Profile Turn into Folder with intact native pages and safe
  inverses. Cross-Profile conversion and assignment use the real page-retirement
  and Note/Easel relocation/rollback transaction. Shared Profile confirmation and
  atomic new-Profile creation close the required Settings/storage dependencies
  without extra family credit. Background theme/folder contexts retain original
  targets and native lifetimes, preserving completed navigation, global appearance
  and original-window theme Undo. Fresh `fullrow_review` independently cleared the
  exact complete source after background-theme lifetime, manager responder/AX and
  conditional durable folder-rename corrections. The final whole-module SIL passes
  with zero diagnostics; 62 management transaction, 14 actual inert card/sidebar
  responder/AX, 31 native header/menu, 798 BrowserStore and 99 inter-Profile
  assertions pass in their recorded scopes. Contracts, native/schema adaptations
  and exact checks: [Space management](space-management.md); local receipts:
  `spaces-profiles-checks/space18`. No functional browser tests or live AX acceptance
  is claimed. SPACE01–SPACE18 are DONE: 18/18, 100% / 0%, +5.6 percentage points
  from the preceding delivery. Author and reviewer retire after confirmed publication.
  remains separately owned.


- **Extensions — October 28, explicitly assigned next by Josh.** Four fresh
  agents own the remaining complete rows; EXT01–EXT10 stay DONE and the fixed
  denominator remains 14. `ext11_installation` owns EXT11 installation education
  and placement/discovery in existing `claude-kbd-kb03`;
  `ext12_geometry` owns EXT12 toolbar/menu/popup/panel geometry and glyphs in
  existing `claude-kbd-kb04`; `ext13_interaction` owns EXT13 focus, keyboard,
  hover/disabled and accessibility in existing `claude-kbd-kb21`;
  `ext14_lifecycle` owns EXT14 popup/panel opening, dismissal, interruption and
  motion in existing `claude-kbd-kb38`. The prior Automatic archive assignments
  and their reviewers are finished and permanently retired; their clean,
  published checkouts are explicitly reassigned to these fresh agents.
  Root coordinates in `claude-split`; only the retained `engine_owner` advances
  canonical `/Users/josh/Parc` or operates the shared engine/package pipeline.
  The Automatic archive app package passed; it is now building reviewed EXT11
  engine inputs in the separately frozen v236 batch.

  Start with the P0-13–16 contracts, retained native extension evidence, current
  `ExtensionControls.swift` and native extension owners, plus the recovered
  1.122 questions. Heavy decompilation uses the shared nonblocking two-slot
  helper; busy owners continue independent work. No functional browser tests.
  Likely shared files are `ExtensionControls.swift`,
  `BrowserWindowController.swift`, `Engine/ParcNative/extension_*` and this
  ledger. Agree exact method/interface ownership directly before overlapping
  edits; geometry belongs to EXT12, interaction to EXT13, and lifecycle/motion
  to EXT14. Preserve real Profile/page/window identities and completed backend
  behavior. Any new backend contract is handed to the engine owner for pipeline
  scheduling while feature source is independently checked and published.
  Each author completes its row, permitted checks/final SIL and documentation,
  then pairs with a fresh independent reviewer in that same worktree. Findings
  and fixes go directly between them until the exact source is clear, before
  publication or DONE. Authors immediately push one-line commits and verify
  remote publication; root is not a delivery gate. Both members retire after
  confirmed delivery. Initial family baseline: 10/14 DONE, 71.4% / 28.6%.

  **EXT11 delivered — October 28:** `ext11_installation` and its fresh
  independent reviewer `ext11_installation/ext11_review` completed ordinary
  installation education and real extension-name discovery. The exact native
  install/result owner remains authoritative; immutable action leases drive
  Command Bar launches and native publications refresh them. Arc1.122 helper
  evidence, explicit current-engine/native-order adaptations and source scope
  are in [Extensions](extensions.md). Final 61 inert AppKit assertions,
  warnings-as-errors whole-module SIL and both actual pinned native unit checks
  pass; independent final source clearance is recorded in
  `extensions-checks/ext11/review-clearance.md`, with receipts and source hashes
  in the same directory. No functional browser tests or real installs ran.
  Fixed ledger advances 10/14 → 11/14 DONE (78.6% / 21.4%, +7.1 pp).
  EXT12–EXT14 retain their owners. Pending for `engine_owner`: overlay243 inputs
  `extension_install.mm` and `extension_install_presenter.{h,mm}`; apply/build/
  package only after source publication. Author and reviewer retire after
  confirmed publication. The separate Onboarding and Command Bar requirements
  receive no additional DONE credit.

- **EXT13 delivered — October 28:** `ext13_interaction` and fresh reviewer
  `ext13_interaction/ext13_review` completed extension keyboard, native control
  interaction and accessibility comparison in `claude-kbd-kb21`. Physical
  picker keys, original-window event scope and immutable gesture leases now
  match their recovered owners. Sidebar and top-bar controls retain distinct
  feedback; policy-aware Pin/Unpin/Show Menu remain accessible without hover.
  Shared EXT12 Swift style/geometry is included by agreement, with its actual
  native-cell press and image-only corrections independently reviewed. This
  gives EXT12 no partial row credit. EXT14's reviewed dismissal coordinator and
  original-page dispatch are preserved in the integrated source.
  Final independent clearance and source hashes are retained in
  `extensions-checks/ext13/review-clearance.md`; 38 inert native control and
  61 integrated Site Control Center assertions pass, as does the finished
  warnings-as-errors SIL with zero diagnostics. No functional browser tests,
  live Tab traversal or VoiceOver acceptance ran. [Contract and adaptations](extensions-interaction.md).
  Fixed ledger advances 11/14 → 12/14 DONE (85.7% / 14.3%, +7.1 pp).
  EXT12 and EXT14 retain their current work. This increment is Swift-only;
  it adds no engine input. The author/reviewer retire after verified delivery.

- **EXT12 delivered — October 28:** `ext12_geometry` completed the full static
  geometry/glyph row in `claude-kbd-kb04`. Sidebar and toolbar controls retain
  their distinct recovered surfaces with 16-point genuine artwork; the native
  renderer requests a 32-point logical image. Popup anchoring follows the
  visible placeholder or focused pane/Peek; existing native context-menu and
  popup-window geometry match the retained contracts. EXT14's positive native
  gate/construction evidence resolves the panel boundary through an explicit
  a fitted trailing body, a 32-point native close header, separate genuine page
  container and precise header/content focus scope. Close and shell Escape call
  the real original-window native service from reviewed dependency `73068de0`.
  [Geometry and source evidence](extensions-geometry.md) records the finite
  comparison and [native adaptation](extensions-side-panel-adaptation.md).
  The final complete diff, including new files, is independently CLEAR from
  `ext12_geometry/ext12_panel_review`; prior published icon/popup work was
  cleared by the now-retired `ext12_review`. Final whole-module SIL passed with
  zero diagnostics; 10 inert header and 104 outer-layout assertions pass.
  Light/dark control specimens confirm glyph/header fit. Source-identical
  reconciliation preserves the reviewed app changes and exact native header.
  Receipts and source hashes are in `extensions-checks/ext12/`, including
  `panel-review-clearance.md`. No functional browser tests ran. Fixed ledger
  advances 12/14 → 13/14 DONE (92.9% / 7.1%, +7.1 pp). EXT14 retains lifecycle
  closure after this integrated consumer publication. This final increment is
  app-only and requires the already-reviewed overlay246 native API; the engine
  owner batches those inputs together. Author and final reviewer retire after
  confirmed full-row publication.

- **EXT14 delivered — October 28:** `ext14_lifecycle` completed popup/panel
  opening, dismissal, replacement, interruption and motion comparison in
  `claude-kbd-kb38`. The positive Arc1.122 native feature table, typed local
  default-off preference and empty panel UI slot at ordinary construction
  resolve the reference boundary shared with EXT12. [Lifecycle](extensions-lifecycle.md)
  and [explicit compatibility adaptation](extensions-side-panel-adaptation.md)
  preserve the distinction between recovered native popup behavior and the
  current-Chromium panel shell. The Site Control Center dispatch waits behind
  every native close and rejects stale original-page actions. Genuine panel
  close-button and unhandled Escape dispatch preserve the original Browser,
  Profile, page and window, deferred host drains and panel-only focus scope.
  Native dependency `73068de0` (overlay246) and EXT12's required app consumer
  `f6ba5a78` are integrated; no source dependency remains deferred.
  Both actual native-target syntax checks, 23 inert AppKit input/focus
  assertions and final whole-module Swift SIL pass. The original close-barrier
  component has 47 assertions; EXT12's consumer has 10 header and 104 layout
  assertions plus its final SIL. Fresh completion reviewer
  `ext14_lifecycle/ext14_completion_review` cleared the exact complete native
  source, original popup integration and final published app seam without
  findings. Receipts and hashes are in `extensions-checks/ext14/`, including
  `panel-completion-review.md`, `panel-publication-inputs.json` and
  `full-row-integration.json`. No functional browser tests or live keyboard
  acceptance ran. Fixed ledger advances 13/14 → 14/14 DONE (100.0% / 0.0%,
  +7.1 pp); the denominator remains 14. Author and completion reviewer retire
  after confirmed full-row publication. The dedicated engine owner receives
  the integrated overlay246/native/app source for its next build and package;
  compiler/component completion does not claim that pending package was built.

- **EXT14 reviewed lifecycle increment — October 28:** `ext14_lifecycle` in
  `claude-kbd-kb38` connects extension action/context-menu dispatch to the
  native Site Control Center dismissal. A separate coordinator keeps all
  in-flight close barriers after PageInfo session cleanup and cancels stale
  queued actions. Dispatch rechecks the original window, Browser, page,
  document and Space; terminal PageInfo callbacks cannot close a replacement.
  Native panel focus restoration rejects hidden/disabled old controls.
  Original child-window popup presentation, identity, load/close cancellation
  and native motion already match the recovered contract and remain intact.
  Independent `ext14_review` cleared the exact finished source; source/check
  receipts are in `extensions-checks/ext14/`, including the final SIL and
  pinned native compiler check. [Contract](extensions-lifecycle.md).
  At this earlier increment EXT14 remained LEFT: the Arc1.122 side-panel reducer immediately clears
  state and ignores its animation argument, but no rendered shell consumer or
  original panel transition is established. EXT12's separate geometry lookup
  shares that dependency. No functional browser test ran; the denominator
  remains 14 and this increment keeps 11/14 DONE (78.6% / 21.4%, 0.0 pp). Engine owner receives
  the published side-panel source and overlay244 for its next scheduled build.
  Author and reviewer retain this original assignment through publication;
  the author continues the still-open row afterward without repurposing.

- **Automatic archive — October 28, explicitly assigned by Josh.** Root coordinates
  AUTO09–AUTO12 through completion; AUTO01–AUTO08 remain DONE and the fixed
  denominator remains 12. Four fresh agents own the remaining complete rows:
  `auto09_eligibility` uses existing `claude-kbd-kb03` on
  `codex/auto09-eligibility`; `auto10_scheduling` uses existing `claude-kbd-kb04`
  on `codex/auto10-scheduling`; `auto11_presentation` uses existing
  `claude-kbd-kb21` on `codex/auto11-presentation`; `auto12_interaction` uses
  existing `claude-kbd-kb38` on `codex/auto12-interaction`. The previous Keyboard
  owners are retired; these clean, published worktrees are explicitly reassigned
  without new checkouts or inherited agent transcripts. Coordination docs use
  existing `claude-split`; the dedicated engine owner and canonical checkout
  retain their current roles.
  AUTO09 owns typed-item/multiwindow/modal eligibility and original retirement
  validation; AUTO10 owns scheduling and wake/occlusion activity behavior;
  AUTO11 owns automatic-archive settings/status/feedback presentation; AUTO12
  owns the remaining automatic-archive focus, motion and interaction states.
  Shared files are `BrowserStore.swift`, `AppDelegate.swift`,
  `BrowserWindowController.swift`, `SettingsWindow.swift` and this ledger; keep
  changes narrow and exchange exact interfaces before overlapping edits.
  Each row begins with retained `native-analysis/auto-archive` evidence,
  `docs/archive.md` and applicable current handoffs, then uses the local
  Preserve native protection, original Profile/Space/window identity, accepted
  retirement, PiP and every existing exclusion. Archive/History's separately
  counted unfinished requirements are not silently absorbed or credited here.
  Owners complete implementation, permitted component/compiler checks and final
  SIL, docs and immediate one-line commit/push independently. Functional browser
  tests remain prohibited. New engine support, if needed, goes to `engine_owner`.
  Root supervises through brief five-minute checks and updates rather than a
  continuous wait loop. Finished row owners retire permanently.

  **AUTO09 delivered — October 28:** `auto09_eligibility` completes the
  typed-item/multiwindow/modal comparison and original-item preflight. The
  sweep now uses Today sidebar roots, retains mixed saved splits as complete
  items, and refuses original placement/document/group changes during consent.
  Each physical window protects selected and pending panes as well as rendered
  content and retained Peek parents. Arc1.122 retained contracts and helper
  annotations answered the comparison without a new decompiler session.
  Whole-module warnings-as-errors SIL and 796 BrowserStore model assertions
  pass; receipts/source manifest: `automatic-archive-checks/auto09/`.
  Fixed ledger advances from 8/12 to 9/12 DONE (75.0% / 25.0%, +8.3 pp).
  AUTO10–AUTO12 keep their owners; no engine change or browser functional test.
  [Contract and adaptations](archive.md#automatic-archive-typed-item-and-window-eligibility--auto09).
  AUTO09 retires permanently after publication.

  **AUTO10 delivered — October 28:** `auto10_scheduling` completes the
  clock/wake/occlusion comparison. Application maintenance now owns the
  recovered one-second archive/five-second cleanup launch effects and separate
  continuous-clock periodic jobs, including sleep-time deadline coalescing.
  Each physical window owns its activity clock and samples actual occlusion;
  wake/occlusion notifications no longer produce extra archive work or activity
  stamps. Cancellation rejects old queued work through shutdown and replacement.
  Retained evidence and local helpers answered the comparison with no direct
  REA/decompiler session. Warnings-as-errors whole-module SIL and 26 inert
  scheduler assertions pass; inputs/receipts: `automatic-archive-checks/auto10/`.
  Fixed ledger moves from 9/12 to 10/12 DONE (83.3% / 16.7%, +8.3 pp).
  AUTO11–AUTO12 keep their owners; no engine change or browser functional test.
  [Contract and adaptations](archive.md#automatic-archive-clocks-wake-and-occlusion--auto10).
  AUTO10 retires permanently after publication.

  **AUTO11 source increment — October 28:** `auto11_presentation` publishes the
  original interval row, per-profile save plus captured All Profiles sheet,
  inherited global interval, local information entry, original-profile Settings
  deep link, static education card and real accepted-archive producer. The key66
  activation is new-user sign-in, not a launch default; the explicit account-free
  adaptation arms it once at genuine first local setup completion. Loading a
  migrated session does not arm it; an interrupted first setup may arm only at
  genuine completion. Interval customization consumes eligibility.
  Retained evidence and helpers supplied the contract without direct REA.
  Warnings-as-errors whole-module SIL, 25 focused model assertions, 796 existing
  BrowserStore assertions and 16 inert native card assertions pass. Receipts and
  input manifest: `automatic-archive-checks/auto11/`; [contract](archive.md#automatic-archive-settings-and-education--auto11).
  That partial delivery kept AUTO11 LEFT at 10/12 DONE (83.3% / 16.7%,
  0.0 pp). Its real sidebar host, guarded callbacks and reviewed completion
  are delivered with AUTO12 below; no partial credit was taken.

  **AUTO11/AUTO12 integrated delivery — October 28:** the genuine shared
  education producer now reaches each regular window's native sidebar card.
  Original-window Settings actions reveal the captured Profile's interval;
  dismissal preserves unrelated focus, hidden controls leave the key loop,
  and window destruction invalidates queued work. The recovered bottom/opacity
  entry spring, exit ease and retained dismissal lifetime use the original
  SwiftUI primitives. Background archive cleanup preserves unchanged selected
  page hierarchies; displayed-pane removal retains the existing rebuild path.
  The finite scope and explicit native adaptations are recorded in
  [AUTO12's contract](archive.md#automatic-archive-interaction-and-education-motion--auto12).
  Inert native host lifecycle checks and the integrated warnings-as-errors
  whole-module typecheck/final SIL pass with zero diagnostics. Evidence and
  the 333-file input manifest live in `automatic-archive-checks/auto12/`.
  Fresh independent `auto11_code_review` and `auto12_code_review` reviewers
  cleared the exact source before publication; the AUTO11 documentation
  clarification was folded into this delivery. Their receipts are the respective
  `automatic-archive-checks/auto11/review.md` and `auto12/review.md`.
  Fixed ledger advances from 10/12 to 12/12 DONE (100.0% / 0.0%, +16.7 pp).
  AUTO01–AUTO10 and the denominator remain unchanged. No functional browser
  test or new engine dependency was introduced; live motion/keyboard acceptance
  and the independently counted Archive/History gaps remain unclaimed.
  The author/reviewer pairs retire permanently after confirmed publication.

- **Codex recovery — October 28, explicitly requested by Josh.** Claude's
  Keyboard coordinator (`6c3322f6-dcbb-48ab-ab58-663a47b4868a`) and Split/engine
  coordinator (`67444a14-a579-4b8f-8cdc-b84fb6ea9ec3`) stopped at the weekly
  session limit overnight. Resume in their existing worktrees; no replacement
  checkouts. Root coordinates Keyboard; the dedicated `engine_owner` owns the shared
  engine pipeline and uses `claude-kbd` for engine documentation while canonical
  `/Users/josh/Parc` supplies immutable build/package inputs. Fresh agents each own one original unfinished assignment:
  `recover_kb03` in `claude-kbd-kb03`, `recover_kb04` in `claude-kbd-kb04`,
  `recover_kb17` in `claude-kbd-kb17`, `recover_kb21` in `claude-kbd-kb21`,
  `recover_kb22` in `claude-kbd-kb22`, `recover_kb38` in `claude-kbd-kb38`,
  and `recover_sp33` in `claude-split-sp33`. Finished agents are retired and
  never reassigned; fresh agents receive focused briefs without inherited
  transcripts. These transfers supersede the historical Claude claims below.
  All 38 Keyboard rows are now DONE; KB17's scoped
  keyboard-lock correction/overlay 242 and KB22's default-off Cycle gate are
  delivered below as follow-ups to DONE rows. SP33 recovered the two retained commits
  (`bad5d11`, `37f053e`) in its original worktree and is now delivered after
  source review and current-main reconciliation. Recovery also corrects
  Separate All's sidebar-slot preservation and focus reclaim, and retains the
  newly entered folder name through Undo/Redo. Final SIL and focused receipts
  are `claude-split-checks/codex-sp33-review-fixes-*`; original commits remain
  at `codex/recovery-sp33-original-37f053e`. Keyboard
  recovery began at 34/38; Split moves from 32/33 to 33/33 DONE (+3.0 pp).
  SP33 has no remaining Split row; its inline folder-title editor handoff
  stays with Folders below. No browser functional test was run.
  Shared files include `AppDelegate.swift`, `BrowserWindowController.swift`,
  `KeyboardShortcuts.swift`, `TabCommandNavigation.swift` and this ledger.
  Each row owner reviews retained evidence, completes allowed checks, reconciles
  current main and publishes directly; root is not an integration gate.
  Preserve dirty source and unique receipts. Final source needs whole-module
  SIL; functional browser tests remain prohibited. KB17 publishes engine
  source normally; only `engine_owner` applies/builds/seals/packages the shared engine.

  **KB38 live discovery delivered (October 28):** `recover_kb38` preserves and
  finishes the retained implementation in `claude-kbd-kb38`. Weak live tooltip
  and context-menu projection follows customization, conflicts, removal, reset
  and retired/reintroduced command identities. Sidebar/toolbar/Developer Mode,
  popup/Peek Close, Library, Site Control Center, Start/Ready text and contextual
  Favorite Rename use current real command bindings. SP33's actual split-cell
  menu receives Rename/Duplicate/New Folder bindings without changing its action
  owners. The native command-field URL-copy hint retains its original panel/page
  and records its two-calendar-day cooldown only after passive presentation.
  Fresh Arc1.122 action attribution corrected the assumed missing chooser:
  Open in and Expand share the same current-modal/current-window-Space route.
  The genuine Command–O/Use Both menu and live Expand hint now preserve original
  page/Profile/referrer ownership, validate the current Space, and refuse stale
  (100.0%), 0/38 LEFT (0.0%), +2.6 pp from KB04. The row owner retires after
  publication; no new feature is assigned.
  [Evidence and scope](keyboard-navigation.md#live-binding-discovery-and-copy-education--kb38).
  Whole-module warnings-as-errors SIL and focused component manifests/logs:
  `claude-kbd-checks/kb38-recovery/`. No functional browser test ran; actual
  physical shortcut/clipboard execution and visual/motion acceptance are unclaimed.

  **KB04 delivered (October 28):** recovered in the original
  `claude-kbd-kb04` worktree. Command-number Sidebar targets, all numbered
  Space commands, actual conditional ordering controls and the native Note
  Find variants are complete. Recovery additionally fixes initial/live Space
  registration, unbound Spaces after nine, saved defaults after dynamic rebuild,
  conditional ninth-item settings and stale Note-document refusal. Current
  Keyboard count is 37/38 DONE, 1/38 LEFT (97.4% / 2.6%, +2.6 pp from KB03).
  [Contract](keyboard-navigation.md#numbered-targets-and-native-text-find--kb04);
  focused receipts `claude-kbd-checks/kb04-recovery-final-checks.json`, final
  source manifest beside it, SIL `claude-split-checks/recovery-kb04-inventory-integrated.*`.
  No engine change or functional browser test. This row owner is retired after
  publication; KB38 retains its separate active owner.

  **KB17 follow-up delivered (October 28):** overlay 242 removes the blanket
  lock refusal for registered shortcuts, so otherwise eligible unlocked keys
  retain their selected priority while another key is locked. Chromium's
  per-key `skip_if_unhandled` bypass and Escape-first exclusive-access route
  interceptor has no explicit lock predicate, but its complete locked-key
  delivery remains untraced; the KB26 adaptation is retained. The cue component
  uses current dependencies and the child-window API. Checks: pinned native
  syntax compile, read-only full overlay reconstruction, 16 cue assertions and
  35 inert presentation assertions (`claude-kbd-checks/kb17-recovery`). No app
  Swift source changed and no browser test ran. **Engine handoff to `engine_owner`:**
  overlay 242 apply/build/seal passed in v235 at `3301647a`; final release
  packaging passed at app source `8c35faf7` against that seal. The feature owner did not modify shared inputs. KB17 remains DONE; Keyboard stays 34/38 (89.5% DONE,
  10.5% LEFT), 0.0 pp for this correction. `recover_kb17` retires after publication.

- **KB03 recovered and complete — October 28.** `recover_kb03` delivered in
  the original `claude-kbd-kb03` worktree: complete included menu/hidden-command
  inventory reconciliation, Blank Window, New Profile, Duplicate, Reveal Tab in
  Sidebar, Library, Rename Space, Extensions, native Window actions and the
  independent bracket/fn equivalents. Duplicate remains menu/Shortcuts-only
  as its record has no Actions identity; Reveal and New Profile retain the
  genuine browser/command-panel and sheet gates. Native Format/Font and other
  absent feature owners have explicit contracts in the [inventory](keyboard-navigation.md#complete-command-inventory-reconciliation--kb03).
  KB38 subsequently recovered and delivered the genuine `openTabIn` Command–O /
  Use Both current-Peek promotion; the earlier missing-chooser assumption was
  KB04 owns the remaining numbered and native-Find execution contexts; KB38
  owns live discovery. Fixed ledger: 36/38 DONE, 2/38 LEFT (94.7% / 5.3%,
  +2.6 pp). Retained recovery SIL matched all 323 recorded inputs before
  reconciliation; finished-source SIL and focused registry components are
  recorded under `claude-kbd-checks/codex-kb03-main-final*` (SIL) and `codex-kb03-merged*` (registry components). No browser functional
  tests or new installed-reference inspection ran. This agent retires after
  direct publication; no further family assignment is implied.

- **Claude `claude/navigation` — General navigation and gestures (claimed October 27).**
  Checkout `claude-nav` (branch `claude/navigation`). Family complete
  (16/16 DONE; NAV16 shipped October 28). One sub-agent per row in its own worktree `claude-nav-<row>`,
  shipping its row to main as soon as it is verified; evidence goes in
  [navigation.md](navigation.md). Likely shared files: navigation controls and
  history chooser views, `NativeNavigationHistory`, HistorySwiper engine overlay,
  `BrowserWindowController.swift` (bounded). No navigation rows remain.

- **Claude `claude/web-interactions` — Web interactions (claimed October 27).**
  Checkout `claude-web` (branch `claude/web-interactions`). **Family complete
  (October 28): WEB01–WEB19 DONE, 19/19.** Per-row evidence is in
  [web-interactions.md](web-interactions.md). Pending for the engine owner:
  overlays 239 (WEB15 follow-up), 240 (WEB19 permission press) and 241 (WEB16
  menu, status and banner dispositions); until 241 is built an older engine still
  shows the removed infobar shelf and pop-up chooser. Open contracts from this
  family are listed per row below.
  "Tab crashed. Maybe reload the page?" with its reload link, error code) in
  every pane and Peek, light/dark; the hang sheet takes Chromium's own strings
  (overlay 235, applied). [Evidence](web-interactions.md#failure-and-recovery-surfaces--web17).
  **WEB18 DONE:** page-action inventory, Paste and Match Style, Delete and the
  text submenus, Share…, View → Appearance and shipped menu placement; no engine
  overlay. Menu contracts for Notes, Easels, Command bar, Windows, Extensions,
  Archive and the folder/sidebar owners are in [WEB18](web-interactions.md#contracts-for-other-families).
  buttons, extensions grid with pins and ⌘E picker, Settings rows, Secure
  footer) is the one surface behind the Toolbar, address-pill and popup entries;
  the old Extensions popover and Toolbar Extensions button are gone, and a
  blocking): per-host state and toggle for the Content Blockers row.
  [Evidence](web-interactions.md#site-control-center--web14).
  "Don't show this again") and before unload, the login sheet, the
  the sidebar's page controls; certificate and capture pickers stay stock
  (built in v233; its mailto title, login-font and proxy-title follow-up is
  overlay 239, applied). `BrowserWindowController` gains
  `parcSitePermissionAnchorForPage:`. [Evidence](web-interactions.md#dialogs-authentication-certificates-and-permissions--web15).
  View; no profile, QR, Lens, Glic or reading-mode items; search first for a
  and "Share this tab instead" on the sidebar row (touches the Sidebar's
  `SidebarView.swift` row and `SidebarRowActionButton.swift`). Overlay 241, applied. Contract for Split views: Option/Option-Command link clicks to
  a split, then their status explanation. [Evidence](web-interactions.md#context-menus-hovered-status-and-banners--web16).
  black/white glyph at 0.55/0.675, fill 0.05/0.09 hovered and 0.09/0.13
  pressed, 0.18 s hover and 0.16 s press ease-in-out. The Toolbar's appearance
  follows the theme. In the Site Control Center: the address pill's 10/100 ms
  show delay behind a stale token; the 0.1 s ease-out on the Skeu buttons and
  setting icons; the 0.12 s section hover; the 0.36 s pin dwell. The
  [Evidence](web-interactions.md#surface-motion-hover-and-haptics--web19).
  **Contract for the Navigation family (receiving: whoever owns
  `NavigationControlButton`), pending:**
  - Glyph: `FullOpacityForegroundPrimary` (black/white) at 0.55 light /
    0.675 dark while enabled, 0.25 disabled.
  - Fill: a continuous six-point rounded fill in the same ink at 0 at rest or
    disabled, 0.05/0.09 hovered and 0.09/0.13 pressed; press wins.
  - Motion: 0.18 s ease-in-out on hover changes, 0.16 s on press.
  - `NavigationControlButton` still draws its own 0.08/0.16 fill and should
    adopt this table, for example as `BrowserToolbarActionButton` does in
    `BrowserToolbar.swift`. The history-hold state is the Navigation owner's.

- **Stalled October 27 — Onboarding (was Codex root), Available.** Last
  delivery `8e1320d` (October 27, 00:20) is on main; the checkout
  `parc-completion-audit` (detached at that commit) has no uncommitted or
  unpushed work. Resume from the next step in the note below.
  **Codex root — Onboarding (last note):** delivery checkout `parc-completion-audit`;
  reference scratch `arc-onboarding-presentation`. **OB19 is complete.** The
  Favorites step now has the original nine-app illustration, catalog artwork,
  light/dark selected tiles, hover/press springs and retained native owner.
  The original YouTube/Calendar initial choices and front-inserting ordered
  selection persist into the real session; older Parc drafts retain their
  choices. Fixed ledger: 25/36 DONE, 11/36 LEFT; 69.4% / 30.6%, +2.8 pp.
  Next: OB20's onboarding theme-editor composition. OB11/16/17/22/23/32–36
  retain their separate optical, conditional, reveal and whole-flow interaction
  requirements. The inert component's direct AX traversal did not expose
  SwiftUI's virtual buttons; no AX acceptance is claimed or credited to OB33.
  Evidence/checks: `onboarding-favorites`; [onboarding evidence](onboarding.md).
  Shared scope remains bounded `Onboarding*`, draft/store commit and the shared
  theme editor. This increment has no engine changes; the previously published
  import bridge remains pending with the existing engine handoff below.

- **Claude `claude/keyboard` — Keyboard shortcuts and keyboard gestures
  (claimed October 28).** Checkout `claude-kbd` (branch `claude/keyboard`).
  LEFT rows KB03, KB04, KB17, KB21, KB22, KB25, KB38; one session per row in its
  own worktree `claude-kbd-<row>`, shipping its row to main as soon as it is
  verified. Evidence goes in [keyboard navigation](keyboard-navigation.md),
  [Settings](settings.md#shortcuts) and [tab switcher](tab-switcher.md). Likely
  shared files: the shortcut registry/menu owners, `RecentTabSwitcher*`,
  keyboard-priority queue, sidebar/command-bar/Peek focus routes. The Codex
  note below is retained as the starting point.
  **KB25 DONE (October 28):** cross-surface keyboard/AX traversal and return;
  (`CommandBar.mayRestoreOriginal`, `ContentFocusRequest.returnsToSaved`).
  Fixed count 32/38 DONE (84.2%), 6/38 LEFT; +1/38 = +2.6 pp.
  [Evidence](keyboard-navigation.md#cross-surface-traversal-and-return).
  continuation, Shift reversal, consumed keys/repeats, unmonitored clicks) and
  silent refusal for positional traversal; Cycle Tab Forward/Backward follow
  source in
  `RecentTabSwitcher.swift`, `RecentTabOrder.swift` (`RecentTabSwitcherInput`)
  and the four traversal validators in `BrowserWindowController.swift`.
  Fixed count 33/38 DONE (86.8%), 5/38 LEFT; +1/38 = +2.6 pp.
  [Evidence](tab-switcher.md#held-repeated-and-interrupted-input--kb22).
  **KB22 follow-up delivered (October 28, Codex recovery):** Cycle menu
  default-off flag. Saved Cycle bindings/priorities survive unrelated edits;
  held-MRU and original-page ownership are unchanged. The retained six-file
  change was recovered in `claude-kbd-kb22`, with fresh keyboard-navigation
  model/inert registry checks and whole-module SIL on matching hashed inputs
  (`claude-kbd-checks/codex-kb22-recovery-*`). No browser was driven. KB22 was
  already DONE; the fixed count stays 34/38 (89.5% DONE, 10.5% LEFT), 0.0 pp.
  **KB21 DONE (October 28, Codex recovery):** completed the retained card
  variants, copied native template artwork with provenance, hidden reserve
  promotion and direct panel choreography in `claude-kbd-kb21`. Original-page,
  Peek, profile and close-consent ownership are preserved. The inert presentation
  passes 37 assertions; light/dark synthetic variants were inspected, and final
  whole-module SIL covers matching hashed inputs. No browser was driven. Fixed
  count advances 34/38 → 35/38: 92.1% DONE, 7.9% LEFT, +2.6 pp. KB03, KB04
  and KB38 remain. [Evidence](tab-switcher.md#completed-variants-and-transitions--october-28).
  **KB17 DONE (October 28):** all 41 MainMenu priority records reconciled
  to editable page content too, except chords whose typed characters are
  reserved; a consumed Use Both Exit arms Press Again only with no modal and
  expanded full screen. Source in `KeyboardShortcuts.swift` and the cue owner
  in `BrowserWindowController.swift`; no engine change.
  Fixed count 34/38 DONE (89.5%), 4/38 LEFT; +1/38 = +2.6 pp.
  [Evidence](settings.md#context-exceptions--kb17).
- **Stalled October 27 — Keyboard (was Codex `arc_ui_features_polish`),
  now claimed above.** Last delivery `fbbbbc3` (October 27, 00:07) is on main; the
  checkout `parc-keyboard-delivery` (branch
  `delivery/keyboard-essentials-parent`) has no uncommitted or unpushed work.
  Resume from the next step in the note below.
  **Codex arc_ui_features_polish — Keyboard (last note):** delivery checkout
  `parc-keyboard-delivery`; current cohort `arc-keyboard-mru-presentation`
  replaces the provisional held-switcher renderer with the recovered native
  popover/SwiftUI card surface, exact focus fill, typography, spacing and scroll
  easing. Original page previews, held input, selection and close-consent owners
  remain. The historical KB21 gaps (custom-info/snapshot variants and reserve/
  panel transitions) are closed by the October 28 recovery delivery above.
  KB03/KB04/KB17 and KB22/KB25/KB38 retain their existing command, context,
  interruption and cross-surface focus/discovery boundaries. Shared scope is
  RecentTabSwitcher and its passive presentation; no BWC or engine change.
  Clear Today retains the Today/Archive handoff for its original clear filter;
  its Undo is registered
  ([Close Undo](reopen-closed-tabs.md#close-undo)). Its formerly
  unproved native-text Find tags 0/12 are closed by the KB04 recovery above.
  The fixed ledger remains 31/38 DONE and 7/38 LEFT, latest 0.0 percentage points;
  no denominator or scope change. [Switcher evidence and limits](tab-switcher.md#original-card-surface-and-ownership--kb21)
  **From TAB22 (Claude Today/Favorites), informational:** TAB22 adds no
  access stays with Control–Space and the existing menu commands.
  **From TAB21 (Claude Today/Favorites), informational:** a Peek whose page
  fullbleed Peek" in `keyboard-navigation.md` (Exit priority) no longer
  applies. The Exit command's modal-priority branch is unchanged. Status:
  delivered, no reply needed.

- **Claude `claude/downloads` — Downloads: family complete (October 27).**
  Checkout `claude-downloads` (branch `claude/downloads`). DL33 is DONE, so
  native carrier reviewed and corrected, child window, flight, bin, no haptic)
  lifecycle, hover flyout and row actions. Along the way DL25's settings now
  [arrival](download-library.md#original-downloadtolibrary-arrival),
  [Library entry](download-library.md#original-library-entry),
  [flyout](download-library.md#original-library-flyout),
  [prompt and picker](download-library.md#original-download-prompt-default-and-download-location).
  Shared files touched: `SidebarView.swift` (entry replaces the Downloads
  button), `SidebarChromeLayout.swift` (dock slot and strip),
  `BrowserWindowController.swift` (arrival receiver, Library route, flyout
  actions), `LibraryView.swift` (last-page hook), `SettingsWindow.swift`
  (Downloads section), `scripts/test.sh` (picker check) and the SidebarChrome
  tests. The Sidebar owner's Downloads-entry contract is delivered. Pending:
  the engine owner's overlay apply and build (see Shared engine ownership).
- **Stalled October 27 — Downloads (was Codex `download_integration`),
  now claimed above.** Last delivery `a03cb74` (October 27, 00:05) is on main. The
  checkout `downloads-accessory-delivery` (branch
  `delivery/downloads-accessory`) holds **uncommitted, unreviewed DL33 engine
  work**: changes to `Engine/ParcNative/downloads.cc`, `downloads.h`,
  `native_appkit_application.mm`, `native_appkit_bridge.h` and
  `Engine/ParcHost/integration/native-host.patch` (5 files, +99/−9) and new
  `Engine/ParcNative/native_download_arrival.h`/`.mm`. It was never compiled,
  reviewed or published; the next owner should inspect it before reusing it.
  **Codex download_integration — Downloads (last note):** delivery checkout
  `downloads-accessory-delivery`; current source/evidence cohort
  `downloads-artwork-contract`. DL32 closes the original24-point file artwork,
  14-point empty template, provisional native icon/thumbnail ownership and
  lowercase/highlighted/dimmed title states; the native row comparison preserves
  original file paths and actions. [Evidence](download-library.md#original-file-artwork-and-title-states).
  Next: DL33's attributed `DownloadToLibrary` arrival owner and final
  transition/haptic comparison, using a genuine original-document creation event.
  Shared scope: Downloads view/provider and subsequent native creation seam;
  no Sidebar/importer ownership changes. Fixed32/33 DONE and1/33 LEFT,
  latest exact1/33×100=+3.0 percentage points; no scope or denominator change.
- **Claude `claude/split` — Split views (claimed October 27, transferred from
  stalled Codex `browser_runtime`).** Checkout `claude-split` (branch
  `claude/split`) under the work root; per-row worktrees `claude-split-<row>`.
  SP33 completed through the Codex recovery above. Active rows: none;
  all 33 rows are DONE (fixed 33/33 DONE, 0/33 LEFT). The
  Sidebar round 3 `PaneTitleLabel` pin is delivered (SP27); TAB19 → SP30 is
  answered by SP30. The Sidebar round-4
  `.splitDividerResize`/`.splitInteractiveEditing` items are delivered (SP10).
  SP27's engine overlay `PCNativePage (SecureContext)` (`native_appkit_bridge.h`,
  `native_appkit_page.mm`; overlay version 238 in `overlay.json`) is tracked
  under shared-engine ownership below.
  Likely shared
  files: `ParcSplitView`, `BrowserPane`, `PaneTitleControl`, `BrowserToolbar`,
  `SidebarSplitGroupView`, the split sections of `BrowserWindowController.swift`
  and `split-groups.md`. Shared-engine work follows the Codex recovery
  ownership above. No Split row remains. SP22 closed after
  starter, so Parc binds no pane handle ([evidence](split-groups.md#pane-snapshot-drag-source)).
  ([details](split-groups.md#contract-for-general-navigation-bottom-handle-loading-indicator)).
  icons (`.icon`); builds before SP26 cannot read a state file containing one
  and fail at `BrowserStore.init` (the file is not overwritten), so keep older
  worktree builds away from a profile that has used the new picker.
- **Stalled October 27 — Split views (was Codex `browser_runtime`), claimed
  by Claude above.** Last delivery `edd0a3b` (October 27, 00:12) is on main; the
  checkout `parc-split-delivery` (branch `split/family-delivery`) has no
  uncommitted or unpushed work. Contracts addressed to the Split views owner
  (TAB19 → SP30, Sidebar round 3/4) stay open for whoever claims it.
  **Codex browser_runtime — Split views (last note):** delivery checkout `parc-split-delivery`;
  current source/evidence/check cohort `split-pane-center-layout`. The real pane
  title now uses the recovered independent center-stack allocation and Copy Link's
  leading balanced slot; actual frame collisions control optional room. Compact
  headers share centered placement while retaining their original actions.
  Shared scope: `PaneTitleControl`, `BrowserToolbar`, the narrow `BrowserPane`
  header layout, native Toolbar checks and Split docs. No Sidebar, Store or engine
  edits. Next: the original insecure-state carrier, modal/title action/menu owners
  and populated comparison, then pane-source initiation/collapse and source
  snapshots (SP22/SP27/SP29/SP31/SP32). Existing non-Split edge presentation and
  very narrow containment remain explicit adaptations. Fixed 21/33 DONE and
  12/33 LEFT, latest exact 0.0 percentage points; no scope or denominator change.
  [Mechanism and limits](split-groups.md#center-stack-and-edge-collisions).
  0.1 s after creating it (`WindowAction.setEditingItem`, payload case 44, from
  menu opens the folder's existing Rename prompt there. When the Folders
  family builds inline folder title editing, replace that prompt with it. The
  reusable owner (`SidebarFolderFromItems`, `BrowserStore.createFolder(containing:)`
  and `revertFolderCreation`, whose returned receipt retains folder metadata
  for "New Folder…" Redo) is available for the tab and
  multi-selection menus' New Folder with *n* Items. Status: open; no reply
  needed.
- **Split views → Today/pinned owner (SP33, note):** Archive Other Tabs /
  Below / Above now validate against the sidebar's Today order
  (`SidebarTodayArchive.order`, roots in order with a split's children
  together) instead of the model's tab array order, which refused most
  requests with two or more Today tabs. The tab menu's group shares the fix.
  split child cell (`SplitViewCellChildItemView`) inside each compact
  `SidebarTabRow`: a 28-point cell, icon slot 2 points in, 14-point title 6
  after it, Close 2 inside the trailing edge, no reset target, slash or
  subtitle, and TabCellChildBackground on every child of the selected split.
  Children no longer draw their own current, content-visible or hover fills,
  and a child's Close follows the hover of its `SidebarSplitGroupView` (the row
  adds a tracking area to its container). Geometry and addresses are in the
  [TAB19 entry](#ordinary-row-presentation--tab19). For SP30, the container
  hover, multi-selection, ring and dim fills from `SplitViewCellState`, which
  passes `canResetTab` false), its `SplitViewCellChildrenContainerView` lays
  children out with `SplitViewItem.ChildItem.padding` 4 and draws separator
  layers (`separatorHeight` 16), and `SplitViewItem.Container.insets` is 0 / 12
  / 0 / 12. `SidebarSplitGroupView` still draws its 1-point accent border and
  10-point move handle. Status: answered by SP30 (October 27): the split cell
  Close and the custom-info cell, without the border or handle; TAB19's child
  cell is unchanged apart from its 28-point frame and Close availability
  ([split cell container](split-groups.md#split-cell-container--sp30)).
- **Claude — Sidebar:** delivery checkout `claude-sidebar` (branch
  `claude/sidebar`); per-row worktrees `claude-sidebar-side10/16/17`. DONE: SIDE11
  lights in the header, pinned drawn content and an idle main thread during
  the slide) and SIDE17 (focus and accessibility inventory), both DONE on
  October 27 on verified code at the user's direction (their on-screen
  look-and-feel checks were skipped), and SIDE16 (edge resizing, chrome
  first-run App Tray empty state, the renderer-acknowledged page hold built
  Space menu on the header, the dock's Space items and the list's empty
  area), DONE on October 27 on verified code at the user's direction (its
  on-screen check skipped as for SIDE10/SIDE17). **All 17 Sidebar rows are
  DONE.** Open contracts for other families are listed below and in the
  Sidebar documents. Follow-up: share
  the preview source-route host check with the page-link route.
  **Sidebar round-3 contracts (October 27; details in
  [sidebar motion](sidebar-motion.md), [sidebar resizing](sidebar-resize.md)
  and [sidebar accessibility](sidebar-accessibility.md)):**
  Split views/Toolbar: pin `PaneTitleLabel` with
  `SidebarMotionController.pinDrawnContent(label, to: .center)` (or keep the
  title button's width fixed during the Cmd-S group) and assign the surface
  frame inside the group (delivered by SP27, October 27, with the Toolbar's
  drawn rule pinned too). Developer Mode: move `DeveloperToolbarView`'s tint to
  its layer so it can be pinned. Renderer crash presentation: pin
  `PageFailureView`'s title and detail centred (delivered by WEB17, October
  27). Engine: the maximize guard in `native_browser_window.mm` now finds the
  sidebar's zoom widget through `-standardWindowButton:`; use a stored
  reference or `can_maximize` if zoom capability can change after creation. Library: it keeps the window's own
  and lifecycle: persist each window's sidebar width with its session record
  and seed `BrowserWindowController` from it. Window key-view loop: point the
  page side's last key view at `sidebar.keyViewEntry` and set
  `sidebar.keyViewExit` to its first. Media: give `MiniPlayerRow`, its title and
  the deck's expand button a ring or make them refuse focus. Downloads: if it
  Library entry, now in that slot with no stop or ring). Space creation: expose the draft theme so the creation
  dock item can take its tint. Status: open, except the window key-view link
  and the mini player ring, delivered by SIDE17 (October 27).
  **Sidebar round-4 contracts (October 27; details in
  [sidebar resizing](sidebar-resize.md#page-size-during-a-width-drag) and
  [sidebar accessibility](sidebar-accessibility.md)):** Codex root (engine):
  apply and build the `PCNativePage (RenderFrameViewport)` overlay
  (`Engine/ParcNative/native_appkit_bridge.h` and `native_appkit_page.mm`,
  hashes in `Engine/ParcHost/overlay.json`; syntax-only compiled against the
  pinned tree). It reports the primary main frame's `RenderFrameMetadata`
  viewport in points after each activation, which releases a page held during
  a sidebar-width drag; until it is built, `responds(to:)` is false and pages
  resize live as before (built into v231, October 27). Windows and lifecycle: call
  `setContentResizeReason(.windowResize, active:)` around full-screen
  `.splitDividerResize` (0x2) during a divider drag and
  `.splitInteractiveEditing` (0x4, locks every displayed pane) during
  interactive pane editing; `BrowserPane` now places its page through
  `PageContentResizer` (minimal hook) (delivered by the Split views owner in
  SP10: 0x2 from pan begin to its end or cancellation, 0x4 from a split drop's
  first admitted entry to its end, [evidence](split-groups.md#divider-regions-pane-input-and-content-resize-reasons)). Window key-view loop: `keyViewEntry` is
  now a gate that never takes focus; link the page side only to it, never to
  other sidebar members. Page actions: whether the sidebar shows is
  `SidebarView.isPresented`; popovers and menus opened from the sidebar while it
  is not presented anchor to the page. Every owner that restores a saved first
  responder: restore none into a sidebar that is not presented
  (`SavedFocus.mayReturn(to:in:)`, which every Parc restore path now uses). Folders:
  (minimal hook). Selection (informational): a folder's disclosure alone no
  longer clears the sidebar multi-selection. Status: open.
  **Contract for Codex browser_runtime (Split views):** implemented in source,
  view, which Parc does not draw, and keeps grips visible
  ([evidence](split-groups.md#sidebar-transition-grip-backgrounds)). Original note:
  `ParcSplitView.isAnimatingResize` hides only passive divider backgrounds. The
  BWC anchored transition sets it before preparation; the existing generation-
  guarded completion and `settleSidebarMotion` clear it. Floating-only reveal
  does not initiate resize suppression; interrupted anchored suppression remains
  until the current owner settles. New divider backgrounds inherit the flag.
  no native renderer throttling or manual Sidebar-width drag policy is implied.
  [Mechanism and checks](split-groups.md#sidebar-transition-grip-backgrounds).
  Status: delivered; Sidebar owner should preserve these hooks when changing
  transition lifecycle. Shared scope:
  `SidebarMotionController.swift`, the sidebar presentation/geometry section of
  `BrowserWindowController.swift` (`setSidebarPresentation`, `layoutChrome`
  sidebar frames), sidebar-owned `SidebarView.swift` presentation, focused
  checks and `sidebar-motion.md`/`sidebar-previews.md`. Any engine change is
  published as an overlay for the next root engine increment, not applied to
  the shared output.
  background is a 52-point `CellSelectionStateView` inset 8 on every side, which
  35 points. TAB19 draws inside the existing row frame and does not change row
  height, spacing or sidebar insets. Status: closed by SIDE16 (October 27):
  row 2 points down ([sidebar chrome spacing](sidebar-resize.md#sidebar-chrome-spacing)).
- **TAB19 → Sidebar owner (SIDE17, informational):** `highlightItemForKeyboard`
  now marks an ordinary `SidebarTabRow` target as highlighted instead of adding
  maxContrastColor ring with 12-point continuous corners on the visible row
  other items keep `SidebarKeyboardHighlightView`. The keyboard cursor's
  producer, item mapping and scrolling are unchanged. A resettable row's
  icon-slot reset target is an AX button labeled "Reset Tab to Original URL",
  as the former trailing Reset button was. Status: delivered, no reply needed.
- **Split views → Sidebar owner (SIDE17, informational, SP30):**
  `highlightItemForKeyboard` now also marks a `SidebarSplitGroupView` target
  as highlighted: the split cell draws the same 2-point maxContrastColor ring
  through its own `CellSelectionStateView`, so split containers no longer get
  `SidebarKeyboardHighlightView` (folders and other items still do).
  `refreshItemSelection` gives a split the multi-selected fill instead of the
  accent border. List-stop Tab focus uses the same 2-point HighlightRingView
  as the keyboard cursor, so the cell layer no longer rounds or clips the
  current-item shadow or child pills. The
  split's Close joins its accessibility children while shown, and a split with
  its own Close gains an "Archive/Close Split View" action
  (`sidebar-accessibility.md` updated). Status: delivered, no reply needed.
- **TAB22 → Sidebar owner (SIDE17, informational):** `SidebarTabRow` and
  `FavoriteTile` are each one AX button. Rows are described as "Tab" (web) or
  as a plain button (Easel/Note); tiles as "Favorite". Each
  speaks its title as AXTitle with no AXDescription, keeps the URL as help,
  reports selected for the current item (rows also for multi-selection) and
  supports press and show-menu. SIDE17 owns container roles, grouping and focus
  order. If it wraps items in AX rows or an outline, keep each item as the
  item-level keyboard focus inside the tablist. Status: delivered, no reply
  needed.
- **Claude — Today / pinned tabs / favorites:** owner checkout
  `claude-today-favorites` (branch `claude/today-favorites`), a separate Claude
  contributor from the Sidebar owner. Work runs in parallel lanes, each with its
  own worktree under the work root and direct publication to main.
  **Family complete (October 27): TAB01–TAB22 DONE, 100.0%.** Final rounds:
  TAB16 Favorite tile overlays (`c73ca83`: recording dot, Peek badge, music
  them behind a default-off remote flag); TAB17 focused-pane Favorite selection
  (`04afd7b`); TAB18 closed with no Favorite unread badge (see below); TAB19
  review fix `6dd1d03`); TAB20 reopen and TAB21 provenance (rounds 1–2).
  Not verified on screen: no runtime or visual comparison was run. Waiting on
  Codex root: three published engine sources need the next overlay apply
  (TAB20 `ReopenedPeek`, TAB21 `routedLinkCreation`, TAB16
  `mediaSessionStatus`; see Shared engine ownership). Until then, Swift guards
  each with `responds(to:)`. Open item for Split views (SP30): the TAB19 →
  Split views contract note.
  **Proposal for the Sidebar owner (TAB18 / SIDE15 unread):** SIDE15 keeps the
  unread model, attribution and row presentation; this family adopts that
  bottom-right inset 8, 0.3 s ease-out opacity; recovered in the TAB16 pass).
  TAB18 closes when SIDE15's producer lands and the tile shows it. Status:
  agreed by the Sidebar owner (October 26): SIDE15 keeps the unread model,
  never marks a locally created item unread (all 46 constructor sites pass
  (`dot`), both excluded. There is therefore no included unread producer to
  publish for tiles, and sidebar rows show no unread badge. Parc's local unread
  Favorite App Tray child badge is a different mechanism,
  `AppTrayBadgingProvider` (title, URL, badging-disabled hosts), not
  reads only `Inputs.keyboardShortcutToShow` (the default-off ⌘N flag) and
  `Previews.PreviewData` (`UnreadEmail`, `GoogleCalendarPreviewData`,
  `CalendarEvent`, `PreviewMetadata`) from the excluded mail/calendar/social
  live providers, and the verified AppItem fields carry no unread value, so
  Details: [unread ownership](saved-tabs.md#unread-state-and-badge-ownership).
  Row spacing stays with SIDE16 and sidebar-wide focus with SIDE17.
  Shared scope: `FavoriteTile.swift`, `FavoriteTileLayout.swift`,
  `FavoriteRenameDialog.swift`, the Favorites grid and item-row sections of
  `SidebarView.swift` (not sidebar presentation/motion/spacing), saved-tab and
  closed-item model paths in `BrowserStore.swift`, creation-provenance owners in
  `BrowserWindowController.swift`, focused checks, `saved-tabs.md` and
  `reopen-closed-tabs.md`.
  `SidebarHeaderView` classifies widths at 212 and 228 points, where 228 =
  App Tray item of the focused pane: the focused content's sidebar item, or the
  (`button.selected = state.selectedTabIDs.contains(tab.id)` in the Favorites grid
  of `SidebarView.swift`). Requested change in that section: select a tile when
  the render's existing `activeID` (`focusedTabID ?? state.selectedTabIDs.first`)
  is the tile's tab or, for a split Favorite tile, one of its group's members. A
  Favorite in an ordinary Space split is a single tile and is selected only while
  its own pane is focused. Status: landed in the Favorites grid; TAB17 closed.
- **TAB16 overlay delivery (Claude, Today/Favorites): shared files.** Favorite
  tiles show the recording dot, highlight ring, Peek badge and music particles
  and dim with their window ([evidence](#favorite-tile-presentation--tab16)).
  Bounded shared changes: in `BrowserWindowController.swift`, `updateNavigation`
  takes one `presentedState` snapshot and calls `sidebar.updateFavoriteOverlays`
  before `render`; the new `favoriteOverlayStates(_:)` only reads
  `capturePresentations` (#11), live Peeks, Developer Mode and
  `mediaSessionStatus` (#14), and the Developer Mode subscription also
  refreshes it. `refreshCaptureIndicators` and `refreshMiniPlayers` are
  unchanged. In `SidebarView.swift`: the new `updateFavoriteOverlays`; the
  clickable Favorite capture buttons (`favoriteCaptureButtons`) and their
  layout and palette code are removed; `highlightItemForKeyboard` gains a
  Favorite branch; the Favorites `applyPalette` call passes `maxContrastColor`.
  `PeekController.swift` (Peek, unowned) calls `onUpdate` when dismissal
  starts, when a close is refused and on a favicon-only change.
  **For the Sidebar owner (SIDE17, informational):** a keyboard-highlighted
  Favorite, single or split, draws its own App Tray ring instead of
  `SidebarKeyboardHighlightView`. The cursor producer, item mapping, TAB19's
  row ring and scrolling are unchanged. Status: delivered, no reply needed.
  **For Screenshots/recordings (#11, unowned, informational):** Favorites have
  November 2 at Josh's direction; a capturing Favorite's tile menu now opens
  the same Stop menu through `onCaptureMenu`, covering the Favorite's page,
  its Peeks and its Easel pages.

## Shared engine ownership

**1.1.1 patch release delivered — November 6:** pulled published main, then ran
`bash scripts/release.sh --type patch` to completion. Source `f083a16d`,
engine overlay 341, bundle build 3. [v1.1.1](https://github.com/etsenake/parc/releases/tag/v1.1.1) is stable/latest
with verified signed/notarized ZIP and DMG. Production Team remains `94HKA7L2DR`.
App submission: `c4292f6d-42bb-490b-8c98-592af9c44076`; DMG submission:
`6f522cab-3bbb-4b86-8d19-7788232b07d2`. Both were accepted, stapled and Gatekeeper verified.
Tap commit `6681e13042521e3336484cf7c982884c303b284e` publishes the 1.1.1 cask. The script performed
no local installation, quit, launch, browser tests or Homebrew upgrade. No pipeline
errors occurred. Receipts: `build/releases/20261106T073716Z-9a03d3fb/delivery.json`.

**1.1.0 release delivered — November 5:** the new master command completed
engine/app/sign/notarize/publish/cask delivery for source `ee799c69`, overlay 333,
bundle build 2. [v1.1.0](https://github.com/etsenake/parc/releases/tag/v1.1.0)
is stable/latest, with ZIP and DMG. Both Apple submissions were accepted,
stapled and Gatekeeper verified; production Team remains `94HKA7L2DR`.
App submission: `ed1a3d5c-888f-4a11-9abf-c33d293e8afc`; DMG submission:
`b16b4c04-c9b2-4338-af14-ffc100de42f6`. Tap commit:
`0cded575c236f496a2246f0512b7b8a53947992d`. Source and engine stages resumed
without a second version bump; cancelled engine compilation resumed its cache.
No app install, quit, launch, runtime test or Homebrew upgrade ran. The local app
and Homebrew receipt remain 1.0.0 pending Josh's manual upgrade. Publication
metadata is `build/releases/20261106T042042Z-046471e2/delivery.json`; 217 packaging
checks passed (one platform skip), plus 75 engine-source checks. Secure private-key
backup remains pending the already-reported one-time 1Password CLI login; this
Mac's working Developer ID/notary profile were used for the release.

**Latest release scope correction — November 5:** Josh requires a release-only
master command: engine/app build, Developer ID signing, app/DMG notarization,
GitHub publication and version/URL/checksum publication to the Homebrew tap.
No local install, app quit/open, runtime checks or Homebrew install/upgrade are
part of it. Josh upgrades manually. No quiet-window logic belongs in the script;
tonight's one-time coordination wait is finished. These directions supersede the
older install-on-publication and startup-promotion gates for this command and
1.1.0. Pristine artifact signatures, code hashes, source identity and actual Apple
acceptance remain verified; no startup acceptance is claimed. The installed
1.0.0 app/profile remain untouched by this release. See [the command](master-release.md).

**Latest direction — November 5:** Josh authorizes the final nightly **1.1.0**
release after remote main has been unchanged for 10–15 minutes. Root must use
and test the new [master release command](master-release.md), not manually run
the older pipeline. This supersedes the ready-signal hold below for that release.
Root continues alone on canonical main; the behavior crash remains assigned
elsewhere. The recurring refresh stays deleted. The command handles frozen
inputs, reviewed cumulative overlays, incremental shipping engine, production
signing/notarization, immutable publication, immediate profile-safe installation,
bounded startup, and Homebrew publication/upgrade. Credential portability still
requires actual one-time private-key provisioning and a synced notary profile;
the existing Mac's working credentials are sufficient for this release but are
not evidence of an iCloud backup.

**Latest authorized Homebrew test — November 5:** Josh asked for a real tap
upgrade without losing browser data, authorizing this specific existing-release
installation. Root upgraded 0.1.0 to 1.0.0 with
`brew upgrade --cask etsenake/tap/parc`. The closed profile was backed up and
verified first; all 4,348 files (666,436,194 bytes), directories and symlinks were
identical after Homebrew finished and before normal app launch. The prior app
and private profile backup remain retained. All 12 installed signed-image hashes,
Team `94HKA7L2DR`, stable requirement, strict signature, stapled ticket and
Gatekeeper checks passed. The installed app then stayed alive for 60.07 seconds
with no new app/helper crash reports; post-launch normal deep signing and hashes
passed. Homebrew now records 1.0.0. Receipts and the backup are in
`build/homebrew-upgrade-test-20261106T034702Z`. The separate behavior crash was
not investigated, no source/app rebuild occurred, and further builds still await
Josh's ready signal. This supersedes the earlier pending-upgrade status only.

**Current handoff — November 5:** Josh assigned the behavior-triggered crash to another
agent and explicitly stopped crash investigation here. Root and the focused
Homebrew agent continue only production release setup/tooling, documentation
and inert checks. No further app launch, replacement, engine/app build or
repackaging is authorized in this chat until Josh signals the new source is
ready. Preserve other agents' edits and the shared engine caches.

**User correction:** the crash was not a startup failure. Josh explicitly
confirmed that 1.0.0 launched and worked normally, then crashed when he
deliberately triggered a specific behavior during testing. Root's earlier
startup-failure classification was incorrect. The raw process/crash observation
is retained as an uncontrolled interval, and Josh's normal-startup confirmation
is recorded separately. The existing 1.0.0 release can be stable and promoted to
the tap without waiting for the separately owned behavior fix. No new app build
or installed-app change is being made here; Josh will signal the next ready
build. Future promotion accepts either an isolated passed observation or an
explicitly recorded user confirmation, bound to the exact release artifacts.

The official overlay 327 engine built and sealed from `ba53bf63` with three
incremental actions in 2m23.54s; source lock and shipping flags are unchanged.
Versioning and DMG/Homebrew tooling are published in `cd78e23e`. The
[v1.0.0 candidate](https://github.com/etsenake/parc/releases/tag/v1.0.0) contains
both ZIP and DMG. App submission `05dcbc42-4fdb-4d2b-814a-ee8d6d8e995c` and DMG
submission `9c612964-9edc-464a-8450-b37fcc915ac5` were accepted, stapled and
Gatekeeper verified. All production signing uses Team `94HKA7L2DR` and the
unchanged Developer ID requirement. Immediate installation/open occurred at
03:15:40 UTC November 6. Its observer recorded an exit at 20.05s with a new crash
report during Josh's deliberate behavior testing. Josh confirmed normal startup
worked; do not call this an isolated startup failure or an automated pass. The
legacy-key migration marker was observed; this does not establish encrypted
restart acceptance.

The authorized failure rollback completed at 03:17:12 UTC before Josh's stop
direction arrived, restoring the original notarized 0.1.0 app. That restoration
was based on root's incorrect interpretation of the uncontrolled observation.
No additional app changes are being made here while the other agent owns the
behavior investigation. The retained 1.0 artifact and latest pristine package,
raw reports and engine seals are preserved in
`build/install-1.0.0-production-20261106T030536Z` and
`build/app-1.0.0-production-20261106T030536Z`.

The public tap is cloned at `~/homebrew-tap`, with the bootstrap cask published
in `eabcc781d95d74fa065da5f10c9183454c276c05`; the existing 0.1.0 app was adopted
without replacing it. The 1.0.0 cask promotion uses Josh's explicit acceptance
of normal startup; it is independent of the specific behavior fix. The next
changed app needs a new immutable version, normally 1.0.1,
followed by the same signing, notarization, immediate installation, bounded
startup and Homebrew promotion checks. Recurring refresh remains deleted.

**November 5, current Mac production setup:** Josh transferred this chat's work
to root alone, directly on `main` in `/Users/josh.etsenake/parc`. No subagents or
new worktrees are used. Root owns the shared engine, production signing,
notarization, package publication, installation and checks on this Mac. The
previous Codex engine owner is interrupted. Existing contributor work remains
preserved. The production setup moves to Developer ID Application on the same
Team `94HKA7L2DR`, with accepted Apple notarization and a verified stapled ticket
required before publication. Completed packages are still installed/opened
immediately, with the bounded startup check and obsolete-copy cleanup.

**November 5, first notarized production delivery:** app source `e38d702a`
reuses the unchanged official ARM64 non-component overlay 326 seal and preserved
objects/caches. Published
[app-20261106T023749Z-e38d702a](https://github.com/etsenake/parc/releases/tag/app-20261106T023749Z-e38d702a)
was installed at `/Applications/Parc.app` and opened immediately at 02:43:27 UTC
on November 6. Apple accepted submission `4781fbea-90d7-4918-8264-91ff2cff226c`
with no issues. The ticket is stapled and validated, and Gatekeeper reports
Notarized Developer ID. The package and all 12 actual signatures use Developer
ID Application on Team `94HKA7L2DR`; strict pristine/staged/installed verification
passed before launch. The deliberate Apple Development-to-Developer ID
requirement transition is recorded; future production builds must retain the
same Team-based requirement. Post-launch normal deep verification and every
signed-image hash passed, preserving the custom Finder icon metadata.

The fresh installed process remained alive for 90.06 seconds with no new
app/helper crash reports. The private GitHub release/tag target and downloaded
asset digest were checked. macOS lists the installed app for HTTP, HTTPS, HTML
and XHTML; the new declarations do not change the user's default browser.
Superseded standalone app bundles were removed after verification, the newest
pristine package retained, and Spotlight lists only `/Applications/Parc.app`.
Receipts are in `build/app-326-production-20261106T023743Z` and
`build/install-production-20261106T023743Z`. The recurring refresh automation was
deleted at Josh's request. Josh subsequently requested a separate Homebrew tap,
upgrade/versioning setup and a 1.0 release after it; that agent owns this new
assignment. Root retains production delivery and the reported Safe Storage
label investigation. No family counts change.

**Current storage follow-up:** Josh reports that the new app still asks for
Chromium Safe Storage. The direct native CEF startup bypasses the wrapper's API
version configuration; the unset runtime version makes CEF skip the settings
names. Metadata-only Keychain inspection finds the Chromium item and no Parc
item. Root's correction explicitly configures shared OSCrypt names before
initialization and preserves the exact existing key in a distinct Parc-owned
Keychain account through normal user authorization. It leaves the Chromium
item, previous Parc keys and ciphertext intact, uses a nonsecret atomic marker,
and fails closed on denial/conflict. Fake-adapter policy checks cover migration,
retries/races and preservation; shipping-flag native compilation passes.
The first 1.0 candidate delivered this change and Josh confirmed normal startup;
he assigned a separately triggered behavior crash elsewhere. One Chromium approval may still be needed
during migration on another existing profile. Actual encrypted
restart and fully rendered/responsive browser acceptance remain unverified;
protected authorization has not been inspected or bypassed. See the
[namespace contract and checks](../tests/KeychainNamespace/README.md).

**Ownership transfer — October 28, requested by Josh:** dedicated Codex
`engine_owner` owns shared apply/build/seal/package, stage receipts, canonical
source freezes/advances, queue checks and engine documentation/publication.
Root coordinates and supervises. This one agent is retained and reused only for
this engine role; every other completed agent retires. Operations use
`/Users/josh/Parc` and existing `work/engine-source`; engine documentation is
published from existing `work/claude-kbd`. No new checkout is created.

**Previous November 5 Apple Development shipping refresh on this Mac:** source `2193db9c`,
overlay 326, is built, sealed, published as
[app-20261106T015401Z-2193db9c](https://github.com/etsenake/parc/releases/tag/app-20261106T015401Z-2193db9c)
and installed at `/Applications/Parc.app`. Canonical source remains
`/Users/josh.etsenake/parc`; the preserved workspace is
`/Users/josh.etsenake/ParcBuild/engine`. The official ARM64 non-component Release
engine built 23 incremental actions in 2m33.21s, including the native application
and dependent units and a 1m54.36s ThinLTO link. The source lock and official shipping
recipe are unchanged, and compiled objects/caches were preserved. The release
app's 334 Swift sources compiled with whole-module optimization.

The recorded Apple Development identity signs with real Team ID `94HKA7L2DR`.
The package report and all 12 actual code signatures match it and use hardened
runtime. Main app and ordinary helpers retain library validation; only the CDM
helper has its required exception, and Renderer/GPU JIT entitlements are checked.
Root strictly verified the source, staged and installed app before launch,
installed and opened it immediately at 01:58:12 UTC on November 6, then observed
its main process for 90.06 seconds with no new app/helper crash reports. After launch, normal deep
signature verification passed and all 12 installed code hashes still matched the
package. The actual designated requirement exactly matches the signed overlay
316 baseline. This verifies bounded main-process startup; the first normal Safe
Storage approval remains unverified. Agents did not inspect or bypass protected
authorization UI, and no window/browser functionality is claimed. Notarization and Widevine VMP host
signing remain absent; no VMP certificate or service is configured.

Stages, engine seal, signing/entitlement audit and exact artifact/release digests
are in `build/engine-326-signed-20261106T014702Z`. Delivery metadata distinguishes
the report's sorted-JSON manifest hash from the raw manifest-file hash. The
completed package is `build/local-20261106T015401Z/development`, and root's
installation/startup receipts are in `build/install-refresh-20261106T014525Z`.
After verification, root removed the superseded package app bundle while
retaining its report and engine receipts/caches, kept the latest pristine
package, and unregistered noninstalled app copies; search lists only the
installed app.
This build uses one frozen source snapshot; newer main changes,
including later engine work, belong to the next twenty-minute refresh. Published
guard `181cc48f` is included in this snapshot and requires a valid Apple-issued
identity and actual Team ID, refusing ad-hoc publication. Actual Apple signatures
and Team ID were independently checked. No family counts change.

**Overlay 286 engine and app — November 1:** overlay 283 (with 282's feature
policy) built 12:15–12:26 on the DCHECK-off workspace. Overlay 285's install
presenter failed to compile inside Chromium (`std::abs` without `<cmath>`);
`5fc88fa0` fixed it as overlay 286, built 12:44–12:52. Sealed and
release-packaged from app source `388a7b53` at
`build/local-20261101T185309Z/development/Parc.app` (development-component,
not distribution eligible, not executed). The macOS codec change follows as
overlay 287 in the next large build.

**Overlay 279 — October 31 (applied and built November 1):** fixes the DevTools mobile→desktop
renderer abort (SIGABRT, Sad Tab error code 6). A Blink overlay-scrollbar fade
timer from the emulated mobile theme fired after the page switched to the Mac
theme and failed a DCHECK. That DCHECK was fatal because Parc's engines kept
non-official DCHECKs before the `dcheck_always_on=false` source-lock change;
the scrollbar. Upstream Blink patch only; no Parc app source changed. Read-only `overlay-check` against
the v278 workspace passes. See [Engine DevTools notes](../Engine/README.md#native-devtools).

**Overlay 287 and codec source lock pending large rebuild — November 1, from
Cursor `cursor/platform-codecs`:** Josh chose H.264/HEVC/AAC through macOS's own
decoders and encoders, without bundling FFmpeg's H.264/AAC decoders or
OpenH264. Hangout services are approved alongside. The source-lock and
`SHIPPING_DEFINES` changes add `proprietary_codecs=true
ffmpeg_branding="Chromium" enable_ffmpeg_video_decoders=false
media_use_openh264=false enable_hangout_services_extension=true`.

`platform-codecs.patch` does six things:

- It routes every AAC profile to Chromium's AudioToolbox decoder in the GPU
  process, with HE-AAC layer selection and ADTS handling.
- It gives FFmpeg-demuxed AAC a sample format, so `src=` MP4 and ADTS configs
  stay valid without FFmpeg's decoder.
- It adds FFmpeg's raw ADTS demuxer and AAC parser (no decoder) to the
  Chromium-branded macOS arm64 FFmpeg, with the demuxer reading rate,
  channels and frame size (which packet timestamps need) from the first
  header.
- It relaxes media's Chromium-FFmpeg GN assert on macOS.
- It lets WebRTC encode H.264, Constrained Baseline included, with
  VideoToolbox.
- It drops the assumed software fallback for H.264 receive.

`scripts/build.py` refuses an engine whose `args.gn` lacks the new defines.

The [AAC decoder check](../tests/NativePlatformCodecs/README.md) compiles the
patched decoder, `ffmpeg_common.cc` and FFmpeg units with actual target flags
and links them to the current dev engine's FFmpeg, media and base objects. It
passes 142 assertions unsandboxed and the same 142 under Chromium's GPU seatbelt
profile. They include FFmpeg demuxing of MP4 and raw ADTS with defined
timestamps, header-only ADTS frames, and `Decode()` after a failed
`Initialize()`. It shows the renderer
profile refusing AudioToolbox. The two patched Blink WebRTC files pass
`-fsyntax-only` with the actual platform target flags. The EngineSource and
Packaging suites pass. `media/BUILD.gn` and `third_party/ffmpeg/BUILD.gn` wait
for the engine owner's GN run. An independent review is still needed before
publication.

Needs the engine owner: `reconfigure` with the previous lock, then
`overlay-apply`, then `build`. Josh's hold on new engine work applies.

Known gaps to verify after the build:

- renderer decoder selection, the Mojo hop and actual `<audio>`/`<video>`, MSE,
  HLS and WebRTC playback;
- no software H.264 decoder: 4:2:2 and 4:4:4 streams fail, High 10 probably
  does, and with hardware video decode disabled no H.264 plays;
- implicitly signalled HE-AAC without an `mp4a.40.5`/`.29` hint plays its
  AAC-LC core at half bandwidth (mono for v2), which overlay 291 below
  addresses;
- AAC Main, SSR and LTP are refused by AudioToolbox;
- HE-AAC's first decoded packet is 962 frames short (AudioToolbox drops its
  SBR delay), which overlay 291 below lines up with macOS's own decoding;
- WebAudio `decodeAudioData` of AAC and M4A is overlay 292 below.

See [macOS codec route](engine-flags.md#macos-codec-route).

**Widevine host signatures and CDM helper (overlay 289) — November 1, from Cursor
`cursor/widevine`:** Widevine already works as an unverified host: CEF compiles
in the key system and host verification, Chrome's component updater fetches the
CDM (Parc's profile holds 4.10.3112.0), and CEF's signature paths fall inside
`Parc.app`.

`scripts/build.py` now writes and checks the two VMP signatures, for the
framework and `Parc Helper (CDM)`, when a certificate and key or a signing
service is supplied. It records `unsigned` otherwise
same code).

Google signs the CDM, so a certificate-signed Parc needs a library-validation
exception to load it. The coordinator, for Josh, chose the narrow route over
`Parc Helper (CDM)`, through `cdm-helper.patch` (an internal content setter plus
an embedder flag) and a CEF browser-client hunk in `native-internal-urls.patch`.
The hunk checks at startup that the bundle has that helper, and otherwise keeps the
CDM in the default helper. Packaging signs that helper alone with
`disable-library-validation`.

Rebuild scope on macOS: six translation units. They are `service_factory.cc`,
`media_interface_proxy.cc` and `cdm_helper_impl.cc`, Chrome's and CEF's browser
clients, and `mac_notification_provider_factory.cc`. No content public header
changes. Both changed translation units pass `-fsyntax-only` with
their real target flags, and a read-only `prepare_overlay` replay accepts 289. It
needs the engine owner's apply and build, and packaging refuses older engines.
LEFT:

- **External:** Google's VMP certificate, which needs a Widevine license
  agreement (no fee, approval at Google's discretion).
- **Unverified:** that the CDM process actually starts in `Parc Helper (CDM)`
  and loads the CDM there, playback, the status license servers see, and whether
  the helper's flag-0 signature is what the CDM expects.

See [Widevine](engine-flags.md#widevine).

**Overlay 291, implicitly signalled HE-AAC, pending engine build — November 1,
from Cursor `cursor/implicit-heaac`:** HE-AAC and HE-AAC v2
whose config and container give only the AAC-LC core now play at full quality.
That covers AAC+ internet radio and `.aac` files through `src=`, MSE
`audio/aac`, MP4 and MPEG-2 TS without an `mp4a.40.5`/`.29` codec string, and
WebCodecs. The decoder judges by the first access unit that can be judged, as
Chrome's FFmpeg decoder does, and macOS's ADTS parser reads SBR from it in the
GPU process. The output matches FFmpeg's: twice the core rate, and stereo for a
mono core. `AudioRendererImpl` now takes that rate change for `src=`, as it
does for Media Source, but only for configs the decoder could double. Those
are AAC with no config at 24 kHz or less (raw ADTS), and bare two-byte AAC-LC
configs at a core rate of 24 kHz or less. Chrome never needs that, because
FFmpeg's decoder fixes the rate while the stream is being probed.

HE-AAC, signalled either way, now matches macOS's own decoding sample for
sample, as Josh chose. Its last 962 frames (22 ms) are no longer dropped at end
of stream. Priming, remainder and other discard padding land on the access
unit they belong to, as `ExtAudioFile` applies them. Chrome's FFmpeg decoder
starts the same audio 962 frames later. AAC-LC and HE-AAC samples are no longer
peak-limited, so HE-AAC v2 overshoot above 1.0 survives as in Chrome. Upstream's
limiter stays for xHE-AAC.

Implemented, not runtime-verified. The decoder, renderer and test compile with
their target flags. `prepare_overlay` validates 291 read-only against the
applied workspace. A standalone probe with the same detection code passes
unsandboxed and under the GPU seatbelt, including damaged input. Raw
AudioToolbox probes reproduced macOS's decoding bit for bit with the same tail
and alignment. The
[AAC decoder check](../tests/NativePlatformCodecs/README.md) has new cases for
it, and they wait for the engine build to finish. Its runner now prepares
sources file by file, so it accepts a checkout built with overlay 287.

Remaining:

- detection depends on Apple's undocumented parser behaviour;
- `src=` implicit HE-AAC is resampled to the device rate, and so is plain
  AAC-LC with a core of 24 kHz or less. With a Web Audio
  `MediaElementAudioSourceNode` it stays at the core rate and channel count;
- configs longer than two bytes, 960-sample frames, program-config-element
  layouts and cores above 24 kHz are not covered;
- WebCodecs gets HE-AAC output a chunk late, since each access unit's last 962
  frames wait for the next one; `flush()` returns the rest. Chrome outputs each
  chunk as it decodes it.

See [macOS codec route](engine-flags.md#macos-codec-route).

**Overlay 292, WebAudio AAC, built — November 1, from Cursor
`cursor/webaudio-aac`:** Josh asked for AAC/M4A through `decodeAudioData`, so
browser audio editors can import those recordings, without widening the renderer
sandbox. `webaudio-aac.patch` and the new `platform_audio_file_decoder.{h,cc}`
keep FFmpeg demuxing and Chromium's priming and padding trims in the renderer.
When FFmpeg can't decode a file and it is AAC, they send each packet to the GPU
process's AudioToolbox decoder through `MojoAudioDecoder`, as WebCodecs does,
with eight decodes in flight, and keep the decoder's rate and channels.
`MojoAudioDecoder` now accepts several decodes and `MojoAudioDecoderService`
answers them in order, feeding the decoder one at a time; playback sends one at
a time and is unchanged. A GPU process crash, an unreachable GPU process, a
refused stream or 30 seconds without an answer rejects with `EncodingError`.
rejected. Neither sandbox profile nor `platform-codecs.patch` changes. With
overlay 291's decoder, HE-AAC's tail, peaks and full rate (raw ADTS included)
need nothing more here: the
[WebAudio AAC check](../tests/NativeWebAudioAAC/README.md) requires every
fixture, HE-AAC included, to match macOS's `ExtAudioFile` to the frame and
sample. It compiles all seven patched units and its test with actual target
flags; the EngineSource and Packaging suites pass, and read-only
`prepare_overlay` accepts 292. Built into the November 1 overlay 292 engine,
where the check passed: 53 checks, no failures, every fixture equal to macOS's
decode to the sample. A 10-minute AAC-LC file decodes in a median 578 ms with
Parc's eight decodes in flight (950 ms one at a time); macOS's `afconvert`
takes 350–680 ms. Details in
[WebAudio `decodeAudioData`](engine-flags.md#webaudio-decodeaudiodata). The
Blink half that builds the `AudioBuffer` runs only in a renderer and hasn't
run. No known WebAudio gaps beyond the codec's own (AAC Main, SSR and LTP).

**Overlay 294 pending — November 1, from Cursor `cursor/top-band-color`
(renumber at publication):** adds Blink's `TopBandColorTracker` for ordinary
pages' outermost main frames, detecting only while the browser observes it
(`third_party/blink/renderer/core/frame/parc_top_band_color_tracker.*`,
`top-band-color.patch` hooking `LocalFrame`, `LocalFrameView`'s post-lifecycle
steps, `Document::FinishedParsing`, `Document::OnLargestContentfulPaintUpdated`
and `DocumentLoader::CommitNavigation`), `parc.mojom.TopBandColorAgent` in
`mojom_core`, the browser's frame sampler in `native_appkit_page.mm`,
`PCNativePage (TopBandColor)` with the sampled website's host (http or https
only), and `PCNativeHistoryDidDeleteNotification` for a regular profile's
history deletions (not expiry). All five Blink units and
`native_appkit_page.mm` pass `-fsyntax-only` with their targets' flags and
generated bindings (`tests/TopBandColor/run.py`); nothing is linked or run.

**Overlay 293 pending — November 1, from Cursor `cursor/split-chrome`
(renumber at publication):** `PCNativePage (PageBackgroundColor)` returns the
page's background as Chromium composites it (`WebContents::GetBackgroundColor`:
the root CSS background over white, or the dark canvas for `color-scheme:
dark`), nil only until the renderer first reports it for the document. The page
observer now notifies on `OnBackgroundColorChanged` and theme-colour changes
when the colour the pane top bar shows changes (`TopBarPageColor`), which the
shell notify filter used to drop. Pane and Peek bars use it after the declared
theme colour, through `browserViewDidChangePageColor:`, which repaints only the
bar ([page colour](split-groups.md#top-bar-page-colour)). `native_appkit_page.mm`
passed a single-TU `-fsyntax-only` compile against the engine tree, and the
facade syntax-checks against its CEF headers; `tests/PageShellNotify` covers the
filter and `tests/PageColorDelivery` the delivery path. Until it is built, pane
bars follow the declared theme colour only, a page without one has the
colourless bar, and a theme colour changed after load (YouTube switching to
dark) reaches the bar only with the next title, URL or loading change.

**v241 freeze — October 29:** dedicated engine owner freezes canonical source `7c22497bd16bed379e8e4f36855185b0789898a3` with published overlay 258 for apply, build, seal and package. Later publications remain queued; do not advance canonical until package completion.

**Next engine queue:** published overlay 262 at `32b6baa6` includes MEDIA12 admission overlay 260 and split separation. Isolated replay is preliminary; the official cumulative workspace check remains pending until the v241 package finishes. The engine owner will check the then-current published manifest before apply/build.

**Earlier pending source:** overlay 253 includes MEDIA12's overlay 249, MEDIA15's
overlay 251 and MEDIA16's genuine desktop and current-tab pickers with exact
delegated-session ownership. The affected MEDIA16 native and Chromium units
passed pinned compiler checks; 564 cumulative targets replayed forward and
backward without changing the shared engine. The dedicated owner applies/builds/seals/packages it; no runtime
acceptance is claimed.

**v240 / overlay 248 passed — October 29:** overlay 248 applied (57.53 s),
the four-job build passed (193.94 s), sealing passed (103.63 s) and release
packaging passed (1008.31 s) from clean frozen
`043b253f3b976b455abc32e134be263dc713b272`. Packaging finished at 19:33:36 UTC
(1:33:36 p.m. Edmonton). The artifact is
`/Users/josh/Parc/build/independent-v240/development-app-043b253`.
Engine manifest: `/Users/josh/Parc/build/independent-v240/engine-artifacts.json`.

This batch applies TOOLS14 DevTools pane focus-on-appear and TOOLS16 reader/
translation/print/save/data-dialog appearance, including
`native_popover_prompt*` and `native_page_tool_appearance.h`. Overlay hashes
for the four published DevTools pane files were refreshed before apply so the
reviewed source would take. Whole-module SIL on the frozen tree exited 0 in 96 s
with zero diagnostics. All 771 source/asset/pipeline inputs and 475 compiler
inputs stayed unchanged through packaging. All 148 resource files are
byte-preserved. Strict app and sibling-component signing passed for 519
pre-sign engine copies and 526 signed images. The packaged framework contains
`PCPopoverPromptTitle`/`Icon`/`Button`, `PCNativeDevToolsPaneView` and
`focusTools`. Receipts and artifact verification are in
`work/integrated-engine240`.

Canonical freeze is released; no pipeline remains active and earlier packages
are preserved. This development component package requires its sibling
libraries. No browser was executed or runtime-verified; standalone distribution
remains unclaimed.

**Final Easels package passed — October 29:** all 29 fixed Easel rows are
independently reviewed and delivered in the release package from clean frozen
source `e82e4f5e5482233fd5ec474a87813f916fc96ad2`. Packaging exited 0 in
477.52 s at 09:24:03 UTC (3:24:03 a.m. Edmonton). The final artifact is
`/Users/josh/Parc/build/independent-v239/development-app-e82e4f5`.
It includes EASEL26 keyboard/AX, EASEL27 appearance and EASEL28 motion alongside
all earlier completed rows. The unchanged v239/overlay247 seal was reused;
no Chromium rebuild was required.

All 259 Swift inputs match the finished 34-second zero-diagnostic SIL; all
361 compiler inputs and 758 source/asset/pipeline inputs stayed unchanged.
The audit verified all 148 resource files byte-for-byte, both required native
capture classes, all ten reviewed native icon outputs and the existing privacy
descriptions. The actual icon exporter compiled once and ran ten render/iconutil
pairs. Strict app and sibling-component signing passed for 519 pre-sign engine
copies and 526 signed images. Source/review provenance, actual package and
exporter receipts, final artifact verification and completion record are in
`work/integrated-engine239-easels-final`.

The final freeze is released; canonical is clean and no pipeline remains
active. Published app and Engine queues are empty at this delivery. Earlier
outputs remain preserved. **Stopped after Easels as Josh directed:** no next
family or further package is started. The dedicated engine owner remains
retained only for a future explicit engine assignment. This development
component artifact requires its sibling libraries; it was not executed or
runtime-verified, and standalone distribution remains unclaimed.

**v239 / EASEL23 integration passed — October 29:** overlay 247 applied
(57.38 s), the four-job build passed (228.96 s), and sealing passed (77.71 s)
from engine source `18b4012f0ce51884055d213c754805662c9a7b71`. Release app
packaging passed in 612.36 s from reviewed source
`a60c0157bba59882ed429a4b987ffdc43ca9b903`, including EASEL22 text fill and
EASEL23 live capture. It finished at 08:32:38 UTC at
`/Users/josh/Parc/build/independent-v239/development-app-a60c015`.

All 369 combined review inputs and 755 source/asset/pipeline inputs stayed
unchanged. All 148 resource files are byte-preserved, all ten native icons
match reviewed exports, and both new capture-layout/live-position native
classes are present in the packaged engine. Strict app and sibling-component
signing passed: 519 pre-sign engine copies and 526 signed images. Receipts,
export-symbol evidence and final artifact verification are retained in
`work/integrated-engine239`. This required EASEL23 engine/app integration is
delivered; its original author published row/contract closure at `11e5ebe0`.

**v239 guide/transfer app package passed — October 29:** release packaging
exited 0 in 575.34 s at 08:43:41 UTC from clean frozen
`e9221af7f35c4cf45b441408e20e85f66a75526d`, including reviewed EASEL25 guide
feedback and EASEL29 cross-Profile transfer alongside EASEL23's built native
integration. The artifact is
`/Users/josh/Parc/build/independent-v239/development-app-e9221af`.
The unchanged v239/overlay247 seal was reused without another Chromium build.

All 359 reviewed production inputs and 755 source/asset/pipeline inputs stayed
unchanged. The final 61-second zero-diagnostic SIL and independent CLEAR
receipt were reused. Both new native capture classes are exported; all 148
resources are byte-preserved, all ten icons match their reviewed outputs, and
strict app/component signing passed for 519 pre-sign copies and 526 signed
images. The package receipt, actual icon exporter invocations, source/review
coverage and final artifact verification are in
`work/integrated-engine239-transfer`.

Both earlier v239 package freezes are released and their outputs are
preserved. EASEL26's later app publication `ed60428d` was outside this guide/
transfer package; the final Easels package above now includes it together with
EASEL27 and EASEL28 using the same engine seal.
These development component packages require their sibling libraries. No
browser was executed or runtime-verified; standalone distribution remains
unclaimed.

**Final Screenshots/recordings package passed — October 29:** release
packaging exited 0 in 527.07 s from clean frozen
`0889e4a516503b3c0b1b0fbed72b0b2bdf9806bc`, including all reviewed CAP01–CAP24
source and final editing/motion integration. It completed at 07:33:59 UTC
(1:33:59 a.m. Edmonton), at
`/Users/josh/Parc/build/independent-v238/development-app-0889e4a`. Engine, bridge
and helper inputs were unchanged; the existing v238/overlay 246 seal was reused.

All 257 Swift files matched the final 29-second zero-diagnostic CAP24 checked
manifest; all 358 compiler inputs and 755 source/asset/pipeline inputs stayed
unchanged. The packaged Desktop/Documents/Downloads privacy descriptions match
the reviewed CAP23 values. All 148 resource files, including the three capture
cursor representations, are byte-preserved. Native load commands reference
macOS ScreenCaptureKit and QuickLookThumbnailing frameworks and the system Swift
UniformTypeIdentifiers library. All ten native icon hashes still match their
reviewed outputs. Strict app and sibling-component signing passed, with 519
pre-sign engine copies and 526 signed images. Actual exporter invocations,
source/review coverage, load commands, package and artifact-verification receipts
are retained in `work/integrated-engine238-capture`.

Canonical's freeze is released; no pipeline remains active and earlier outputs
are preserved. Published app/Engine queues are empty at this delivery. EASEL23
has reported an unpublished native dependency for authentic capture
viewport/crop/scroll/zoom metadata and guarded live-region positioning on the
existing embedded page; its feature owner retains implementation and checks.
The engine owner will batch its exact reviewed published handoff after release,
using the retained read-only pinned syntax helper for private author checks.
This development component package requires its sibling libraries. No browser
was executed or runtime-verified; standalone distribution remains unclaimed.

**Final Settings app package passed — October 29:** release packaging exited
0 in 554.23 s from clean frozen `052acfb01d337f8cd1b47167722c48121dd0be7f`,
containing all independently reviewed SET01–SET27 deliveries and the full local
membership card. It completed at 06:13:27 UTC (12:13:27 a.m. Edmonton), at
`/Users/josh/Parc/build/independent-v238/development-app-052acfb`. Engine, bridge,
helper and packaging inputs were unchanged, so the v238/overlay 246 seal was
reused without rebuilding Chromium or duplicating unchanged checks.

All 349 compiler inputs/248 Swift files matched the final 31-second,
zero-diagnostic author SIL base plus exact independently reviewed source. All
738 source, asset and pipeline inputs and the engine manifest stayed unchanged.
The packaged 144 resource files are byte-preserved, including all 18 new
membership-card and Settings PNGs. All ten native icon exports still match the
reviewed outputs, with Original as the main icon; the actual renderer compile,
ten exports and ten iconutil calls are retained. Strict app and sibling-component
signing passed, with 519 pre-sign engine copies and 526 signed images.

Stage, source/review coverage, artifact verification and completion receipts are
in `work/integrated-engine238-settings`. Canonical's freeze is released, no
pipeline remains active and earlier packages are preserved. At that delivery the app and engine queues were empty; the subsequent
Screenshots/recordings source is covered by the completed package above. This development component package requires its sibling libraries. No
browser was executed or runtime-verified; standalone distribution remains
unclaimed.

**Final App identity package passed — October 28:** release packaging exited
0 in 679.20 s from clean frozen `35a9b82685d055e0f9a62897d6c539c085f84c5e`,
including all reviewed ICON08–ICON11 deliveries. It finished at 05:15:52 UTC
October 29 (11:15:52 p.m. Edmonton October 28). The package is
`/Users/josh/Parc/build/independent-v238/development-app-35a9b82`; unchanged
engine/bridge/helper inputs reused the v238/overlay 246 seal without rebuilding
Chromium. Passing author SIL/component/packaging receipts were reused after
source verification. All 340 compiler inputs and 706 source, asset and pipeline
inputs, including `scripts/render_app_icon.swift`, stayed unchanged.

The actual package captured one `xcrun swiftc -warnings-as-errors -O` renderer
compilation, ten renderer exports and ten iconutil conversions. All ten packaged
ICNS hashes exactly match ICON09's independently reviewed native outputs; all
ten cleaned masters and both derived marks are byte-preserved, and the main
ICNS equals Original. Python 3.13.12 orchestrated the package; the renderer used
Xcode's Apple Swift 6.4. Actual commands, toolchain identity, source hashes and
artifact verification are in `work/integrated-engine238-identity` alongside the
stage receipt and completion record. Strict app and sibling-component signature
verification passed, with 519 pre-sign engine copies and 526 signed images.

Canonical's freeze is released and no package pipeline remains active. Earlier
packages are preserved. Published Engine inputs are covered through overlay 246;
later Settings source is outside this identity snapshot and is covered by the
completed Settings package above.
This development component package requires its sibling libraries. No browser
was executed or runtime-verified; standalone distribution remains unclaimed.

**Final Spaces/Profile app package passed — October 28:** release packaging
exited 0 in 578.35 s from clean frozen
`4462f062a21789b713a15060f44c0992a737e07f`, completing at 04:41:15 UTC October 29
(10:41:15 p.m. Edmonton October 28). This contains the complete independently
reviewed SPACE18 delivery, SPACE17 (`6117eb45`) and all earlier Space increments.
The package is `/Users/josh/Parc/build/independent-v238/development-app-4462f06`.
Engine, bridge, helper and pipeline inputs were unchanged, so it reused sealed
v238/overlay 246 without a Chromium build or duplicate unchanged checks.

All 339 compiler inputs/238 Swift files matched the final 28-second,
zero-diagnostic author SIL base plus exact independently cleared source; all
remained unchanged through packaging. The engine manifest also retained its
preflight hash. The report confirms app deep/strict and sibling-component strict
signature verification, 519 pre-sign engine copies and 526 signed images.
Receipts, source/review coverage and completion record are retained in
`work/integrated-engine238-spaces-final`. Canonical's source freeze is released,
no package pipeline remains active and all prior outputs are preserved. At that delivery the
published engine and app queues were empty; subsequent App identity source is
covered by the completed package above. This development component package requires its
sibling libraries; no browser was executed or runtime-verified, and standalone
distribution eligibility remains false.

**v238 Extensions and SPACE15/SPACE16 packages passed — October 28:** all
four engine/package stages exited 0 from clean frozen
`cc0a1fab4c65f4962a8926f1ab99cdb3b54e9d74`, overlay 246: apply 88.84 s, four-job
build 271.44 s, seal 101.58 s and release packaging 625.70 s. The full reviewed
Extensions source and required panel consumer are in
`build/independent-v238/development-app-cc0a1fa`, completed at 03:11:08 UTC
October 29 (9:11:08 p.m. Edmonton October 28). Engine manifest:
`build/independent-v238/engine-artifacts.json`. Stage receipts, review coverage
and the 43-second zero-diagnostic integrated SIL are retained in
`work/integrated-engine238`; all 335 compiler inputs/234 Swift files stayed fixed.

The requested app-only follow-up at `e88ca92f840cd570db39fea8c1c4b431b0ecbfc2`
includes reviewed SPACE15 (`4554d42b`) and SPACE16 (`e88ca92f`) and reused that
unchanged v238 engine seal. Actual packaging exited 0 in 568.52 s, finishing
03:21:54 UTC October 29 (9:21:54 p.m. Edmonton October 28), at
`build/independent-v238/development-app-e88ca92`. All three changed production
files matched SPACE16's reviewed final hashes and corrected author SIL, including
the SPACE15 dependency; unchanged inputs retained the prior integrated SIL
coverage. All 336 recorded compiler inputs/235 Swift files and the engine
manifest remained unchanged. Receipts are in `work/integrated-engine238-spaces`.
No duplicate Chromium build or unchanged checks ran.

Both package reports confirm app deep/strict and sibling-component strict
signature verification, 519 pre-sign engine copies and 526 signed images. They
are release-optimized development component packages requiring their sibling
libraries, not standalone distributions. Neither browser was executed or
runtime-verified. Both earlier source freezes are released, their pipeline operations are complete
and all earlier outputs are preserved. Published engine inputs are covered through
overlay 246. SPACE17 rendering/motion and the full SPACE18 management delivery
are now included in the final Spaces/Profile package above. These earlier
package snapshots retain their original source and receipts.

**v237 Extensions engine batch passed — October 28:** overlay 245 apply,
the four-job engine build, sealing and release packaging all exited 0 from
`d16b2f52a4c8c788b2daa8479a8b338819653d82`. Durations were 53.04 s, 143.61 s,
80.88 s and 661.58 s; packaging finished at 02:35:39 UTC October 29 (8:35:39 p.m.
Edmonton October 28). Canonical stayed clean and unchanged through the pipeline.
The snapshot includes reviewed EXT14 side-panel focus guard (`726001d2`), EXT12
32-point icon/popup-anchor increment (`758dfb6d`), EXT13 interactions (`e44badeb`)
and SPACE13 appearance parent (`83c530b2`). Both changed native units matched
passing pinned compiler receipts. The earlier common app snapshot passed a
54-second whole-module SIL check; EXT12's 50-second final SIL covered the finished
source, with all 333 compiler inputs/232 Swift sources and reviewed deltas checked.
Receipts, source manifests and runner are in `work/integrated-engine237`.
The engine manifest is `/Users/josh/Parc/build/independent-v237/engine-artifacts.json`;
package `/Users/josh/Parc/build/independent-v237/development-app-d16b2f5`.
Its report confirms 519 pre-sign engine copies, 526 signed images and app
deep/strict plus sibling-component strict verification. It is release Swift with
`development-component` classification: keep the sibling libraries with the app.
No browser was executed or runtime-verified. Previous outputs remain intact;
the v237 source freeze is released and no pipeline operation remains.

**Next engine/app coverage:** newer reviewed SPACE14 `d1694ea0` is app-only and
is outside the v237 package snapshot. No later engine inputs are published at
this delivery. EXT14 has reported an unpublished exact-selected/key-window
side-panel close API, plain-Escape handling and scoped header/content focus
restoration; EXT12 owns the actual panel header/body consumer. Those active owners
continue checks/review and will publish exact source/receipt handoffs to the engine
owner. The next required batch uses reviewed published inputs without retargeting
finished packages or treating an engine/package pass as feature-row completion.

**v236 Extensions engine batch passed — October 28:** overlay 243 apply,
the four-job build, sealing and release packaging all exited 0 from canonical
source `a3d80734edd6a677c95d87d9a05f54f45be01e78` (reviewed EXT11 `5d3d0c6c`
plus documentation). Durations were 105.97 s, 185.97 s, 91.52 s and 728.50 s;
packaging finished at 02:17:13 UTC October 29 (8:17:13 p.m. Edmonton October 28).
The manifest is `/Users/josh/Parc/build/independent-v236/engine-artifacts.json`;
package `/Users/josh/Parc/build/independent-v236/development-app-a3d8073`.
Receipts, logs, runner and preflight are in `work/integrated-engine236`.
The package verifies 519 pre-sign engine copies and 526 signed images with app
deep/strict and sibling-component strict signatures. It is release Swift with
`development-component` classification; keep the sibling libraries with the app.
No browser was executed or runtime-verified. The v236 source freeze is released.

The subsequent reviewed overlay 245 and app inputs are now in the separately
frozen v237 batch above; v236 retains its original source and receipts.

**v235 Automatic archive package passed — October 28:** release packaging
of reviewed family delivery `081cc06c45d5f66bf47f514dd90ca81fb05f8273` exited 0
at 01:44:07 UTC October 29 (7:44:07 p.m. Edmonton October 28), after 735.39 s.
Canonical stayed clean at that source throughout. All 333 final whole-module
SIL inputs matched, including 232 production Swift files; all 13 exact source/
test hashes in the independent AUTO11/AUTO12 CLEAR reviews also matched.
Engine, bridge and pipeline inputs were unchanged from sealed `3301647a`, so
v235/overlay 242 was reused without another Chromium build. Exact receipts and
preflight are in `work/integrated-engine235-auto`; the completed package is
`/Users/josh/Parc/build/independent-v235/development-app-081cc06`.
Its report confirms 519 pre-sign engine copies, 526 signed images and successful
app deep/strict plus sibling-component strict verification. This is a release
Swift `development-component` package: keep its sibling libraries with
`Parc.app`. No browser launch or runtime verification occurred. Previous packages
are preserved. The source freeze is released and no pipeline operation remains.
No later engine inputs are published at this delivery. EXT11 installation/
presenter and EXT14 side-panel owners have reported pending engine changes;
`engine_owner` will batch the reviewed published inputs for the next engine
apply/build/seal/package while feature owners continue their own publication.

**v235 final recovery package passed — October 28:** KB38 published as
`d886b312`; canonical advanced cleanly to app source
`8c35faf7028d7aea54ce01af948d497d3a083914` (that source plus the first package
result documentation). Final release packaging exited 0 after 520.99 s at
00:41:45 UTC October 29 (6:41:45 p.m. Edmonton October 28). The owner independently
matched all 647 inputs from KB38's successful final SIL receipt, including all
229 production Swift files. Engine, bridge and pipeline inputs remain identical
to sealed source `3301647a`; the completed overlay 242 engine was reused.
Separate stage receipts/preflight are in `work/integrated-engine235-final`;
the final output is
`/Users/josh/Parc/build/independent-v235/development-app-8c35faf`.
Its package report records 519 verified pre-sign engine copies, 526 signed
images, app deep/strict and sibling-component strict verification passed,
release configuration and `development-component` classification. Keep the
sibling libraries with `Parc.app`; this is not a standalone distribution and
was not executed or runtime-verified. The first package and its original stage
receipts remain intact. No engine/package process remains, the canonical freeze
is released, and the engine owner can fast-forward canonical to published main.
There are no engine inputs queued beyond the v235 seal at this delivery.

**v235 first recovery package passed — dedicated engine owner, October 28:**
overlay 242 apply, the four-job build and sealing exited 0 from clean canonical
engine source `3301647a69dd2eb7851a22f11c46848194368272` (104.15 s, 220.22 s,
125.21 s). Release packaging against that unchanged seal exited 0 from app
source `3fdd45799b595ce4a7d8991a17bee2d0b36d5eaf` at 00:30:58 UTC October 29
(6:30:58 p.m. Edmonton October 28; 731.13 s). The actual 227 Swift sources match
the successful final whole-module SIL manifest; 101 native/bridge headers match
retained receipts. Per-stage results and `package-preflight.json` are in
`work/integrated-engine235`. The engine manifest is
`/Users/josh/Parc/build/independent-v235/engine-artifacts.json`; the package is
`/Users/josh/Parc/build/independent-v235/development-app-3fdd457`.
Its report verifies app deep/strict and sibling-component strict signatures,
526 signed images and `development-component` classification. Keep its sibling
libraries with `Parc.app`; this is not a standalone distribution. No browser was
executed or runtime-verified. Python is `/opt/homebrew/bin/python3.13` (3.13.12).
That first package freeze ended successfully. KB38 is outside this earlier
snapshot and is included in the successful final package above. Preserve this
package and its stage receipts. Only new engine inputs require a new engine batch.

**v234 finished successfully (Claude, engine owner):** overlay apply, the four-job build and sealing exited 0 at source `62af8131fe9c4b8e662a99f31ea60bd7a2f55865` (apply 06:59–07:02, build to 07:07, seal to 07:10 UTC October 28), building overlay version 241 with WEB16 (`5b50d77`), WEB15 (`b2b3f07`) and WEB19 (`712d10e`). The first release packaging refused (07:17) because `d153903` read `plan` before `self.init` in `BrowserWindowController.swift`, a definite-initialization error that `-typecheck` does not raise. After the fix (`bf0cd5e`), packaging against the same sealed engine exited 0 from app source `7e9983afb64734117115e68bd293b30e6fa30433` (07:19–07:33, 843 s; no `Engine/` change since the sealed source). Receipts are in `work/integrated-engine234` (first attempt kept as `package-attempt1.*`). The engine manifest is `/Users/josh/Parc/build/independent-v234/engine-artifacts.json` and the development package `/Users/josh/Parc/build/independent-v234/development-app-7e9983a` (not executed). No engine apply or build is running, and the v234 freeze of the canonical checkout has ended.

**v233 finished successfully (Claude, engine owner):** overlay apply, the four-job build, sealing and release packaging all exited 0 at source `56c28ecc4c73c45a3c08d85e5ab55c6c9181fea0` (apply 03:25–03:29, build to 03:35, seal to 03:37, package to 03:46 UTC October 28; receipts in `work/integrated-engine233`). It applied overlay version 238, which builds every engine source published since v232: NAV11 (`6113e6a`), WEB17 (`2177afa`), WEB14 (`1223c77`), WEB15 (`9df042d`) and SP27's `PCNativePage (SecureContext)` (`56c28ec`); their pending applies are now built. The engine manifest is `/Users/josh/Parc/build/independent-v233/engine-artifacts.json` and the development package `/Users/josh/Parc/build/independent-v233/development-app-56c28ec` (not executed). No engine apply or build is running, and the v233 freeze of the canonical checkout has ended.

**v232 finished successfully (Claude, engine owner):** overlay apply, the
four-job build, sealing and release packaging all exited 0 at source
`d3e8297905dbce7d69cdf01d3aead8e4a201e428` (apply 18:38–18:40, build to 18:46,
seal to 18:48, package to 18:59 UTC; receipts in `work/integrated-engine232`).
It applied overlay version 233, including the Downloads DL33 engine source
below. The development package is
`/Users/josh/Parc/build/independent-v232/development-app-d3e8297` with
`package-report.json`; it was not executed. No engine apply or build is
running, and the v232 freeze of the canonical checkout has ended.

**Engine owner: Codex root, transferred October 28 at the user's request to
continue Claude's session-limited work.** Claude previously held this role
from October 27. Codex root applies and builds from the canonical checkout
`/Users/josh/Parc` advanced to current main, with receipts in
`work/integrated-engine231` onward, using the same supported commands
(overlay apply, four-job build, seal-engine, release packaging) and the rules in
the [collaboration guide](collaboration.md#shared-engine-and-cleanup). Other
owners keep publishing engine overlays from their own checkouts and recording
them below. **v231 compiled, sealed and packaged successfully** from source
`12afb77a5b141f840d51a6e3761d7f962ae67532`: overlay apply 11:55–11:59 UTC (196 s),
four-job build to 12:06 (435 s; 39 steps), seal-engine to 12:09 (184 s) and
release packaging to 12:20 (655 s), all exit 0; receipts and `run.sh` in
`work/integrated-engine231`. The engine manifest is
`/Users/josh/Parc/build/independent-v231/engine-artifacts.json` and the
development package `/Users/josh/Parc/build/independent-v231/development-app-12afb77`
(with `package-report.json`; not executed). v231 includes every engine source
published since `da37e92`: TAB20 `ReopenedPeek`, TAB21 `routedLinkCreation`,
TAB16 `mediaSessionStatus` and Sidebar round 4's `PCNativePage
(RenderFrameViewport)`; those pending applies below are now built. The
canonical checkout stays at `12afb77` until the next engine owner build.
Before the transfer, Codex root stopped (user report). **v230 finished successfully** after the
note below was written: overlay apply, the four-job build, sealing and release
packaging all exited 0 at source `da37e9276055248279204ae96a4ec658cec19d8d`
(apply 05:03–05:10, build to 05:33, seal to 05:39, package to 06:21 UTC; receipts
in `work/integrated-engine230`). The development package is
`/Users/josh/Parc/build/independent-v230/development-app-da37e92` with
`package-report.json`; it was not executed. No engine apply or build is running.
v230 does not include the engine sources published after `da37e92`: the
pending applies below (TAB20, TAB21, TAB16) and Sidebar round 4's
`PCNativePage (RenderFrameViewport)` overlay (`9c9a536`; see the Sidebar
handoff note). The v230 freeze of the canonical checkout ended with its packaging.

Codex root owned the shared pipeline (last note follows). **v229 compiled, sealed and packaged
successfully** from checked source
`a9ee54989201cd1422036a35266975bac47c8402`, including the external-URL Split
receiver handoff and Claude's preceding sidebar geometry transaction. The
540-target overlay applied successfully; the incremental build passed in 905.24
seconds total, with 9 executed build steps and 97,494 unchanged actions skipped.
Sealing passed in 424.70 seconds; release app packaging passed in 4,900.31 seconds.
The development package and sibling libraries are at
`/Users/josh/Parc/build/independent-v229/development-app-a9ee549`, with strict
signature verification recorded in `package-report.json`. It was not executed.

**v230 is now applying/building for the onboarding password choice** at frozen
source `da37e9276055248279204ae96a4ec658cec19d8d`. The canonical checkout
`/Users/josh/Parc` and shared engine inputs must stay at that source through
build, sealing and packaging. Root's independent `parc-completion-audit`
checkout continues Onboarding work and publication without changing that freeze.
Other owners continue publishing normally from their own delivery checkouts.

The pipeline uses the supported overlay/apply, four-job incremental build,
seal-engine and release packaging commands. It stops on the first failure.
Current start/result receipts and logs are in `work/integrated-engine230`;
planned output is `/Users/josh/Parc/build/independent-v230/development-app-da37e92`.
No completion or browser-runtime claim is made before those receipts exist.
Version230 is consumed. The preceding completed v229 engine manifest remains at
`/Users/josh/Parc/build/independent-v229/engine-artifacts.json`, with its receipts
in `work/integrated-engine229`.

**Engine change applied, from Claude TAB20 (Reopen a closed Peek):** the
engine source is published. It adds
`-[PCNativePage openPeekWithURL:]` in a new `PCNativePage (ReopenedPeek)`
category in `native_appkit_bridge.h`, implemented in `native_link_routing.mm`.
The method checks the shell's `canPresentPeekFrom:` for that exact parent, then
opens the HTTP(S) URL from the parent's own WebContents
(`NEW_FOREGROUND_TAB`, browser-initiated). The ordinary navigator records the
parent as the created page's source, and the method marks only that page for
the existing posted Peek offer (`containerForPage:` → `adoptPeek`). Profile,
window and opener ownership are unchanged, and no navigation session is
restored. `Engine/ParcHost/overlay.json` hashes are updated. Swift checks
`responds(to:)`, so the current v229 package records no Peek reopen. Status: applied and built (in the November 1 overlay 286 engine). Details: [Reopen Closed Tab](reopen-closed-tabs.md#closed-peeks-folders-and-the-cache-lifetime).

**Engine change applied, from Claude TAB21 (routed link creation):** the
engine source is published. It adds the read-only `BOOL routedLinkCreation`
to the existing `PCNativePage (CreatedPage)` category in
`native_appkit_bridge.h`, implemented in `native_link_routing.mm` as the
page's `CreatedPage::routed_creation_`. It is YES only when
`creationSourcePage` was carried into another Space by a matched current-link
as active-before. No request, Profile, opener or window ownership changes.
`Engine/ParcHost/overlay.json` hashes are updated. Swift checks
`responds(to:)`, so an older package keeps the earlier same-Profile referrer.
A syntax-only compile with the pinned GN command and this checkout's headers
passed. Status: applied and built (in the November 1 overlay 286 engine). Details: [creation ownership](folder-commands.md#same-profile-routed-creation-across-physical-windows).

**Engine change applied, from Claude TAB16 (Favorite music particles):** the
engine source is published. It adds `PCNativeMediaSessionStatus` (active,
the read-only `mediaSessionStatus` to the existing `PCNativePage
(MediaControls)` category in `native_appkit_bridge.h`, implemented in
`native_media_controls.mm` as `MediaState::Status()`. It reads the exact page's
Chromium session through `GetMediaSessionInfoSync` behind the same ownership
gate as `mediaState`. A missing, closed, retiring or foreign page, and an
and dismissal are neither read nor changed. The first read creates the page's
existing media observer, so later transitions publish through the coalesced
`nativePageDidChange`; such a page now also publishes its media metadata,
action and audio-state changes. `Engine/ParcHost/overlay.json` hashes are updated (the bridge
header over current main); no overlay version was claimed. Swift checks
`responds(to:)`, so an older package keeps the particles hidden. A syntax-only
compile with the pinned GN flags and this checkout's headers passed; nothing
was linked. Status: applied and built (in the November 1 overlay 286 engine). Details: [Favorite tile presentation](saved-tabs.md#favorite-tile-presentation).

**Engine change applied, from Claude Downloads DL33 (DownloadToLibrary arrival
and download prompt default):** the engine source is published. It adds
`PCNativeDownloadArrival` and the window client's
`-nativeBrowser:downloadDidBegin:` in `native_appkit_bridge.h`, implemented in
the new `native_download_arrival.h/.mm` (listed in `native-host.patch`'s
BUILD.gn sources), and a `Created` callback in `NativeDownloads`
(`downloads.cc/.h`) that fires only for a genuine `OnDownloadCreated` with a
live initiating document, never for history, imports or constructor
enumeration. The receipt is admitted once at creation (key window, visible
original page, Profile/OTR context, no security reservation), resolves the
hovered anchor's centre in an isolated world (mouse location otherwise), and
re-checks identity only. `native_appkit_application.mm` wires the regular and
private managers and stops seeding `download.prompt_for_download` true; a
one-time `ClearSeededDownloadPrompt` pass per persistent Profile directory
clears the previously seeded value. `tests/NativeDownloads/downloads_unittest.cc`
covers history and detached items never arriving. `Engine/ParcHost/overlay.json`
is version 233 with every touched hash updated; a read-only `prepare_overlay`
validates it. Syntax-only compiles with the pinned flags pass; nothing was
linked. An older engine never calls the delegate, so the arrival simply does
not play, and the prompt default changes only after the build. Status: applied and built in v232. Details: [arrival](download-library.md#original-downloadtolibrary-arrival).

**Engine change applied, from Claude NAV11 (alternate navigation destination):**
the engine source is published. `native_appkit_page.mm` opens a history-row
alternate with `NEW_BACKGROUND_TAB` instead of `NEW_FOREGROUND_TAB`. It also
gives each alternate Back/Forward/Reload/history clone a one-page receipt,
`PCNativePage.alternateNavigationSourcePage` and
`alternateNavigationPlacesAtTop` (declared in `native_appkit_bridge.h`).
`Engine/ParcHost/overlay.json` is version 234 with both hashes updated. The
pinned-flag syntax-only compile passes; nothing was linked. Swift checks
`responds(to:)`, so an older engine keeps the earlier behavior: a foreground
history alternate and no referrer. Status: applied and built (in the November 1 overlay 286 engine). Details:
[alternate destination policy](navigation.md#alternate-destination-policy).

**Engine change applied, from Claude WEB17 (hang sheet text):** the engine
source is published. `native_appkit_application.mm`'s hang sheet now takes
Chromium's own `HungRendererDialogView` strings (plural title and body, the
pages sharing the hung process through `GetHungWebContentsList` /
`GetHungWebContentsTitle`, Wait as default, Exit Page), and
`native-host.patch` adds `//chrome/browser/ui/hung_renderer` to
`libcef_static`'s deps. `Engine/ParcHost/overlay.json` is version 235 with the
three hashes updated (the patch replays to its recorded `cef/BUILD.gn` hash).
The pinned-flag syntax-only compile passes; nothing was linked. No Swift or
bridge interface changed, so an older engine keeps its earlier sheet text.
Status: applied and built (in the November 1 overlay 286 engine). Details: [failure surfaces](web-interactions.md#failure-and-recovery-surfaces--web17).

**Engine change applied, from Claude WEB14 (Site Control Center rows):** the
engine source is published. `native_page_info.mm` adds a headless genuine
PageInfo session per page (`SiteControls`, a `PageInfoUI`) behind the new
`PCNativePage (SiteControls)` category in `native_appkit_bridge.h`
(`openSiteControls(handler:)`, `toggleSiteControlsPermission(_:revision:)`,
`closeSiteControls`). It publishes PageInfo's permission rows, toggles one
through `OnSitePermissionChanged`, builds Automatic Picture-in-Picture from the
profile's content setting until PageInfo lists it, ends on navigation or page
change and closes with `OnUIClosing` (Chromium's reload infobar).
`Engine/ParcHost/overlay.json` is version 236 with both hashes updated. The
pinned-flag syntax-only compile passes; nothing was linked. Swift checks
`responds(to:)`, so an older engine shows the Site Control Center without
PageInfo rows. Status: applied and built (in the November 1 overlay 286 engine). Details: [Site Control Center](web-interactions.md#site-control-center--web14).

**Engine change applied, from Cursor `cursor/document-close` (CWS installs
are not Library downloads):** `NativeDownloads` no longer publishes Chrome
Web Store CRX transfers (`IsExtensionDownload`,
`application/x-chrome-extension`, `.crx` targets). Those stay on Chromium’s
installer/consent path and appear as Site Control Center 48×32 tiles.
`Engine/ParcHost/overlay.json` hashes for `downloads.cc` and
`downloads_unittest.cc` are updated. Status: published, applied and built (in the November 1 overlay 286 engine).

**Engine change applied, from Claude WEB15 follow-up (mailto prompt title,
login fonts and proxy title):** the first WEB15 engine source (`9df042d`) is
built in v233. The follow-up is published: `site_permissions.mm` titles a
mailto protocol-handler request "Make <site> your default mail app?" by
reading the scheme through `RegisterProtocolHandlerPermissionRequest::handler()`,
which the new host patch `native-protocol-handler-request.patch` adds (and
`BUILD.gn` adds `//components/custom_handlers` to `native_permissions`);
auth engine unit test follows. `Engine/ParcHost/overlay.json` is version 239,
with every hash current. The pinned-flag syntax-only compile passes against the
patched header; nothing was linked. No Swift or bridge interface changed.
Status: applied and built (in the November 1 overlay 286 engine). Details: [dialogs and permissions](web-interactions.md#dialogs-authentication-certificates-and-permissions--web15).

**Engine change applied, from Claude WEB19 (permission prompt press
feedback):** the engine source is published. `site_permission_presenter.mm`'s
prompt buttons draw at 75% while pressed, the press feedback of the SwiftUI
`Engine/ParcHost/overlay.json` is version 240, with every hash current. The
pinned-flag syntax-only compile passes; nothing was linked. No Swift or bridge
interface changed. Status: applied and built (in the November 1 overlay 286 engine). Details: [surface motion](web-interactions.md#surface-motion-hover-and-haptics--web19).

**Engine change applied, from Claude WEB16 (webpage menu, status pill and
banner disposition):** the engine source is published.
`native_appkit_page.mm` supplies its link outcomes; `native_confirm_infobars.mm`
no longer presents a shelf and adds `PCNativePage (TabSharing)`;
`native_tab_sharing.{h,mm}` keeps only Share This Tab Instead; and
`native_blocked_popups.mm` is now comment-only (its `PCNativePage
(BlockedPopups)` category is removed). `native_appkit_bridge.h` gains the
observer's split methods and `PCNativeStatusTextThemeSource`; `BUILD.gn` adds
QuartzCore to `native_components`. `Engine/ParcHost/overlay.json` is version
241, with every hash current. The pinned-flag syntax-only compile passes for
all six units; nothing was linked. The facade checks `respondsToSelector:`,
so an older engine shows no share button, while its old shelf and chooser stay
until the apply. Status: applied and built (in the November 1 overlay 286 engine). Details: [WEB16](web-interactions.md#context-menus-hovered-status-and-banners--web16).

feature states, overlay 282):** `native_startup_policy.h` now enables
`CertificateTransparencyAskBeforeEnabling`, which turns on Certificate
Transparency enforcement. It disables `MacAppCodeSignClone`,
`MacAppCodeSignCloneRenameAsBundle`, `FedCm`, `AutofillServerCommunication`,
`PreloadMediaEngagementData`, `BrowsingTopics`, `NetworkTimeServiceQuerying`,
`LiveCaption`, `MerchantTrust`, `PageInfoAboutThisSite`,
`PageInfoAboutThisSiteMoreLangs` and `TailoredSecurityIntegration`. This matches
Chromium `BASE_FEATURE`. These states are defaults: a feature named explicitly in
`--enable-features` or `--disable-features` keeps that state, while the product
group on November 1, so `Glic`, `GlicActorUi`, `AutofillActorMode` and
`LensOverlay` join those exclusions. Once applied, no
launch-time bundle clone is made, so the transient code-sign cleanup helper seen
at quit in the v55 and v67 runs no longer launches.

The same overlay carries Josh's other November 1 decisions (see
[Fixed scope](#fixed-scope)). On-device search suggestions return: the two
`OmniboxOnDeviceHeadProvider*` exclusions are gone, `NativeLocationBar` no
longer refuses construction when the provider is enabled, and the command bar
adds the on-device head provider under Chrome's own gate. Page translation is
excluded: startup adds `--disable-translate-trigger` and excludes
`TranslateRankerQuery` and `TranslateRankerEnforcement`; `translate.enabled`
defaults to off; the page menu drops Translate; `NativeBrowserWindow` refuses the
translate bubble; and `native_translate.{h,mm}`, its GN target and the
engine's translated-site reset API are removed with the Settings button.
`libcef_static` now names its remaining `translate_pref_names` dependency
directly instead of reaching it through the removed target.

`native_popover_prompt.{h,mm}`, whose only caller was the translate popover,
are removed too; site permission prompts build their own card.

`Engine/ParcHost/overlay.json` is version 282, identity `25a5bf25…0b2e`. It
follows main's overlay 280 (extension install) and 281 (Site Control Center).
Read-only `prepare_overlay` against the built v279 workspace accepts it: 17
targets change, 13 from this batch (including `cef/BUILD.gn` through
`native-host.patch` and the Parc `BUILD.gn`) and four from 280 and 281, and the
two `native_translate` and two `native_popover_prompt` files retire. This
batch is not a one-file increment: about 38 of 95 Parc native translation units
include a changed header, and both `BUILD.gn` changes regenerate GN. Pinned-flag
syntax-only compiles pass for the 42-assertion regression and the six changed
engine translation units, checked through a clang VFS overlay of the worktree
sources; nothing was linked.

Josh's other November 1 decisions: proprietary codecs (`proprietary_codecs=true`,
`ffmpeg_branding="Chrome"`) go into the next large engine rebuild, not a build of
Parc's page host handles cache restores and measure its memory (PERF07). Pinned
CEF already disables `GlicActorUi`, `AutofillActorMode` and `LensOverlay` in the
browser process. These are behaviour and parity changes, not measured savings.
Every flag and decision: [engine flags](engine-flags.md).
Separately, `scripts/build.py` now also sets `LSEnvironment` `MallocNanoZone=0`
without an engine rebuild. The Settings removal of **Reset Translated-site
Prompts** is Swift-only and can ship before the engine: without a Google API key
Chromium already never offers translation, so there are no choices to reset. The
engine's removal of that API must not ship before the Swift removal. Status: applied and built (in the November 1 overlay 286 engine).
Details: [startup policy](../tests/NativeHelperRouting/README.md).

## Reference and current work




**Current engine integration:** v228 compiled, sealed and packaged successfully at source `f45d354`, replacing v225 as the latest development package. It includes original-page Find results and cold-profile download settings. App deep/strict and sibling-component strict signature verification passed; the package was not executed. Compile took 305.26 seconds, sealing 57.88 seconds and packaging 2512.78 seconds. See [shared engine ownership](#shared-engine-ownership) for receipts, package path and the released freeze. Later Swift source is independently published on main and requires app packaging to appear in a runnable package; it does not by itself require another Chromium build. No browser functional test ran.

**Page translation (excluded November 1):** Parc no longer offers or performs
page translation; see [Fixed scope](#fixed-scope). The page-owned AppKit
translate popover (`native_translate.mm`), its `native_popover_prompt*` chrome
and the Settings translated-site reset were removed; site permission prompts
`0x68e6bd0`, `0x68e6c70` and `0x68e6cac` identify translate, revert and supported
languages. Reader viewing stays Chromium DOM-distiller; Print/Save stay IDC_PRINT /
IDC_SAVE_PAGE; Save-to-PDF is the print-preview picker; profile Clear Browsing
Data is Chromium WebUI and the private-profile copy uses the shared 430×180
AppKit decision sheet. No visual or runtime acceptance is claimed.

**Password management entry points:** the command bar's Manage Passwords action
and Settings button open the actual `chrome://password-manager/passwords` page
in the originating Space/profile. An existing available manager in that same
Space/profile is selected without discarding its detail view or edits; another
`ev_f3f33e55cb701d3ba8d50055a84c51c2dac78791849d69fe5e5857f86732c885`
has an incomplete jump-table recovery; retained instructions establish the
the key-icon command and actual Chromium password-manager WebUI, displayed by
import/export and macOS reauthentication. This source integration does not claim
whole-shell layout/motion parity or new functional browser-test results.

**Capture picker mechanism:** native screen/window selection retains Chromium's
picker at `0x553e6ec`, installs selection/cancel/error callbacks at `0x553e734`,
sets the screen/window modes at `0x553e900`/`0x553e814`, and presents it at
`0x553e850`/`0x553e93c`. REA evidence
`ev_d18cb85d6c83722958d61034caee7ba5fa388e187ede2aa52cdbede9b75e3fcc`
and the retained instructions establish that mechanism. Parc consumes actual
offered sources/thumbnails, policy restrictions and audio options; document,
profile, page and native-window changes cancel the request. Chromium's registered
factory retains ordinary Chrome fallback without adding a Chrome-to-CEF build
dependency. The surrounding 640-by-430 AppKit list/preview layout is an explicit
motion remain owned by macOS. No functional browser test was run for this batch.


Chrome extension support is part of this P0 architecture gate: installation, permissions, toolbar placement/pinning, popups, commands, tabs/windows APIs, lifecycle and profile isolation. The candidate stock embedded-CEF route has browser-window/extension limitations; this is a reason to retain or implement the needed Chromium browser machinery, not to defer or remove extensions. Choose and verify the native embedding architecture against these requirements.


This ledger is intentionally open-ended. Each family includes small interactions that need their own comparisons: hover and press states, focus, dismissal, keyboard navigation, drag feedback, timing, animation curves, persistence, error recovery and accessibility. No row below claims complete parity.

Current P0 source milestone: the independent engine has built and linked through v69; v70 validates reused production outputs, both fresh development packages pass signing/provenance, and its actual engine-to-shell selection/action harness passes. The production native factory, Objective-C facade, Swift shell, helper and packager are canonical. The standard CEF development layout is source-complete: a fresh directory holds the app beside unchanged component libraries, with no dependency or search-path rewriting. The earlier relocation workaround is superseded. All 37 packaging tests pass, including five real Mach-O fixtures; 14 runtime-launcher guard tests pass. Startup corrections have source checks and 34 passing linked checks. The v52 incremental engine build succeeded in six steps (40.50 seconds of compilation/linking); normal generation accepted all 117 already-applied patches with no failures. The earlier standard-layout package at `build/independent-v52-development/Parc.app` passes app deep/strict and sibling-library strict signing plus final source-provenance validation: 519 exact pre-sign engine image copies and 524 signed images, preserving original engine dependency/search paths. Actual v52 startup, local JavaScript interaction, native address navigation, HTTPS MDN rendering/scroll and ordinary Cmd-Q passed; exit was 0 with no surviving helpers. Observed engine images all came from the owned development directory. HTML accessibility was absent on both local and HTTPS pages in v52. The first component launch took about 91 seconds before the native application log, with sampled dyld mapping/signature work; repeat reached that log at 9.480–9.589 seconds with a fresh profile. Visible fixture observation by 27.406 seconds includes tool overhead and is not exact first-frame timing. Shipping performance remains open. Repeat Cmd-Q crashed through renderer-error callback reentry into guarded tab selection. The native harness passed registration and three auth cases but failed on the final renderer-exit callback; no overall lifecycle pass is claimed. No dialogs, downloads, restart/persistence, beforeunload Stay/Leave or normal Keychain acceptance is claimed for v52.



**Earlier v59 runtime gate:** native extension actions, Swift toolbar/pin/anchor controls, the browser-owned side-panel service and native video PiP are canonical. Overlay validation/application, normal generation and the incremental engine build pass (169 mapped files, 138 patched targets; 2m24.85s and 27 local actions). Full Swift/affected Objective-C checks, 21 extension-control assertions, 36 video-PiP assertions and all 37 packaging tests pass within their stated scope. Component receipt `work/actions-pip-v59-checks/component-receipt.json`, SHA256 `8b774af39c39c035cbef419dd668292593af3d116792b1974318614cfd132db7`, remains separate from compiler evidence. The fresh package passes app/sibling strict signing and provenance (519 exact pre-sign copies; 524 signed images), report SHA256 `ccc45bb25e494a40f6a5bed861bc6b302a9b9a7bc7925f17afa47e4e4a894922`.

Actual v59 unpacked installation, enabled state, pinning, the first real popup and Escape dismissal pass. Its setup fails on a fixture assumption: ordinary popup messages omit `MessageSender.documentId`. The corrected context-port fixture installs and pins after restart, but its popup never appears; no global/contextual side-panel check is reached. Browser-info response warnings also occurred during the successful first popup and do not establish the cause. Native PiP controls and Return to Tab work, but floating video is black while the returned source frame renders. Webpage clicks then stop responding despite working shell controls; one reload does not restore input, while restart does. That input failure’s cause remains unassigned. The first ordinary Cmd-Q exits 0; the restarted session hits the teardown watchdog and exits 2. Its orphan helper exits naturally, with final exact-package scans empty and no agent-forced app/helper cleanup. Frozen receipt: ignored `work/independent-v59-extensions-m8419ipj/receipt.json`, SHA256 `8ab90e26a39329f31925507ab79783e570cf7c40d9198e18aec84110fe258eed`. This is a failed extension/media acceptance checkpoint, not whole-P0 completion.

The v60 PiP layer correction is canonical in `c409f84` and builds in the combined v61 increment: five steps, 1m05.84s, normal generation, actual driver header validation and required exports pass. Its fresh runtime package passes signing/provenance. The default controller suite passes native AX, genuine renderer crash/recovery, three authentication-controller cases and shutdown (exit 0, 98.088s). The optional extension-action suite fails on its disabled-fixture developer-mode precondition before snapshot/selection/grant checks. Both runs finish without timeout, forced cleanup or surviving package processes; exact receipts remain in `tests/NativeRuntime/README.md`.

The normal developer-mode correction and gated popup/input diagnostics build successfully in v64 (eight steps, 42.57 seconds). Normal generation accepts all 117 CEF patches and the exact runtime-driver header check passes. Both fresh development packages pass signing/provenance with 519 exact pre-sign copies and 524 signed images: runtime report SHA256 `8c8a76513dec5e1230794c1198e735af085750dd07573a4a8c1f6c6a2b9c72bf`, production report SHA256 `dd35ed5ac29754122178d59fb1e62bb4d61cdaed31bf6b94f69a4a1765bdd082`. The actual v64 action suite passes registration, then fails its internal 15-second readiness/controller deadline before snapshot/selection/grant markers. It shuts down cleanly with exit 1 after 99.021 seconds, no outer timeout, forced cleanup or remaining package processes. Receipt `build/parc-runtime-g35bhtke-logs/result.json` hashes to `68d2b8ac9f090b55d1e875f53598a675b2f7dec5925460dfe5614c573d88e21e`. Bounded readiness diagnostics (`ae12af3`) preserve the deadline and assertions and passed strict compilation before the subsequent v67 run. The combined v67 activation/readiness increment builds successfully in six steps (30.94 seconds); both development packages pass signing/provenance. Its action suite now passes real pin/snapshot/stale-selection/grant assertions and clean shutdown (exit 0, 84.394 seconds; no timeout, forced cleanup or remaining helpers). The earlier readiness timeout did not recur and its cause remains unresolved. Receipt `build/parc-runtime-c65epowf-logs/result.json` hashes to `a3a30c93d744b128d91fa768fd9099dd91bea5b7bb7b1cf363c6baa5c122d056`. The separate v69 selection correction is canonical, with native/Swift checks and 88 model assertions passing. Normal generation accepts all 117 CEF patches and its engine build succeeds in 13 steps (84.75 seconds); the actual v70 selection regression now passes as scoped below. The subsequent v70 overlay check/apply and normal build pass: all 117 CEF patches are accepted, GN generates 36,724 targets, and Ninja reuses production outputs with zero compile/link steps (11.13 seconds). The non-key PiP presenter compiles successfully during production app packaging; its mapped test unit passes the exact-owner compiler check and its component suite passes 43 assertions. Both fresh packages and the actual selection regression now pass; real PiP input acceptance remains open. The supplementary `//cef:libcef_static` header check remains an open dependency-ownership gate in CEF and older Parc-native source. No file changed by the v61-to-v64 cohort appears in its error set; no all-target header-check pass is claimed. The existing Chrome test fixtures remain unexecuted, and the earlier v58 production crash/recovery evidence remains separate.

**Current production PiP evidence:** v61 real bear pixels, native play/pause, seek and resizing from 320×180 to 562×316 close the observed black-video defect. The v67 rerun verifies only partial Return restoration: after source-window minimization, the native diagnostic captured before any CUA query reports the exact window visible and unminimized, but still non-key/non-main, with the app inactive and renderer focus absent. Source media controls still fail after Return and one reload; a fresh counter tab remains at zero after AX and coordinate clicks. The input-ignore, process-blocked and modal flags are zero without establishing the cause. Ordinary Cmd-Q exits 0; a transient code-sign cleanup helper exits naturally, leaving no package processes or forced cleanup. Receipt `work/independent-v67-pip-ifbvp4tq/receipt.json`, SHA256 `07772fab51b86bd59da1cab8abc8dbf391fb998d5ceba074ff415f3ed36c53c0`, binds 30 evidence files. Earlier v61/v64 receipts, short-clip and CUA-observation limits, and remaining PiP lifecycle/style gates are retained in `tests/NativeVideoPiP/README.md`. The canonical activation repair has run; full activation and input recovery remain unresolved.

**Verified v70 packages and selection regression:** the exact seal is `build/independent-v70-seal/engine.json`, SHA256 `452a94fa655256e825543a1c54c1f166e8ca5cd977a63dcd9480a7e8ebbabd74`, bound to overlay identity `cd5d86b264913f2508eca22548d7a14b77cfdb3720fddb3465d23d6b897a8465`. Runtime report SHA256 is `ccce9d51ec2f81fce799b8dbe8760f88929693e3c704f2a7b1bc7d857fc041a9`; production report SHA256 is `c2a975c884cc95b8a687b152ec5226efe892c24deced8e5e08fb07b5d7729c79`. Both preserve 519 exact pre-sign engine copies, verify 524 signed native images, and remain `development-component` with `distribution_eligible: false`. The actual harness passes exact-page engine-to-shell selection after observer unwind, geometry-only synchronization, latest-selection handling and explicit shell-command override. Real copied snapshots/pin order, stale selection/action refusal, no grants on refusal, and activeTab grants restricted to the selected tab and loopback origin then pass; other tab/origin access remains denied. Post-shutdown AX querying and clean engine shutdown pass, with exit 0 after 81.245 seconds, no timeout or forced cleanup, and an empty final exact-package process scan. Receipt `build/parc-runtime-fmzi86mf-logs/result.json` SHA256 is `65770685b84fbbf8de6e21b2e8a32f283faa10f3b8c68a3a714fc4d606cfb219`. This verifies the actual tab/controller regression, not the original side-panel GUI stack, popup restart, split/move lifecycle or PiP input. The production selection/restart result below is separate; PiP checks remain in progress. The earlier v64 readiness failure remains unexplained; no default recovery/auth rerun is claimed by this optional suite.

**Earlier v64 extension/side-panel evidence:** genuine unpacked install, enabled state, pinning, the first visible action popup and corrected nonce/A-B setup pass. GLOBAL and CONTEXTUAL panels visibly render with matching Profile/window/tab identity and accept actual text edits and counter increments. Switching to the other tracked tab aborts at `TabStripModel`'s reentry guard: engine tab activation → side-panel visibility → Swift layout → synchronous native selection → nested `ActivateTab`. The process exits -6 after 141.642 seconds; final exact-package process scans are empty naturally. No retained-state switch, panel close/reopen or ordinary quit is accepted after this abort. The prior v59 missing-popup and late-shutdown watchdog remain separate unresolved evidence. Receipt `work/independent-v64-popup-gz_am6xl/receipt.json`, SHA256 `84855efe8ca6fed7a49fa8e3bdb12f080ca8f7026729011068d7920d6ef088d4`, records the closed run. Selection repair is canonical and passes the v70 actual tab/controller regression; the subsequent production GUI result is below, and no whole side-panel or P0 row is complete. Saved screenshots/AX establish visible modes and identity; text/counter changes are the operator's live observations recorded in the receipt, without a separate post-edit capture.

**Current v70 production extension/selection result:** actual extension-driven A-to-B selection no longer aborts and retains the exact GLOBAL panel instance/text/count. Sidebar return to A restores its original page and exact CONTEXTUAL state; close/reopen creates a fresh panel. B was created in the background and remains blank with empty webpage AX even after sidebar selection, preventing the reverse B-page API action. It had never rendered before switching, so the run does not establish selection as the cause. Source traces show the native WebContents parent starts hidden and the current host only shows its renderer child; the focused visibility correction is integrated in overlay v74 with 126 passing AppKit assertions across nine groups, including a regression that fails against the old component. It is not yet runtime-accepted. Saved Start/Easel-to-web navigation accepts counter input. Same-profile restart renders B, restores the installed popup on its first attempt, retains the profile nonce and permits global panel open/close/reopen. Both ordinary quits exit 0, with no remaining exact-package processes or forced cleanup. The earlier missing-popup/watchdog failure does not recur in this bounded run. A second popup in the first lifetime appears but the fixture rejects multiple live contexts; this ambiguity does not prove a production defect. Receipt `work/independent-v70-selection-wetjgwhd/receipt.json`, SHA256 `780de6c531a6a23d84dc211c0e3d5a36746383689e0121a0bf1a6d8fe0b84260`, binds 58 verified files. [Detailed limits](../tests/NativeBrowserWindow/README.md#production-selection-and-restart-check) remain open; this is not whole-P0 acceptance.

**Current input diagnosis:** v74 generation, build and both packages pass. Its production extension rerun closes the observed blank-background-tab defect and retains both pages/panels across A↔B selection. A separate fresh no-PiP control leaves the same counter at 1 after minimize/manual restore and both indexed-button and coordinate click attempts; one initial page request and no reload/navigation/media were used. Ordinary quit exits 0, with no owned helpers or forced cleanup. Receipt `work/independent-v74-no-pip-control-qn9ix5yx/receipt.json`, SHA256 `68013a4a3badb07a29be59880f220c1b6b3ac8deb3c821ffd85dc70de14f8716`, binds 18 verified files. This localizes the reproduction but does not establish which input boundary fails. The v77 build passes with opt-in event-delivery diagnostics; controlled runtime is next. This is not a behavior fix. An indexed computer-use click is not proof of native AX ingress until the trace observes that route.







## Implementation history









These milestone notes preserve the source and checks available at each increment. Present-tense v16/v22 build statements and then-pending source promotion describe the historical stage; they do not supersede the linked engine and canonical production shell recorded above. The work map below carries current acceptance areas. Runtime, functionality and polish gaps remain open unless a later milestone explicitly closes them.


Native extension action models, supplied-host popup ownership and an AppKit child-window presenter are now source-owned and included through a shared engine/browser-test target. The presenter executes 57 assertions in seven groups; generation and target header-dependency checks pass. All three production units and the four-case real-host test source pass the pinned compiler with actual generated target flags. The four genuine ExtensionViewHost browser cases remain unlinked and unexecuted. Real toolbar/context menus, permissions/grants, unload/reload, security/modal/DevTools behavior, deferred Browser/Profile destruction and integrated shell/renderer focus still require verification. This is not extension compatibility or visual/motion parity completion.

Native extension context-menu presentation now preserves Chromium’s real dynamic model and native Cocoa dispatch, with exact ownership guards through cancellation and synchronous command callbacks. The production unit and ten genuine browser cases pass actual-target compiler checks, both target dependency checks pass, and the patched full upstream menu model compiles. Linking and execution are pending. Uninstall checks its Browser-owned native service. The v59 canonical Swift action bridge now reaches the native menu/popup and side-panel services; actual presentation and command behavior remain runtime gates. Pin preference updates are preserved without a Views element, while native feedback, downstream commands and exact menu behavior remain unverified.



Extension teardown source has advanced through v25: popup close observers run after actual host destruction, native menu cancellation waits for tracking/model-lease unwind, and action shutdown retains real models and popup hosts through terminal cleanup. The three production units and added popup/menu browser cases pass actual-target compiler checks via isolated VFS; linking/execution and full Browser/Profile teardown remain open. The active v22 build continues unchanged; later source is not applied until it finishes or reports an actual failure. This advances P0-09 without marking its native runtime gate complete.


Native construction source now advances through v27: profile-bound one-use reservation, real BrowserManager registration, native window/platform factory, concrete AppKit page/service ownership, first-tab focus/color setup, real popup-page adoption and typed engine startup/idle shutdown. Thirteen complete modified upstream translation units and the new native units pass actual-target compiler checks; read-only overlay replay validates 81 mapped and 93 patched targets. The per-window model executes 35 assertions. The Swift/facade candidate compiles but production promotion remains gated on integrated checks. The full build still runs on v22; no standalone launch or runtime gate is claimed. Subset-page preflight, singleton relaunch, permissions and packaging are the connected work in progress, not a restart of the feature inventory.

Exact subset-page retirement is source-connected in v28, sharing the actual coordinator between production and genuine controller tests. Whole-set approvals precede the model validator and native document/owner revalidation, then actual unload; success waits for real destruction. Late replies, navigation, transfer, renderer crash/retry and competing window closes are covered by nineteen compile-checked controller cases. Six actual-target units and the full Swift consumer compile; the model executes 420 assertions. Read-only replay validates 87 mappings and 94 patched targets, with the v22 full build unchanged. No linked/native beforeunload, archive or quit completion is claimed.

Native singleton relaunch and independent Keychain identity are source-connected through v31. The real CEF handler consumes copied launch destinations through the required native client; normalized argv remains owned through shutdown. The Core parser executes 22 assertions. CEF156 initializes normal OSCrypt encryption with `Parc Safe Storage` / `Parc`; no private identity interposer is needed for this replacement. Integrated native compiler checks and v31 read-only replay pass (87 mapped, 94 patched). Swift routing remains a compiled candidate; second-instance/Dock behavior and actual independent encrypted restart are unverified. The running build remains v22.


Uninstall integration correction v33: the aggregate host security query included the service's own reservation and caused self-cancellation. Exact sheet/sole-reservation exclusion now preserves the pending confirmation; competing exact-window reservations cancel it, with acquisition notifications and release reentry handled explicitly. The AppKit suite executes 52 assertions; actual host/request and fifteen browser cases compile. Read-only replay still covers 93 mapped and 96 patched targets. Linked uninstall behavior is unverified and the active v22 build remains unchanged.

Site-permission completion correction v34: consent requires its sole exact-window lease and own sheet; after release, another reservation or sheet invalidates that decision. Two additional genuine-manager regressions cover held competition and notification permission persistence under release-observer reentry. Both changed source/test units compile; fifteen manager cases remain unlinked/unexecuted. Read-only replay passes with 93 mapped and 96 patched targets; no active build interruption.

Extension-install consent source v35: the real ExtensionInstallPrompt captures native ownership before icon loading; the AppKit presenter preserves permission messages, withholding policy and once-only decisions. Actual installer results use that captured owner. Exact page/document/selection, shared security reservations and deferred revalidation handle cancellation and callback reentry. Forty-two AppKit assertions execute; six combined compiler checks include thirteen genuine prompt cases, not linked/executed. Read-only replay validates 99 mapped and 98 patched targets; v22 compilation stays unchanged. Store/unpacked installation, enterprise/parent approval, grant persistence and visual/motion parity remain open.

Live-transfer source v36 preserves the actual same-profile TabModel/WebContents and uses both real UnloadControllers to protect detachment/rollback. It verifies restored ownership after attachment callbacks and defers source teardown until native result delivery returns; preexisting destinations survive failure. The Swift candidate validates actual owner/final attachment and retains unresolved claims for recovery. Fifty-seven model assertions execute; five integrated compiler checks include twenty-two real controller cases, not linked/executed. Read-only replay covers 103 mapped/98 patched targets without changing the v22 build. Real rendering/extension identity, focus, native reparenting and visual/motion parity remain open.

Downloads/file-selection source v37 uses the actual profile DownloadManager and GUIDs, real item controls and the normal Chrome target/security pipeline. The native macOS picker preserves request options/policy and exact source ownership, with sole-window reservation checks and cancellation on navigation/detach. Delivery and runner retirement wait past nested observer loops. The model executes 25 focused plus 420 baseline assertions; ten combined compiler checks include twelve real item and ten chooser cases, not linked/executed. Read-only replay covers 110 mapped/101 patched targets while v22 continues. Browserless save prompts, review-required download UI, destination preferences, drag/drop and exact original presentation remain gaps.

HTTP/proxy authentication source v38 keeps the real Chrome authentication coordinator, policy/interception, credential manager, LoginHandler continuation and modal manager under page-bound native presentation. Exact document/window checks cover inherited credentials and release-time reentry; detach closes the attachment gate before cancellation. Thirty-six AppKit assertions execute; six combined compatibility compiler checks include twelve real controller cases awaiting link/execution. Read-only replay covers 116 mapped/104 patched targets without changing v22. Real 401/407, retry, saved credentials, background/competing prompt queuing and original presentation remain open. The ordinary Chrome test environment does not initialize the CEF context required by this build; a compatible runner/fixture is an explicit P0-29 gate, not a passing test result.

DevTools source v41 retains actual tools/toolbox contents, Chromium docking and
close state, and the real auxiliary Browser keyboard delegate. Native panes
protect later view owners, and scoped modal bindings follow actual tab transfer,
including popup destinations. Forty AppKit assertions execute; thirteen combined
compiler checks include six DevTools and eleven chooser cases awaiting link and
execution. Non-tab chooser requests cancel safely. Read-only replay covers 128
mapped/113 patched targets. Docked tools still require exact auxiliary service
attachment for CEF focus/coordinates, JavaScript and page-owned permission/file/
authentication paths. Swift window promotion, full docking/close runtime and
presentation remain open; this does not close P0-25.

Native runtime source v42 supplies a production-lifecycle runner for three real
HTTP-auth controller/presenter cases on a genuine native Browser/page. It avoids
the incompatible Chrome test mains and a second CEF/process owner. One driver
compatibility compiler check, the external AppKit main link and two launcher
guard tests pass; 131 mapped/113 patched targets replay. Generation, framework
link/exports, independent packager/helper promotion and actual controller case
execution remain open. Synthetic challenges do not prove real network auth.

External-protocol source v43 connects native page-owned consent to Chrome's
checked request and genuine preference/OS continuation. Attachment generations
prevent queued acceptance reviving after detach/reattach; actual activation and
PiP protections remain. Thirty-five AppKit assertions and seven compatibility
compiler checks pass; seventeen genuine cases remain unexecuted. Read-only
replay covers 138 mapped/117 patched targets. Real launch/policy/input behavior,
remain open; P0-19 is not complete.

WebAuthn source v44 connects genuine Chrome request/model/sheets and Apple
authenticator window ownership. Exact request/document/native attachment guards
and deferred modal-host cancellation preserve real engine callbacks. Seven
combined compatibility compiler checks pass; eleven genuine controller cases
remain unexecuted. Read-only replay covers 143 mapped/123 patched targets.
Conditional/autofill/ambient UI, separate WINDOW stages, non-request settings,

DevTools auxiliary source v45 binds the actual docked main frontend to its
inspected Browser/Profile/native window. Detach, transfer and replacement revoke
captured ownership; real AppModal decisions revalidate after queue advance.
HTTP cancellation latches before deferred cleanup. Sixteen combined compiler
checks pass; twelve new auxiliary and thirteen HTTP-auth genuine cases remain
unexecuted. Read-only replay covers 148 mapped/127 patched targets. Actual
remain open; P0-25 is not complete.

Server-certificate inspection source v46 follows the recovered native OS panel
contract with exact document/visible certificate/window ownership. Thirty-four
real OS-panel assertions and five combined compiler checks pass; thirteen genuine
controller cases remain unexecuted. Replay covers 155 mapped/129 patched targets.
Chromium retains SSL warning decisions. Actual target generation, native page-info
not complete.


**Current completion rule, October 25:** this table tracks implementation completeness. Functional browser tests, runtime regression/acceptance, benchmark runs and distribution launch tests are not blockers. Historical verification language elsewhere in this document and test READMEs does not override this rule. Remaining rows must identify actual missing production code, configuration or presentation. PiP is done by user acceptance.

Client-certificate selection is source-connected in v40, retaining the actual
Chromium selector, policy, identities, private-key acquisition and continuation.
REA establishes an auxiliary native window produced by Chromium's selector;
the supplied native parent and genuine page-modal manager own presentation.
Six combined compiler checks pass, including fourteen genuine controller cases
not linked or executed. Read-only replay covers 122 mapped/109 patched targets.
Actual TLS, OS authorization, details, modal behavior and presentation remain
open; this does not close P0-19.

Page-owned hover status is source-connected in v39 through the actual CEF
source-page callback, with recovered visibility/expansion delays, compact sizing,
click-through and pointer avoidance. Thirty-five AppKit assertions and four
isolated compiler checks pass; read-only replay is 118 mapped/104 patched targets.
Real callback clearing on pointer exit, URL/routing formatting and exact
presentation remain open. This advances P0-24 without claiming integrated runtime
or visual/motion parity.


| ID | Engine area | Implementation status | Remaining implementation / scope |
|---|---|---|---|
| P0-01 | Engine build and link | Implemented | Independent Chromium/CEF framework, helper dispatch, native integration and application build/link path. The v172 native increment compiled and linked successfully, including page security, blocked popups, confirmation banners and profile search. The v178 favicon, shortcut and MRU increment compiled, linked and packaged with strict signing/provenance. The v180 profile-history/retirement and v181 Peek increments compiled and linked successfully. The v182 history-control increment has affected native and combined Swift compiler checks passing. |
| P0-02 | Independent packaging and signing | Implemented | Separate standard GN non-component release output, owned build receipt and standalone app packaging are connected without altering development objects or rewriting load commands. Actual shipping GN generation passes; source/build-tool and packaging-policy checks pass. A full shipping engine has not yet been compiled or packaged. Those execution steps do not keep the implementation row open under the current rule. |
| P0-03 | Engine startup, event loop and shutdown | Implemented | Startup/export boundary, native AppKit event loop, helper dispatch and shutdown path are connected. |
| P0-04 | Profiles, private contexts and encrypted storage | Implemented | Persistent profile identity/preferences, versioned isolated engine storage, private contexts and Parc Keychain configuration are connected. Unrun restart/isolation tests do not keep this row open. |
| P0-05 | Native Browser construction and registration | Implemented | Profile-bound native Browser construction, one-use supplied-window reservation, manager registration and readiness; no stock BrowserView fallback. |
| P0-06 | Swift shell and actual page attachment | Implemented | Swift native windows and containers own the actual WebContents attachment; selection, geometry, navigation/title/loading/error updates and attach/detach are connected. |
| P0-07 | Splits, shared windows, profile selection and live moves | Implemented | One-to-four split panes, selected profile/browser reconciliation and real same-profile tab transfer preserve WebContents; cross-profile live transfer is refused before mutation. |
| P0-08 | Popups, openers and internal windows | Implemented | Exact-profile creation, original WebContents/opener/POST adoption, native geometry/capabilities, compact popup shell, initial/inactive presentation, empty-shell retirement and actual minimize/maximize/restore/hide/restored-state operations are connected. Extension window updates validate before mutation; deferred placement is tied to the exact physical window and superseded by newer requests. Exact appearance/motion remains whole-product polish. |
| P0-09 | Close, beforeunload and asynchronous teardown | Implemented | Native beforeunload Stay/Leave, page/window/app close coordination, pending-download decisions and deferred ownership teardown are connected. |
| P0-10 | First-tab feature initialization and colors | Implemented | First-tab color observation, native focus controller and page-created integration are source-connected before insertion. |
| P0-11 | Input, focus, accessibility and shortcuts | Implemented | Native renderer focus/accessibility, keyboard/IME delivery, native menu and DevTools/extension ordering, split/profile focus and native text-control routes are connected. Browser tests are not a gate. |
| P0-12 | JavaScript dialogs and Find | Implemented | Page-owned alert/confirm/prompt and native Find presentation, callbacks, focus and cancellation are source-connected. |
| P0-14 | Extension toolbar, commands, popups, menus and removal | Implemented within the mapped action/menu contract | Native pin/action state, popup ownership, commands, context menus, uninstall and policy routing are source-connected. Unrun lifecycle tests are not remaining implementation. |
| P0-15 | Extension side panels | Implemented | Global/contextual extension side panels use the real ExtensionViewHost, selection/state, close/unload and profile ownership paths. |
| P0-16 | Extension API compatibility and background lifecycle | Implemented within the mapped extension API contract | Actual tab/window identities/events, selection, opener/disposition, permission grants/denial and profile-owned background services are source-connected. Broad API test coverage is not an open-code item. |
| P0-18 | Site permissions and security prompts | Implemented | Ordinary typed consent and all six permission-element follow-up variants use genuine manager decisions and platform authorization/settings callbacks. Exact origin/document/profile/window ownership and late-response cancellation are preserved. Desktop/screen/tab selection consumes real offered models, OS ScreenCaptureKit selection and supported audio choices. Exact appearance and motion remain in the full-product polish pass. |
| P0-19 | Authentication, certificates and external protocols | Implemented | Ordinary HTTP auth, request dialogs, Apple authorization, conditional/autofill/QR/hybrid, ambient sign-in, recovery WINDOW, settings PIN changes, certificates and external protocols have native source routes. Genuine controllers/results and exact document/profile/window ownership remain authoritative; recovery releases its reservation before the next PIN dialog. Exact presentation polish remains whole-product work. |
| P0-23 | Automatic archive safety and discard lifecycle | Implemented | Live form/edit/media/capture protection, conservative missing-state handling, pre-retirement revalidation, expiry/restore and split/selected-tab protection are source-connected. A real-day wait or browser tests do not keep this row open. |
| P0-24 | Webpage menus, hover status and page security UI | Implemented | Genuine Chromium webpage menus now track in the supplied AppKit window; original-frame image capture, content policy, same-profile Easel choice and persistence are connected. Blocked-popup count/chooser, real PageInfo certificate/permission/device/cookie controls, genuine profile WebUI routes and native confirmation banners are connected. Reachable tab-sharing banners retain the actual capture controller, Stop/source-switch/endpoint actions, original Profile and captured-surface PageInfo permission entry. Hover status and certificate details are connected. |
| P0-25 | DevTools, PDF, print and page tools | Implemented | Native EyeDropper (page translation is excluded since November 1), genuine DevTools and auxiliary ownership, Print/Save PDF/Save Page/View Source, and reader extraction/cancel/exit/history return are connected. Clear Cache and Refresh bypasses cache; Clear Cookies and Refresh clears genuine origin/partition data then refreshes the same document; Clear Browsing Data opens the actual profile dialog. Reader and data-dialog visuals remain explicit current-engine adaptations for the whole-product polish track. |

Current count: **29 implementation-complete areas, none with identified remaining production code in this mapped P0, and P0-29 removed as a completion gate.** These unequal areas are not a percentage or time estimate.



Retained evidence limits and deferred work: exact side-panel layout/focus/motion, full-product permission/auth/password/page-tool appearance, historical upstream header-check failures and unrun native-shell cases, shipping execution and signing continuity across rebuilt packages. These are not unidentified production-code blockers in the completed P0 map. Record new evidence against the appropriate row. Full-product feature and polish requirements below remain in force after the engine replacement.





## Fixed scope


**No Google API keys or paid Google services — Josh, November 1:** Parc must not depend on Google API keys or paid Google services, because Josh intends to open-source it. Page translation is therefore excluded: Chrome's translate service needs a Google API key. Startup adds `--disable-translate-trigger` and turns off the translate ranker, `translate.enabled` defaults to off, the page menu has no Translate item, and Parc's translate popover and Settings' translated-site reset are removed. Page language detection stays, because Autofill and other features read it. Safe Browsing stays without a key, by Josh's choice; it is inert without one. On-device search suggestions are re-enabled: their model arrives through the component updater and needs no key. Every entry point and its handling: [engine flags](engine-flags.md#page-translation).

The source repo must contain used implementation, focused tests and useful documentation. Build products, browser dependency binaries, profiles, logs and raw reverse-engineering dumps stay out of Git. Every commit is immediately pushed and checked against origin.

Engine maintenance must keep receiving upstream security fixes through deliberate
engine version is a reverse-engineering reference, not a required version freeze.
This ongoing maintenance requirement does not change the active P0 work order.

## Delivery order

The genuinely new `arc_ui_features_polish` agent follows these existing priorities and owns end-to-end implementation wherever engine support exists. A missing P0 dependency requires a REA-backed contract, implementation as far as that dependency permits, and specific handoff notes for the engine agents. Do not replace complete feature work with disconnected UI, placeholder behavior or a documentation-only handoff.


The user-set next-family order and current ownership are recorded in the [single family table](#family-completion). This October 26 order supersedes earlier family priorities. Finish the current owned family, then select the highest-priority unfinished family that has no owner; do not restart completed work or take over another owner's family. Automatic archive is priority 3 despite completed earlier implementation batches: its remaining counted requirements stay open.


**Chromium AI cleanup — user decision, October 29:** Josh accepted the existing state and closed the proposed broader cleanup. The proposed investigation and removal of Gemini/Glic, Actor, Compose and other Chromium AI paths was not performed, and its CPU, memory and startup effects were not measured. Preserve the already-committed exclusions, ordinary password/autofill/security behavior and macOS dictation.



## Completion requirements and explicit user feedback


- Compare the entire journey, including first launch/onboarding, ordinary browsing, settings, shortcuts, recovery and long sessions. Check real HTTPS pages and responsiveness as well as local fixtures.
- Recreate the **entire first-launch experience**: opening animation before any browser window appears, music/audio cues and synchronization, haptics, setup/tutorial interactions, transitions, and the final browser reveal. Matching only the setup screens is insufficient. Discover reduced-motion and audio preference/mute behavior, interruption/replay rules, cue triggers and timing; do not invent unobserved behavior or mark an asset inventory as a working sequence.
- Fix misplaced, undersized and misaligned icons throughout the interface. Audit icon bounds, optical alignment, baseline, stroke/weight, padding and hover/selected/disabled states against the installed reference at matched window sizes.
- Run a dedicated full-product functionality and experience polish pass: spacing, typography, colors/backgrounds, controls, focus, accessibility, animation timing/curves, transitions, gestures, drag/drop feedback, shortcuts and small interactions. Correct defects as each feature is built as well.
- **Exhaustive polish coverage:** inventory and review every menu and menu item, modal/sheet/popover, click/action, keyboard interaction, hover/pressed/selected/disabled/focus state, haptic trigger, animation/transition, icon variant/size/alignment, and visual style across every feature. Track each interaction's reference evidence, implementation, runtime comparison and unresolved defects. Include rapid repeats, interrupted/reversed motion and accessibility/reduced-motion variants. Do not extrapolate whole-product parity from sampled screens or a few passing flows. Mapped P0 implementation is complete. Apply this coverage to each active whole-product family without abandoning its current implementation batch.
- Every visible control and preference must perform its intended behavior, and saved settings must actually be applied. Remove unused or misleading controls and abandoned code; present temporarily unsupported actions honestly instead of leaving functional-looking placeholders.
- Preserve task order when new reminders arrive. Record them durably or delegate independent investigation; finish the current batch through verification, documentation, commit and immediate push before changing feature.
- Never imply overnight work or a completed browser from a partial batch. Report actual implemented and tested behavior, unresolved gaps and any genuine blocker.

This ledger is the sole current progress, delivery queue, scope and acceptance record. README contains the project/build overview and at most one current-state line; do not duplicate progress, requests or work lists there. Keep source, focused tests and useful documentation in Git, with raw analysis and runtime evidence outside it.

## Feature families

Current percentages for all 32 families are in the [single family table at the top](#family-completion). The [active-family requirements](#counted-active-family-requirements) and [remaining-family requirements](#counted-remaining-family-requirements) below provide their counted evidence. Owners must update their stable requirement states and DONE/LEFT percentages with each delivered increment, record percentage-point movement from the previous counted snapshot, and disclose any denominator change. Completed work is verified and pushed directly to main by its owner without waiting for root integration.

The [counted active-family requirements](#counted-active-family-requirements) below replace the previous unsupported percentage estimates.

**Whole-family delivery (October26):** current ownership and priorities are in
the [single family table](#family-completion), with active checkout and next-step
notes in [current ownership](#current-ownership-and-handoffs). Each owner continues
through complete production behavior and essential presentation/interaction.
Frequent commits are increments, not family closure. A status question does not
reassign work. New contributors claim and publish the next available family as
explained in the [collaboration guide](collaboration.md).


| Family | Current source / verified behavior | Remaining work and details to compare |
|---|---|---|
| Settings | Application-menu and account-free General default-browser actions now use genuine sequential macOS HTTP/HTTPS consent and actual handler readback. Native General/Profiles/Links/Shortcuts/Icon/Advanced panes, routing editor, replay/restore/sidebar controls and genuine profile/search preferences. Rename and pane/profile selection persist atomically. Individual and bulk unused-profile removal connect typed confirmation, exact original profile identities and durable recovery to real Chromium deletion. Bulk authorization is atomic; per-profile results, retry and cancellation preserve partial outcomes and exclude newly created profiles. Default, assigned and busy profiles stay protected. Combined 70-file Swift check and 37 file-backed model / 17 isolated controller assertions pass. More Settings opens the genuine Chromium Settings page in the original window/Space/profile, retaining an existing subpage and native navigation guards. Advanced translation reset clears only original regular-profile language/site choices after exact context preparation, with cancellation and truthful completion; other preferences and policy remain intact. Its 70-source Swift and actual native application compiler checks pass with zero diagnostics. Private windows now open application-owned Settings through their actual regular parent; profile preferences persist normally without assigning the private Space. More Settings, Passwords and replay retain exact regular ownership. Ordinary View → Show/Hide Toolbar (Command-Shift-D) and the Advanced full-URL preference now persist as application appearance shared by regular/private windows; original-page controls and extension leases remain authoritative. Advanced sound and tab-reordering-haptic switches now persist independently. Genuine valid capture completion uses the bundled native sound at volume 0.7 while active/enabled; accepted original sidebar drag proposals combine distinct child indices with the live haptic preference for generic/now feedback. Onboarding and webpage audio retain their owners. The Advanced webpage-dragging switch now controls the original native page/window grabber; see SET-DRAG-01 below. Advanced Shared Quotes now controls the original-selection sidebar action, with recovered mouse-release/debounce behavior and genuine text-fragment copying; explicit Copy URL as Quote remains independent. | The Advanced theme-data switch is source-integrated through the actual window/document renderer owner; local Markdown data export is source-integrated; Settings theme preference inventory/default and actual consumer coverage are complete under SET22; remaining General/Profiles behavior and exact color/selection/motion also stay open. Individual removal engine compilation is complete; the v181 development package includes it with Peek and Easel styling. Bulk cleanup is source-integrated without browser tests; its footer/sheet geometry and scheduling are explicit adaptations. See [settings architecture](settings.md). |
| App identity and icon variants | Ten approved P treatments share corrected native ICNS optical framing and actual small-size light/dark inspection. Icon Settings saves/restores the app-wide choice; native app/Dock/Finder consumers and the non-running Dock plugin share the packaged family. Original and Alerts-helper defaults remain intact. Borderless/monochrome production marks, source-preserving alpha cleanup, picker interaction and explicit offline availability are delivered. Export, native component, packaging and compiler checks pass with independent review. | All eleven implementation rows complete. Integrated product-wide visual polish remains separate; historical service gates are excluded as documented in the [availability contract](app-icon-availability.md). |
| Spaces and profiles | Separate local profiles, exact-window Space menu/sidebar commands with stable destination identities and guarded cycling, window-local focused-pane and split-layout return, shared source-owned theme editor/renderer, 45 presets, linked colors, application appearance parent/reset, intensity/noise/textures, original-window theme Undo across popovers, local draft undo and persistence, recovered pointer/rotation/scroll mappings with interruption-safe history, native theme detents, separate material/content appearance and interruption-safe theme motion; keyboard/accessibility and selected runtime paths checked | Profile management polish and full settings parity |
| Today / pinned tabs / favorites | Saved destinations survive Pinned/Favorite changes; saved-tab Reset and focused-Favorite copy titles now use the recovered full-URL equivalence while navigation retains original URLs; original-page reset, pinned-row hover and context/accessibility actions, current/visible reset commands, Today Other/Above/Below archive groups and contextual close/reopen availability are source-integrated. The shared retirement transaction preserves refused groups and original profiles. Reopen now uses the physical window’s saved-item priority and manual Today/complete split stack; see [Reopen Closed Tab](reopen-closed-tabs.md). Window-local same-Space Today/pinned/folder/split multi-selection now has original-ID modifier/range selection, native selected-state/AX feedback, bulk copy/move/close and existing beforeunload ownership; see [sidebar selection](sidebar-selection.md). | All 22 counted requirements (TAB01–TAB22) are DONE. Remaining: the next overlay apply of three published engine sources (Codex root) and an on-screen comparison. See [saved tabs](saved-tabs.md). |
| Automatic archive | Profile settings, activity/start/unread rules, typed-item/multiwindow/modal eligibility, original-item consent snapshots and native traits/forms/media protection implemented. Independent 60-day retention, launch delays, continuous-clock scheduling and per-window occlusion/activity ownership are connected. | Original automatic-archive settings/status/feedback and remaining focus/motion/interaction under AUTO11–AUTO12; preserve existing protection rules and PiP acceptance. |
| Archive and history | In-window Library beside the live page; date groups, search, closure/single-Space filters, native keyboard/multiple selection, bulk Put Back, explicit same-profile destinations and confirmed delete/clear. Provenance and original profiles survive Space reassignment; complete archived splits restore together. Exact-profile native database favicons and 60-day retention are integrated. The combined 78-source Swift check and 696 model assertions pass, including exact Put Back destinations and group preservation. | Put Back now follows the recovered selected-filter/current-window destination and missing-Space fallback. Exact row preview/snapshot caching, transition/filter motion, nested archived-root reconstruction and broader closed-item restoration beyond the delivered window-owned saved/Today cache remain. Same-profile validation and original-record split restoration are explicit adaptations; legacy reason remains unknown. See [Archive ownership](archive.md). |
| Split views | Persistent typed per-Space groups with original child controls and whole-group selection; orientation/ratios, expand/restore, divider sizing and original-pane commands. Same-window original-tab drag insertion/replacement now preserves newly grouped pinned/Favorite saved homes in their exact standalone or old-group parent slots (members reorder through the pane menu's Move entries), with one durable publication and the original native/local owners. Explicit child separation, stale-owner cancellation and legacy group migration are implemented. Original ordinary/Favorite container Rename, custom icon, Reset Name and Icon and guarded native Undo are wired through the existing shared group. Single external HTTP(S) URL drops into original web/Note/Easel panes now create and persist a new URL plus split placement through an original-window native drag lease; standalone pinned tabs and Favorites preserve a fresh saved-home reference at the original section/folder slot while whole-Favorite groups retain their original container. Whole ordinary mixed-placement groups also move across physical windows through the existing all-child transaction. Original pages and local editors remain alive. Original pane Move/Add/Copy/Separate/Convert menu actions and the shared Add Split entry now use exact owner receipts; Add parks a temporary empty presentation until a real native navigation or original ordinary tab fills it, with atomic publication and cancellation cleanup. | Cross-Profile and copy variants, legacy mixed Favorite/Today external URL target policy, exact container relocation, proprietary icon catalog/populated edit appearance, precise controls, placeholder geometry/motion and haptics. Original-tab and external-URL target regions now use the recovered classifier and insertion-refusal replacement fallback. The original-sidebar-item decoder excludes whole splits; generic URL fallback is a separate operation, not group transfer. See [split groups](split-groups.md). |
| Peek | Source-integrated original-page adoption, retained parent/tab/window/profile ownership, explicit Shift-link request preservation, real close consent, same-wrapper Today/split expansion, current-page tools and persisted Links preferences. Full Swift and affected native compiler checks pass. | Ordinary current-tab automatic Peek is source-integrated through its original-request policy seam; internal matched OpenURL routing and persistent URL-lock state are source-integrated. Actual overlay appearance, exact modal shortcuts, continuous swipe/snapshot motion, hover/pressed states and haptics remain; explicit adaptations are recorded. See PEEK breakdown and [Peek ownership](peek.md). |
| Easels | Native pinned tabs and local text/images/shapes/drawing/links. Whole-object and selected-range Mono/Fancy/Hip/Clean × five sizes, emphasis and links now retain native text storage, typing/format undo and atomic document persistence. Paragraph commands add Heading 1–3, bulleted/numbered lists, nested Tab/Backtab, Return/Backspace behavior and structural undo through that same owner. Recovered typed markdown prefixes/delimiters now use exact original native ranges while preserving imported literal text and composition. Canvas marquee/content-specific selection, original-object group move/nudge/resize, arrow endpoints, image aspect controls, alignment/canvas guides and duplicate use the shared document, exact targets and real undo/save outcomes. Versioned private rich copy, mixed RTF/RTFD and native in-text paste preserve supported fonts, colors, links, paragraph/list metadata and original inline image bytes; unsupported attributes refuse without flattening existing text. Genuine embedded browser objects and captured PNG cards now retain exact native page ownership, selected-object input, navigation/security controls and shared-document beforeunload retirement. Native Address/Search authoring and actual selected-page URL persistence now share those original owners without recreating another editor’s page. | All 29 fixed Easel requirements are delivered, including image-only attachment refusal/external clipboard, native fill metrics, live capture regions, focus/AX, appearance, motion and Profile retirement. Source/component checks and native presentation adaptations are distinguished from unclaimed installed-browser acceptance. See [Easel architecture](easels.md) and [appearance contract](easel-appearance.md). |
| Notes — local restoration | Native title/rich-body editing, local save/reopen and shared-window updates, New Note/New Note in Split View, command-bar creation and the combined Easels & Notes Library are source-integrated. Failed drafts retain their editor and block closure; deletion preserves surviving split panes. | Paragraph gutter and twelve Notes-specific formatting actions are source-integrated; the actual fullBlob writer does not establish a nested-tree editor. Selection formatting and the recovered title/body keyboard boundary commands are implemented. Historical save timing, remaining editor discovery and appearance/motion remain. Notes stays prioritized through full completion; the other agents continue older parity work in parallel. See NOTE breakdown and [local Notes](notes.md). |
| Screenshots and recordings | Real original-page region/viewport/full-page capture and opaque-token element hover/click capture, PNG preview/crop/Retake/Copy/Save/Easel output and native document/geometry policy leases are source-complete in the paired capture batch. Save to Library now commits exact PNG bytes and original metadata to a profile-owned local catalog; Media provides a two-column grid, search, preview navigation, original-image Copy/export, source actions and confirmed revision-checked deletion. The capture palette now offers direct New Easel/existing UUID-bound Easel insertion and the real macOS Compose Message service, preserving original pixels, shared undo sessions, disabled availability and truthful cancellation/failure handling. See [capture Library](capture-library.md) and [capture destinations](page-capture.md#direct-destinations-and-messages) for evidence and ownership adaptations. | Library app compilation and real-store checks pass. Combined 57-file Swift and native capture compiler checks pass; the production Easel destination component passes 20 assertions, and all 466 queued engine overlay targets validate without changing active build inputs. CAP20 destination ranking, expansion/search and original URL/image-only message attribution are checked and independently reviewed;43 inert assertions and final whole-module SIL pass. Share-composer appearance, motion/haptics, richer editing and captured-item-specific context variants remain; CAP23 separately completes OS media discovery/permissions. Portrait entry, remembered Color/Page/Desktop configuration, recovered framing/gradient composition, optional Parc watermark and existing output destinations are integrated. The 58-file combined Swift check, native tint check and isolated compositor/preference checks pass. Recording scope is independently traced, never inferred from an indicator or OS media filename. The requested unified framing/menu improvement is source-complete under CAP-10; no recapture occurs when framing is edited or removed. No functional browser tests or runtime acceptance are claimed. |
| Extensions | Genuine installation/consent without native result UI, action/command discovery, toolbar/menu/popups and global/contextual panels are connected to original Profile/page/window owners. EXT11–EXT14 complete the recovered appearance, interaction, accessibility and lifecycle comparison; the default-off original panel boundary and explicit current-Chromium native-shell adaptation are documented. | Fixed Extensions ledger is complete under the current source implementation rule. Actual native/inert component checks and independent review are recorded with each row; functional browser tests and live keyboard/VoiceOver acceptance were not run. The overlay246 app/native package remains the dedicated engine owner’s pipeline work. |
| Media | P0-22 media/capture state and native controls are implemented; PiP remains accepted as DONE. The original-page Mini Player now connects real media-session playback/track actions, tab mute, volume, camera/microphone capabilities, episode Hide, and exact-page Return in a five-row sidebar shelf. See [Mini Player](media-mini-player.md) for source/document/Profile ownership and the current Chromium volume adaptation. View/page-menu/command-bar Cast now connects the original native page to Chromium’s real device discovery, Sources, route status/Stop and supported pause controls, with exact document/Profile/window cancellation. See [casting](media-casting.md). | Mini Player host filtering, presentation-set producer re-admission and integrated appearance are source-complete under documented adaptations; The combined 60-file Swift, native media bridge and modified Chromium media-session compiler checks pass with zero diagnostics; they do not establish runtime acceptance. The Cast entry and genuine router dialog are source-implemented; the separate website-initiated chooser uses the native-parented GMC view and original route context. Actual device interoperability and permission/appearance/motion comparison remain unverified or separately scoped. Fixed Media ledger is complete under the current source implementation rule. Standalone screenshots/recordings remain separate. No PiP work is reopened. |
| Web interactions | Live HTTPS React/MDN/WebGL, dialogs, Back, native accessibility and MDN scrolling checked; default canvas fixed with explicit color and CSS scheme checks | Individual-tab beforeunload consent, context menus, popup/opener/POST state, permissions, authentication and full action coverage |
| Downloads | Production family routes are connected: native manager loading/search/Profile filter/newest-first order; asynchronous thumbnails; complete status/progress/More controls; original single-item keyboard/menu actions; Pause/Resume/Cancel/Retry/security review; owned Quick Look/focus; asynchronous Trash outcomes; cold-profile policy-aware Settings; original-item entry activity/completion and lazy completed-file drag. Regular and private windows now share the recovered merged normal/private collection, with private rows held only in memory and genuine original-context actions; context retirement clears only its own offers and records. See [Downloads Library](download-library.md). | The recovered compact populated row is implemented:56pt height,24pt file artwork/32pt custom accessory, 14/12pt two-line text, original spacing and native controls. The parent-sized preview follows recovered centered geometry, native original-item toolbar, actual original-artwork snapshot handoff and source-frame/content/backdrop/shadow springs. The trailing32pt accessory now follows original hover/selection, scroll suppression and recovered pressed/hover palette. Essential remaining work is the LEFT requirement DL33 below. The entry now uses the original SwiftUI renderer/interpolation and exact original-item retirement; the inferred echo is removed. The original filter title/Done/chips, shared0.3-second curve, native query/focus ownership and stable equal-date source order are implemented. The original optional-item view and direct Hide/Trash reducer have replaced the earlier range/plural/confirmation adaptations. Quick Look, available-window routing within the original private context and native filter control sizing/focus are documented adaptations. The extra All Profiles row and equal-date ID sorting are removed. Modern populated/private appearance is unavailable in the empty installed Library; no exact-match or browser-runtime claim. DL-PERF-01 remains after polish. |
| Data and credentials | Local browser profiles, independent Parc Keychain namespace, and direct source-browser import through genuine profile services. The app/onboarding chooser, per-profile category/extension selection and original-destination bookmark insertion are connected; see the browser-import entry below. | Stable signing, full source-specific import/profile-choice experience, unsupported source credentials and recovery/polish remain. Source capabilities and partial outcomes are explicit; no browser functional tests ran. |
| Live integrations | Excluded by the user on October 25; source-owned dependency audit complete | No dedicated Calendar/GitHub/Slack/mail/social implementation, assets, preferences, controls or dependencies were found to remove. Audit covered Sources, ParcNative/ParcHost overlays, Resources and build/package entry points. Ordinary website navigation/search definitions, extensions, local folder/recent-history previews and shared browser authentication remain included. Exact inspected-file hashes and classified findings: `work/arc-live-integration-audit/source-audit.json` and `HANDOFF.md`. |
| Page tools | Find Next/Previous and Use Selection to Find join the original-page route, native text finders and shortcut registry. The recovered floating panel now connects genuine query/document-bound match results without shrinking the page; current-version populated interaction comparison remains in the Keyboard family. Existing zoom, reader, print/save/source and data-clearing routes now include exact-host Developer Mode, Control-D, the page-owned full-URL toolbar and real Console/Network/Inspect actions. Repeated generic/Console/Network commands now close or select the actual frontend panel, with original-document reply guards and exact undocked-window close. Existing native ownership, capture and shortcut paths are reused; see [Developer Mode](developer-mode.md). The independent ordinary Toolbar now shares real page navigation/history, address entry, clipboard, extension popup anchors, page controls and split commands, with exact original-page/window validation. Its View command joins shortcut customization and the recovered Use Both priority. | Existing Chromium docking and initial tools-focus ownership are retained; TOOLS14 docking/restore/focus, TOOLS15 first-edit/stripe/narrow toolbar presentation, TOOLS16 reader/print/save/data-dialog appearance, and TOOLS17 keyboard/AX/hover/disabled/first-edit spring are delivered. Developer Mode completes a bounded feature batch, not every Page Tools or keyboard interaction. ParcNative `devtools_pane` focus-on-appear and TOOLS16 overlay 248 remain an engine-owner apply. |
| Keyboard shortcuts and keyboard gestures | Distinct positional, per-Space selection-history and held-MRU tab commands; native Essentials with live bindings and real actions; versioned migration preserves custom/disabled MRU chords and priorities. Searchable recording, persistent bindings and per-command Prefer Websites / Use Both / Prefer Parc. Use Both arms only after the original focused renderer consumes the key; the validated original menu item runs once, with document/focus/window/binding cancellation and visible Press Again cue. Native editing, IME, keyboard lock and DevTools/extension ordering are preserved. Combined Swift and three native-unit checks pass. | Dedicated high-priority family: complete action/default-binding inventory, hold/release/repeat and multi-key behavior where present, modifier transitions, contextual focus/selection, conflict/recording/priority experience and discoverability. See KBD breakdown below; scripting belongs to its separate family. The recovered five-second hover-aware cue and exact Edit target are implemented below. Command-specific defaults and priority context exceptions are complete (KB17); cue presentation is delivered in KB16. |
| Automation and scripting | Source-owned Cocoa window/Space/tab interface and original-page JavaScript execution preserve stable identity, focused split children, same-page navigation and native close consent. File / Cmd-Shift-N and Cocoa make now create genuine primary-OTR private windows with an explicit normal parent and memory-only app model. Original private native-created windows/DevTools and the empty omnibox retain their actual context. Async creation and commands complete or cancel once; no private session/history/archive writes. Normal scripting permissions and original native requests remain authoritative. | Remaining quit/command/error and collection-order fidelity, private sidebar sharing, private Library/capture/Easel ownership and complete private appearance/motion. Native window/location properties remain read-only without recovered mutation handlers. See the private-window breakdown and [scripting architecture](scripting.md). No browser functional test or Apple Event was run. |
| Windows and lifecycle | Native window/menu termination with beforeunload Stay/Leave checked | Private windows, independent multiwindow selection, Dock/logout, activation/focus and session restoration fidelity |

## Interaction-level family breakdown

**External split-link integration:** the combined 145-source Swift application
passes with warnings as errors and zero diagnostics (288.92 seconds). The actual
model/store and native session pass 30 and 20 assertions after integration; the
15 native router assertions and both pinned native compiler units retain exact
matching inputs. Overlay221 passes exact forward/reverse replay across 537
unique targets. Ordinary page entry is complete; local editor and Favorite
entry, whole-group copy/external dragging and detailed preview polish remain
in their existing work items. No functional browser tests were run.

**Native Cast integration:** the combined 143-source Swift application passes
with warnings as errors and zero diagnostics (67.26 seconds), retaining the
published Full Screen and split-customization changes. All four affected native
compiler units retain exact matching source/header inputs. Overlay219 passes
exact forward/reverse replay across 533 unique targets without changing the
running engine218 inputs. View, page-menu and command-bar entry points are wired;
no browser/device tests or full Media-family completion are claimed.


For **every family and each concrete interaction**, record these dimensions together in this ledger (focused mechanism documents can hold supporting architecture/evidence):

2. **State and transition:** initial/empty/loading/ready/error, hover/pressed/selected/disabled, focus/selection/editing, cancellation, repeated input, interrupted/reversed motion and return to the prior state. Mark irrelevant states explicitly rather than silently omitting them.
3. **Ownership and context:** exact window/page/frame/profile/Space/split/Peek owner; active versus background window, renderer versus native text editing, modal/fullscreen/private context and lifecycle invalidation.
4. **Experience:** geometry, icon/typography/color/material, timing/curve/spring, scrolling, feedback/haptics/audio where observed, accessibility labels/focus and reduced-motion behavior.
6. **Delivery:** actual source/action/backend path, remaining production code, compiler/component-check scope and remaining experience comparison. A button, declaration, asset, generic Chromium capability or passing build does not complete the interaction or family.

### Keyboard shortcuts and keyboard gestures

| ID | Concrete coverage | Evidence and remaining breakdown |
|---|---|---|
| KBD-01 | Complete commands and default bindings, menu key equivalents, dynamic tab/Space/split/window targets, unavailable commands | KB03 reconciles all 219 non-separator MainMenu records, the hidden-shortcut producer and 92 reducer cases, including existing owners, new menu/default wiring, explicit exclusions and named feature contracts ([inventory](keyboard-navigation.md#complete-command-inventory-reconciliation--kb03)). KB04 completes numbered/programmatic execution and native Find contexts; KB38 retains live discovery. New Folder stays unbound from its retained reference appearance, with its original runtime override unattributed. |
| KBD-03 | Website versus browser priority, consumed-key second press, visible cue, changed focus/document/window and modal contexts | Native consumed-key trace and actual priority implementation exist; the selected priority now uses the observed native pop-up. The original menu queue, five-second hover-aware expiry and exact Settings accessory are implemented in KBD-03e. KB17 completes the command-specific defaults (all 41 MainMenu records) and the recovered context exceptions: editable page content shares the same priority, typed-reserved chords stay with the page, and Exit's Press Again requires no modal and expanded full screen. See [keyboard priority](settings.md#keyboard-priority) and [context exceptions](settings.md#context-exceptions--kb17). |
| KBD-06 | Native text editing, IME/composition, keyboard layouts, accessibility, fullscreen/keyboard lock, DevTools and extension commands | Complete under KB17/KB26, preserving actual native/engine ordering and the documented Chromium per-key lock adaptation. |
| KBD-07 | Discoverability: Essentials, menus, tooltips/keycaps, command search, shortcut-change feedback | Complete under KB33–KB38: Essentials presentation/interaction and live valid bindings across menu, tooltip, command-search, Start/Ready and original command-field copy education, including the genuine Peek command. Component/source checks are distinct from physical browser execution and whole-product visual/motion acceptance. |

### Keyboard family implementation checklist

**Current delivery, October 28:** all 38 fixed Keyboard requirements are DONE
under the active source-implementation rule. Recovery owners retire after their
original row's publication. Included absent feature commands remain explicitly
assigned in KB03's feature contracts; they are not silently excluded or claimed
as working. The fixed ledger below retains those boundaries and each row's
check/adaptation limits.

- [x] KBD-01: genuine command inventory/defaults, numbered targets and native
  Find contexts (KB01–KB04); named absent-feature contracts remain with their owners.
- [x] KBD-02: recorder/conflict/reset, layout translation and detail/settings
  presentation (KB05–KB11, KB27).
- [x] KBD-03: original renderer acknowledgment/queue, cue presentation and
  recovered priority contexts (KB12–KB17).
- [x] KBD-04: held/repeated/reversed/interrupted MRU and positional/history
  traversal (KB18–KB22).
- [x] KBD-05: sidebar session and native keyboard/AX traversal/return among
  page, command bar, splits, Peek, menus and popovers (KB23–KB25).
- [x] KBD-06: native editing/IME/layout, fullscreen/keyboard-lock, DevTools and
  extension ordering, with the documented lock adaptation (KB26).
- [x] KBD-07: actual copy/creation/Find owners, Essentials and live discovery
  including Peek Open in and copy education (KB28–KB38).

### Shortcut row-menu removal — KB09/KB11

Native row context menus now expose the recovered Remove Shortcut / Reset
Shortcut to Default entries without selecting another detail. Their original
command/revision/window receipt survives row reordering and refuses stale or
unavailable owners. Selected explicit removal uses the original keycap content
rectangle and native macOS poof effect, with Reduce Motion and weak exact-window
checks; failed persistence produces no removal effect. Reset, recorder Delete,
conflict cleanup and removal of another row retain their separate behavior.
attributed in [Settings](settings.md#shortcut-row-menus-and-removal-effect).
Focused inert checks pass 62 detail/menu and 43 recorder/conflict assertions;
the combined 164-source app check passes with zero diagnostics.
KB09 retains the broader conflict/reset comparison. The subsequent recorder
focus delivery below closes KB11; this row-menu increment alone did not do so.

### Tab navigation and Essentials


| ID | Implemented interaction and states | Remaining coverage |
|---|---|---|
| KBD-04a | Separate Control–Tab/Control–Shift–Tab commands retain the existing held MRU preview, delay/reverse/hold/release/Escape behavior; saved custom/disabled chords and priority migrate with MRU semantics. | Existing held-switcher visual, transition and interruption comparisons remain; this batch adds no browser-runtime verification. |
| KBD-03a | Version-one bindings/priorities migrate atomically to distinct command identities; new defaults cannot take a saved custom chord. Failed save retains usable in-memory bindings and reports the error. Existing native input and menu validation remain. | Recorder/priority cue and full IME/modal/fullscreen/keyboard-lock contexts continue under their parent entries. |

### Shortcut detail presentation — KB11

The recovered right-column producer now supplies the actual intro, unassigned
and bound states, 200-point column and count-sensitive caps. Native title/body
measurement preserves the original 24/8/24-point spacing; a missing binding
hides priority rather than presenting a disconnected preference. The bundled
five-second smiley uses its original vector paths and play-once/Reduce Motion/
were compared with a disposable production component; no browser command or
preference was exercised. The focused recorder now uses the recovered native
layer/label producer, exact delayed halo and actual first-responder lifetime.
Short/long held-modifier previews keep the original 200-point column and native
focus; Escape restores the saved chord without persistence. The passive label
exposes no duplicate accessibility child. The focused native component passes
72 recorder/conflict and 62 detail/menu assertions. [Mechanism and limits](settings.md#recorder-focus-and-detail-transitions)
separate the original appearance/animation evidence from invisible-work and
long-chord fitting adaptations. KB11 is DONE; KB09 remains LEFT for broader
conflict/reset presentation. The fixed family count is 26/38 DONE and 12/38 LEFT,
no scope change; latest movement `(26−25)/38 × 100 = 2.631578947…` percentage points.

### Shortcut editing and priority detail


| ID | Implemented interaction and states | Remaining reference comparison |
|---|---|---|
| KBD-02a | First-responder/AX capture; held-modifier keycaps; commit, Delete, Escape, Tab traversal, repeat rejection and rejected/unsupported completion. Focus, deactivation, removal, disabled and pane changes remove the capture monitor. | Full keyboard layouts/dead keys/IME, Shift-Tab appearance and exact focus/hover/transition geometry. |
| KBD-02b | Saved red conflict and named owners; actual conflicting menu equivalents/native queries are inactive. More/row context removes other assignments atomically. Original 16-point red reveal button scrolls without changing selection/focus; actual Carbon OS shortcuts supply the advisory orange warning. | Original setter, state recomputation and menu projection are attributed. System-warning refresh cadence is a bounded adaptation; no personal OS shortcut changes. See settings saved-conflict contract. |
| KBD-02c | Clear selected binding; reset-one saves default chord/priority and any resulting visible conflict; Reset All directly commits defaults without confirmation. Search, selection and pane departure preserve completed assignments. Exact revision/window receipts reject stale menu actions. | Original action5/client reset path is attributed. Reset/conflict cleanup do not use selected Remove’s native effect; no invented haptic or transition. |
| KBD-03b | Observed native Prefer Websites / Use Both / Prefer Parc pop-up targets the selected action, retains saved conflict priority and disables unsupported bindings. Existing renderer acknowledgment and Press Again cue remain. | Full command-specific defaults and modal/IME/lock comparison; cue geometry/motion is delivered in KB16 and recovered expiry in KBD-03e. No cue haptic is attributed. Renderer-first migration default remains an explicit adaptation. |

### Press Again cue and exact shortcut editor

The complete cue presentation is now delivered as KB16. The original clear
600×600 non-key child follows its actual parent screen frame, with the recovered
Big Key/body/accessory geometry, local-default Space material and exact
scale/opacity spring. The delayed Edit control stays below the body; retirement
revokes input before the original passive one-second exit, and replacement,
1.122 REA and actual light/dark inert native appearance are separated from the
unexercised installed 1.170 website cue. [Details and adaptations](settings.md#press-again-presentation-and-original-window-lifetime).

This bounded KBD-03 delivery retains the actual renderer-consumption acknowledgment and all existing native input ordering. The fixed 129-source Swift cohort passes with warnings as errors and zero diagnostics; the affected native shortcut translation unit passes the pinned compiler flags with private headers. Twenty-three isolated Cocoa assertions cover original menu identity, stale binding rejection, exact Settings selection without writes/recording, actual cue layout, accessibility, focus and accessory hit ownership. An offscreen native cue render was inspected. No browser, renderer or Apple Event test was run.

| ID | Implemented interaction and states | Evidence and remaining comparison |
|---|---|---|

### Creation/capture command defaults — bounded KBD-01 / KBD-07

Four existing real actions now have the shipped defaults: **New Note** Control–Shift–N, **New Note in Split View** Control–Option–N, **New Easel** Control–Shift–E and **Capture Portion…** Command–Shift–2. The original registry applies one binding to actual menu items, Shortcuts default/live keycaps and Actions search snapshots. Existing document/page/capture validation, original profile/window ownership, native editing/IME and recovered command priorities are preserved; there is no new key pipeline or engine contract.


The focused native menu/registry/discoverability/migration component passes 78 assertions; existing migration and copy-default components pass 169 and 25 respectively. The fixed 140-source Swift application passes with warnings as errors and zero diagnostics; no functional browser tests or personal preference changes. Remaining KBD-01 inventory includes New Folder's unattributed runtime override, missing genuine command owners and programmatic/dynamic bindings. Alternate navigation/Zoom/Developer Tools delivery is recorded immediately below. Full context/keyboard-layout and hover/pressed/AX/motion comparison remain open; this does not close the command/default inventory or Essentials family.


### Alternate navigation/page-tool bindings — bounded KBD-01 / KBD-03 / KBD-07

Command–Left/Right now have independent Back/Forward alternate identities and real original-page navigation actions, with recovered native text-ancestor exclusion. F12 has its own editable Developer Tools identity and recovered Use Both priority through the existing renderer-ACK/cue owner. Command–equals and Command–Shift–minus are actual Zoom menu supplements tied to the primary binding, suppressed by explicit customization/disable or a conflicting user chord; that user-choice protection is a stated Parc adaptation. Settings retains three distinct alternate commands, Actions search retains one result per actual operation, and existing primary IDs/chords/priorities are preserved. Symbolic Zoom In also matches the actual Shift-produced plus through its primary owner; a competing saved physical chord suppresses the live symbol equivalent, including for unavailable targets. Active-layout translation and the real input-source notification maintain that suppression without a fixed US alias.

The additive marker preserves saved legacy choices and prevents a new alternate bypassing an explicit parent customization/disable or taking a custom key. Untouched old commands gain the actual new alternates; explicit Reset checks conflicts. Declared defaults survive AppKit clearing a conflicting menu key during insertion. Retained registration/selector REA and installed Settings appearance establish identity, priority and native text ownership; installed New Folder is unbound, so no speculative Incognito collision alias was added. [Mechanism and compatibility boundaries](keyboard-navigation.md#alternate-navigation-and-page-tool-bindings).

The focused isolated native-menu component passes 97 assertions, plus 78 creation-default, 169 migration and 25 copy-default assertions; all seven compiled component inputs match the integrated source. The combined 140-source Swift app, including live Easel transfer and cross-window creation origins, passes with warnings as errors and zero diagnostics in 48.64 seconds. No functional browser tests, personal shortcut changes or new key pipeline. Remaining family work includes original programmatic/dynamic commands, New Folder's exact runtime override, auxiliary DevTools-window contexts, keyboard-layout and full visible-state/AX/motion comparison. This does not close KBD-01/03/07.



### Close Window — bounded KBD-01 / KBD-07

File → Close Window now registers Command–Shift–W, Prefer Parc, an editable Shortcuts entry and one Actions-search row. It owns the original normal/private/popup browser window through a weak one-invocation lease, dismisses only its owned command panel, and revalidates the actual key window before `performClose`. Existing Note composition/save barriers, transfer recovery, genuine native beforeunload/retirement and cancellation remain authoritative. It does not route through selected-tab Archive/Close or a fallback browser behind another window. Saved custom/disabled chords and priorities survive; untouched legacy files receive this newly introduced command, while a saved conflicting chord suppresses its default through an additive marker.


### Full Screen and auxiliary-window boundary — bounded KBD-01 / KBD-07

View → Enter/Exit Full Screen now connects Command–Control–F, Use Both, the
editable Shortcuts row and dynamic Actions title to the exact original native
browser window. Real NSWindow validation supplies title/capability; original
window/key/sheet/close state is revalidated after the owned command panel
returns focus. The command invokes the existing native toggle and will/did
engine lifecycle without synthetic completion or page recreation. Additive
migration preserves explicit custom/disabled bindings and priority, and cannot
steal an existing saved chord.

REA are reused. Installed Arc1.170 View exposes Enter Full Screen; Settings
File explicitly disables Close Window. No reference command was executed and
no functional browser tests ran. The fixed 142-source Swift app passes with warnings as errors and zero diagnostics;
59 isolated native-window/menu/migration assertions and 425 prior shortcut/window
assertions pass on unchanged inputs. Exact auxiliary fullscreen policy, dynamic
command inventory, full menu/focus/AX appearance and overlapping-transition
motion remain open; this does not reopen completed fullscreen engine work or
close the KBD family. See [native window command](keyboard-navigation.md#full-screen-on-the-original-browser-window).

The integrated Full Screen and split-group appearance source passes the combined
143-file Swift application check with warnings as errors and zero diagnostics
(294.92 seconds). All inputs stayed fixed. The 484 window/shortcut and 139
split appearance/title/Undo component assertions retain exact matching inputs.
These app-only changes are published independently of the running engine218
DevTools build; canonical engine inputs remain frozen. No functional browser
tests or native fullscreen transitions were performed.



### Contextual Exit — bounded KBD-01 / KBD-03 / KBD-05 / KBD-07

Exit now has the actual Escape/Use Both Shortcuts entry, custom/disabled binding
and Actions discoverability. Invocation holds the original browser context:
current Peek first, otherwise exact page fullscreen or already-fullscreen
window. Peek keeps its real confirmation/beforeunload retirement. The native
content token checks the original browser/document/page/window and invokes the
real FullscreenController, preserving nested browser-fullscreen restoration;
refusal never falls through to another target. Existing native control/text/IME
and renderer-acknowledgment Escape remain separate from configurable commands.
The original raw producer establishes this split; the current menu transport,
weak one-shot lease and hidden registration are explicit Parc adaptations.
Saved choices/conflicts survive and Reset remains transactional.

MainMenu 1324, action 70 and the complete modal/fullscreen forwarder are backed
Use Both, description and default reset state were inspected without executing
an action or changing a preference. The integrated 144-source Swift application, including Cast and New Window,
passes with warnings as errors and zero diagnostics (200.39 seconds). The
combined native host compiler check also passes with 95 unchanged source/header
inputs; overlay220 retains the published Cast sources and updates the exact
Exit bridge/host fingerprints. Focused components pass 54 new Exit assertions plus 527
existing recorder/window/default-binding assertions (581 total), all inputs
unchanged.
Default-Escape cross-priority runtime comparison, other auxiliary modal
bindings, complete dynamic command inventory, exact focus/AX presentation and
motion/haptics remain open. No browser functional tests, fullscreen transition,
page close or preference mutation was performed in the reference app. See
[original-context ownership](keyboard-navigation.md#exit-the-original-context).


### Copy commands and recovered priorities

Edit → Copy URL, Copy URL as Markdown and Copy URL as Quote are implemented through real command registry entries. The live-page paths share Chromium clipboard policy; Quote requests an actual text-fragment selector from the original page. Full 50-file Swift typecheck and the native translation unit's actual pinned compiler flags pass with zero diagnostics. Focused checks pass 17 copy-default/migration, 19 existing migration and 43 recorder/conflict assertions. Exact source patch reverse/replay passes. No functional browser or clipboard tests were run.

| Child | Implemented interaction | Remaining reference/polish boundary |
| --- | --- | --- |
| KBD-03c | Decoded overrideWebView maps to fresh Prefer Parc defaults for all three selectors. Version-three migration preserves old implicit/explicit Prefer Websites for the existing plain command, custom/disabled chords and saved priorities; reset adopts recovered defaults. Native key arbitration is unchanged. | Other command-specific defaults, the previously recorded priority-cue timing/geometry/context gaps. |

### Website theme data sharing



### Shared Quote selection affordance

Advanced's Shared Quotes switch and the selection-driven sidebar subtitle/icon
mouse drag/multiple-click tracking, release and a 200 ms debounce; its store
inspected without changing the preference or clipboard. Actual native selection
observations and opaque document/window leases feed the existing Blink fragment
generator and enterprise clipboard policy; selected text stays native. Navigation,
selection, focus, capture, security and owner changes revoke stale actions.
Versioned app-wide persistence preserves unreadable/future records. Explicit
Edit → Copy URL as Quote and customized shortcuts remain independent.

The merged 83-source Swift application passes with zero diagnostics. The exact
native compiler inputs and 27 isolated preference/lifecycle assertions also pass.
Factory registration/default, rich tooltip behavior, ordinary Toolbar placement
and exact hover/pressed/motion/keyboard treatment remain open. Enabled fallback
matches the observed installation, and Chromium main-frame/site eligibility is
an explicit adaptation. See [settings](settings.md#shared-quote-affordance) and
[keyboard navigation](keyboard-navigation.md). No browser functional test or full
appearance-parity claim is made.

### Ordinary Toolbar controls

View → Show/Hide Toolbar (Command-Shift-D) and Advanced full-URL display share an application-owned persisted preference, including actual private windows. Native page strips connect existing history/navigation, original command-bar sessions, clipboard policy, extension action leases, page controls and split transactions. The selected Toolbar becomes the extension popup anchor and the sidebar hides duplicate controls. Developer Mode retains its separate strip.


### Interface sound and reordering haptics

| Interaction | Implemented/evidence | Remaining comparison |
| --- | --- | --- |

CAP-02/CAP-10 acquisition feedback uses this owner; crop, frame, output, stale and failed results do not add cues. See [Settings feedback architecture](settings.md#interface-sound-and-reordering-feedback) for the recovered event paths and their limits.

### Webpage window dragging

| Interaction | Implemented/evidence | Remaining comparison |
| --- | --- | --- |

The combined application source check covers 78 Swift sources with zero
diagnostics; isolated
components pass 56 assertions for preference preservation, original event/window
identity, hit testing, movement accounting and cancellation, with no real window
drag.
See [Settings architecture](settings.md#webpage-window-dragging).

### General quit warning

| Interaction | Implemented/evidence | Remaining comparison |
| --- | --- | --- |
| SET-QUIT-01 | General **Warn before quitting** persists application-wide across regular/private windows. The original browser owns a custom **Quit Parc?** sheet; Cancel has no close effects, Quit enters existing Notes-save/native webpage consent, and **Quit, and don’t ask again** changes the preference before that consent. Repeat Quit follows the recovered ordinary path; original-owner loss and repeated controls retire once. Current Arc1.170 dispatcher/factory/reducer REA establishes the window selection, three actions, preference ordering, 62pt app image and custom native sheet. | Off-on-absent matches the inspected checkbox but is not a recovered factory default. Current AppKit geometry, typography, keys/AX, modal/stale-owner protection and approval scheduling are explicit adaptations. Exact current sheet appearance/motion and factory registration remain. 122-source Swift application check passes with zero diagnostics; eighteen isolated real preference/native-control assertions pass without a displayed window; no functional browser test or real Quit ran. See [quit warning](settings.md#warn-before-quitting). |

### General preview settings

SET-PREVIEW-01: General's original-window-owned Previews Settings sheet now edits the same Folder/recent-page preferences used by the sidebar menu. Immediate changes retire active previews and refresh existing windows' folder/menu/accessibility actions; Done/Return dismisses, parent close retires controls, and stale callbacks cannot write. Folder and genuine native-history providers stay included; live mail/calendar rows and vendor links stay excluded. Arc1.170 UI/AX plus REA rows/getter/setter and default Done action establish the contract; native AppKit presentation, shortened sheet and existing Confluence support are explicit adaptations. Swift compilation is separate from runtime/appearance acceptance; exact motion/material remains whole-product polish. See [Settings](settings.md#general-preview-preferences).

### Global current-item Rename — bounded KBD / NAV-04

Rename Current Tab… now uses the genuine command search/customizable shortcut
registry with no default key. It targets the originating window's selected
ordinary sidebar item or whole split container, reveals its row and enters the native editor;
custom binding/priority, original page/profile lifetime, cancellation, atomic
persistence and memory-only private names retain their owners. A keyboard
current-Space sidebar-item map/reducer is recovered; installed 1.170 command-label
appearance is directly observed without activation. Hidden menu registration and
pre-edit disclosure/layout are Parc adaptations. Favorite concrete editing,
rename-hint choreography, regional hover/title/shortcut/unread states and
full keyboard/focus/motion coverage remain open. No browser functional tests.
The original 21 selection/registry assertions and 35 native-editor/model
assertions remain covered by the current split-title check below. See
[Rename ownership](saved-tabs.md#global-rename-ownership).

### Whole-split container Rename

The recovered concrete split editor now commits a separate original-container
name through global/custom-shortcut, context and AX entry. It never renames the
focused child. Native selection/IME/Return/blur/Escape, original group/page/local
editor leases, failed-write refusal and private memory-only persistence are
wired end to end. Clearing restores child rows; saved names and current native
capture controls survive ordinary group reconstruction and window restoration.
Child page/saved titles, history and selection are untouched.

| Interaction | Source implementation / evidence | Remaining boundary |
| --- | --- | --- |
| Entry/target | Actual original selected split, context/AX and existing command registry; original group ID + optional-title consumer/reducer recovered. | Whole-Favorite original-container dialog routing is delivered in the group appearance slice below; no focused-child substitute. |
| Editor/commit/cancel | Shared native field, Title placeholder, select-all, trim/clear, once-only completion and original lifecycle checks; atomic persistence. | Exact installed named-editor appearance remains open; original-container Undo is implemented below. |
| Presentation/ownership | Recovered custom-info replaces child-items projection; current saved name, original activation/action/capture owners preserved. | Title/icon-present/editing condition, count glyph/geometry and child-action submenu are explicit Parc adaptations; full producer hover rules and exact close/reset/keycap/motion remain open. Group icon/reset consumers are delivered below. |

The exact 110-source private Swift cohort passes with zero diagnostics. Focused
checks pass 46 split-title model/native-editor assertions, plus all 35 ordinary
editor and 21 global-command assertions, with fixed inputs. No browser functional
See [split-title ownership](saved-tabs.md#split-container-rename-ownership).


### Container Rename Undo / Redo — bounded KBD / NAV-04

Whole-split Rename now registers **Rename Item** on the originating window's
existing Undo stack, sharing chronology with ordinary close operations. Undo /
Redo changes only the original container name, publishes shared labels atomically,
and preserves current pages, selection, geometry and same-profile relocation.
Cancel/no-op retains Redo; write failure is retryable; native editable/IME/security
ownership, retirement, profile changes, conflicting shared names, deletion and
window teardown are guarded. Actual OTR models keep name history in memory.

Arc1.122 original item/old-title registration, WindowID manager and inverse
registration for Redo are recovered; installed 1.170's dynamic Edit-menu Undo name
was inspected without executing any command. The exact 115-source app compiles
with zero diagnostics. Focused components cover actual model persistence,
original-window stacks, competing shared names, failure/retry, retirement cancel,
private memory and native field cancellation: 41 new Undo, 46 split-title editor
and 23 existing async-stack assertions pass with exact fixed inputs. Shared-name conflict checks, current-profile gating and no
selection effect are explicit adaptations; full inverse focus/effect choreography,
[container-name Undo](saved-tabs.md#container-name-undo-and-redo).

### Ordinary-tab Rename Undo / Redo — bounded KBD / NAV-04

Today/pinned manual Rename now records **Rename Item** on the original window's
existing stack after successful persistence. Undo/Redo changes only that original
tab's optional custom title; current page/saved destinations, selection, split and
same-profile membership survive. Other windows receive the shared label without
an extra stack entry. Equal/cancelled edits retain Redo; actual write failures are
retryable. Conflicting names, archive/deletion, changed or retiring profiles,
native retirement and original-window/modal/security gates refuse or suspend the
inverse. Native text/IME keeps its existing Undo owner; actual private stores
write no name/history files. This adds no Favorite editor or membership command.

inverse is established with fresh REA. Existing installed 1.170 inline field and
dynamic Edit-menu appearance are reused; no reference rename/Undo was performed.
The exact 117-source private Swift cohort passes with zero diagnostics, plus 41
new model/stack assertions, 35 existing native-field/model assertions and 23
existing async-stack assertions. The checks include actual disk failure/retry,
shared conflicts, original identity after moves/membership, mixed tab/container
selection/invalidation rules, modern Rename menu/AX/motion and Favorite editor
remain open; current-name checks and no selection effect are explicit Parc
adaptations. No functional browser tests. See
[ordinary-tab name Undo](saved-tabs.md#ordinary-tab-name-undo-and-redo).

### Sidebar transition hierarchy — explicit Cmd-S regression

The previous implementation committed nested native geometry with actions disabled, then animated only five root layers. The transition now uses the recovered AppKit implicit-animation group around the actual view-tree layout. Preparation flushes the old layout; repeated requests retain current presentation geometry and one final generation. Cancellation removes only the exact current geometry animations created by this owner, preserving replacements and unrelated properties. Floating spring definitions are temporary; New Space, native selection, Peek, Library and Reduce Motion keep their existing lifecycle owners.

The focused AppKit component passes **39 assertions**, covering nested bounds, immediate reversal, repeated requests, interruption/replacement, recovered floating constants, original animation dictionaries and unchanged responder identity. It uses an off-desktop inert window without a browser or input. The pinned complete **148-source Swift check** passes with warnings as errors and zero diagnostics. No functional browser test was run.





Each piece had an independent review, a fix pass and a separate verification; the integrated series had a three-lens review. Focused checks: SidebarChrome 114,591 layout + 64 strip, SidebarWindowButtons 71, SidebarMotion 56, SidebarHover 69/25, SidebarAccessibility 45, SidebarResize 50/20/60, SidebarPreview 99, SidebarPreviewTitles 52, BrowserToolbar 118; whole-module typecheck with zero diagnostics. No functional browser test ran and the running app was not inspected, so SIDE10, SIDE16 and SIDE17 stay LEFT; the owner contracts are in the handoff note.


- **Item list outline (SIDE17).** `SidebarOutlineView` exposes the list as an `AXOutline` of `AXRow`/`AXOutlineRow` + `AXCell`, one row per entry including the pinned header and divider, with `AXDisclosing` for folders, a selection that survives disclosure, AppKit's outline notifications, and the outline as the focused element while the list stop has focus. Row heights match the 1.170 tree within its pixel rounding.
- **Preview anchor (SIDE12 fix).** A preview card now anchors to its row's own visible part (`visibleRect` intersected with the row's bounds) instead of the list's visible area.

Each lane had two independent reviews, a fix pass and a separate verification; the merged series had a three-lens review with two skeptics per finding, and its seven confirmed findings were fixed: focus left in or restored into the hidden sidebar (major), selection commands on the hidden list, and five documentation accuracy issues. Focused checks: SidebarChrome 114,610 layout + 12,127 outline rows (overlay and legacy scrollers) + 66 strip, SidebarOutline 169, SidebarAccessibility 68, SidebarMotion 73, SidebarWindowButtons 76, SidebarHover 69/25, SidebarResize 50/20/60 with PageContentResize 32, PageContentResizer 37 and PageRenderFrames 19, SidebarPreview 99, SidebarPreviewTitles 52, BrowserToolbar 118, DeveloperMode 13, DownloadLibrary 424/39/44/10, Favorites 25/49/50/96/49/145, sidebar rows 60/157; a syntax-only native compile of the overlay against the pinned tree; whole-module typecheck with zero diagnostics. No functional browser test ran and neither app was inspected at runtime, so SIDE16 and SIDE17 stay LEFT.



Checks: each row's independent verifier ran the whole-module typecheck (zero diagnostics) and every focused check on its commit (SIDE17: SidebarAccessibility 83, SidebarOutline 183, SidebarWindowKeyLoop 46, SidebarMiniPlayerFocus 33, Easels and EaselPagePool among them; SIDE10: SidebarPacing 105 and SidebarMotion 87 with their negative controls). Both commits applied onto main without conflicts or code changes over a docs-only base change, each pushed on its own. Neither app was launched. At the user's direction (October 27) the on-screen look-and-feel checks were skipped and SIDE10 and SIDE17 are DONE on this verified code (16/17, 94.1%). SIDE16 is still in its row run.

### Sidebar preview presentation — SIDE12 (DONE)


### Sidebar preview titles and modifiers — SIDE13 / SIDE14 (DONE)


### Sidebar hover reveal and dismissal — SIDE11 (DONE)


### Sidebar accessibility inventory — SIDE17 (DONE)


### Sidebar chrome spacing — SIDE16 (DONE)



### Sidebar edge resizing — SIDE16


### Favorite tile owner and actions — bounded NAV-04 / KBD-05

| Interaction | Implemented source | Evidence and remaining parity |
| --- | --- | --- |
| Primary activation / selection | Dedicated native Favorite button with original-item lease; selected state independent of keyboard outline; current native select owner retained. | Original App Tray item/phase payload recovered. Full click-phase, double-click/modifier behavior, app-tray multi-selection and native numbered shortcut overlays remain untraced; ordinary button release activation is retained Parc behavior. |
| Context / Control-click | Fresh original-item context provider; Close available only through exact original owner, Reset through existing original-page reset. | Wrapper menu-provider and Control-click route recovered. Actual modern Favorite menu arrangement and hover Close/Reset surface unavailable in the inspected personal profile; no new hover glyph invented. |
| Accessibility / keyboard | Full title, Favorite role, exact URL help, dynamic original Reset/Close actions and native press/menu entry; Control–Space uses existing original-ID session. | Original button/Favorite/title semantics recovered; full AX navigation and current hover appearance remain open. No page text/IME shortcut pipeline added. |
| Press / lifecycle | Recovered .99 scale and .5/.2 spring; current-presentation interpolation; removal/hide/disable/deactivation cancellation. | Original transform/helper constants recovered; cancellation and Reduce Motion are explicit Parc adaptations. Modern dimensions, favicon fidelity, exact hover/selected/theme/pressed comparison and haptics remain. |

The combined 101-source Swift cohort passes with zero diagnostics, and the isolated AppKit Favorite-control component passes 20 assertions covering original action refresh, stale refusal, title/role/selection and removal. The reusable runner passes shell syntax checks. Browser functionality was not tested. This delivers the bounded owner/actions/press slice, not all Favorites or NAV-04 parity.

### Favorite tile presentation — TAB16

Favorite tiles now follow the recovered App Tray tile instead of a themed
monogram button. The tray spans the sidebar with 8-point insets and gaps, at most
four columns of at least 47 points, row-balanced (five Favorites lay out 3 + 2,
seven 4 + 3) with 47-point rows on a 55-point pitch. Each tile has 12-point
continuous corners. Real page favicons come from the existing original-page /
exact-profile icon owner at 16 points; split Favorites show one cell per page
with 12-point icons, 2-point gaps and outer-corner masks. Idle and hovered
tracks only in the key window. A selected tile shows a white fill (0.8 light,
0.45 dark), a blurred saturated wash of its own icons, a 2-point selection ring
carved by the same page layout, and a 1-point black shadow at opacity 0.1;
selection itself changes instantly. The existing press spring, pointer, menu,
overlay stack (recording dot, highlight ring, Peek badge, music particles) and
dim while their window is neither key nor main.

| --- | --- | --- |

Not verified: on-screen appearance of the overlays, dim and ring (the runnable
package predates this source); particles stay hidden until the pending engine
while Parc's outline is a tile layer below every overlay; they do not overlap.

Checks: the Favorites component script passes 25 control, 49 pointer, 50
split, 86 reset-URL and 24 reset-target assertions, 49 tile-geometry
assertions (grid, split cells, rings and the selected/dim style table) and
145 overlay assertions (host list, eligibility, recording mapping, geometry,
springs, emitter cells, tints, sprites, z-order, idempotent updates, dim,
highlight and developer-tab ring). The whole-app Swift typecheck (188
`Sources/ParcCore` + `Sources/ParcApp` sources, warnings as errors, with this
checkout's bridge headers) passes with zero diagnostics. The engine change
passes a syntax-only compile with the pinned GN flags; it is not linked. No
on-screen parity is not claimed.

### Favorite pointer phases — bounded NAV-04 / KBD-05

Primary/Shift Favorite clicks now activate the original item on first down;
exact Command-down resets its saved home and selects the same original;
double/repeated down uses existing reset eligibility without entering Rename.
Keyed tile reuse preserves the original pointer through sidebar redraws, and
one-shot native leases plus drag/owner/Space/deactivation cancellation prevent
release replay. Ordinary outline multi-selection and native text/IME remain
unchanged. Actual AppTray producer/reducer, key/multi-set predicate and topApp
reset branch are traced; modern idle appearance exposes no Favorite tile and no
personal state was created. Full 123-source Swift compilation passes with zero
diagnostics; isolated AppKit checks pass 20 existing plus 28 pointer/lifecycle
assertions. No functional browser tests.

This closes the bounded primary/Command/double-click owner, not all App Tray
selection. Option split/duplicate is delivered below; exact Option–Command is
collection selection outside the outline and populated
hover/pressed/AX/focus/motion and haptics remain.
See [Favorite pointer ownership](saved-tabs.md#favorite-pointer-phase-and-saved-home-reset).

### Saved-tab Reset eligibility — bounded NAV-04 / KBD-05

Reset row/context/AX/menu availability and Favorite repeat-down now use the recovered full-URL equivalence rule rather than raw string inequality. Focused-Favorite Option duplication uses that same result for saved/custom versus live title, while retaining its exact original current URL. Case, HTTP→HTTPS, one `www.` prefix, ordinary fragments, one trailing slash and empty/`utm_` query differences alone do not enable Reset. Hashbang, retained query order, ports and genuinely different destinations preserve their distinct rules. Actual reset/navigation, forced Command reset, original identities and stale-owner/refusal handling are unchanged.


### Reset All visible saved targets and original navigation

Reset All now uses the original ordered hierarchy: profile Favorites, then current-Space pinned siblings, expanded folder descendants and original split children. It excludes collapsed descendants and Today roots, applies actual saved-home comparison, blocks staged profile removal and preserves selected webpage/folder disclosure. Menu enablement uses the same producer. The existing one-use original-page actions issue independent native navigation requests in this order; Chromium owns asynchronous beforeunload commit/refusal. No serial consent or optimistic model URL update was added.



### Favorite Option release — bounded NAV-04 / KBD-05

Exact Option first release now inserts the original Favorite after focused pane;
if already focused, it creates a fresh same-profile Today copy from the current
native URL without resetting its original saved home or cloning history. Existing
pane focus, group identity/geometry and all original native owners are preserved.
Release-time modifiers, one-shot window/page/selection leases, original Profile
and retirement/security gates, and atomic persistence cover dispatch through
native page creation and resulting focus. Failed saves expose no partial copy.
Option–Command is positively traced to LittleBrowser internalLink/window creation
combinations retain original ordinary activation. See [Option ownership](saved-tabs.md#favorite-option-split-and-focused-duplication).

Fresh REA on the actual duplicate and LittleBrowser factories records
`ev_4ead7a4ca4c19a72b50e4c6a9d81b56f0dd53aaadd8d3c27fa614541f745aa99` and
`ev_d9390888d80710f57dac4219d6b0fc1e16f5ed96c093ff9fd0de2011b27d687e`.
The fixed 124-source app cohort passes Swift with zero diagnostics; isolated
checks pass 20 native Favorite, 35 pointer and 39 model/persistence assertions,
including durable-save refusal, stale selection and profile retirement. No
browser functional test, modifier navigation or personal-profile mutation ran.

Remaining: exact empty/unready/full-capacity fallback, foreign physical-owner
transfer, inactive first-mouse and collection multi-selection; current-Space
Today placement/weight normalization are explicit model adaptations. The
unchanged installed 1.170 reference had no populated Favorite to inspect, so
modern modifier/hover/AX/geometry/motion/haptic parity remains open.

### Favorite / App Tray modifier corner cases — TAB17

**What changed.** The App Tray has no multi-selection to recreate: Shift and

- **Down and release:** a first click selects on down only in the key window and
  without Option. Every other first click is resolved on release (in Parc only
  the Option click, because the activation gate refuses a non-key press), and a
  repeated down always takes the reset branch.
- **Inactive window:** the tile does not accept first mouse, so the click that
  activates an inactive window does not press, select or drag it.
- **Option release:** with no presentation the Favorite is selected normally; a
  fifth pane shows “Cannot Add New Pane”; the focused Favorite at capacity is not
  duplicated.
- **Page in another window:** selecting such a Favorite moves its page here with
  window's current Space.
- **Option release, page in another window:** the page moves here in the
  background and is inserted after the focused pane through the existing
  Favorite split owner.
- **Split Favorite, page in another window:** selecting a split Favorite (or a
  Favorite in a split) moves each of its pages that another window holds, one
  transfer at a time, then selects the whole split.

plus Mach-O/Swift-metadata helpers, kept outside Git in `claude-tab17-rea/tools`
and `round2/`; the shared Ghidra corpus was still not ready):

  with no `setAllowsMultipleSelection:`. `didSelectItemsAtIndexPaths:`
  WindowState `+0x1b0`) and masks the flags with `~0xf0`. The double-click branch
- **Moving window content:** `WindowsData.reparentWindowContent(for:from:to:trigger:)`
  `targeted(itemSelected | itemMoved)` and `untargeted(itemDeselected |
  keyed by sidebar item; that a split reparents each child's content is inferred
  from that key, not traced through `selectItem`.
  A zeroed `location` is `WindowToast.Location.window`: the factory's location
  content from the map at state `+0x58`, else the split view's focused content at
  `+0x40`), looks it up in the content → sidebar-item map at `+0x68`
  if the parent is a split view, else the item. `isSelected` (byte 0) is set when
  Favorite containing it, is selected; other displayed Favorite panes are not.
  emits `moveSidebarItems` and makes no call through the multi-set `modify`
  no longer outline rows, so they leave the set. That AppKit reports the changed
  selection after the move is an inference.
  is in the App Tray wrapper or tile superclass chain. An AppKit probe shows that
  `NSButton` accepts first mouse and `NSView` does not.

Details are in [App Tray selection](saved-tabs.md#app-tray-selection-and-modifier-corner-cases).


- **`isHighlighted`** (byte 1) is true when the optional item ID at
  order it is `highlightedItemID`, but that name is inferred. The Parc producer is
  the sidebar keyboard highlight (`keyboardHighlightedItem`).
- **`isSelected`** (byte 0) follows the focused pane, as recovered above, and
  the Favorites grid now selects only the tile holding the focused pane.
- **`shouldDim`** (byte 5) is `!state[0x21] && !state[0x22]`; neither field is
  named.

**Adaptations.**

- **Moved page placement:** if the window's Space, panes or focus changed before
  the page arrived, the moved page is selected normally.
  five seconds, held while hovered ([toasts](toasts.md)).
  clears it before routing the release.

**Remaining** (TAB17 stays LEFT): Favorite tiles must mark only the focused
pane's Favorite, or its split, as selected. The rule is settled, but the change
belongs to the Favorites grid section of `SidebarView.swift`, which the TAB16
lane is editing; the contract note in the handoffs gives the exact change.

**Checks.** `tests/WindowPresentationTests.swift`, compiled with all of
`Sources/ParcCore`, passes 116 assertions, including a new one that a Favorite
moved for an Option release leaves the destination's panes until placement.
`scripts/test-window-presentation.sh` still omits `SplitPaneControls.swift` and
does not build. The whole-app warnings-as-errors typecheck (`Sources/ParcCore` +
`Sources/ParcApp`) exits 0 with no output. The transfer, split insertion and
selection paths are app-level and have no model test. `scripts/test-favorites.sh`
covers unchanged sources and was not rerun this round (round 1: 253 assertions).

### Favorite context Rename dialog — bounded KBD / NAV-04

Favorite context **Rename…** and the equivalent accessibility action now select
the original Favorite and open its separate, required-name **Rename Tab…**
dialog. Native single-line text/IME/local Undo remain intact; explicit Rename
persists only the manual title and registers **Rename Item** on the original
window's stack. Cancel/no-op preserves Redo, failed writes retain the draft, and
original page/profile/Space/selection/retirement leases refuse stale commits.
Favorite membership, saved/live URLs and page identity remain unchanged.

The recovered topApp menu action12 selects the original item then builds the
window-owned dialog; its actual text callback reaches the shared original-title
Undo updater. The installed 1.170 sidebar had no Favorite tile, so no state was
manufactured to inspect it. AppKit sheet geometry, select-all/key/AX policy and
stale-owner safety are explicit adaptations. Global Favorite Rename routing,
modern dialog appearance, whitespace validation, focus/motion/haptics and wider
menu state details remain open. No tile hover control or AI title behavior was
added. See [Favorite dialog ownership](saved-tabs.md#favorite-rename-dialog).

Exact fixed application check: 119 Swift sources, zero diagnostics. Meaningful
isolated components pass 26 Favorite dialog/model assertions and all 41 prior
original-tab Undo assertions, covering actual persistence/failure, conflicting
names, membership/retirement cancellation, unchanged saved/live destinations,
literal Unicode input, native IME/caret handling, once-only commit, cancellation
and retry. No functional browser tests or Apple Events ran.


### Favorite Type Travel Rename — bounded KBD / NAV-03

The command bar now offers **Rename Current Tab…** for its original selected
Favorite and opens the existing native dialog without replaying context
activation. The exact current-item payload, original window/Space/profile/native
binding/page/local-editor lifetime and immutable title/membership identity survive
panel dismissal. Native keyboard/pointer/AX dispatch, IME, explicit cancel,
failed-save draft and shared Rename Item Undo retain their existing owners.
Ordinary/split inline fields and the global menu/custom shortcut are unchanged.

REA distinguishes TypeTravel18's current SidebarItemData eligibility and direct
WindowID dialog call from MainMenu15's editing-ID setter. Installed Arc1.170
query/icon/title and Escape focus were inspected without executing a result; no
Favorite tile was present, so Favorite-specific result/dialog states remain
unobserved. The separate global Favorite menu/shortcut consumer remains open,
as do ordinary/split Type Travel dialog equivalence, exact ranking, native icon
pixels, modern AX/availability and motion/haptics. No AI title behavior added.

The fixed 120-source application typechecks with zero diagnostics. Focused
components pass 27 original command/model/Undo assertions and 26 existing native
dialog/persistence assertions. No browser functional tests or Apple Events ran.
See [Favorite command ownership](saved-tabs.md#favorite-rename-in-command-search).

### Ordinary Today and pinned row actions
The bounded NAV04 row batch now routes pointer, context and accessibility
activation/Close/Archive through exact original model/Space/split/wrapper/page
leases; stale and unavailable actions refuse instead of reporting unconditional
success. Reset retains genuine original-page navigation and saved-URL semantics,
with original Space and transfer-recovery guards. Private Today still closes
without normal archive writes. Existing typed keyboard cursor, multi-selection
and whole-split owners remain unchanged.

| Interaction | Implemented owner/state | Evidence and remaining comparison |
| --- | --- | --- |
| Row activation / context | Pointer-down original lease, release-inside, Control-click/secondary menu, native AX row/selected state and truthful press. Drag/removal/key-window loss cancels pending activation. | Installed 1.170 selected Today row/context observed. Exact whole-row pressed/hover-region/subtitle transitions remain open. |
| Close / Archive | Separate native control, current availability, captured one-use command, original retirement/beforeunload, dynamic menu/AX; saved close and Today archive remain distinct. | Original SidebarCellButton native target/hover/press owner, Close 14×2 rounded bars and GrayA4/GrayA5 fills recovered ([TAB19](#ordinary-row-presentation--tab19)). Slot placement and exact disabled/keyboard appearance remain adaptations. |
| Reset | Fresh original-page action, actual saved destination, menu/AX and retained hover slot. Stale Space/transfer/replacement/navigation refuses. | Existing original WebContent reset trace retained. Exact reset URL equivalence, regional icon/title/shortcut producer and current pinned-row appearance remain open. |
| Button motion / lifecycle | Recovered .95 scale, .6 damping ratio / .3 response spring with presentation reversal; hide/detach/disable/window loss cancels. | Raw-function REA plus full-image imports/constants; no modern pressed movie or haptic claim. Native focus ring and settled Reduce Motion are adaptations. |

The merged 104-source Swift application passes with zero diagnostics; 26 isolated
AppKit control assertions and exact patch reconstruction pass. No functional
browser test, tab activation/reset/close, clipboard action or personal preference
family or its remaining favicon/unread, reset-region, modifier, spacing and polish
comparison. See [saved-tab ownership](saved-tabs.md#ordinary-row-action-ownership).

### Item keyboard and accessibility — TAB22

is one button with a spoken title instead of a repeated description. Web rows
are described as "Tab", Easel/Note rows as a plain button, and tiles as
"Favorite". A row speaks its visible title. A Favorite speaks its page title; a
split Favorite speaks its own name, otherwise each page title joined by ", ",
and "Favorite item" when it has none. The split container row reads the same
row titles. Original activation, menu, Close/Archive/Reset/Rename and move
owners are unchanged.

| --- | --- | --- |

Evidence came from bounded `llvm-objdump` ranges and Mach-O method-list,
category, field and key-path helpers (the shared Ghidra corpus was still
importing). Split container rows (`SplitViewCellView`) and Note rows
accessible names. Sidebar-wide AX structure and focus order stay with SIDE17.
A tile's AX element is its native button cell, so the component check confirms
the button role, title and description values in-process, not what the AX

Checks: the whole-app typecheck (all `ParcCore` and `ParcApp` sources, warnings
as errors) exits 0 with no diagnostics. `scripts/test-favorites.sh` passes 25
Favorite control assertions (5 new for title, description, role and the split
title rule), 41 pointer, 42 split, 86 reset-URL, 24 reset-target and 24 geometry
assertions. Rows have no isolated component; the typecheck covers them. No
browser functional test ran and the running app was not inspected. See [item
keyboard and accessibility](saved-tabs.md#item-keyboard-and-accessibility).

### Sidebar unread ownership — bounded NAV-04 finding

and distinguishes the `mobile` badge from the GitHub-enabled automatic-live-folder
`dot` branch. That dedicated service producer is excluded. A generic local dot
is not supported by this evidence, so production source is unchanged; current
Parc background/copy archive protection remains an explicit independent policy.
The generic tab constructor accepts unread as an input: ordinary creation,
restoration and split-child propagation remain unresolved rather than being
inferred from false-initializing container constructors. Installed 1.170 idle
sidebar appearance was inspected without input; no active unread badge/AX/motion
state was available. No browser functional tests ran. Exact document patch replay
and source-unchanged fingerprints pass; no compiler rerun is claimed for this
document-only result. See [unread ownership](saved-tabs.md#unread-state-and-badge-ownership).

### Ordinary row favicon presentation (bounded NAV-04 follow-on)


| Interaction/state | Coverage and remaining boundary |
| --- | --- |
| Async update/private/lifetime | Genuine native producer, deletion, original OTR page, stale query and view disposal are wired. Image-only notifications do not create history visits. No normal-profile history lookup for private/unknown/mixed owners. |
| Unread | Original mobile/dot enum and centered6-point native dot recovered. Full producer/clear/timing mapping remains open; no guessed `isUnread` badge. |
| Saved versus live title/icon | Separate original fields are recovered; complete saved/custom/live precedence, rename and reset-icon transitions remain open. Favorite imagery remains separate. |

The merged 106-source application, exact native/facade compiler checks and 13 isolated AppKit reply/lifetime/color assertions pass. No functional browser test; these checks do not close the complete Sidebar/NAV04 family. See [saved-tab image owner](saved-tabs.md#ordinary-row-image-ownership).

### Ordinary row presentation — TAB19

focus/hover fills. An unflipped, non-interactive `SidebarRowBackgroundView`
The current item gets TabCellBackgroundCurrent and a one-point
TabCellShadowSelected shadow below it. The row a sidebar drag starts from,
multi-selection gets Mutiselected, and hover gets SidebarItemBackground. Fills
points, centered in a 24-point slot 6 points inside the row; titles draw from
36 points in at 14-point regular. TabCellView's stacks place the label by its
alignment rect, 2 points inside each edge of its frame where AppKit bounds the
text, so the label starts 2 points before the inset and ends 2 points past the
36.9 with JPEG blur; the screenshot's titles render pixel-identically with
either trailing edge, while a title whose next character fits in the 2 points

row. A window that is neither key nor main dims the row fill and shadow to half
opacity. Close is a 24-point square 6 points inside the trailing edge, and the
title runs to 2 points before it, or to 10 points from the edge while Close is

- The icon region (leading edge to the slash) and the body region each get
  their own hover fill with 12-point corners. Pressing the icon region uses
  TabCellBackgroundPressed.
- A 4 × 15 TabCellSlash slash sits between icon and title. The title then
  starts at 38 points.
- The icon region's tooltip is "Reset Tab" plus the reset shortcut, shown only
  while a reset shortcut is bound.
- Hovering the icon shows "Back to Pinned URL" below the title, in the
  11-point system font and the theme's title color at half alpha. The title
  lifts 7 points and the subtitle fades in over 0.1 seconds. Meanwhile the
  icon shows the saved destination's icon. Holding Command switches the
  subtitle to "Separate From Pinned Tab" and restores the page icon.
- A click on the icon resets the page through the existing original-page
  lease. A Command-click separates instead: the live page moves to a new Today
  tab at the top of Today, the pinned item keeps its identity and returns to
  its saved destination, and "New Tab Created" appears. Either way, the pinned
  item is then selected unless it is already showing; after a separation it
  entry for separating, and Parc adds none.

or subtitle, and no selection, hover or ring fill of their own. Each child of
the selected split shows TabCellChildBackground in a 28-point cell, rounded by
the smaller of 8 and half its width. A child places its 24-point icon slot 2
points in, its 14-point title 6 points after the slot, and Close 2 points
inside its trailing edge. Close shows while the split is hovered, if it clears
the icon. The title needs more than 20 points. A child no wider than its slot
shows only its centered icon.

Page, Space, split and action ownership are unchanged.

| --- | --- | --- |
| Loading | `TabCellState` has no loading member; `isLoadingAITitle` is excluded AI. | Implemented: no row loading glyph. |

`00674b60…4050`); TabCellChildBackground is black or white at 7%. Shape,
geometry, motion and producers come from the 1.122 executable: bounded
`llvm-objdump`, Swift field and key-path metadata, names from the executable's
export-trie region, and whole-text call scans (no decompiled output is kept in
Git). The whole-program Ghidra corpus was not ready.

TAB19 is complete.

### Today divider, Clear and New Tab

October 31 presentation pass (no added credit). The rows between the pinned
[D] code read, [I] inference, [O] observed.

| Element | Recovered reference | Parc status |
| --- | --- | --- |

The ~6-point offset between the captures and Parc's renders is the captures'
origin: relative to the address field, Parc's rows, divider and New Tab land on
traffic lights sit 22 points above the field in both. No list-offset follow-up
remains.

An offscreen render draws an NSTextField's text twice: the field's own
`draw(_:)` and its private `NSTextFieldSimpleLabel`. In raw sRGB bytes, black
at 0.3 measures 0.51 that way and 0.30 from the private view alone, and on
screen only that view's layer composites. Render harnesses must skip the
field's own drawing before comparing translucent labels.

Checks: `tests/SpaceManager/check.py` (142 assertions) covers the divider at
rest, on sidebar hover and after the fade-out (frames, border, hit testing,
accessibility and VoiceOver's press), Clear never a key view, re-entry during
the fade-out, leaving during the fade-in, a render while hovered, no divider
and no hint without Today, drops at New Tab's halves, and New Tab's geometry,
colours, plate (including the window resigning and taking key, and a render
moving the row under the pointer), press springs, a release bounce that
survives the render, action and missing tooltip. Negative controls fail as
expected: Clear always shown, a divider without Today, a fade-out that never
hides, a fade-in completion that hides, no press scale, a press removed on
completion, a New Tab tooltip, a plate that ignores the key window, no pointer
re-read on taking key or after a render, and a focusable Clear.
`tests/SidebarChrome` checks the slots, insets and border thickness.
November 1: the same check (156 assertions) covers New Tab as the current
item (fill, shadow, palette title colour, no animation, hover kept under the
fill, restored at once), a selected tab and split that are not current while
it holds and are again after it, split children losing their plate, a
Favorite keeping its look, the live-metadata path refusing while the flag
differs from the last render, and source assertions on the window's wiring
(Command-T and Add Split set it, the sidebar search does not, closing the bar
clears it, only the window's own sidebar receives it).

Checks:

- `scripts/test-sidebar-rows.sh` passes 60 row-control assertions (12 new: the
  Command hover state and the separate and reset commands) and 160 appearance
  assertions (the fill host stays unclipped so TabCellShadowSelected can paint
  into the cell padding, and translucent current/hover fills composite onto
  the theme).
- `scripts/test-favorites.sh` passes, including 96 saved-tab reset assertions
  (10 new for separation in the store).
- `scripts/test-sidebar-favicons.sh` passes 13 assertions.
- The whole-app Swift typecheck (warnings as errors) exits 0 with no output.

on-screen parity is not claimed.

### Ordinary sidebar titles and inline Rename

This bounded title slice preserves separate custom, saved and live page sources.
The ordinary-row context/AX Rename starts an actual native select-all editor and
atomically saves only the manual override. An empty edit clears that override;
legacy sessions remain readable, private edits stay memory-only, and actual
write errors leave the published model unchanged. Original Space/profile/group,
wrapper/page, window and retirement/transfer identity govern completion.

| Interaction | Implemented source | Evidence and remaining comparison |
| --- | --- | --- |
| Hover subtitle / shortcut / unread | Existing row owners preserved. | Regional reset/resetAndSeparate state and two key-path inputs are retained but the complete visible text/keycap mapping is not established. No genuine hover input was available in CUA; no hover animation or unread producer/clear rule is invented. |

The final fixed 106-source cohort passes the full Swift compiler check with
zero diagnostics; the focused model/native-field component passes 35 assertions.
preference change was run. This closes the bounded original-row title/editor
implementation, not the whole Today/pinned/Favorites presentation family.
See [title ownership](saved-tabs.md#sidebar-title-and-inline-rename).

### Sidebar Select All and plural commands

This bounded Folders / KBD-01/03/05 / NAV-04 follow-on uses the original sidebar selection and genuine retirement coordinator. The full 69-source Swift compiler check passes with zero diagnostics; model checks pass 540 assertions and copy/default migration checks pass 25. No functional browser or clipboard test was run. [Sidebar selection](sidebar-selection.md#select-all-and-plural-commands) records exact retained menu/reducer evidence, installed singleton-menu appearance and adaptations.

| ID | Implemented interaction and states | Remaining comparison |
|---|---|---|
| KBD-03d | Existing Close Tab ID/chord now uses recovered overrideWebView → Prefer Parc for fresh settings/reset. Additive migration preserves previous implicit/explicit priority and custom/disabled chords. Select All remains a fixed native editing action. | Additional explicit menu defaults are delivered below; programmatic priority and existing arbitration/cue/context gaps remain under KBD-03. This does not complete the keyboard family. |

### Shipped shortcut priorities — KBD-03 / KBD-01

Twenty-four existing command owners now use their explicit shipped menu priority
for fresh settings and Reset: Back/Forward, positional/linear-history/MRU tab
commands, command bar, New Tab/Window/Incognito, Reopen and Hide/Quit/Minimize
prefer Parc; Add/Close Split, New Note and New Note in Split, Print and
Sidebar/Pin/Reveal use Both. Legacy omitted website-first choices
are ambiguous in the actual writer and conservatively preserved by an additive
marker. Explicit priorities, custom/disabled chords, previous migrations and
original native/IME/cue dispatch remain intact. See [priority defaults](settings.md#shipped-command-priority-defaults).

REA's static NIB decoder plus an ordered raw-array cross-check confirms the
executing either command. The fixed 131-source Swift application passes with
warnings-as-errors and zero diagnostics; isolated components pass 169 migration,
25 existing copy/default and 43 recorder/conflict assertions. No browser
functional tests ran.

The ordered raw-array cross-check recovers ten explicit policies omitted by
the older flattened metadata; all ten implemented owners are included. Close Window
and Full Screen now have the original-window owners recorded above. Exit now has
a mapped registry owner;
policies, complete keyboard/context comparison and exact cue/editor motion stay
open; this does not close KBD-03 or the full command inventory.

### Folder disclosure commands


| ID | Implemented interaction | Remaining comparison |
|---|---|---|
| FOLD-05a | Ordinary Delete and tab Close now bind original-window creation referrers, creation-active identity and the actual ephemeral referrer pool. Adjacent children, pooled related siblings, the original creation-active item and the real previous-selected item in the matching outer Space/Profile container precede the existing previous/next whole-item fallback. A Favorite can return to an original same-Profile tab in another Space through an exact destination-Space close receipt. Background selection and surviving panes retain focus. Native-created pages carry actual original source/document ownership, including same-Profile matched routes into another physical window; plural Duplicate and copy-to-folder receive fresh nil-referrer/current-active receipts. Existing native consent, original split ownership and folder durable publication are preserved. | Accepted Peek Expand/Add to Split replace the original window pool and preserve the modal source in both creation fields. Cross-Profile creation relationships and fresh-window active-before behavior beyond the recovered URL-only action remain unclaimed. The previous-selected consumer and producer are now attributed; nested folders share their outer Space, and Favorites compare actual Profile. Accepted opened duplicates update the pool through ordinary creation; saved-only copies remain pool-neutral. Date mapping/ties and focused-ID notification timing are explicit adaptations. Ordinary Close retains its existing deferred persistence; Folder Delete remains durable. Duplicate undo remains unestablished. The preceding creation carrier passes its pinned native unit; full 138-source Swift passes with the completed same-container branch. Components pass 51 new original-selection/consent/durable-return assertions, plus 49 provenance, 39 copy, 35 plural-duplicate, 696 store and 114 window assertions. No browser tests. See [selection and creation ownership](folder-commands.md#selection-after-ordinary-delete). |
| FOLD-05b | Ordinary Delete Undo/Redo restores exact original folders, archived tabs, mixed order and split provenance through one durable transaction and the originating window’s selection owner. Native Edit-menu and Cmd-Z routing preserve text/Easel/editable-page undo; actual native close consent runs again for Redo. Exact group/revision binding, stale originals, cancellation, failure retry and window-close invalidation are wired end to end. | Window cache, insert/regroup actions, focused-step selection and redo close registration are REA-backed. Async UndoManager adapter, archived-afterimage validation, sibling anchors and prompt count are adaptations. Toast/motion, Duplicate undo and gated folder archives remain; typed descendants are implemented in FOLD-05c below. The merged 75-source Swift application and pinned native shortcut compilation pass; exact checked inputs retain 641 model, 114 window and 23 UndoManager assertions. Overlay194 includes the two mapped native changes; no browser tests. See [ordinary Undo](folder-commands.md#ordinary-delete-undo-and-redo). |
| FOLD-05c | Single ordinary-folder Delete/Undo/Redo now accepts mixed web/Note/Easel descendants and complete mixed splits. Actual original-Profile document capabilities preserve shared contents/assets and aliases outside the tree; exact native Note editors are retained and their composition/save barrier is repeated at final close admission. Undo restores original sidebar/document IDs, retains shared edits and remains retryable when original data temporarily becomes unavailable. | REA confirms the original non-split insertItem versus split regroup owner; local store validation/archive DTO and final-editor barrier are adaptations. Multi-root context entry, gated folder archive, Duplicate Undo and precise modern appearance remain separate. Full 123-source Swift and real 34 mixed-store / 8 native Note / 696 model / 23 UndoManager assertions pass; no browser functional tests. See [mixed-document close ownership](folder-commands.md#mixed-document-folder-delete-and-undo). |
| FOLD-06 / NAV-05e | Same-profile cross-Space Move to for original tabs, whole splits, nested folders and ordered multi-selection. Both hierarchies, physical native ownership, Note/Easel editor identity, pending transitions and exact original menu state are revalidated. Save-before-publication preserves metadata/order/geometry and refuses foreign-owner groups. Original-window completion focuses the destination Space, expands ancestors/nonempty target, scrolls and requests attention without page activation. Shared typed reveal is reusable by genuine command results. Ordinary New Space and Move to → New Space now share an original-window name/Profile/icon/theme draft, parked live owners, Cancel/footer restoration and one durable create-and-move transaction. Storage failure retains the draft. Whole ordinary splits with mixed original folder/section placements now move as one destination container, including inside moved folders; original child/group/document identities and saved metadata survive. Partial groups still refuse. | Retained 1.122 configuration producer, profile resolver, commit/toast and exact WindowAction getter prove same-physical-window ownership and reveal versus select. Installed 1.170 original tab menu/submenu inspected only; no move executed. Destination append, native menu/AX styling, notice geometry/expiry and stationary attention are adaptations. The New Space delegate/commit/cancel and after-anchor insertion are separately REA-backed; native draft appearance was inspected without creating content. The original item/parent mutation is separately REA-backed; flat-record placement normalization is an explicit adaptation. Cross-Profile and Favorite-to-New-Space moves, physical-window mixed-placement drag admission, full selection/order corner cases and exact toast/hover/focus/motion/haptics remain. The integrated 148-source Swift application passes warnings-as-errors with zero diagnostics; exact final source hashes retain the component results: 121 move, 62 New Space, 114 window-presentation and 44 existing Favorite-move assertions pass. The expanded move checks cover original document/saved metadata, nested order, stale/partial/foreign owners, storage reload and failed atomic saves. No functional browser test. See [cross-Space moves](folder-moves.md#move-to-another-space). |
| FOLD-06a / NAV-05 | Same-profile physical-window drag transfer for original folders, whole splits and ordered roots. One original-window grant, collection claim, actual native TabModel/WebContents transfer, durable sidebar commit and same-editor handoff preserve IDs, document sessions and geometry. Attachment/save failure rolls surviving originals back; uncertain external ownership retains the complete collection and genuine consent recovery. | Actual distinct WindowID producer/drag state and same-Profile Core transfer are REA-backed. Destination focus for local items, retained empty shell owner, collective rollback and recovery presentation are explicit adaptations. Cross-Profile/Favorite transfer, drag-copy/Undo and exact modern appearance remain open. The combined 140-source Swift app and three actual pinned compiler units pass; 41 collection and 51 previous-return assertions pass together, and the command-bar checks pass 82 native-editor and 36 background assertions. Five additional native fixture cases compile only. No browser tests. See [physical-window collection transfer](folder-moves.md#move-a-collection-to-another-physical-window). |
| FOLD-02 / NAV-04 | Ordered, window-local multi-selection for visible Today/pinned items, folders and whole splits. Modifier/range selection preserves active page/pane identities; context/AX copy, original-item atomic moves/drag and beforeunload bulk close are source-complete. | Favorite/app-tray selection, plural Quote, cross-focus selection, exact outline anchor corner cases and modern appearance/motion remain. Native outline/ordered-ID mechanism recovered; view-backed range and controls are explicit adaptations. 540 model assertions pass; no functional browser tests. See [sidebar selection](sidebar-selection.md). |

**Ordinary split placement correction:** moving a complete same-Space split now preserves its original group and tab identities even when its children began in different folders or saved sections. The existing explicit destination applies to every child in one transaction; exact snapshots, Profile ownership and separate Favorite admission remain. The focused retained hierarchy-move check passes 35 assertions and the existing Favorite-move check passes 44 against the fixed Core. The broader BrowserStore suite passes this corrected case but stops later at its separate per-Space Favorite-layout expectation; no full-suite pass is claimed. Cross-Space mixed-placement groups remain outside this correction. No browser functional test ran.

### Sidebar keyboard session


| ID | Implemented interaction/state | Observed/recovered evidence and remaining comparison |
| --- | --- | --- |


### Reopen Closed Tab


### Closed-item restoration — TAB20


**Implemented.**

- **Closed Peek.** A user dismissal that closes the Peek page records its current URL and parent. Reopen selects the parent and calls the new engine method `-[PCNativePage openPeekWithURL:]`, which offers the page through the existing Peek adoption. The engine source is published and pending the next overlay apply (see [shared engine ownership](#shared-engine-ownership)). Swift checks `responds(to:)`.
- **Folders.** A committed folder Delete, and its Redo, push one step. Reopen restores it through the folder Undo transaction, with original folders, children, order, split provenance and each folder's expansion. Undo and Reopen expire each other.
- **Lifetime.** The history and the saved slot stay in process memory, so a relaunched window starts empty.



**Adaptations.**

- Ratios: the returning pane keeps its original share, measured against the current members' original shares.
- Every pane step carries the regroup, and steps follow model order.
- Survivors and Peek parents must be live, usable original owners in this window.
- A Peek parent that is not loaded is selected first; its step stays for the next Reopen.
- A folder step covers the whole deletion transaction.
- At this earlier TAB20 delivery, Parc did not restore `itemLastActiveDates`;
  the subsequent Windows and lifecycle increment records them per window.

**Remaining.** Nothing for TAB20. The Peek reopen becomes active once Codex root applies the published engine source.


### General navigation and gestures

| ID | Concrete coverage | Evidence and remaining breakdown |
|---|---|---|
| NAV-03s | Native website scoped-search offers, entry, query and exit | Native implementation complete: real Chromium keyword hints carry exact session/result/publication ownership; entered website scope drives the actual keyword provider and preserves the existing full search navigation request, including POST/headers. Engine/pref changes, profile retirement, original page/context loss, stale offers and cancellation invalidate production state; OTR uses its actual originating Profile. The native unit passes pinned compiler syntax checking; no browser tests ran. Shell pill/Tab/Escape integration now uses these actual native publications and requests. A lost-scope error remains deliverable across coalesced provider notifications and stays sticky until explicit editing, so a preference update cannot silently reroute scoped text through the default provider. Space entry uses the exact selected native offer and originating profile preference; empty Backspace restores the preceding query, while Escape restores the original session input. Native extension keyword scopes now have a separate genuine event-action owner (see NAV-03s extension delivery below). Full Type Travel ranking, scope switching, universal restoration and motion parity remain open. |
| NAV-06 | Peek entry, Back/Forward within Peek, close, expand, open in split and opener return | Native/shell integration preserves actual adopted WebContents and explicit Shift-link OpenURLParams. Ordinary current-tab automatic entry is source-integrated with original-request admission and authentication exceptions. See PEEK entries for controls, focus, lifecycle and motion limits; no cancelled URL replay. |

### Actions scope — bounded NAV-03 / KBD-07

Empty-input Tab now opens the actual **Actions** command-only scope. Existing
original menu, Manage Passwords, Space, folder, pin/copy, Favorite and Rename targets supply up to
100 rows with live keycaps and original dispatch; no search/navigation fallback
is inserted. Empty Tab/Backspace leave the scope, nonempty Tab remains editing,
and Escape restores the empty open panel before a second Escape returns original
focus. Website scope tokens/menu/restoration remain separately owned. Actions
edits issue no native queries and cannot adopt stale autocomplete publications.
Native composition, original window/Profile/page lifetime and the sidebar
keyboard session remain authoritative.

REA recovered the real native Tab action, empty-query tuple construction,
appearance confirmed Actions entry/list/query/toggle/Backspace/Escape without
executing a result. The fixed 131-source Swift cohort passes with zero diagnostics
under warnings-as-errors; 67 actual AppKit scope/editor/pill assertions pass.
No browser functional tests ran. Local command matching/inventory/order,
empty-result/AX wording and existing layout are explicit adaptations; broader
Type Travel coverage/ranking, full restoration/IME/theme combinations, hover,
pressed, animation and haptics remain open. See [Actions scope](command-bar.md#actions-scope-command-only-type-travel).

### Contextual Favorites membership — bounded NAV-03 / KBD-05

**Favorite Tab** / **Unfavorite Tab** now appear as genuine contextual typed actions for the original eligible ordinary-tab collection, or active ordinary tab when no collection exists. Favorite appends those exact items to the Profile’s Favorites; Unfavorite prepends them to Today in the captured current Space. Atomic persistence preserves original page IDs, pinned home, current URLs, selections and native/local editor owners. Mixed membership, stale item/parent/Profile/window, split/folder targets, private/popup/Peek and security/retirement/transfer states refuse rather than redirect. Existing tab results already switch to Favorite/pinned/Today identities and are not duplicated.


### Command-bar Pin to an existing folder — NAV-03 / FOLD-01


REA recovers the list provider, **Pin to** prefix, collection/current-item fallback, parent predicate and actual ordinary move-items branch. Installed query/Escape reference contained no named folder destination, so exact modern capsule/plural/modifier-held appearance remains unverified. See [Pin to an existing folder](command-bar.md#contextual-type-travel-pin-to-an-existing-folder) for explicit matching/expiry/notice adaptations. The distinct force-open duplicate-to-folder branch is delivered for ordinary web collections below; typed Note/Easel reference copies are delivered below. Full Type Travel ranking, Undo/attention timing, motion/haptics and detailed visual/AX parity remain separate. The fixed 118-source Swift app compiles with zero diagnostics; 45 actual model, durable-store and AppKit row assertions pass. The seven updated existing check runners pass shell syntax checking. No browser functional tests.

### Command-bar copy to an existing folder — NAV-03 / FOLD-04

Command–Option–Return on the original **Pin to [folder]** row now copies ordinary tabs/Favorites, complete ordinary folder trees, whole splits and ordered collections into the exact same-profile destination. Fresh identities and mixed order persist in one save; originals, selection and pages remain unchanged. The genuine all-window page URL or original saved fallback feeds only new pages. The recovered indexed policy eagerly opens the first five root items; folder descendants are lazy while split children use their separate eager policy. Existing native background-page ownership and failure/retry presentation are reused. Retirement/security, source/destination snapshots, actual Profile, original item incarnation and intervening selection remain authoritative.




### Command-bar retained-panel background open — NAV-03 / KBD-05

Command–Option–Return now follows the recovered force-open action before the split bit: actual native navigation opens a distinct background Today page without dismissing the command bar or selecting/splitting its original page. Repeated opens clone the complete immutable native request into new one-shot operations, retaining original POST/headers/transition/Profile; existing web-tab rows classify their actual original address while typed menu/Space/Folder/local-document routes retain their identities. Original document/window/Profile/Space/result and edit/selection generations govern admission and completion, including exact OTR ownership and stale refusal. The new unread model item preserves the original split and return selection; failures retain the complete token for explicit retry. See [force-open](command-bar.md#force-open-while-keeping-the-command-bar-open).


### Command–Return native field-editor force-open — NAV-03 / KBD-05

Command–Return and Command–keypad Enter now reach the existing retained-panel background action from AppKit's actual `noop:` control-delegate phase. The original selected row and complete native request remain authoritative: POST/headers/transition, original normal/OTR Profile, document/window/Space, scope, async cancellation and one-operation admission are unchanged. Typed folder copy and command dispatch retain their existing owners. Pointer Command-click and the prior Command–Option key-equivalent path are unchanged; marked text, editing commands, unrelated key codes and unsupported modifiers remain native. No new physical-window route or URL replay is added.


### Command-bar suggestion deletion — NAV-03 / KBD-05


### Command-bar selected completion and Tab — NAV-03 / KBD-05


### Command-bar default-result inline completion — bounded NAV-03 / KBD-05


### Command-bar split submission

Website scoped search is also source-integrated: the combined 52-file Swift cohort and exact native search unit pass compiler checks without diagnostics. Tab enters the actual selected keyword provider; scoped requests retain their original native owner. This is compiler evidence, not functional browser verification.


| Interaction | Implemented source | Evidence and remaining comparison |
| --- | --- | --- |
| NAV-03 query-result keyboard cycle / KBD-05 | Up/Down wrap the current query's actual table results, scroll the selected original row into view and retain input focus/native suffix selection. Existing request/typed-target identities, background-open expiry, disabled rows, IME and original-session guards remain authoritative. Empty-query/sidebar traversal keeps its separate owner. | Arc1.122 actual input/weak SuggestionsView/presentation/table consumer recovered with fresh REA; installed 1.170 first/last wrap, suffix and Escape focus inspected without activation. The real AppKit component passes 27 assertions and the fixed 111-source Swift application passes with zero diagnostics. Empty-query recency remains an adaptation; exact physical-key aliases, all IME/AX/layout states and motion/haptics remain open. No functional browser test. See [cyclic selection](command-bar.md#cyclic-result-selection). |
| NAV-03 pointer/keyboard selection ownership | Pointer hover has an independent row highlight and genuine delete accessory; it preserves the keyboard-selected original result, input completion/caret and Return/Copy target. Direct row mouseDown/AX retains exact publication/payload and existing typed/native submission, with key/owner/IME/expiry guards. Original accessory hit testing, reuse/detach/deactivation cleanup and pointer background-open selection continuity are connected. | Actual Arc1.122 separate hover/selection witnesses, selected-color priority and original-suggestion action callback recovered with fresh REA. Existing installed 1.170 selected-surface/focus reference is retained; modern hover/pressed color, exact motion/haptics and broader modifiers remain unobserved or explicit adaptations. Actual AppKit components and whole-source compilation are separate from browser behavior; no functional browser tests. See [pointer ownership](command-bar.md#pointer-hover-and-original-row-activation). |
| NAV-03c offer and entry | Actual selected native result owns Search [site]/Tab accessory. Native Tab and button share exact opaque-offer entry; no host/URL matching, local-command offer or IME interception. Accepted entry clears query and displays the actual native scope name. | Arc1.122 selected-row→action6→active-engine candidate→empty scoped query traced; Arc1.170 actual accessory/Tab/pill inspected. Space entry and scope menus/switching are implemented in their bounded rows; exact hover/pressed/disabled comparison remains. |
| NAV-03d scoped results/submit | Only genuine native keyword-mode matches appear in scope. Return and recovered Option-Return preserve original complete navigation tokens. Empty/failed scope has no fake query, URL template, default-provider or local-row fallback. | Actual native keyword provider is an independent-engine adaptation. Full ASE ranking, extension keyword dispatch and builtin Type Travel actions remain separate. No browser functional test. |
| NAV-03e exit and lifecycle | Escape leaves native scope and restores original session input selected; second Escape returns original eligible page focus. Offer/snapshot identity, profile/window/page lifetime, publication ordering and cancellation remain native owned. Lost scope clears rows and keeps an error until explicit editing/closure. | Arc1.170 Cmd-L address restoration observed; Cmd-T/sidebar empty restoration follows the same Parc owner. Universal query restoration, Backspace, full keyboard/AX behavior and interruption-state appearance remain. |

### Website scope gestures and shipped definitions — bounded NAV-03 / KBD-05 follow-on

The private combined 52-file Swift cohort and both affected native units pass their source checks with zero diagnostics. The source is based on the frozen scoped UI plus the final integrated-184 native backend, retaining sticky invalidation and coalesced error publication. No functional browser tests, page destination actions or preference mutations were performed. Keep the encompassing NAV-03/KBD families open.

| Interaction | Production behavior and evidence | Remaining comparison |
|---|---|---|
| Space/Tab entry | Actual selected-result offer and profile preference; Space enters only for the recovered old-query-plus-one-space transition. Real native scope entry preserves profile/session and complete original navigation tokens. The bridge exposes the actual flag; the hint switches between Tab and recovered “Space or Tab.” Arc1.122 helper/strings and Arc1.170 Tab-only appearance are separately attributed. | Installed preference-enabled Space appearance/pressed/focus states, full keyboard-layout and IME combinations; no reference preference was changed. |
| Empty Backspace and re-entry | Recovered native backward-delete commands exit only an already empty scope, restoring the immediately preceding query with end caret. Nonempty text deletion remains AppKit editing, retaining scope. Each accepted re-entry captures a fresh preceding query. Direct Arc1.170 empty-delete/deleted-selection/re-entry observations corroborate retained reducer ownership. | Complete restoration matrix across other scope types and entry surfaces; exact undo/selection behavior outside this bounded path. |


### Split drag and typed sidebar groups


### Split-pane commands


| ID | Implemented interaction and states | Evidence and remaining comparison |
|---|---|---|
| NAV-05c | Main-menu tracking, command search and page-menu actions share actual availability and original target identity. Peek/other-window/modal/fullscreen/retiring/transfer contexts cannot affect a split underlay. Start/Easel receive real local focus after native deselection. | Existing real native selection/security lifetime plus recovered application-owned focus effects. Multi-pane hover/pressed/selected styling, accessibility announcements, haptics, interrupted motion and full keyboard-layout behavior remain comparison work. No new gesture/haptic/animation was invented. |

### Page capture interactions


| ID | Implemented interaction | Remaining comparison or production work |
|---|---|---|
| CAP-01 | Real File/page-menu/command-search region, visible-page and full-page actions; original document/Profile/Space/window identity and native screenshot policy. | Original modifier gesture/default binding, full menu placement and unavailable-state appearance; visible-page entry is an explicit adaptation. |
| CAP-02 | Page-coordinate drag selection and genuine element hover/click capture use the original document/viewport and compositor pixels. Latest opaque target offers drive the recovered expanded rounded outline; click revalidates the same element before copying. Exit/drag/retake/lifecycle cancellation, Return/Tab/Escape, accessibility actions and Reduce Motion are connected. Full-page native capture retains cancellation cleanup. | Exact grayscale treatment, cursor artwork, reference spring timing, interrupted-motion appearance and haptics. The source-owned camera cursor, 3-point drag threshold and 120-ms path interpolation are explicit adaptations. Combined app/native compiler checks pass; no browser functional test or runtime parity is claimed. |
| CAP-03 | Actual PNG preview; searchable keyboard/mouse output actions; crop from original pixels, Retake, Escape and original-focus restoration. | Richer editing, exact preview/palette placement, focus/hover/pressed treatments and motion. Current crop/layout are explicit adaptations; Portrait is covered by CAP-08/09. |
| CAP-04 | Copy writes actual PNG and checks success; native Save sheet writes the chosen file or reports the error. Direct New Easel and original UUID-bound Easel rows use real local asset/document/undo persistence. The actual macOS Compose Message service receives the genuine image and reports cancellation/failure separately from completion. Save to Library persists original bytes/metadata, updates the same saved item after edits and supports toggle removal. Combined app compilation and 20 production importer assertions pass. | Exact destination ranking, optional message attribution and share-composer appearance. The immutable revision transaction and local destination ordering are explicit adaptations. |
| CAP-05 | Original-document/selection/profile/security/geometry invalidation, stale-result rejection, own-output-sheet lifetime and truthful capture failure. | Full appearance/interruption comparison. Current deadlines and concurrent-DevTools refusal are documented Chromium adaptations. |
| CAP-06 | Screenshot, website stream state and external filesystem media have distinct recovered owners; [CAP22](capture-capabilities.md) completes the bounded producer investigation. | No shipped standalone recording workflow is established by the recovered entry/session/output contracts. Imported movies and website indicators do not become a recorder; CAP23 retains actual OS-media discovery/permissions. |
| CAP-10 | Implemented requested unified flow: Portion, Visible Area and Full Page share one preview, crop, Frame/Edit/Remove Frame, Copy/Save/Library/Easel/Messages palette. Framing never recaptures the viewport; original and cropped PNGs survive reversible composition. File/page controls expose the three acquisition modes, with Capture Visible Area in the excluded Boosts control area and during portion selection. Original document/profile/window/security cancellation remains authoritative. | The new placement, cancel-to-preview and reversible state are intentional Parc improvements. Focused production compositor/state checks and the combined 62-file Swift app compiler check pass. Integrated appearance, interruption, motion and haptic comparison remain; no browser functional test is claimed. |

### Easel text editing and styles


| ID | Implemented interaction and states | Reference and remaining coverage |
|---|---|---|
| EAS-03 | Native typing and range-format undo/redo, atomic saving of accepted edits, coalesced document history and document fallback; failed range validation/save preserves published state. Shared-session changes retire obsolete native history without resetting semantically identical updates. | Local undo/storage/weak delegate ownership recovered; typed ranges, grouping and fallback are Parc adaptations. Original full coalescing and multi-object selection policy remain. |
| EAS-07 | Native paragraph authoring: Text / Heading 1–3 / bulleted / numbered, exact touched paragraphs, nested Tab/Backtab, Return continuation/exit, Backspace outdent, structural renumbering and one native undo transaction. Heading semantics survive durable storage and rich clipboard; original object-wide palette and image importer remain intact. | REA native paragraph/list/selection owner and 32/26/22-point heading constants recovered. Installed ordinary text controls inspected; rich paragraph menu appearance unobserved. Current-family heading styling, indentation, numbering/Return defaults and third palette row are explicit adaptations. Inline images are implemented below; exact palette/reducer parity remains open; typed markdown is tracked separately below. |
| EAS-11 | Content-specific pointer/context/marquee selection; original group move/resize alignment and 24-point neighbor spacing, native velocity admission/session hysteresis, reversible Command suppression and checked Use Alignment Guides control. Changed targets retire guides; exact selected originals, transient previews, cancellation and single durable undo remain authoritative. | Actual content witness/ShapeView REA `ev_be34cff112449cd84cde56b936f2be6e3846c828e751068b4a385cf15874a613`; SnapGuides owner/acceptance REA `ev_9f03810f94262ac8535ea19b863eb38eeb0d4207a797ed8a57594d2a54f4acc7`. Full fixed 72-source Swift and 177 model / 255 native text / 53 native canvas assertions pass. Point-coordinate proximity, stable target order, event-derived velocity, local toggle and accent guide lines are explicit adaptations. Canvas/drag-begin anchors are delivered below; complete hover/AX and exact active-guide appearance remain; no browser/visual acceptance claimed. |
| EAS-12 | Canvas left/center/right guides use recovered 42/1000 margins; each original gesture captures exact active anchors and resizes independently about its starting horizontal/vertical centers. Live Option adds axes; Command suppresses new snap corrections without rewriting captured centering. Exact original document/window cancellation and one shared-session undo remain. | REA weak canvas producer `ev_1e5fd7b4c3f0cfbc635d71800f49cf6b590b77417a10aa9fd06ba41ff27d99cb`, active snapshot `ev_9dcf27a0debdb5d96ac7083de684643e14f2541a3d4c3ff141449ec05feac607`, captured-axis lookup `ev_bfc8750917bc8749d3a1614db3d2bfb74af484cfc5c32be0ce1b68984c33ed60`. Point-coordinate conversion and width-change cancellation are explicit adaptations. No invented persistent document guide state or vertical canvas margin. Fixed 72-source app check has zero diagnostics; reusable components pass 197 model/store, 255 native rich-text and 63 native canvas assertions. Endpoint/aspect controls are delivered below; exact guide/hover/AX appearance remains; compiler/components are distinct from browser/visual acceptance. |
| EAS-14 | Inline image authoring uses the original native text selection, centered line boundaries, exact PNG/JPEG/TIFF bytes, shared-session atomic persistence, delete/undo/redo and reopen. Native file/PNG/TIFF and RTFD import, version-3/legacy private carriers, selected-range RTFD export and explicit plain-text fallback are connected; active composition and failed saves preserve the original text/document. | Dedicated weak-container/original-size image cell, U+FFFC range factory, native RTFD-first paste and cell writer recovered; fresh REA `ev_5128d9bf90496e0c5bc367b9f7f082a14d06b99926c6ed175d9edcb59b909f7c`. Byte-bearing JSON, bounded formats/budgets and enabled rich-editor images are explicit adaptations. Easel-specific reference enablement, exact image hover/selection/context/AX appearance, non-image attachments remain; embedded browser objects are covered below. The merged 77-source app compilation has zero diagnostics; reusable components pass 233 model/store, 290 native text and 87 native canvas assertions. See [Easel architecture](easels.md); these checks are separate from installed appearance and browser acceptance. |

### Local Notes restoration



| ID | Implemented behavior and remaining coverage | Evidence / completion boundary |
|---|---|---|
| NOTE-03 | New Note / New Note in Split View are real File-menu and menu-derived command-bar commands. Original window/Space/Profile owns the saved Note tab, original split panes survive creation, close/reopen retains document identity and private mode cannot open normal Notes. Typed local Note addresses select the original current-profile document; native WebUI translation reserves the Note host. | Menu actions 18/19 are recovered. Shared rich text is a primitive, not an Easel canvas substitute. No invented default key equivalent, fake WebUI, native page clone or URL replay. |
| NOTE-05 | Recovered centered document constraints, responsive split-pane margins, native title/body measurement, bundled Nunito34 title/18 body and actual paragraph/cursor/selection/link styles. The actual Blueprint→WindowContent backing now supplies the named translucent NotesBackground in inherited light/dark appearance, including load errors; pane composition restores ordinary opaque backing when Notes leaves. Named default BodyText remains semantic across save/reopen/formatting/private clipboard; explicit authored RGBA and legacy runs stay fixed. Separate load errors, retained save drafts, selectable read-only/tombstone text, native Title placeholder/IME and formatting retirement remain intact. | Layout REA `ev_41ff9b56bc17e5dc81755c6387d9bfcb5823f9d1712ceeb6eb4d5741a79738bc`; actual background producer REA `ev_15148dded5153c2a10a147e981ff96fdc209fb061982a53704918549acf7fc59` plus complete native color field/key-path chain. The Share palette remains excluded. Surviving 1.170 light/dark resource bytes, Parc’s optional semantic-ink storage tag, native backing integration, local error/footer/AX and current-AppKit measurement are explicitly attributed adaptations. Exact historical compositing/theme inheritance and hover/motion remain; retired Notes was not visually activated. 126-source Swift and actual Notes32/314/8/23, shared310/export20 components pass; no browser functional test. Notes stays prioritized. See [document appearance](notes.md#native-document-appearance-and-semantic-ink). |
| NOTE-06 | Paragraph gutter uses recovered 42×30 control/five-point native text gap, Aa/H1–H3/plus and disclosure, 0.33 idle/full hover opacity, 4pt backgrounds and exact owned tracking-area enter/exit. Retained metadata is revalidated against original body/revision/attributes; movement cannot retarget the open menu, exit/layout do not revive stale hover, key/IME/read-only/owner loss revokes action. Actual trailing empty-line geometry owns its end-of-body plus. Native line-content spans exclude terminators; concrete image-bearing attachment cells suppress only their own line. The recovered newline-half branch retains separate zero-length action/icon ranges and original-window anchor through refresh/menu admission, with native formatting and Undo. The document-owned 34pt icon menu retains original eleven-slot grouping, inline four-option emphasis expansion, actual checked/hover state, gutter-centered containment and stale-control invalidation; original formatting/save/Undo stays authoritative. Gutter and compact-menu named colors now resolve light/dark appearance through their original distinct checked/hover/text consumers, including the recovered half-point dark-only menu border; active controls and exact target survive redraw. | Original SwiftUI control and pointer handlers are recovered with fresh REA; current native NSButton, strict snapshot lease and footer/AX fallback are explicit adaptations. Factory/body/reducer REA establishes compact dimensions, initial nil keyboard selection and in-place expansion. Native viewport scrolling, divider/shadow, layer stroke placement, keyboard/AX focus and current symbol contours are adaptations; color names/state gates are 1.122 and surviving asset values are separately attributed 1.170, without historical pixel equality. Actual producer/container image gate and newline boundary are recovered. Current Unicode-safe glyph mapping and distant-canvas rejection are explicit TextKit adaptations. Original font-only gutter classification now uses the first actual font run and exact32/26/22 sizes, after recovered list text predicates; newline-only empty caret state uses its exact typing font or Plus. Current AppKit list-marker adaptation validates the actual marker/list record. Original UnorderedList/OrderedList mapping and separately attributed surviving1.170 vector contours now drive both gutter/menu at14.4pt. Historical1.122 contour-byte equality and motion remain unobserved. Retired Notes was not visually activated; no functional browser tests. |

The merged 88-source Swift application passes with zero diagnostics. Local components pass 24 store, 14 native editor and 23 tab/retirement assertions, including real write failures; existing model and shared rich-text checks remain separate from browser or historical visual acceptance. No functional browser tests were run. These checks close the first implementation delivery only. They do not complete Notes or demote its remaining structured editing, import/export and historical experience work.

Notes paragraph-format follow-on: fresh REA `ev_72dfd6f18dc7112bd60a4182d63f6d40312c116f5a0dc42639d3a64296ea0fc8` establishes the fullBlob writer and `ev_a6dc92b75af7e2119f84d77a609e00d38ca59a4484b601f34a38f1da7e3d3206` establishes the original window/range-owned gutter menu. All twelve recovered actions are connected to actual native rich-text operations with original selection, save, Undo and stale-owner cancellation. This corrects the earlier metadata-only nested-block requirement; the selection menu is delivered below, while historical title/keyboard behavior and appearance/motion work remain. Notes stays prioritized. The merged 104-source application compiles with zero diagnostics; isolated components pass 24 store, 41 native editor, 23 tab/retirement and 310 shared rich-text assertions. This includes native authored-font fallback formatting, title-focus reentrancy, stale menu/range ownership and actual native Find. No browser functional tests were run.


### Notes selection formatting

The native selection menu now owns exact original Note text ranges: Format Selection, Bold, Italic, Underline, Strikethrough and Link. Its genuine native paragraph submenu exposes Plain Text/H1/H2/H3/Bulleted/Numbered, derives checked state from actual paragraphs and preserves selection after emphasis or first Escape. Multi-range formatting/paragraph edits validate atomically, persist through the original Note session and restore every range with native Undo; stale owner/range/content/viewport/menu callbacks refuse. Automatic presentation keeps body focus. REA recovers the controls, captured ranges, replacement/removal, dimensions and placement; notification timing, native glyph styling, narrow-pane scrolling and AX/keyboard entry are explicit adaptations. No browser tests or retired-Notes appearance acceptance is claimed. The title/body keyboard delivery below covers the recovered transitions; remaining historical editor experience stays prioritized. See [native selection formatting](notes.md#native-selection-formatting). The merged 106-source application compiles with zero diagnostics; 71 native editor, 24 Notes storage, 23 tab/retirement and 310 shared rich-text assertions pass. These component checks are separate from browser runtime and historical appearance acceptance.

NOTE-02 selection-menu appearance now uses the recovered shared horizontal menu factory and named light/dark control states. Both menu owners draw Nunito B/I/U/S with the original decorations; selection Aa has its original disclosure. The 225.5×50.5 host retains the recovered34pt inner surface; appearance refresh preserves control identity, selection and native Undo. Original primary-range first-character Link state is recovered and wired. The genuine paragraph submenu now uses Plain Text and the original document-relative popup anchor. Retired buttons cannot invoke a replacement selection, and explicit keyboard formatting retains the chosen original control after current-range re-admission. Current per-slot native widths/scrolling, symbol rasterization, shadow, pressed feedback, AX/keyboard entry and exact motion remain adaptations. See [selection control presentation](notes.md#selection-control-appearance-and-action-lifetime). Notes remains prioritized; no retired-editor activation or functional browser test is claimed.


NOTE-02/NOTE-06 image authoring now follows the original Notes caller into its native single-file sheet: JPEG/PNG/PDF/BMP/TIFF, no directories or multiple selection, and unmodified system title/prompt. The original completion constructs one NSImage; Parc preserves exact originating Note/range/Undo/save ownership. Existing raster bytes remain unchanged; BMP and native first PDF page become bounded local PNG attachments, an explicit carrier/scale adaptation. Final focus return revalidates the original target identity before inserting. Actual native pixel, persistence and Undo components cover this path; historical sheet appearance and original Link-popover presentation remain unclaimed. See [image picker ownership](notes.md#image-picker-and-local-image-ownership). No browser functional tests or retired-Notes activation.

### Notes local export

The original export boundary and UTF-8 HTML/ZIP writer are recovered with REA; production File → Export Notes and the menu-derived command-bar action snapshot the original current-profile documents after all matching editors save. Native HTML carries actual rich text/links and embedded image bytes; duplicate titles keep separate documents, original modification times survive, and the saved archive uses Parc branding. A window/Profile-owned asynchronous exporter prepares without blocking the UI, presents the native save sheet, atomically publishes the approved archive and cleans temporary content. Current-profile scope, native HTML serializer, collision policy and cancellation/atomic replacement are documented adaptations. The full 98-source app compiles with zero diagnostics; 18 isolated native HTML/real ZIP assertions pass. No functional browser tests ran. This closes export implementation, not the remaining Notes editor/experience work or historical import discovery. See [local export ownership](notes.md#local-html-archive-export).

### Peek


| ID | Implemented interaction and states | Remaining comparison / code |
|---|---|---|
| PEEK-01 | Original new foreground WebContents admission uses exact document/profile/window identity and saved pinned/favorite classification. Explicit Shift/new-window link handling copies complete OpenURLParams and uses the original Chromium navigator/security callback. Refusal preserves the original page and ordinary route. | Ordinary current-tab automatic Peek is now source-integrated via an exact original-request policy query and one-use document token through normal OpenURL. Nine recovered authentication exceptions and current/saved-host guards are connected. Internal matched OpenURL ATC and the recovered persistent URL-lock transitions are source-integrated; IPC latency and current suffix data are explicit adaptations. |
| PEEK-02 | Links has two persisted, live native switches with observed Shift-first order, divider and Favorites/Pinned note; native keyboard/accessibility activation. | Reference registered defaults are unknown; both enabled is explicit Parc policy. Exact focus/hover/motion still needs comparison. |
| PEEK-03 | Live centered card and close/expand/split controls; split disabled at four panes or during close/fullscreen; exact current page exposed to native presenters. | Recovered 80% width/12-point inset and control spring; title band, radius/material, tiny-window clamp and fade are adaptations. Actual overlay geometry and control styling remain unobserved. |
| PEEK-04a / KBD-05 | Original Peek page entry and dismissal/promotion return now use the existing registered native focus owner. Refused close preserves the actual original control/editor; a different concrete responder, changed page/session/window, sheet/security owner, hidden/retiring page or transferred owner cancels return. Deferred native host focus also validates original window/renderer and still-owned firstResponder. | Reused original FirstResponderManager REA plus fresh ModalV2 child-attachment dossier `ev_4a7b569af7064c02885820335a052022223dc120254fe953e901fc4113f5af82`. Weak one-use return and deferred no-steal checks are explicit Parc lifetime safeguards. The bounded route passes 32 inert Swift return-lease assertions and 103 real hidden-window AppKit focus-manager/page-host assertions, actual host/component native syntax checks and the fixed whole-app compiler. No browser functional test. Actual Peek Tab/Shift-Tab edge handoff, complete native keyboard/AX traversal and visible focus/hover/motion comparison remain open; the untouched installed reference had no Peek. |
| PEEK-05 | Back/Forward/Reload/Stop, classified address entry, Copy URL/Find/Zoom, page security, capture, errors and fullscreen target the actual unsaved Peek. | Original-page Back/Forward history controls now use real entry snapshots and genuine history-preserving alternate navigation. Shortcut/focus and exact modal presentation still require comparison. |
| PEEK-06 | Expand and Add to Split promote the same wrapper into a saved Today record, restoring attachment on refusal. Tab/Space deselection hides the retained session; returning reveals the same page. | Exact transition snapshots/motion and original missing-parent policy remain. Independent-parent destruction preserves a live child by promotion as an explicit Parc policy. |
| PEEK-07 | Parent and children join genuine whole-set retirement; Peek protects parent from auto-archive. Closing/promotion releases monitors/observers. Accepted modal lifetime follows parent-tab identity, not an admission getter after document navigation. | Moving the parent to another physical window while Peek exists is explicitly refused. Broader transfer experience remains. |

Other families must receive this same per-interaction expansion within their current bounded implementation batches. Easel styling and Peek handoffs explicitly include it; unsurveyed families remain open. This is an evolving evidence-backed inventory, not a declaration that nothing remains undiscovered.

### Private-window creation and ownership

Automation/private-window increment: genuine primary-OTR factory is implemented through File → New Incognito Window / Cmd-Shift-N and Cocoa make with incognito or mode creation properties. Fresh per-window memory-only tab/Space IDs preserve the actual parent context; real private native-created windows/DevTools, empty-window omnibox, same-page scripting and beforeunload-aware close use original ownership. Async parent loading creates no page and shutdown cancels pending creation. Private app history/archive/session/frame writes and normal Library/Easel/download publication are prevented. The integrated 72-source Swift application, three affected native engine units and Objective-C facade compile with zero diagnostics. The latest combined 72-source application check passes with zero diagnostics. The merged BrowserStore, private model and window-presentation components pass 619, 27 and 107 assertions; exact unchanged Easel inputs retain 177 store / 255 text / 53 canvas results. The earlier 74 Cocoa assertions remain separate evidence for their unchanged checked inputs. Overlay193 reconstructs 474 source targets without modifying the running engine183 build. These are compiler/component results, separate from browser and visual acceptance.

Application Settings is now available from private windows through the real regular parent store/profile and remains application-owned after the private browser closes. Explicit profile creation is regular and unassigned; More Settings, Passwords and onboarding replay retain exact normal destinations. Missing/retiring parents cannot fall back to unrelated profiles. New Window now opens the new standard window’s real command bar while startup restoration retains its separate focus path. The concrete retained WindowsAction tag4 consumer ignores its modifier payload and emits standard style with `showCommandBar=true`; no modifier-specific incognito behavior is invented. Physical regular-window arbitration and initial parent selection remain explicit Parc adaptations; original animation and private WebUI destination policy remain partial. Focused retained AppAction7 REA and installed private Settings appearance are recorded in [settings architecture](settings.md#application-settings-from-incognito). No browser test or Apple Event was run.

The New Window delivery passes the complete 143-source Swift check with warnings as errors and zero diagnostics, plus 27 existing private-profile model assertions. All 240 app-check and 33 model-check inputs match the integrated source exactly; no engine change or browser test was required by this delivery.

Remaining Automation coverage: quit/additional command/error and collection-order fidelity; private sidebar sharing between physical windows, private Library/capture/Easel and detailed private visual/motion/focus parity. Window-state/sidebar-location properties remain read-only because declarations are not handler evidence. No browser functional test or Apple Event was run. This closes the specific genuine private factory + ephemeral owner dependency, not whole Automation or Incognito parity.

### Direct browser import — onboarding / data and credentials

The application menu and first-launch setup now open the same original-window
import flow: installed source selection, actual supported profiles/categories,
explicit cookie replacement and per-profile extension choices, progress/Stop,
ordered bookmark selection and real partial/failure results. Native data writes
to the captured regular Profile through genuine services; new Profile/Space
records persist before context acquisition without a hidden browser. Bookmark
subtree selection and expansion are independent, preserve duplicate identities,
and commit atomically to the original sidebar. Closing or losing the owner stops
new work while accepted writes drain; earlier results survive a later failure.
Replay onboarding retains its session-preserving, in-memory-only contract.

The independent utility reader uses private database/WAL snapshots, source locks
and explicit platform capabilities. Chrome-family history/bookmarks/cookies/
passwords/forms/addresses/cards and selected Web Store extensions are supported
where the source permits them; Safari supports default-store history/bookmarks,
and Firefox history/bookmarks/forms. Actual Keychain and extension consent stay
with their native owners. History and autofill results follow checked outer
commits; password/cookie completion and teardown distinguish confirmed records
from unconfirmed pending writes. No credential values enter Swift.

writer and bookmark reducers. The installed 1.170 source chooser informs its
[browser import](browser-import.md) and [native import](../Engine/ParcImport/README.md)
for exact addresses, evidence and adaptation limits. The parent wizard now
selects one original source profile, then offers an initially unselected existing
or named new destination. New Profile forces cookie replacement; existing makes
it editable, and the actual native importer receives the matching keep/replace
policy. Original target validation, native name editing/IME, submit-only atomic
Profile/Space creation, cancellation and persistence failures are connected.
The one-Profile destination appearance and option/cookie transitions were
observed without importing data. First-readable source choice, the extra source
capabilities page, first-launch reuse, bookmark Space placement and larger-list
layout remain explicit adaptations. Safari access guidance now precedes destination
selection, uses real selected-source readiness and separate Continue/Restart
paths, and resumes through fresh discovery without submitting an import.
Explicit exported Safari passwords now use the separate confirmed file path below. Exact hover,
focus details, motion and haptics do not become complete through compilation.

This destination increment passes 66 isolated model/store assertions, including
real persistence refusal, stale/retiring Profiles and actual durable destinations.
The pinned 135-source app check and isolated native chooser preview are recorded
with the delivery; neither is a browser/import runtime acceptance claim.

Safari access now uses the observed 790 × 630 navy screen, Parc branding,
real System Settings/Finder actions, recovered one-second polling and owned
activation refresh. Readable History capability enables Restart; Continue
rechecks actual capabilities. Original destination/onboarding resumption,
duplicate-request prevention, close/owner-loss cancellation and durable failure
presentation are connected to the application's restart owner. The instructional
panel, selected-source readiness and active-view polling bounds are explicit
adaptations. The pinned 138-source app check and 33 isolated actual-coordinator
assertions pass; the native view was rendered separately. No browser, personal
source, permission grant or restart was exercised by those checks. The root-owned
restart helper/packaging checks remain separate from this UI receipt.

The exported-password increment now connects Safari's optional CSV stage and
explicit file-only entry to the original destination Profile. Native file
selection/drop, genuine sandbox CSV parsing, actual password-store write/readback,
aggregate partial/failure results, Stop/retry/Skip and separately consented,
identity-checked Move to Trash are implemented. Direct Safari credential
extraction remains unsupported. Ordinary direct and CSV imports share destination
admission; accepted writes drain on cancellation. Password-only destination UI
omits cookie replacement. This stage placement, keep-existing snapshot policy,
native 580 × 630 composition and recoverable Trash are explicit adaptations;
while current password-screen appearance and full entryPoint policy remain open.

The pinned 139-source app check passes with warnings-as-errors and zero
diagnostics. Both modified native session units compile with actual pinned
flags; 69 isolated coordinator and 17 actual synthetic-file assertions pass.
All 527 private overlay targets reconstruct read-only. Initial, partial and
completed native view states were rendered independently. No browser functional
test, personal credential file/import, permission change, password unlock or
source deletion ran. Native password-store runtime acceptance and final combined
engine/package integration remain distinct from these checks.

The combined 134-source Swift app and all 11 native/generated units pass with
warnings-as-errors and zero diagnostics. Exact inputs retain 29 model/store,
54 Chrome, 84 Safari/Firefox and 42 legacy plus 42 scoped database assertions.
All 524 overlay targets reconstruct exactly. Overlay 212 compiled successfully
in 5 minutes 12 seconds overall, including 167 compile/link actions. Its source
64c0948 development package passed strict app/sibling signing and source
provenance checks (519 exact pre-sign engine copies, 525 signed images). This
package predates the destination chooser and following Peek/extension increment;
it was not executed. No functional browser test, personal-data import, Keychain
read or extension installation was run for this batch.

## Complete first-launch verification gates

The user explicitly requires the full experience, beginning before the browser appears. This remains part of onboarding even when theme editing is delivered as a bounded batch. The former four-step sheet has been replaced by a standalone pre-browser sequence. The implementation and its remaining exact-reference limits are recorded in [first-launch implementation](onboarding.md).


- **Sequence and state:** use REA state/actions and the running reference to establish entry conditions, opening animation, setup/tutorial branches, back/skip behavior, completion and browser reveal. Record what appears before the browser window is created or shown. Do not infer live order from an enum or asset filenames alone.
- **Motion and sound:** map each animation/music/audio cue to its trigger, duration, delay, transition curve, overlap, volume/fade and cancellation behavior. Compare recordings from initial launch through reveal at matched display conditions, including synchronized audio. Preserve unknown measurements as gaps until verified.
- **Haptics:** identify actual triggers and feedback types from native calls and confirm the experience on supported hardware. A recovered call or a platform API invocation alone does not prove matching feedback; record any hardware-dependent check that cannot be performed.
- **Accessibility and preferences:** discover the reference's reduced-motion and audio preference/mute behavior, then exercise those variants in Parc. Verify keyboard/focus progression, accessibility labels and dismissal behavior throughout. Do not add guessed controls or substitute effects in place of evidence.
- **Lifecycle and persistence:** test fresh first launch in a disposable profile, interruption and relaunch, back/skip/replay paths where the reference supports them, and completed-onboarding relaunch. Verify cue cancellation, no unintended repeat audio/haptics, no premature browser flash, and the correct final browser state.
- **Acceptance record:** distinguish recovered assets/types, implemented source and runtime-verified behavior. Keep timing, audio, haptic, accessibility or lifecycle gaps open until their checks pass. Account/service and AI steps remain excluded; explicitly document the necessary local-flow adaptations without representing them as the original sequence.

## Evidence boundaries

- Easel text now includes range-based attributes above the original four-family/five-size palette. Native text storage, local undo, rich clipboard and edit-delegate boundaries are REA-backed; the complete-run carrier and two-row palette are Parc adaptations. Content-hugging fill, non-image attachment contracts and exact canvas/palette appearance remain separate. See [Easel ownership and font mapping](easels.md).
- Screenshots and screen recording are separate investigations. A tab's recording indicator alone is not evidence of a built-in screen recorder.
- Notes have retirement strings in the installed product; a residual menu selector does not establish a currently active feature.
- The original engine's encryption-key namespace has been traced and narrowly remapped to Parc. A normal same-signed-app restart recovered an encrypted HttpOnly cookie after macOS authorization. This does not establish signing continuity across future rebuilt versions.
- Local and real-web functional tests do not establish full design, motion or performance parity. This ledger records current verification and limitations.


### Notes title/body keyboard transitions

The original title’s native text/Undo owner now replaces the field-editor approximation. Title Tab/Down and Right-at-end focus body offset zero; Return transfers its suffix before the existing body. Body first-line Up/Left-at-start return to the title; default-typing Backspace joins its first line into the title. Escape dismisses an owned menu first, then collapses the active field selection. Plain title paste normalizes newline characters. Actual IME, original key-window/responder, sheet, document and cross-window field checks govern these operations. Paired transfers publish once or retain both failed drafts; native title/body Undo managers remain separate, as recovered. UTF-16 safety, current native layout/default-style representation, atomic local paired save and refusal to erase a first-line image are documented adaptations. The original retired editor was not activated; exact appearance/motion/save timing remains unfinished and Notes stays prioritized. See [title/body ownership](notes.md#title-and-body-keyboard-ownership).

The exact 107-source Swift application compiles with zero diagnostics. The reusable Notes checks pass 32 local store, 107 native editor and 23 tab-model assertions, including real local write failures, separate native Undo/Redo and composition. Editor components use no displayed window; no browser functional tests or historical Notes appearance checks were run.

The merged 109-source application compiles with zero diagnostics. Exact unchanged components retain 32 Notes storage, 107 native editor and 35 sidebar-title assertions; the shared Notes tab model was recompiled against the new custom-title field and all 23 assertions pass. This validates source integration and isolated components, not browser or historical appearance parity.

### Notes document layout and states

The original native title/body now use the recovered 900-point maximum column, 100-point preferred and 20-point minimum margins, soft 250-point field width, 64-point top/bottom and 16-point field gap. Actual native glyph measurement preserves wrapping, original selection and separate Undo; narrow split panes can yield instead of clipping a hard minimum. The bundled licensed Nunito ExtraBold title uses recovered 34pt/paragraph metrics and surviving named-resource colors. A failed load gets the dedicated centered Note error view; a failed save retains the original editable draft, and a tombstone keeps copyable read-only text while retiring formatting. Source evidence and adaptations are detailed in [Notes presentation](notes.md#native-document-presentation). Historical Notes remains visually unavailable; no functional browser test or appearance acceptance is claimed, and its remaining experience work stays prioritized.

The exact 110-source Swift application compiles with zero diagnostics. The reusable Notes components pass 32 storage, 136 native editor and 23 tab-model assertions, including actual bundled font resolution, wide/narrow native constraints, original Undo/selection, real disk failures and retained read-only content. Components display no window and do not launch a browser. These checks are separate from historical appearance and motion acceptance.

The merged 111-source application compiles with zero diagnostics. Scope-menu native compilation and all 502 reconstructed integration targets pass. Exact Notes editor/storage and scope-button components retain their successful checks; the changed shared tab model was rebuilt and all 23 assertions pass. These are source and isolated component checks, with no functional browser tests.

**Engine v195 completed:** the independent incremental build succeeded in 4h37m46s with 4,207 actions and 93,275 unchanged actions skipped. Its matching development package passes strict app/component signing and source provenance: 519 exact pre-sign engine copies and 525 signed images. The engine is sealed before newer source is applied; this is a component development package, not a standalone shipping or experience-parity claim.

### Settings local data export


The merged 113-source application compiles with zero diagnostics. The Export Data formatter/file component passes 15 assertions, and the unchanged real result-table/editor component retains 27 passing assertions against identical inputs. The engine209 incremental build has completed from the previously published source; these application-only additions do not alter its sealed inputs.

Notes body-style follow-on: exact 111-source Swift application compilation passes with zero diagnostics. Reusable local components pass 32 storage /155 native editor /23 tab-model assertions and 310 shared rich-text assertions, including actual bundled body font/emphasis, original keyboard-default admission, heading return, untouched saved runs and exact native system-monospace restoration. No window was displayed and no functional browser tests were run.

The merged split-name, Notes body-style and command-pointer application compiles across 115 Swift sources with zero diagnostics. Fresh components using the changed shared tab model pass 46 split-title, 23 Notes-tab, 15 browser-export, 26 pointer-row, 21 deletion-control and 27 cyclic-selection assertions. The unchanged Notes storage/editor and shared rich-text inputs retain their exact successful component evidence; no functional browser tests ran.

**Engine v209 completed; app-link correction:** the independent incremental build succeeded in 14m05s with 153 actions (151 local, two no-execution) and 97,335 unchanged actions skipped. Its output is sealed. The matching package stopped at Swift linking because the implemented `PCNativePageHost` class had hidden visibility; the webpage-dragging consumer now references that class directly. Overlay 210 exports this existing class through the same public visibility annotation as the other native bridge classes. A real hidden-visibility production library and Swift typed-cast consumer reproduce the old missing-class link error and link successfully with the correction; the packager now rejects that missing export before compiling the app. All 19 focused packaging guards pass. Read-only overlay reconstruction validates all 502 targets and changes only the host header. The corrected v210 engine increment completed successfully in 34.26 seconds: 13 actions with 97,475 unchanged actions skipped. Its sealed output packages successfully with the updated Swift app; strict signing verification passes for the app and all 525 signed images, and all 519 engine copies match their sealed inputs before signing. The package remains a development component layout, with no new functional browser test. The completed v195 development package remains retained. Compilation and packaging remain distinct from standalone distribution and whole-experience parity.

Notes title-placeholder delivery: exact 114-source Swift application check passes with zero diagnostics; actual local components pass 32 storage /171 native editor /23 tab assertions. Native in-memory rendering verifies empty/focused/read-only/marked-text placeholder behavior, and original title Undo/Redo, failed-save drafts/retry and tombstones preserve real data. No window was displayed and no functional browser tests were run.

The merged container-name Undo, native Notes placeholder and contextual Favorites application compiles across 117 Swift sources with zero diagnostics. Fresh checks against the combined tab store pass 41 original-container Undo, 41 Favorite action and 23 Notes-tab assertions. The 32 storage and 171 native Notes-editor assertions retain exact unchanged source/font inputs. These are source and isolated component checks; no functional browser tests ran.

Notes gutter delivery: the exact 115-source Swift application cohort compiles with zero diagnostics. Real local Notes components pass 32 storage /192 native editor /23 tab assertions, including native gutter pixels, exact tracking-area ownership, metadata reentry/revocation, menu freezing, empty-line targeting, key loss and IME. No window was displayed and no functional browser test was run.

The merged ordinary-tab Rename Undo and Notes gutter application compiles across 118 Swift sources with zero diagnostics. Fresh checks against the combined tab store pass 41 original-tab Undo and 23 Notes-tab assertions. The 32 storage and 192 native Notes-editor assertions retain 22 exact unchanged source/test/font inputs. No functional browser tests ran.

The merged Favorite Rename and command-bar Pin to folder application compiles across 120 Swift sources with zero diagnostics. Fresh checks using the combined store pass 26 Favorite dialog/model, 41 ordinary-tab Rename Undo, 45 folder-placement model/storage/native-row and 23 Notes-tab assertions. The updated focused runners pass shell syntax checks. No functional browser tests ran.

Notes compact paragraph-menu delivery: the exact 117-source Swift application cohort compiles with zero diagnostics. Real local Notes components pass 32 storage /208 native editor /23 tab assertions, including actual icon controls, original eleven-slot construction, inline emphasis expansion without an edit, checked/hover state, narrow-pane containment, formatting/Undo and stale-control/revision rejection. No window was displayed and no functional browser test was run.

Notes native targeting delivery: the exact 120-source Swift application cohort compiles with zero diagnostics. Real local Notes components pass 32 storage /230 native editor /23 tab assertions, including terminator-excluded line spans, Unicode separators, original newline boundary and distinct metadata, exact menu admission/format/Undo, retained geometry and concrete image-cell eligibility. No window was displayed and no functional browser test was run.

The merged compact Notes menu/native line targeting application compiles across 122 Swift sources with zero diagnostics. All 32 actual Notes runner/source/test/font inputs match the successful 32 storage /230 native editor /23 tab component run exactly. No functional browser tests ran.

**Integrated Favorite command Rename and folder copying:** the combined 123-source Swift app passes with zero diagnostics. Fresh isolated components pass 27 Favorite command/model/Undo, 39 copy/atomic-persistence and 45 original move/row assertions against the combined source. The exact original Favorite dialog and existing native page owners remain in use. Typed document aliases are a separately recovered follow-on; ordinary copied pages use existing engine support, with no engine-source change. These checks are separate from browser and complete visual acceptance; no functional browser tests ran.

**Integrated Favorite pointer and typed document copies:** the combined 123-source Swift app passes with zero diagnostics. The exact actual component inputs match the successful 20 existing Favorite-control, 28 pointer/lifecycle, 45 typed-alias real-store and 39 ordinary-copy assertions. Primary/Command/double-click handling, stable tile identity and mixed Note/Easel folder copies are source-integrated; plain Option routing remains the active follow-on. No engine change or functional browser test accompanies this batch, and full interaction/appearance parity remains unfinished.

**Integrated Notes saving, Favorite Option routing, mixed-folder retirement and preview settings:** the combined 126-source Swift application passes with warnings treated as errors and zero diagnostics. Fresh isolated components pass 32 Notes storage, 258 editor, 8 final-retirement, 23 Notes-tab, 20 Favorite-control, 35 pointer/lifetime, 39 split/persistence and 34 mixed-document folder assertions. All eight explicit-source component runners include the new Favorite split request used by BrowserStore. The original Notes editors and document stores survive delayed close decisions, and General preview choices reconcile existing local previews across windows. No engine source changed and no functional browser tests ran; full interaction, appearance and motion parity remains open.

**Latest sealed-engine app package:** the app-only package at source `02e46fc` completed using the existing v210 engine seal, with 519 exact pre-sign engine copies and 525 signed images. App deep/strict and sibling-library strict signing pass; package-report SHA256 is `1d82d042d0f29fbf50a7bde822c4d7a91753293f7f1eb7489937e361c41a872c`. It remains a development-component package, is not distribution-eligible, and was not executed. This package predates the subsequent app batches above; those batches have source/compiler/component evidence, not a claim that the older package contains them.

Notes body-publication delivery: original main-queue Combine throttle(0.5s, latest:true) and independent immediate title updates are implemented, with actual native Undo ownership unchanged. Close/export/retry flush exact drafts; composition, discard/tombstone, competing-window conflicts and real disk failures preserve local state. A retained menu/image/link request can advance only its durability revision after its own unchanged captured body saves. The exact 122-source Swift cohort compiles with zero diagnostics; 32 storage /258 native editor /23 tab assertions pass, including real scheduler delivery, retained paragraph-menu action and failure paths. No displayed window or functional browser test; separate unclassified backend save-effect timing, historical appearance and remaining Notes work stay explicit.

Notes gutter-icon delivery: original first-font size/prefix/empty-caret classification and exact surviving named list artwork are implemented through the existing gutter/menu owner. Full 123-source Swift compilation has zero diagnostics; 32 storage /295 actual native editor /23 tab assertions pass, including native font runs, real current-AppKit markers, whitespace/caret/Unicode ranges and rendered list vectors. No displayed window or functional browser test; no engine/schema/resource dependency. Retired historical appearance/motion, original1.122 contour-byte identity and broader untraced Notes contracts remain explicit.


**Integrated Notes gutter and saved-tab Reset comparison:** the combined 126-source Swift application passes with warnings treated as errors and zero diagnostics. Fresh isolated components pass 32 Notes storage, 295 editor, 8 final-retirement, 23 Notes-tab, 20 Favorite-control, 35 pointer/lifetime, 42 split-copy and 86 URL-eligibility assertions. The shared BrowserStore retains the already-published mixed-document copy/Delete/Undo changes. All existing native page and draft owners remain authoritative; no engine source changed and no functional browser tests ran. Full historical Notes appearance and whole-product interaction/motion parity remain open.


### Plural sidebar Delete/Archive — FOLD-05d / KBD-01f

Explicit selected-item context Delete/Archive and AX now capture original same-Space roots, suppress selected descendants, retire the exact web/Note/Easel owner set, and atomically archive references/remove ordinary folders in one durable commit. Whole split IDs/geometry and original profile ownership survive. One window Undo group restores exact roots across their original containers while preserving unrelated siblings; Redo validates original membership/location and obtains real native close consent again. The existing final Notes IME/save barriers and original-window selection lifetime are retained. Close Tabs in Selection, Cmd-W and Delete-key ordinary close remain distinct.

REA recovers the actual plural context collection payload/Set conversion and shared begin/complete close route. Fresh collection-owner evidence is `ev_dedca104895ae256b7140f14a20f48dde0832418f43ec736b73d1f8a88f9ba84`; original full-image assembly and prior exact close/Undo producer evidence supply external identities. Plural native warning/AX text and always-confirm presentation are explicit adaptations. Exact modern plural appearance, toast/motion, remotely gated folder archive entities, cross-Profile/window and Favorite/app-tray deletion remain separate; the recovered saved-item keyboard branch is delivered below. No document deletion/clone, P0/PiP reopening, Downloads performance work or functional browser test. See [plural removal](folder-commands.md#plural-selected-item-delete-and-archive).

The fixed 126-source app compiler passes with zero diagnostics. Actual isolated checks pass 41 plural collection/persistence/Undo assertions, 34 mixed Note/Easel close assertions, all 696 BrowserStore assertions and 23 native UndoManager assertions. These are source/component checks, not integrated browser or modern appearance acceptance.

**Integrated plural sidebar removal and Reset All:** the combined 127-source Swift application passes with warnings treated as errors and zero diagnostics. Fresh isolated components pass 41 plural-removal, 34 mixed-document close, 696 BrowserStore, 23 native UndoManager and 207 Favorite/Reset assertions. Original saved-URL comparison, typed document sharing and native close ownership remain intact. No engine changes or functional browser tests accompany this batch; complete keyboard-close and whole-family appearance/motion work remain open.

### Default-browser system integration

The application menu and General now share a genuine NSWorkspace default-browser controller: original app URL, HTTP then HTTPS, one pending consent operation, cancellation/partial-failure handling and actual system readback. App/Settings activation refreshes without polling. REA of Arc1.170's native client and status helper establishes the sequence; account-free placement, exact-app/both-scheme comparison and duplicate guarding are explicit adaptations. No account/updater/telemetry or engine change. Focused ownership checks use injected system callbacks and never change this Mac's defaults. Exact banner/control appearance and complete menu/settings polish remain open. See [default-browser ownership](settings.md#default-browser).


### Selected-item keyboard Close — KBD-01f / NAV-04

Original Cmd-W's collection consumer is now traced through the actual any-Today versus saved-only branch. Keyboard/Close Tabs in Selection archives the entire captured collection when any original root is in Today, using the existing single-consent durable reference archive/ordinary-folder removal and native Undo/Redo. With only saved roots it retains bookmarks/folders and complete split identity/geometry while unloading content; the original selection revision survives only the owned consent sheet. Existing Notes IME/failed-save and exact original page/Space/Profile barriers remain. Explicit context/AX Delete remains separate; tab-only keyboard commands have no extra warning, folder-bearing commands retain the recovered ordinary confirmation.

Fresh REA deselect helper `ev_e5bdef15445b95e8a89eaa24e0b45f99664b4b9c0a07f2a9339352ad934eedd0`, original collection/predicate/configuration assembly and shared close completion establish this behavior. Focused-sidebar Delete binding and plural AppKit warning/labels remain adaptations. Empty-only folder deselection, Favorite/app-tray selection, cross-focus state and exact modern appearance/motion/haptics remain open; the separately completed saved Reopen consumer is described below. Source/compiler/components only, no functional browser tests or personal content changes. See [keyboard close](sidebar-selection.md#saved-versus-mixed-keyboard-close).

Committed keyboard archives retain the existing exact-window Today Reopen steps, including whole split geometry and original focused pane. Saved references archived by a mixed command use the complete Undo record; the separate saved-only priority follows its recovered single-item window-recency consumer.

The fixed 126-source Swift application compiles with zero diagnostics. Focused actual-store checks pass 36 keyboard-close assertions, 41 plural-removal/Undo assertions, 34 mixed-document assertions and 41 existing ClosedItems assertions. Exact compiler input hashes are retained; component filesystem operations use only disposable directories. The saved-only persistence case forces the real close result to disk before reopening it. No engine inputs changed and no functional browser or personal-content operation ran.

**Integrated selected-item Close and Notes menu appearance:** all 128 Swift application sources pass with warnings treated as errors and zero diagnostics. Fresh isolated components pass 36 keyboard-close, 41 plural-removal, 34 mixed-document, 41 ClosedItems, 32 Notes storage, 341 native editor, eight final-retirement and 23 Notes-tab assertions. The combined source retains original Reset All targets, Notes backing and default-browser controls. No engine source changed and no functional browser tests ran; saved Reopen behavior and full interaction/motion parity remain tracked separately.

The app-only development package for source `5dc2d1f` completed in 7m29s using the sealed v210 engine, with 519 exact pre-sign engine image copies and 525 signed images passing app deep/strict and sibling-component strict verification. Report SHA256 `09428ee69d17a898caec3998b533af0fa4fddb25a6372e0193e874c2195479fa`. It was not launched and predates the selected-item Close and Notes control-palette changes above; no Chromium rebuild was needed.

### Bulk saved Reopen priority

Saved-only keyboard Close now records one original Reopen target selected by the initiating window's most recent actual focus, including exact retained saved splits and Note/Easel references. It does not push a stack of every closed saved item. Original Profile/Space/tab afterimages and retained split identity/geometry must still match; persistence succeeds before consumption. Real native/Notes retirement, Today archive groups and their existing order remain unchanged. The recovered `completeDeselectSidebarItems` consumer, Date provider and positive `WindowState.itemLastActiveDates` field binding are documented in [Reopen Closed Tab](reopen-closed-tabs.md#bulk-saved-close--one-reopen-target); fresh REA `ev_43340c6accd88d0100427d41f311682965e0bb6314be79da087c4bf923a17a1b`. Equal/missing-date tie order and leaf-to-whole-split mapping are explicit Parc adaptations. Folder expansion/restoration, partial regrouping, exact original activity-stamping granularity, process-restored dates and detailed appearance remain separate. Source/compiler/components only; no browser functional tests or personal-content operations.

The exact bulk-saved source cohort passes the full 128-source Swift compiler with warnings treated as errors and zero diagnostics, plus 73 ClosedItems, 36 keyboard-close, 41 plural-removal and 34 mixed-document assertions. Native/engine sources remain unchanged.


**Integrated saved Reopen and shortcut cue:** the combined 129-source Swift app passes with warnings treated as errors and zero diagnostics. Exact component inputs match the successful 73 ClosedItems, 36 keyboard-close, 41 plural-removal, 34 mixed-document and 23 native cue assertions. The changed shortcut native unit passes its pinned target compiler against the exact new bridge headers. Overlay 211 adds the recovered hover-aware expiry and exact original-cue Edit route. The incremental engine completed successfully (29 local actions, 2 no-execution actions and 97,457 skipped; 1 minute 24 seconds), was sealed, and the development app at source b864580 built and packaged successfully with deep/strict app and strict sibling-library signature verification. This package includes the five-format Notes image picker; it predates the following Peek confirmation increment. The app was not executed. The existing Notes selection menu and source-owned page/retirement owners remain intact. No functional browser tests ran; detailed appearance, motion and whole-family parity remain open.


**Integrated Notes image authoring:** all 130 current Swift app sources pass with warnings treated as errors and zero diagnostics against the published shortcut bridge. Fresh isolated Notes components pass 32 storage, 378 native editor, eight retirement and 23 tab assertions, including actual BMP/PDF pixels and local save/Undo. The unchanged production Note fonts are included in the private compiler/component cohort. No engine change or functional browser test accompanies this batch; exact historical Link presentation and full experience parity remain open.


### NAV-03s — native extension keyword scopes

Registered extension keyword entry/query/results now use the exact Profile/OTR
KeywordProvider and original extension events. Typed immutable action results
preserve native order and original content; their placeholder URLs never become
navigation or Copy URL. Cmd-L/Cmd-T retain current/new-foreground invocation,
Command–Option–Return requests background execution, and actual deletable
suggestions retain provider removal. Option split is truthfully unavailable.
The original document/page/window, enabled extension instance, publication,
security reservation and cancellation/request-ID lifetime gate the real dispatch.
Website templates and their Remove/Change menu stay separate; native IME,
query restoration, typed commands and full URL/POST requests are preserved.

REA covers the shipped native keyword controller, actual onInputEntered and
cancelled/request-ID consumers, with the old complete Swift extension route
explicitly untraced. Current-provider empty-entry/deletion adaptations are
recorded in `docs/command-bar.md`. The native unit and full app compile, with
focused real native scope-label/editor/deletion-control components; these are
not a claim of extension execution or functional browser verification. Local
pages without a real selected native WebContents, modern extension-specific
appearance/icon/motion/haptics, full ranking and all IME combinations remain
separate. No personal extension operations or browser functional tests ran.

The integrated destination/Peek/extension cohort passes the full 135-source
Swift compiler with warnings treated as errors and no diagnostics. Overlay 213
adds the native Escape producer and real extension omnibox dependency; its engine
rebuild follows publication. The retained component results are 51 native Escape,
79 confirmation, 74 scope/editor/pill and 21 deletion-control assertions. None
of these checks launches a browser or establishes the remaining visual polish.


### Plural context Duplicate — FOLD-04

The selected-item context **Duplicate** and **Duplicate Selection** AX path now copy the complete original same-Space/Profile root collection through the existing single-save transaction. Overlapping ancestors/descendants normalize once; original mixed hierarchy, empty folders, full split identities/geometry and validated same-document Note/Easel references survive. Every copied sidebar ID is fresh. Original selection, pages, shared drafts and assets remain untouched. Stale original selection/page/tree, foreign/malformed content, pending retirement or disk failure refuses the complete copy. Native background creation starts only after persistence, using recovered first-five ordinary-root, lazy folder-child and independently eager split-child policies in original recursive order. No URL/history clone or fake local-document page is introduced.



### Integrated Safari restart and collection duplication delivery

The Safari access screen and its application-owned restart/resume path are now
source-integrated with plural context Duplicate. Restart registers the exact
parent-process helper before ordinary quit consent, saves only durable import
destination identities, revokes on cancellation and resumes fresh discovery after
actual engine readiness and original setup/browser presentation. The packaged
helper uses normal signing; it never calls another browser or bypasses macOS
permission. Source-specific password guidance remains separate active work.

The merged 138-source Swift application compiles with warnings as errors and
zero diagnostics against unchanged captured inputs. The actual helper's seven
isolated cases, five file-backed intent cases and 33 access-coordinator assertions
are component evidence; no browser or actual TCC/restart run is claimed. Plural
Duplicate retains its actual model/store checks documented above. Full UI,
keyboard, transition and haptic comparison remains in the dedicated polish scope.

The latest engine217 increment at source70c4745 compiled successfully: 34 reported
steps (32 local executions and two no-execution steps), 3 minutes 38 seconds
compiling/linking and 8 minutes overall. It adds live embedded Easel transfer
and same-Profile cross-window creation origins. Its matching development package
completed with strict app/component signing and provenance: 519 exact pre-sign
engine copies and 526 signed images. Report
SHA256: `e054768df6ebfbf3694f1b07a078c78ffddad180d2a4df25a599497a5c74f4d2`.
No browser was launched. The newly combined Favorite moves, original-window Close
Window and DevTools repeat-command source passes all 141 Swift files with warnings
as errors and zero diagnostics (134.64 seconds). Exact unchanged inputs retain
227 Favorite/move/order assertions, 425 Close Window/shortcut assertions and
40 native DevTools pane assertions. Both affected native units and the two actual
frontend TypeScript targets compile; all 529 overlay targets retain exact strict
forward/reverse replay evidence. Overlay218 contains the published DevTools
increment; the completed engine217 package remains the preceding development
build. These source/component checks do not claim browser functional or appearance
parity.


### Completed engine218 development package

The engine218 increment at source `b214830` completed successfully in 39 minutes
30 seconds. Sealing passed in 95.75 seconds, and the matching development package
completed in 13 minutes with strict app/component signing and source checks:
519 exact pre-sign engine copies and 526 signed images. Package report SHA256:
`830291fc757a5d42bcdc7f79e7b9dea943a0bf7ff2543bdfc47b4fe9a2bae307`.
No browser was launched. Cast, contextual Exit and external split-link dragging
are published in overlay221 and belong to the next incremental build. This is
a development component package; distribution and full experience polish remain
separate from implementation completion.

### Same-Profile routed creation receipt — NAV-04 / FOLD-05a

The existing original-request ATC path now preserves its actual source page/document across same-Profile physical windows. Native metadata binds the original source and accepted destination Browsers, and the shell resolves the original page through its actual owner controller rather than destination selection. Stale/closed/transferring/retiring owners refuse; only the destination pool changes. Peek's same-window admission and all original request/POST/security/callback behavior remain unchanged. [Creation ownership](folder-commands.md#same-profile-routed-creation-across-physical-windows) records the exact trace and limits.


### Creation placement and modal provenance — TAB21


Every page that a link route places in another Space now takes the explicit top of that Space's Today, including when the adopting window already shows that Space. A matched current-link (OpenURL) route records no referrer: its same-Profile source becomes only the active-before item (engine flag `routedLinkCreation`, applied and built). Routed created contents keep their source as referrer. A cross-Profile route records neither identity, and the destination window's current item is no longer substituted. Closing such a tab has no creation return (child, pooled sibling or active-before), so it uses that window's remembered same-Space item, else the neighbour and date. A Peek whose page enters tab fullscreen is first expanded through the existing source-owned promotion (parent as referrer and active-before, placement after the parent's run, pool replacement), then takes ordinary tab fullscreen. The former in-place full-bleed Peek is removed.







**Remaining.** Nothing in TAB21. The `routedLinkCreation` engine source needs the next overlay apply by Codex root; until then a same-Profile matched link keeps its earlier referrer. Note/Easel insertion strategies stay with Notes and Easels, Duplicate placement with FOLD-04 and row insertion motion with its own row.

### Favorite / app-tray original-item moves

Same-Profile Favorite reorder and moves into/out of the tray now share the original hierarchy/collection transaction, including real cross-window native pages, Note editors and live Easel children. Whole Favorite splits keep original group/child/document IDs and ratios across all Spaces in their Profile. Moving out targets the actual destination Space; actual positional/Control–Space/Reset All order follows the tray. Folders, foreign Profiles, partial groups, stale owners and a thirteenth root refuse atomically. Menu/AX destinations use the same original lease. Existing Favorite pointer reset/activation/Option release is preserved; no outline multi-selection or copy fallback is invented.

REA `ev_ac378759cfc23fc9ace43099e6dd40ec538d49dffb741dd470ecfe4f02a88bd6`, original action metadata and full-image assembly establish actual app-tray accept→moveSidebarItems, root compatibility and capacity. Installed Arc1.170 had no populated Favorite tile, so exact drag/hover/motion/haptic geometry remains unobserved. Existing feedback, four-point threshold, empty-tray band and menu/AX labels are adaptations. Copy/external/cross-Profile moves, Favorite grid multi-selection and cross-window move Undo remain separate. Whole-Favorite group Rename is delivered in the following appearance slice. No functional browser tests ran. See [Favorite moves](folder-moves.md#favorite--app-tray-moves).


### Whole-split / Favorite group appearance

Ordinary and Profile-wide whole-Favorite groups now have their original-container
Rename, **Change Icon…**, explicit icon removal and **Reset Name and Icon** routes
through context/AX and the existing current-split Rename command. The Favorite
dialog activates the actual group and retains its required literal title; an
ordinary group keeps the existing inline trim/clear editor. Native icon/emoji
selection commits to the original group, never a focused child's title or page.
The original window's native Undo records Customize Tab, Rename Item and Reset
Name and Icon with independent field inverses. Both shared fields survive group
copy/reconstruction, divider edits, window restoration and original-group moves.

Original group/Profile/window/Space/selection and live page/local editor leases
expire on replacement, transfer, retirement or conflicting presentation. Failed
persistence leaves the old state and current editor available for retry. A whole
Favorite whose stored home Space differs from the active Space remains the same
original Profile-owned group. The exact 141-source application check passes with warnings as errors and zero
diagnostics; 52 new appearance/model/native-owner assertions, 46 existing
split-title assertions and 41 existing native title-Undo assertions pass with
unchanged inputs. These checks do not establish browser or complete appearance
acceptance.

reducers register their genuine Undo labels, and the top-app Rename consumer
retains the original item ID. Fresh REA
`ev_a540c81da942d761347d62e18c9a3e30c8141bae2548227cf028aa526c7b7594`
is corroborated by original full-image assembly and metadata. The 24 native
system-symbol palette, system emoji authoring, icon-only joined title and native
popover presentation are documented adaptations. The proprietary icon catalog,
full projection/hover rules and exact populated picker/dialog motion remain
unobserved. The existing installed sidebar had no Favorite/split group; no
personal content was created and no browser functional test ran. See
[split group appearance](split-groups.md#original-group-name-and-icon).


### Integrated Space creation, Peek focus and local split drops

The combined 148-source Swift application compiles with warnings treated as errors and zero diagnostics. Create Space now replaces the old name-only prompt with the sidebar name/Profile/icon/theme draft and a single durable create-and-move operation; its integrated checks pass 62 creation, 57 move and 114 presentation assertions. Peek focus uses the original native page manager and preserves a newer responder across queued entry, dismissal and promotion; both actual native units compile, with 32 Swift and 103 native focus assertions against identical inputs. Notes and Easels now accept the existing URL-to-split gesture through their native editor receivers while preserving original documents, composition and ordinary rich-content drops; the integrated checks pass 29 local-editor, 20 drag-session and 23 Note-tab assertions. The unchanged Note/Easel editor and export component inputs retain their passing results. Overlay222 validates all 537 targets without modifying the running engine221 inputs. No browser functional tests ran. Detailed motion, appearance and the remaining family boundaries stay open.


### Completed engine221 development package

The external split-link engine increment at source `669422e` built successfully in 16 minutes 14 seconds, then sealed and packaged successfully. The release-configured development package passes app deep/strict and sibling-component strict signing and source provenance: 519 exact pre-sign engine copies and 526 signed images. Native app compilation and packaging took 31 minutes 22 seconds. The package was not launched. It predates the now-published search-load reentrancy correction and sidebar hierarchy animation; it must not be described as fixing the reported command-bar crash. The next increment carries that correction and the queued Peek focus changes. No functional browser tests or whole-family completion are claimed.

**FOLD-07 Favorite external URL split targets:** the existing native drag/session
now admits standalone Favorites and whole Profile-wide Favorite groups. Edge
insertion on a standalone Favorite preserves a fresh saved-home reference at the
original tray slot while the original live ID/page/editor joins the new Today
split. Existing Favorite groups retain original group/child IDs, home Space,
name/icon and proportions, including cross-Space projection. Center replacement
preserves displaced originals. One durable transaction handles new URL/home/split
publication; the twelve-root cap, stale owner/selection/hierarchy, document and
persistence failures refuse atomically. Notes/Easels remain validated aliases;
rich-content/IME editor routes are unchanged. Fresh REA attributes the actual
URL→TabCreation→selection→saved-home copy chain, not merely a type name. Installed
appearance/motion, the now-attributed standalone pinned saved-home relocation,
legacy mixed Favorite/Today groups, cross-Profile and whole-group external/copy
drags remain separate. See [Favorite split URL
ownership](split-groups.md#favorite-targets-and-saved-home-ownership). No browser
functional tests.


The integrated Favorite external-drop 148-source app check passes with warnings as
errors and zero diagnostics; 62 actual model/store/typed-alias checks and the
existing 20 native-session/29 native-local-editor assertions pass. The final
source memoizes finite target admission only after current owner validation and
constructs fresh durable state at commit. No engine source changed.


### Floating Find results — KBD-01 / KBD-05 / KBD-06 / KBD-07

The application Find surface is now a 300 × 32-point overlay on the original
native page, including split/Peek bounds, with recovered resource colors, fonts,
control metrics and shadow. Opening Find no longer shrinks the renderer. Real
Chromium result notifications drive unknown, Not Found and ordinal/total states;
query/document changes and teardown reject stale publications. Async results
preserve query selection/composition, and native buttons retain AppKit keyboard
and accessibility ownership.

The private 151-source warnings-as-errors application check and actual pinned
native page syntax check pass with zero diagnostics; 39 isolated AppKit
assertions cover result identity, geometry, native control admission, selection,
IME and focus when a button disappears. Light/dark native component screenshots
a query or navigating; no browser functional test was performed. Populated
current-version hover/pressed/motion details, the separate legacy native FindBar
surface, and the finite remaining Keyboard family checklist stay explicit.

The integrated Downloads/Find application and both changed native implementation units pass warnings-as-errors checks with zero diagnostics. The exact combined app inputs remained unchanged during compilation; the focused Downloads and floating Find components pass. Source overlay replay is recorded separately from the pending engine rebuild. No functional browser tests ran; these increments do not close either family.

### Essentials original window and palette — KBD-07

Implemented the recovered floating/fullscreen-auxiliary education window,
original physical-window placement, fixed light/dark resource palette and
bundled Marlin heading instead of Space-theme colors. Current registry bindings,
custom/reset/disable, original-browser actions and View All remain connected;
hidden/non-key/sheet-owned education controls cannot invoke them. The native

This is a Keyboard family increment, not Essentials/family closure. The outer
parent delegate reducer, conditional absent/disabled-binding row policy and
actual held-event transfer are now implemented in the follow-on below.
Full repeat/focus/AX traversal remains essential work. Shared
keycap bevel/gradient and native View All styling are delivered below. The actual child action
and floating-window contracts are recovered; the follow-on attributes the
parent dispatch and preserves the actual original-browser command owners. No haptic or guessed animation. The
unimplemented tracker removal. Focused production component: 29 assertions;
fixed 154-source whole-module Swift check passes with warnings as errors and
zero diagnostics (233.34 seconds), with every compiler input unchanged. No
browser functional tests or personal shortcut/preference changes.


The Split family now implements original-divider double-click pair equalization:
only the adjacent two factors change, preserving their sum and every other pane.
Original window/page/group admission spans native divider tracking; stale or failed
REA-backed. Native AppKit sizing, minimum pane dimensions and immediate layout
remain adaptations; center snapping/haptics, pane-source entry, container relocation
and the other listed Split interaction gaps remain active. Focused actual native
view/store checks and a 150-source warnings-as-errors compiler check pass. No
functional browser test ran. See [divider pair sizing](split-groups.md#divider-pair-sizing).

The integrated divider pair-sizing increment passes the combined 155-source warnings-as-errors app check with zero diagnostics and all sixteen native divider/store checks, including both orientations and durable-save failure. Original pages and group identity remain unchanged; no browser functional test ran.


**Split family original-tab placement:** the actual sidebar-drop reducer is now
connected to the recovered saved-parent policy. New homes retain saved destinations
and exact mixed parent/group positions while original live IDs join the displayed
split; existing destination children and displaced originals survive. Preview and
commit bind the same hierarchy, physical owner, page and local document identities,
and failed persistence changes neither homes nor group. Focused real store/document
checks and the full application compiler are separate from browser acceptance.
Incoming whole-group activation/merge, pane-handle initiation, cross-Profile/copy
variants and the remaining original presentation/motion remain open; this increment
does not close the Split family.

**Onboarding progression control:** the actual shared SwiftUI control replaces the thin fixed-blue AppKit bezel, with recovered theme semantics and original enabled/hover/press behavior. The complete combined application and the native card/component compile with warnings as errors; actual disposable light/dark setup windows were inspected. Full step content, card details, transition choreography, final reveal and audio/haptic/focus boundaries remain active family work. No browser functional test ran.


Split divider center snapping is implemented through the actual native pan stream:
initially unarmed, 14-point band, original slow-approach120 gate and one generic/now
haptic on snap/release. Only original adjacent panes resize; cancellation/detachment
is REA-backed; page input opts out before recognition. Existing minimum sizes and
immediate layout remain adaptations, with no claim of historical motion or haptic
strength. Pane-handle initiation is still unbound, and the remaining whole-group
drop/placement work stays active. See [divider center snapping](split-groups.md#divider-center-snapping).

The integrated center-snap source passes the combined 155-source warnings-as-errors app check with zero diagnostics and all twenty-five focused native state/admission/lifetime assertions. The prior sixteen double-click/durable-store checks also pass against the final native view in the frozen candidate. Seven-point divider geometry/minimums remain explicit adaptations; no browser functional test or hardware haptic equivalence is claimed.

**Downloads entry integration:** the complete 157-source Swift application passes with warnings as errors and unchanged inputs (229.94 seconds). Actual native Library components pass 44 view, 34 selection and 28 badge/file-provider assertions against the integrated source. The sidebar displays the newest active original download and a bounded completion response; completed-file copy drag revalidates the original item, selection and context when the pasteboard requests its URL. Private Downloads remains active family work; no browser functional or large-history performance test ran.

**Integrated original-tab split placement and Essentials:** the combined 158-source Swift application passes with warnings as errors, zero diagnostics and unchanged inputs (216.18 seconds). The frozen split model/store/alias inputs retain their exact successful 42 new and 27 pre-existing assertions; the integrated native Essentials window/registry passes 29 assertions. Saved-home placement, typed document identity and original-window command ownership remain intact. Whole-family interaction work continues; no functional browser tests ran.


### Private Downloads increment





### Shared keycap and View All presentation — KBD-02 / KBD-07

Essentials and the existing Shortcuts detail/recorder now use the recovered
shared keycap face: 27-point small squares, modifier-count spacing, blue or
pending-conflict red base, lower multiplied shading, continuous white face and
highlight, count-sensitive padding/corners and rounded semibold glyphs. Long
customized chords retain readable caps and semantic accessibility values.
Passive caps cannot steal native editing/focus; custom, reset and disabled
bindings remain owned by the registry. View All now uses the original native
SwiftUI Button, NeutralButtonForeground and GrayA7 border with unchanged exact
window admission and weak action ownership.

and inert production Essentials appearance were compared without executing a
browser action. The large Settings container geometry, disabled dash and
long-label accommodation remain stated adaptations. The outer parent action
mapping, absent-row policy and repeat/hold transfer are still essential family
work; no bespoke press animation or haptic was invented. Source/component
receipts are separate from browser behavior; no functional browser tests or
personal preference changes were performed.

The final 155-source whole-module Swift check passes with warnings as errors,
zero diagnostics and all inputs unchanged (120.86 seconds). The actual hidden
native window/registry component passes 31 assertions, including live custom,
disabled/reset and five-key chord presentation, semantic AX and hidden-action
refusal. Independent read-only native ownership review found no actionable
issue. These are source/component checks, not browser behavior verification.

**Downloads populated row presentation increment:** retained Arc1.122 actual ContentCell list renderer resolves56pt rows,12pt outer padding,24pt leading slot/32pt file artwork, 14/12pt two-line labels,2pt text gap and8pt action spacing. The actual native Downloads row now follows that contract, preserving complete security/progress/Preview/More actions and original tooltip/AX identity. Current-profile/source metadata remains available without a third visual line. Native progress/accessory palette/motion are explicit adaptations. Modern populated reference remains unavailable; original MediaPreviewWindow's200×200 constructor is provisional and does not establish final preview geometry, which remains bounded family work. No browser/file action or DL-PERF investigation ran.

The populated-row increment passes the fixed157-source warnings-as-errors Swift check with zero diagnostics and unchanged inputs; actual components pass139 Library-view,34 selection/table and28 activity/file-provider assertions. A visible native four-state component confirms compact geometry and real controls at400pt width, with no download/file action. Full original status/source context remains accessible once per row. This is a Downloads increment, not whole-family completion.


**Downloads parent-owned preview increment:** actual Arc1.122 MediaPreviewWindow presentation covers the original parent and follows its frame; the centered modal uses max(round(dimension×0.8)−50,100), with10pt corners/70% black backdrop. Production uses this geometry and recovered open0.9/0.25 and close0.95/0.15 damping/response springs from the current original artwork, actual item More/Open/previous-next controls, and immediate context/profile/item/sheet retirement. Closing an interrupted transition starts from its presentation layer; Reduce Motion and missing source frames are immediate. Quick Look, native button metrics/theme and direct-content animation remain explicit adaptations; modern populated appearance is unavailable. Accessory visibility/hover timing remains finite Downloads family work. No browser/file action or DL-PERF investigation ran.

The preview increment passes the exact157-source warnings-as-errors app check with zero diagnostics and unchanged inputs. Actual components pass160 Library/preview,34 selection/table and28 activity/file-provider assertions, including21 new preview ownership/layout/motion cases. These checks use disposable metadata and owned temporary files; they establish the checked native component contract, not browser download/runtime acceptance.

**Preview publication verification:** the merged160-source full application passes warnings-as-errors with zero diagnostics and all260 checked inputs unchanged. Fresh current-model components pass160 Library/preview,34 selection/table and28 activity/file-provider assertions. The five-file preview production delta is published independently of the remaining accessory interaction work.

## Counted active-family requirements

Initial measured snapshot: `75cfe519d13ced8577833ad8e2062b8c3f7b4588` (October 26, 2026). Current counted source: `4edad53` plus the Downloads source-image preview delivery in this commit; published Keyboard, Split and additional-family audit rows are preserved. Private/in-progress increments do not count as delivered.

Current completion and movement for these families are in the [single family table](#family-completion).

Changes during this audit: KB35 closes with the published original Essentials parent dispatch; KB36 closes with original optional-row behavior and delivered held/repeated event transfer; the repeat correction adds +2.6 percentage points from the previous 24/38 snapshot. KB22 and KB37 remain open for broader context/refusal and focus/AX/motion comparison. DL23 closes from the published parent-sized preview; SP28 closes for the published ordinary same-Space Add flow. DL24 closes with the original-artwork snapshot handoff, independent content/backdrop/shadow transitions and original-parent retirement. SP27 stays open: the recovered single-pane directional Add list, populated menu order and original action admission are now connected, but glyph/control placement, hover visibility and exact presentation remain partial. Cross-context Add destinations remain with SP20/SP21/SP33. This records delivered work without turning a partial increment into a completed family.

Method: each row is one explicitly bounded requirement from the existing parity ledger and its focused mechanism documents. DONE requires connected implementation and the applicable existing compiler/component evidence. LEFT includes partial implementation, a known experience mismatch, an unimplemented path, or missing reference attribution necessary to implement the requirement. Browser functional tests are not closure requirements under the user's instruction. Necessary account-free/local/Chromium adaptations do not automatically fail a requirement; differences that change the requested experience stay LEFT.


Do not merge, split, remove, or reweight rows to improve a score. Later discoveries add identified rows, and reports must distinguish scope changes from completed work. Completed child rows do not close their parent family while another row remains LEFT. No overall project percentage is inferred from these four active families.

### Downloads

Scope and evidence: `docs/download-library.md`, including its existing eight-part checklist, original REA addresses, populated-row and private-window sections. Source: `DownloadLibraryView`, `DownloadLibraryTable`, `DownloadLibrarySelection`, `DownloadThumbnailProvider`, `DownloadLibraryPreview`, `DownloadActivityBadge`, `DownloadFileDrag`, `DownloadReviewController`, BrowserWindowController's download routes, BrowserStore's regular/private publication and native download services. Existing integrated evidence: 432 Library-view + 39 selection/table + 44 entry/provider + 228 Library-entry + 99 arrival + 33 Download Location picker assertions, all eight sidebar component suites, the pinned native syntax-only check of the changed engine units, read-only overlay validation (version 233) and the whole-module Swift typecheck with zero diagnostics. The separately requested DL-PERF-01 large-folder investigation is after polish and outside this active delivery checklist.

| ID | State | Requirement |
|---|---|---|
| DL01 | DONE | Open the in-window Downloads Library beside the existing page through its actual entry commands. |
| DL02 | DONE | Prepare actual profile download managers; show loading/failure/retry and reconcile authoritative history without scanning the Downloads folder. |
| DL03 | DONE | Search actual download names and source URLs. |
| DL04 | DONE | Filter by original Profile without changing the current browser Space or retargeting commands. |
| DL05 | DONE | Group by actual start date, newest first, with an explicit unknown-date group. |
| DL06 | DONE | Match original Filter/Done header, toggled Profile chips/removal, retained query/focus and shared0.3-second transition; remove the extra All Profiles row and retain stable source order on equal dates. |
| DL07 | DONE | Use the recovered compact row geometry, title/subtitle typography, artwork dimensions, selection fill and corner radius. |
| DL08 | DONE | Match accessory visibility, palette and hover/pressed/disabled transitions in populated rows. |
| DL09 | DONE | Load real safe-file thumbnails asynchronously, cache bounded results, and cancel stale/detached requests. |
| DL10 | DONE | Keep single-item keyboard selection on the original live identity; skip headings, stop at endpoints and preserve search composition. |
| DL11 | DONE | Reconcile plural/range selection and plural commands: the attributed optional-item view uses one cursor, so the extra AppKit range/Select All and plural dispatch are removed. |
| DL12 | DONE | Resolve original-row contextual and keyboard actions again after selection, filter, window or manager changes. |
| DL13 | DONE | Display actual transfer bytes, determinate/indeterminate progress and paused/completed/canceled/failed state. |
| DL14 | DONE | Connect supported Pause, Resume, Cancel and Retry controls to the real manager with truthful outcomes. |
| DL15 | DONE | Connect native security/scanner review decisions and help to the original item/profile/window. |
| DL16 | DONE | Open, Reveal and Open When Finished through current native capabilities. |
| DL17 | DONE | Copy the genuine completed file or download link; open source URL in the original profile context. |
| DL18 | DONE | Remove through the original manager action and preserve the file according to its contract; the earlier confirmation assumption is corrected by the direct reducer trace. |
| DL19 | DONE | Trash asynchronously, retain failed records, prevent duplicate actions and report the actual result. |
| DL20 | DONE | Reconcile confirmation/plural behavior: the original single-item Hide/Trash chain dispatches directly, so the extra confirmation surface is removed; original native security review and outcome errors remain. |
| DL21 | DONE | Preview only the currently eligible original file; navigate eligible files and expose guarded Open/Copy actions. |
| DL22 | DONE | Retire preview on item/profile/context/window changes and return focus only to its original valid owner. |
| DL23 | DONE | Replace the provisional titled Quick Look window with the recovered parent-sized media-preview presentation and geometry. |
| DL24 | DONE | Implement the recovered preview open/close transition, source-image relationship and toolbar/menu presentation. |
| DL25 | DONE | Expose actual policy-owned profile download preferences, cold-context preparation, folder chooser and truthful save failure. |
| DL26 | DONE | Show the newest active download's genuine progress and a once-only observed completion indicator. |
| DL27 | DONE | Use the attributed SwiftUI progress/completion interpolation and original rendered subtrees; retire animation on original-item/window/accessibility changes and remove the inferred unused echo. |
| DL28 | DONE | Drag one safe completed file lazily through its original manager/row identity; reject stale, plural or unavailable sources. |
| DL29 | DONE | Use the actual OTR manager in private windows, with memory-only records, guarded actions and teardown. |
| DL30 | DONE | Merge actual regular and live private manager records in Downloads while retaining original Profile/context/item actions and memory-only private storage. |
| DL31 | DONE | Provide accessible labels/actions, narrow-row containment and Reduce Motion handling in the delivered controls. |
| DL32 | DONE | Complete original row progress/lifetime, Return cursor, single-click media-preview/Open/unfinished-toggle, plain Search, single-More control/focus/AX, continuous background/selection, state-specific subtitles and attributed24-point file artwork/14-point empty template with original title states; actual native light/dark comparison and exact callback/retirement checks pass. |

### Saved shortcut conflict and reset completion

chords persist, all ambiguous keyboard routes become inactive, and explicit
Remove Conflicting Shortcut(s) clears the other owners. Original menu items,
native priority, held-MRU entry and Essentials share that projection. The
16-point red reveal button preserves detail selection/query/focus; the separate
orange system warning uses genuine read-only Carbon records. Reset All follows
the recovered direct action without an extra confirmation. Existing recorder
layers, keycap states and selected native removal effect remain intact.

KB09 is DONE. The unchanged fixed ledger advances 26/38 → 27/38
(+100/38 percentage points before rounding); 11 requirements remain LEFT.
Source/component checks and an inert production appearance comparison support
this delivery; no functional browser tests or personal preference changes ran.
in [the focused contract](settings.md#saved-conflicts-system-warnings-and-reset).

### Keyboard shortcuts and gestures

Scope and evidence: KBD-01 through KBD-07 in `docs/parity.md`; `docs/keyboard-navigation.md`; `docs/settings.md` Shortcuts/priority/Essentials/keycaps; `docs/tab-switcher.md`. Source: `KeyboardShortcuts`, `ShortcutRecorderView`, `ShortcutsSettingsView`, `ShortcutKeycapView`, `ShortcutPriorityHintView`, `ShortcutEssentialsWindow`, `RecentTabSwitcher`, `PageFindView`, `BrowserFindCommand`, sidebar keyboard models and actual native keyboard routing. Existing evidence includes KeyboardNavigation components, native priority/dispatch compiler checks and the combined app compiler check. Split creation behavior belongs to Split; this family owns its binding and keyboard dispatch, not a duplicate implementation credit.

| ID | State | Requirement |
|---|---|---|
| KB01 | DONE | Register implemented commands from their genuine menu owners and keep menu key equivalents synchronized. |
| KB02 | DONE | Persist custom/disabled bindings atomically, preserve unreadable files and migrate existing user choices without stealing chords. |
| KB04 | DONE | Numbered Sidebar items and every dynamic Space command use their original menu/selection owners, recovered defaults and live ordinal/name/removal registration. The Favorites and ninth-item settings match the recovered conditional controls; migrations preserve saved chords. All six Find menu items are registered: the focused Note forwards native tag 1 for every item, the browser rejects tags 0/12, and the unattributed generic-text route is removed. Model/inert components and final whole-module SIL pass; [evidence](keyboard-navigation.md#numbered-targets-and-native-text-find--kb04). |
| KB05 | DONE | Search action names and modifier names/symbols and group custom versus default bindings. |
| KB06 | DONE | Record only while focused, preview held modifiers, preserve existing chords and end recording on cancel/deactivation/removal. |
| KB07 | DONE | Translate keys using the active ASCII-capable layout and enforce recovered reserved-key restrictions. |
| KB08 | DONE | Support clear, reset-one, reset-all and explicit atomic conflict resolution with truthful save failures. |
| KB09 | DONE | Complete recorder/conflict/reset focus, layout-specific, visible-state and motion parity. Original layers/halo, complete native chord fitting, durable conflicts and inactive dispatch, 16-point conflict/OS warnings, centered reveal without selection/focus change, More/context removal, direct Reset All, original native removal effect and stale-owner refusal are delivered. |
| KB10 | DONE | Draw recovered shared keycap faces, modifier order, count-sensitive spacing and conflict colors. |
| KB11 | DONE | Match Shortcuts detail geometry and keycap/focus layout across chord lengths: original 200-point column, 64-point caps, intro/unassigned/bound states, natural-height descriptions, play-once smiley, native removal feedback and actual focused recorder/held-modifier/cancel transitions. |
| KB12 | DONE | Persist Prefer Websites / Use Both / Prefer Parc and expose the actual selected-command native picker. |
| KB13 | DONE | Arm Use Both only from a genuine consumed-key acknowledgment and dispatch the original validated menu item once. |
| KB14 | DONE | Cancel queued shortcuts on original document/focus/window/binding/security ownership changes. |
| KB15 | DONE | Use the recovered five-second hover-aware cue lifetime and Edit action targeting the original shortcut. |
| KB16 | DONE | Match cue geometry, material, anchor and entry/exit motion: original 600-point non-key window, Space-derived local-default palette, concrete Big Key, delayed below-body Edit accessory, attributed spring and exact passive-retirement lifetime. Inert native light/dark appearance and ownership checks preserve the renderer queue; current-version website interaction is not claimed. |
| KB19 | DONE | Keep held-MRU preview separate from selection, with recovered delay, release/cancel and original thumbnail ownership. |
| KB20 | DONE | Preserve five visible MRU cards, reserve replacement and real confirmed-close handling. |
| KB21 | DONE | Complete held-MRU card/panel presentation: custom split icon/title/count and favicon captions; original image/template/empty snapshots, split panes, Peek overlays and recording marker; hidden reserve opacity/promotion and direct panel show/close/resize. Original page ownership and consent stay authoritative. REA, inert presentation/light-dark captures and whole-module SIL; no browser tests ([evidence](tab-switcher.md#completed-variants-and-transitions--october-28)). |
| KB23 | DONE | Enter sidebar keyboard search with a separate stable-ID cursor, folder Return and original-page activation. |
| KB24 | DONE | Cancel sidebar sessions against original ownership and restore the original responder only when valid. |
| KB27 | DONE | Reconcile Shortcuts Settings layout/composition/accessibility and original context ownership: native search/IME/caret, actual Basics and conditional clear buttons, attributed hover spring, named sections, original selected/conflict rows, full-title help and complete first-selection detail text. Exact window/sheet/detach refusal and native input/AX owners are preserved; component and installed appearance comparison cover this surface. |
| KB28 | DONE | Connect the three genuine Edit copy commands with original-document/native clipboard ownership and shipped bindings. |
| KB29 | DONE | Connect recovered creation/capture/navigation/page-tool/Close Window/Full Screen/Exit bindings to their existing owners. |
| KB30 | DONE | Connect Find/Next/Previous/Selection to original document or native text owners with genuine result state. |
| KB31 | DONE | Implement the recovered floating Find panel dimensions, semantic colors and query/result controls. |
| KB32 | DONE | Match populated Find hover/pressed/focus and transition behavior: native momentary-change press and rounded focus mask, original GrayA4 enabled hover, exact current-window hit/tracking cancellation, passive readable count and immediate original visibility/result replacement. Actual native components and light/dark populated captures preserve query/IME and dispatch owners; current-version populated reference pixels remain unexercised. |
| KB33 | DONE | Open the original-browser-owned Essentials window from Settings/Help and show live registry bindings. |
| KB34 | DONE | Use recovered Essentials window placement, palette, typography, row spacing and native View All control. |
| KB35 | DONE | Correct Essentials parent action semantics, including retaining education for commands and Escape. |
| KB36 | DONE | Implement absent-binding row policy and genuine held/repeated event transfer from Essentials. |
| KB37 | DONE | Complete Essentials focus/AX, hover/pressed/disabled and motion comparison: one passive ordered instruction group, real native View All and NSWindow presentation, active-binding omission and exact owner refusal; actual inert AX/focus/control comparison and 60 native assertions preserve original command owners. |
| KB38 | DONE | Live valid bindings update existing menus, tooltips, command-search entries, Start/Ready discovery and the original command-field Copy URL hint, including weak lifetime and removed-command suppression. The genuine Peek Open in command uses Command–O / Use Both and shares current-window-Space promotion with Expand; both retain original page/Profile/referrer ownership and the live binding. Whole-module SIL and focused native/model components only; no browser execution or final visual/motion acceptance claimed. [Evidence](keyboard-navigation.md#live-binding-discovery-and-copy-education--kb38). |

### Split views

Scope and evidence: `docs/split-groups.md`, NAV-05 and split rows in `docs/parity.md`. Source: `BrowserSplitLayout`/store transactions, `ParcSplitView`, `SplitDropGeometry`, `SplitDragView`, `ExternalSplitDropView`, sidebar split controls/customization/Undo and BrowserWindowController's original-page actions. Existing evidence includes real model/store/sidebar/divider tests, 35 geometry and 23 native-session assertions, 29 local-document drop assertions and combined app compilation. Ordinary folder behavior is not separately credited here; only whole-split consequences are listed.

| ID | State | Requirement |
|---|---|---|
| SP01 | DONE | Persist typed original-child groups, orientation, ratios, anchor and nonoverlapping membership migration. |
| SP02 | DONE | Select the original whole group while preserving the focused original web/Note/Easel pane. |
| SP03 | DONE | Change orientation through original-group commands. |
| SP05 | DONE | Close/reset/capture original children through current sidebar/context/accessibility actions. |
| SP06 | DONE | Separate the focused original page while preserving surviving siblings, saved group and actual focus semantics. |
| SP07 | DONE | Resize only the original adjacent pair with native pan ownership and persist once on an accepted end. |
| SP08 | DONE | Equalize only the double-clicked divider's adjacent pair. |
| SP09 | DONE | Apply recovered divider center-snap thresholds and engage/release haptic triggers. |
| SP11 | DONE | Insert or replace with an original sidebar tab under one original-owner drag lease and atomic publication. Members reorder through the pane menu's Move entries; split children are not drag sources (SP30). |
| SP12 | DONE | Preserve pinned/Favorite saved homes at their original parent slots during supported grouping. |
| SP13 | DONE | Classify recovered pane drop regions and fall back from refused insertion to valid replacement. |
| SP14 | DONE | Cancel a drag on invalid original geometry/selection/profile/page/window and commit at most once. |
| SP15 | DONE | Create a genuine single HTTP(S) URL tab from external drops into supported web, Note and Easel panes. |
| SP16 | DONE | Keep renderer/editor ordinary drops and IME/self-drag behavior outside claimed split gestures. |
| SP17 | DONE | Support external drops on saved standalone/Favorite groups while preserving their saved-home and container identity. |
| SP18 | DONE | Move supported whole groups within a Space or to an existing/new same-Profile Space atomically. |
| SP19 | DONE | Move supported same-Profile whole groups across physical windows with actual native/local editor ownership. |
| SP24 | DONE | Rename original ordinary/Favorite containers without renaming their children. |
| SP25 | DONE | Commit/remove/reset the original custom icon and name with atomic persistence and guarded Undo/Redo. |
| SP28 | DONE | Replace the legacy Add Split interaction with recovered temporary empty-pane/command-bar creation and cancellation for ordinary same-Space navigation/tab/local-document results. |




### Onboarding and complete first launch


| ID | State | Requirement |
|---|---|---|
| OB01 | DONE | Gate all browser creation/URL/relaunch entry paths until the first-launch owner permits the real browser reveal. |
| OB02 | DONE | Use the recovered large, clear welcome window and retain its size/background into setup rather than a browser-attached sheet. |
| OB03 | DONE | Keep one cancellable welcome owner across its recovered reducer phases and manual advance. |
| OB04 | DONE | Animate the approved Parc P in the recovered intrinsic slot with attributed opacity/blur/scale/offset timing. |
| OB05 | DONE | Present the owned screen-sized dark backdrop and recovered gradient/surface choreography with interruption cleanup. |
| OB06 | DONE | Use the recovered headline font, character timing, blur/travel and punctuation delay. |
| OB07 | DONE | Use the recovered arrow control, reveal timing, delayed action and hover/pressed spring. |
| OB08 | DONE | Play one bundled music cue at the recovered volume through welcome/setup and stop on close/finish. |
| OB10 | DONE | Implement recovered video/mask/grain choreography, readiness ownership and rotation. |
| OB12 | DONE | Provide settled Reduce Motion artwork and cancel running decorative motion when the preference changes. |
| OB13 | DONE | Retain the recovered two-column card dimensions, title font, corner and shadow inside the persistent background. |
| OB14 | DONE | Apply the real selected-theme backgroundExtra/maxContrast semantic colors and update the existing controls. |
| OB15 | DONE | Share the recovered setup progression control dimensions, states, labels and Return/IME ownership. |
| OB16 | DONE | Finish card grain, border, complete light/dark optical composition and small-screen presentation. Named CardBackground/CardInnerBorder/CardOuterBorder once-inits; grain drawn by the sidebar theme renderer's rules (theme texture, dial strength, 100-point pitch, multiply; November 2); inner 1pt continuous stroke above the content column (centerline 0.5); outer 1pt stroke and shadow unclipped; 967×548 bounds in 24h/48v one coordinate space. |
| OB17 | LEFT | Complete the full included reference step order and conditional branching beyond the implemented local import/Favorites/theme/default-browser sequence. |
| OB18 | DONE | Complete the browser/bookmark-import step’s reference content, controls and presentation: same-window source/profile rows, source-history top-five recommendation and full bookmark list/folder controls, Safari access, password-method choice, manual CSV/results and parent-owned help. Exact copy/frame/default-selection comparison and native model/compiler/appearance checks are recorded in [onboarding evidence](onboarding.md#import-content-and-initial-bookmark-recommendations). Independent-source permission/progress/error adaptations remain explicit. |
| OB19 | DONE | Favorites uses the recovered nine-app sidebar illustration, exact default/ordered selection, bundled light/dark artwork, selection/hover/press appearance and persistent native owner, wired through draft persistence to the real session. Source/model/compiler and actual native appearance evidence is in [onboarding evidence](onboarding.md#favorites-setup-content-and-selection). Whole-flow traversal retains OB33. |
| OB20 | LEFT | Complete theme/customization step presentation, including its onboarding-specific editor composition. |
| OB21 | DONE | Optional default-browser step: recovered radio geometry, theme colors, hover/selection springs and preferred-choice heart; durable pending choice, genuine sequential macOS consent/readback, refusal/retry and replay/owner guards. |
| OB22 | LEFT | Complete any applicable extension-import/setup step and its real conditional continuation. |
| OB23 | LEFT | Complete final ready/reveal content and reference transition choreography. |
| OB24 | DONE | Route selected browser/HTML imports to actual local readers and retain genuine imported hierarchy/data. |
| OB25 | DONE | Connect draft theme/Space/favorite choices to the actual local model and shared editor. |
| OB26 | DONE | Save selected setup and completion atomically, roll back failed saves and avoid duplicate favorites/bookmarks. |
| OB27 | DONE | Persist/resume the local draft; restart interrupted welcome and preserve existing state on corrupt-draft recovery. |
| OB28 | DONE | Preserve the welcome/music owner across declined quit and cancel scheduled work on genuine teardown. |
| OB29 | DONE | Prepare the real browser hidden, close onboarding before reveal and retain retry on preparation failure. |
| OB30 | DONE | Offer Replay onboarding only from General settings and start it from the original welcome/music. |
| OB31 | DONE | Apply finished replay choices to the originating Space without removing existing tabs, Spaces or settings; preview its theme live and restore it on early close; resume across a Safari restart; never save the theme or light/dark preview, so a crash keeps both; apply only what replay changed; return queued links to the surviving browser. |
| OB32 | LEFT | Match Back/Next and theme/step transition choreography throughout setup. |
| OB33 | LEFT | Complete keyboard/focus/VoiceOver traversal and return throughout welcome, setup and reveal. |
| OB34 | LEFT | Complete the full audio interruption/mute/focus policy beyond the recovered single-player owner. |
| OB35 | LEFT | Attribute and implement any onboarding haptic triggers; bounded absence is not a whole-flow conclusion. |

**OB18 closure:** all five included import compositions have a recovered content/control comparison; actual source visit counts now reach the initial bookmark selection, and the list fills its attributed frame. The final native session and 186-source application checks pass with warnings as errors, alongside 87 selection/store, 156 coordinator and five restart assertions. Actual window captures confirm light/dark native list contents. This closes one existing requirement: Onboarding 63.9% → 66.7%, +2.8 pp, with the denominator unchanged. Whole-flow conditional order, extension setup, theme/card optics, motion and traversal retain their own LEFT rows. The new engine source is published without reopening a browser-test gate.

**OB19 closure:** original fixed choices, initial OrderedSet, index-zero toggle insertion, display geometry/artwork and tile motion are implemented end to end. Model checks cover durable order, reselect/deselect, old drafts/aliases, invalid entries, atomic commit/restart and rollback. Native light/dark card captures and warnings-as-errors compilation are recorded separately from the unaccepted direct AX harness. This closes one existing row: 66.7% → 69.4%, +2.8 pp; denominator36 unchanged.


**OB16 closure:** setup-card overlay mapping is complete on the published grain/outer-stroke chrome: named CardBackground/CardInnerBorder/CardOuterBorder once-inits, grain drawn by the sidebar theme renderer's rules (theme texture, dial strength, 100-point pitch, multiply; November 2), inner 1pt continuous stroke above the content column (centerline 0.5), outer 1pt stroke and shadow unclipped, and 967×548 bounds inside 24h/48v margins in one coordinate space. Isolated presentation checks pass; independent review CLEARed. This closes one existing row: 72.2% → 75.0%, +2.8 pp; denominator 36 unchanged. Theme-editor composition, step order, ready/reveal, motion and traversal retain their LEFT rows. No browser functional test ran.

**OB21 delivery:** the real onboarding owner now presents the optional default-browser step and routes Next through the existing actual macOS controller. Explicit stage ordering preserves old draft tags and removes the generic introduction card. REA recovers the two radio rows, semantic colors, hover spring and preferred Yes heart; [onboarding evidence](onboarding.md#optional-default-browser-step-and-setup-order) records addresses, versions and adaptations. Actual isolated presentation confirms option geometry, selection feedback and native button roles. Draft/migration/commit checks and 23 injected default-browser ownership checks pass without changing system handlers. Whole-flow branching, other step layouts, transitions and focus remain their existing LEFT rows; this closes only OB21.
**Inline import delivery:** the original setup window now owns discovery, source/profile selection, genuine import, permissions and bookmark acceptance through a reusable presenter. Source rows use the recovered 278×92 layout, actual application icons and source-specific colors; first launch imports into its captured Profile without the menu's extra destination wizard. Closing/skip/restart and file-panel callbacks retain their exact owner. The menu retains its dedicated window and explicit destination. OB17/OB18 remain LEFT for full conditional branching and the remaining step compositions, with no denominator change or partial credit. Compiler and isolated import/model checks cover this increment; no browser functional test ran.

**Inline profiles:** multiple-profile choices now appear below their selected source row, with recovered spacing/container/radio dimensions. Native discovery is cancellable without replacing the source screen; Next alone starts import or genuine Safari guidance. Start fresh, file selection and source changes revoke stale callbacks, and explicit extension decisions remain scoped to the actual selected profile. The full 166-file Swift check and 97 coordinator assertions pass; actual light/dark component hosts were inspected. Bookmark/Safari setup composition and remaining profile optics are still OB18 work; Onboarding stays 23/36 DONE, 13/36 LEFT, 0.0 pp.

**Inline bookmarks:** the embedded import list now keeps source-profile selection,
Select All and folder expansion separate, with the recovered light-only white
surface, circular controls, indentation, typography and retained two-plane
native folder drawing. Acceptance keeps its original destination and real atomic
store. [Evidence and adaptations](onboarding.md#inline-bookmark-selection).
Safari setup/profile optics and whole-flow focus/motion remain their existing
LEFT requirements; Onboarding stays 63.9% DONE, 36.1% LEFT, 0.0 pp.

### Essentials parent commands and optional rows — KBD-04 / KBD-07

Recovered the actual physical-window parent reducer and optional-binding
producer. New Tab, Recent Tab, Copy URL and Split keep education alive; Escape
dismisses only its original command bar. View All/actual close clear education.
The actual key event enters the existing held-MRU path, absent bindings remove
and reflow their complete row, and expired menu callbacks cannot fall through
to another browser. A narrow plain-URL auxiliary-command capability now keeps
education focused while reusing the original selected native page and real
clipboard policy/document/window cancellation. Ordinary Copy/Markdown/Quote
admission remains unchanged; no cached-URL substitute or new input monitor.

The final combined 162-source whole-module application passes with warnings
as errors and zero diagnostics (42.87 seconds), with all 262 compiler inputs
unchanged. The actual pinned native Copy translation unit also passes with
zero diagnostics; its 99 inputs exactly match the published source. The prohibited-activation
native component passes 35 assertions for optional rows, custom/reset bindings,
AX presentation, persistence and unavailable-owner refusal. The accessory-app
experiment could not obtain key-window status in this environment, so positive
foreground execution is not claimed. Independent native source
review found no actionable ownership issue. No browser, clipboard or personal
shortcut test ran. The retained installed Essentials/Escape/View-All appearance
and original 1.122 REA are separate evidence tracks. Exact repeat/focus/AX/motion
comparison remains active. The Split family’s delivered Add destination is
preserved through its existing entry; this increment does not close any of the
seven broad Keyboard checklist groups.


**Downloads counted movement — row accessory delivery:** DL08 is now complete: original row hover/selection and live-scroll visibility, 32-point accessory geometry, recovered GrayA foreground/background states and exact native action focus are implemented. The denominator stays DL01–DL33: 25/33 DONE = 75.8%, 8/33 LEFT = 24.2%. This is +1 completed unit and +3.0 percentage points from the preceding 24/33 = 72.7% snapshot (+6.1 points from the initial 23/33). DL24 remains LEFT for the preview snapshot-image transition difference; the other seven unresolved requirements are unchanged. No new scope or weighting was introduced.


**Essentials delivered-repeat boundary (KB36):** the original education window
inherits `NSWindow`; its local Objective-C methods do not replace key-equivalent
(fresh REA `ev_d7f3843cc37b99d7c460dac44d98c2f31c8b31dd4c1b357a240d03849b9dffd1`),
which does not inspect a repeat flag. Parc removes its extra repeated-event
fallback, retaining current chord/owner validation and the real held-MRU event.
The existing absent-binding rows and parent dispatch are preserved. Actual inert
AppKit menu checks cover initial/repeated delivery, once-per-event dispatch,
disable/customization/reset and current registry ownership: 43 assertions pass.
No OS repeat cadence, positive browser execution or full focus/motion parity is
claimed. KB22/KB37 remain LEFT. Fixed denominator remains 38: 25 DONE (65.8%),
13 LEFT (34.2%), +2.6 points from the previous counted Keyboard snapshot.

## Counted remaining-family requirements

Initial source snapshot: `a4f777019869c785003a4926d51928679e10dc43`. These rows use the same DONE/LEFT rule as the four active families above. They count known documented requirements, including necessary experience work; they are not effort weights, an exhaustive-discovery claim, or an overall browser percentage. Overlapping family responsibilities must not be summed into a project-wide score. Each remaining family starts with a new measured baseline; change from earlier uncounted estimates is unavailable. Source references below identify the actual owners; the focused documents preserve REA/version/limitations and existing compiler/component evidence. No browser test is introduced as a closure gate. Performance comparisons remain deferred while browser testing is stopped; they are not reopened P0 gates.

The standalone Chromium family uses the existing unchanged 29 DONE rows P0-01 through P0-28 plus P0-30: **29/29 = 100.0% done; 0.0% left**. P0-29 is excluded under the user's instruction. This counts the mapped architecture implementation, not shipping execution or whole-browser experience.

**Live integrations: excluded by the user, with no completion denominator.** The recorded source/dependency removal audit is complete. Excluded services are not unfinished product requirements and are not credited as implemented features.


Evidence: parity.md P0-28; source-owned app/native integration; build.py dependency guard.

| ID | State | Requirement |
|---|---|---|
| BC08 | DONE | Josh accepted family completion on October 29 based on the existing implementation. The previously planned source-wide initialization/background-path audit was not performed; engine-wide absence and representative runtime network behavior remain unverified. |


### Settings

Evidence: settings.md; [local membership card](settings-membership-card.md); SettingsWindow.swift; SettingsWindow.swift profile pane; DefaultBrowserController.swift; BrowserStore.swift.

| ID | State | Requirement |
|---|---|---|
| SET01 | DONE | Provide the General, Profiles, Links, Shortcuts, Icon and Advanced native panes. |
| SET02 | DONE | Persist the selected pane/profile and profile rename through the actual store. |
| SET03 | DONE | Request actual sequential HTTP/HTTPS default-browser consent and read back both handlers. |
| SET04 | DONE | Expose General replay only through its actual onboarding owner. |
| SET05 | DONE | Connect restore/sidebar appearance preferences to their production owners. |
| SET06 | DONE | Expose real profile search provider and suggestions preferences. |
| SET07 | DONE | Open genuine profile Chromium More Settings without discarding an existing subpage. |
| SET08 | DONE | Open the genuine profile password manager. |
| SET09 | DONE | Remove eligible individual profiles through typed confirmation and real native deletion. |
| SET10 | DONE | Remove unused profiles as an authorized set with per-profile failure/retry/cancellation. |
| SET11 | DONE | Protect default, assigned, busy and newly created profiles during removal. |
| SET12 | DONE | Reset actual profile translation language/site preferences with truthful completion. Removed November 1 with page translation, which is excluded because it needs a Google API key. |
| SET13 | DONE | Route private-window app Settings to the explicit normal parent. |
| SET14 | DONE | Persist shared toolbar and full-URL appearance preferences. |
| SET15 | DONE | Persist independent sound and tab-reordering-haptic switches and wire their consumers. |
| SET16 | DONE | Wire webpage window-dragging and Shared Quotes preferences to actual page owners. |
| SET17 | DONE | Publish theme data to the original website document through the actual setting. |
| SET18 | DONE | Export real local browser data to Markdown through the owned save route. |
| SET19 | DONE | Provide the actual quit warning and original-window continuation. |
| SET20 | DONE | Provide General preview preferences through the existing preview owners. |
| SET21 | DONE | Complete General/Profiles command and preference inventory: original-profile Search Settings and data destinations, accepted/refused native dispatch, atomic explicit preferences and recovered quit-warning default. [Contract](settings.md#general-and-profiles-command-inventory--set21). |
| SET22 | DONE | Reconcile the complete Settings theme inventory and registered default; connect the persistent shared policy to original window/document consumers. |
| SET23 | DONE | Match recovered removal/cleanup sheet geometry, content, palette and controls with truthful partial/retry/completion feedback, original native operation ownership and integrated sheet/parent focus and interruption. [Contract](settings-profile-removal.md). Independently reviewed, with inert native/model checks and final whole-module SIL. |
| SET24 | DONE | Match shared native pane surfaces, included toolbar assets/order, General/Profile control geometry, Advanced glyphs and preserved native selection. [Presentation contract](settings-presentation.md); completed Icon/Shortcuts treatment retained. |
| SET25 | DONE | Match immediate pane changes, native modal transitions and recovered per-control hover/pressed feedback without invented haptics. Shared lifetime-safe hover is integrated into actual Profile command and removal-sheet controls; repeated-pane and sheet cancellation preserve original native owners. [Motion contract](settings-motion.md); 28 inert native assertions, final whole-module SIL and independent exact-source review, plus reviewed SET23/24/26 integration. |
| SET26 | DONE | Complete native pane/key-view navigation, same-pane focus preservation, original-context sheet return and interruption guards. Removed-profile return explicitly selects the surviving list; native controls retain role/label/value/disabled semantics. [Contract](settings.md#settings-responder-ownership-and-interruption--set26). Twenty-one inert native assertions, final whole-module SIL and independent exact-source review pass; no VoiceOver/FKA or browser-runtime acceptance claimed. |
| SET27 | DONE | Restore the complete local membership card in the first personal-name Settings pane: recovered artwork/palettes/title generation/name-derived masks, persistent local identity/date/design, pointer and background motion, native rename/share/download/randomize controls and integrated keyboard/accessibility/lifetime ownership. [Contract](settings-membership-card.md). File-backed model/inert native renders, final whole-module SIL and independent exact-source review pass; account/cloud-service exclusions remain intact. |

### App identity and icon variants

Evidence: settings.md App icon; [UI marks and alpha cleanup](app-icon-marks.md); [optical export](app-icon-optical.md); [availability/discovery contract](app-icon-availability.md); Resources/AppIcons/README.md; AppIconController.swift; IconSettingsView.swift; ParcDockTile.m; build.py.

| ID | State | Requirement |
|---|---|---|
| ICON01 | DONE | Bundle all ten approved P icon variants as previews and native ICNS families. |
| ICON02 | DONE | Persist the selected app icon atomically with truthful save failure. |
| ICON03 | DONE | Restore the chosen identity before browser/onboarding presentation. |
| ICON04 | DONE | Update native app/Dock and Finder identities with partial-failure retry. |
| ICON05 | DONE | Restore the saved choice through the source-owned Dock plugin while the app is closed. |
| ICON06 | DONE | Package the Alerts helper with its own declared icon and matching image bytes. |
| ICON07 | DONE | Provide a real selectable icon Settings control and current-choice state. |
| ICON08 | DONE | Preserve approved master RGB/opaque pixels while cleaning outer alpha; derive the same Original P silhouette for borderless welcome/import marks and monochrome portrait export. Asset/native compositor checks and final SIL pass; independently reviewed. |
| ICON09 | DONE | Normalize native optical framing without redrawing approved artwork; inspect all ten variants at actual small sizes on light/dark backgrounds. All 100 representation checks, ten packaging cases, 80 native controller/compositing assertions and finished renderer/component SIL pass; independently reviewed. |
| ICON10 | DONE | Match selection/hover/pressed and transition treatment in icon Settings. |
| ICON11 | DONE | Reconcile historical account-date/referral availability and reward discovery with the explicit all-ten offline Parc catalog. Original stays the default; service unlock gates/banners remain excluded. Native image consumers use bundled ICNS, with absent-only PNG fallback. Independent review, 50 inert controller assertions and strict whole-module typecheck/final SIL pass; no browser tests. |

### Whole-product polish

Evidence: Explicit exhaustive polish requirement in parity.md; cross-cutting final pass, not a second implementation score.

| ID | State | Requirement |
|---|---|---|
| POL01 | LEFT | Complete the exhaustive included interaction/state inventory across every family. |
| POL02 | LEFT | Close the final icon size, alignment, artwork and optical-bounds pass everywhere. |
| POL03 | LEFT | Close the final typography, spacing, geometry and material/color pass everywhere. |
| POL04 | LEFT | Close the final light/dark/theme and scale/window-size comparison everywhere. |
| POL05 | LEFT | Close the final every-menu and every-modal layout/action-state comparison. |
| POL06 | LEFT | Close the final every-hover/pressed/disabled/selected-state comparison. |
| POL07 | LEFT | Close the final animation timing, curve, continuity and frame-pacing comparison. |
| POL08 | LEFT | Close the final interrupted/reversed/canceled interaction comparison. |
| POL09 | LEFT | Close the final keyboard, gesture and focus-return comparison. |
| POL10 | LEFT | Close the final accessibility, contrast and Reduce Motion comparison. |
| POL11 | LEFT | Close the final sound and haptic trigger/feedback comparison. |
| POL12 | LEFT | Close the final integrated full-experience review without treating sampled flows as exhaustive. |

### Spaces and profiles

Evidence: space-navigation.md; [theme appearance parent](space-theme-appearance.md); [theme input](space-theme-input.md); [theme haptics](space-theme-haptics.md); [theme material/text and motion](space-theme-rendering.md); settings.md; SpaceTheme.swift; SpaceThemeEditor.swift; SpaceThemeEditorView.swift; WindowPresentation.swift.

**Contracts from the Sidebar (October 27, delivered by SPACE18):** the Space header's optional title, inline rename, icon picking, profile indicator and the remaining Space menu items (Change Space Icon…, Set Profile, Delete Space, Manage Spaces…) are listed with interface and behaviour in [sidebar resizing](sidebar-resize.md#space-header).

| ID | State | Requirement |
|---|---|---|
| SPACE01 | DONE | Maintain separate local browser profiles and stable Space/profile identity. |
| SPACE02 | DONE | Create and rename local Spaces through the real shared model. |
| SPACE03 | DONE | Use exact-window Space menu/sidebar destinations with current availability. |
| SPACE04 | DONE | Cycle ordered Spaces with recovered wrapping and original-window ownership. |
| SPACE05 | DONE | Retain current selection/focused split pane when selecting the same Space. |
| SPACE06 | DONE | Restore a returning Space's window-local focused pane and split geometry. |
| SPACE07 | DONE | Guard selection against deletion, reassignment, retirement, modal/security and transfer. |
| SPACE08 | DONE | Provide the shared theme editor and production renderer. |
| SPACE09 | DONE | Provide all 45 theme presets and linked color controls. |
| SPACE10 | DONE | Persist appearance, intensity, noise and texture choices. |
| SPACE11 | DONE | Support local theme undo and durable commit/cancel behavior. |
| SPACE12 | DONE | Create a new Space with original moved items through the existing owner transaction. |
| SPACE13 | DONE | Reset Automatic through the application appearance parent, clear its saved override, and preserve the original Space theme/editor state. |
| SPACE14 | DONE | Original-window Update Theme Undo/Redo survives popover disposal/reopening; durable complete-theme inverses preserve original Space/Profile and refresh open editors. Stale/failed writes and continued cancelled input cannot overwrite restored state. [Contract and checks](space-theme-undo.md). |
| SPACE16 | DONE | Native generic/now feedback on accepted intensity fifth-step and noise rotation/drag tenth-step detents; inclusive endpoints, one pulse per change, native device/preferences gating and silent no-op, discrete noise, Undo/commit/cancel routes. [Contract and checks](space-theme-haptics.md). |

### Sidebar

Evidence: sidebar-motion.md; sidebar-previews.md; SidebarView.swift; BrowserWindowController.swift sidebar hover owner; Native recent-page/favicon services.

| ID | State | Requirement |
|---|---|---|
| SIDE01 | DONE | Connect anchored show/hide to the recovered 80ms cubic timing. |
| SIDE02 | DONE | Connect floating presentation to the recovered spring owner. |
| SIDE03 | DONE | Animate the actual nested AppKit layout in the same transaction. |
| SIDE04 | DONE | Guard animation reversal/cancellation/completion by original generation and object. |
| SIDE05 | DONE | Respect Reduce Motion and original sidebar lifecycle. |
| SIDE06 | DONE | Open local folder and included provider previews after the recovered dwell. |
| SIDE07 | DONE | Provide preview search/keyboard/accessibility entry and real original-tab actions. |
| SIDE08 | DONE | Use actual profile-owned recent history and database favicons. |
| SIDE09 | DONE | Invalidate previews on original window/profile/selection/security changes. |
| SIDE11 | DONE | Match exact reversal velocity and floating geometry/hover timing. |
| SIDE12 | DONE | Match preview geometry, visual states and transition choreography. |
| SIDE13 | DONE | Finish preview title tidying, grouping and badges. |
| SIDE14 | DONE | Finish remaining preview modifier destinations. |
| SIDE15 | DONE | Finish sidebar unread presentation and state attribution. |
| SIDE16 | DONE | Match sidebar resizing/drag feedback and full spacing. |
| SIDE17 | DONE | Complete remaining sidebar focus/AX and interaction-state inventory. |

### Today / pinned tabs / favorites

Evidence: saved-tabs.md; sidebar-selection.md; reopen-closed-tabs.md; BrowserStore.swift; SidebarView.swift.

| ID | State | Requirement |
|---|---|---|
| TAB01 | DONE | Preserve saved destinations through pin/unpin/Favorite membership changes. |
| TAB02 | DONE | Use recovered saved-home URL equivalence for Reset eligibility and copy titles. |
| TAB03 | DONE | Reset the actual current/visible saved pages through their native owners. |
| TAB04 | DONE | Connect Today Other/Above/Below archive actions with original-page retirement. |
| TAB05 | DONE | Connect original ordinary-row close/reset/context/accessibility actions. |
| TAB06 | DONE | Resolve ordinary row images through original item/favicon ownership. |
| TAB07 | DONE | Rename ordinary tabs inline with native composition and actual persistence. |
| TAB08 | DONE | Provide original-tab Rename Undo/Redo. |
| TAB09 | DONE | Provide the original Favorite Rename dialog and command-search entry. |
| TAB10 | DONE | Preserve recovered Favorite mouse-down/up and saved-home reset semantics. |
| TAB11 | DONE | Connect Favorite Option-release split/duplicate operations to original targets. |
| TAB12 | DONE | Reopen through physical-window saved-item priority and the manual Today/complete-split stack. |
| TAB13 | DONE | Maintain original-ID ordinary sidebar modifier/range selection. |
| TAB14 | DONE | Connect plural copy/move/close through actual original-item retirement. |
| TAB15 | DONE | Preserve typed Note/Easel aliases rather than deleting shared documents on tab close. |
| TAB16 | DONE | Match Favorite hover controls, icon geometry and pressed/transition presentation. |
| TAB17 | DONE | Mark only the focused pane's Favorite, or the split Favorite containing it, as the selected tile. |
| TAB18 | DONE | Finish unread-state ownership and its visible badges. |
| TAB19 | DONE | Match ordinary Today/pinned/split-child row presentation, including the icon-slot reset target and Separate From Pinned Tab. |
| TAB20 | DONE | Reopen closed Today tabs, splits and partial splits, Peeks and folder deletions through each window's process-memory close history. |
| TAB21 | DONE | Complete modal, cross-window and cross-Profile creation and return provenance, including automatic modal expansion. |
| TAB22 | DONE | Complete remaining selected-item keyboard/AX and interaction comparisons. |

### Folders

Evidence: folder-commands.md; folder-moves.md; sidebar-selection.md; FolderLinks.swift; SidebarSpaceMove.swift; SidebarWindowMove.swift.

| ID | State | Requirement |
|---|---|---|
| FOLD01 | DONE | Create, rename and persist nested folders with ordered original children. |
| FOLD02 | DONE | Expand/collapse folders through real native controls. |
| FOLD03 | DONE | Copy all descendant links, including the recovered Markdown alternate. |
| FOLD04 | DONE | Collapse/expand all folders through the original Space command owner. |
| FOLD05 | DONE | Move original typed items within a Space with order, nesting and cycle checks. |
| FOLD06 | DONE | Provide before/after/nesting feedback, edge scrolling and menu/AX move alternatives. |
| FOLD07 | DONE | Move complete collections to existing/new same-Profile Spaces atomically. |
| FOLD08 | DONE | Move same-Profile collections across physical windows with genuine native/editor owners. |
| FOLD09 | DONE | Preserve embedded Easel page ownership during supported collection transfers. |
| FOLD10 | DONE | Delete ordinary folders through confirmation and actual page retirement. |
| FOLD11 | DONE | Undo/redo folder deletion with original archived identities and real redo consent. |
| FOLD12 | DONE | Delete/archive plural selected roots without double-deleting descendants or shared documents. |
| FOLD13 | DONE | Duplicate saved subtrees with fresh folder/tab/split IDs and actual local-document aliases. |
| FOLD14 | DONE | Duplicate plural selected collections through the existing original-item copy owner. |
| FOLD15 | DONE | Reveal moved original items in their destination without selecting their page. |
| FOLD16 | LEFT | Finish cross-Profile collection move behavior. |
| FOLD17 | LEFT | Finish external/copy dragging and spring-loaded folder expansion. |
| FOLD18 | LEFT | Finish remaining Favorite/app-tray and selection modifier corner cases. |
| FOLD19 | LEFT | Finish original group-opening behavior. |
| FOLD20 | LEFT | Resolve included folder archive/restoration behavior behind historical remote gates. |
| FOLD21 | LEFT | Match move toast, menu, disclosure and selected-ancestor/highlight presentation. |
| FOLD22 | LEFT | Match original drag geometry, animation and haptic feedback. |
| FOLD23 | LEFT | Resolve whether any included Duplicate entry has Undo through its actual registration owner; the traced context producer has none, so this is an investigation requirement, not an invented Undo feature. |

### Automatic archive

Evidence: parity.md P0-23 and Automatic archive; BrowserStore.swift; native protection traits; ArchiveProtection tests.

| ID | State | Requirement |
|---|---|---|
| AUTO01 | DONE | Persist the original-profile automatic-archive interval/settings. |
| AUTO02 | DONE | Use actual activity/start time and unread rules for eligibility. |
| AUTO03 | DONE | Protect the selected tab and every visible split pane. |
| AUTO04 | DONE | Protect original forms/editing/media/capture through real native traits. |
| AUTO05 | DONE | Treat unavailable native protection state conservatively. |
| AUTO06 | DONE | Revalidate the original item before retirement and archive only accepted closes. |
| AUTO07 | DONE | Retain original profile/Space/closure provenance for restoration. |
| AUTO08 | DONE | Connect independent 60-day archive retention and six-hour cleanup. |
| AUTO09 | DONE | Typed Today roots and complete split candidates preserve original member/document/placement identity through native retirement; every physical window protects selected, rendered and pending panes plus retained Peek parents. Mixed saved groups and malformed local documents remain protected. [Comparison, adaptations and checks](archive.md#automatic-archive-typed-item-and-window-eligibility--auto09). |
| AUTO10 | DONE | Recovered launch delays, independent continuous-clock maintenance, per-window visible activity, late/sleep deadline coalescing and cancellation are implemented. OS wake follows existing clock deadlines rather than extra sweeps; actual occlusion gates activity, not current-content protection. [Comparison and checks](archive.md#automatic-archive-clocks-wake-and-occlusion--auto10). |
| AUTO11 | DONE | Original interval controls, guarded scope sheet, genuine once-only education eligibility and accepted-archive producer connect to the real sidebar host and original-profile Settings destination. [Contract, adaptations and checks](archive.md#automatic-archive-settings-and-education--auto11). |
| AUTO12 | DONE | Accepted background archive preserves selected page hierarchy and focus. Original-window education controls, hidden-key-loop bypass, bottom/opacity spring entry, ease-in exit, retained dismissal lifetime, cancellation and Reduce Motion adaptation are integrated and independently reviewed. [Contract and checks](archive.md#automatic-archive-interaction-and-education-motion--auto12). |

### Archive and history

Evidence: archive.md; archive-preview.md; archive-preview-documents.md; reopen-closed-tabs.md; LibraryView.swift; BrowserStore.swift; native_favicons.mm. The document owner is a partial HIST13 producer; its preview integration and promotion reservation remain open.

| ID | State | Requirement |
|---|---|---|
| HIST01 | DONE | Open Archive/History beside the existing live page in the original profile. |
| HIST02 | DONE | Display real date-grouped title/URL records and actual database favicons. |
| HIST03 | DONE | Search and filter by closure reason and original Space. |
| HIST04 | DONE | Keep unknown historical provenance unknown rather than inventing a reason. |
| HIST05 | DONE | Provide actual keyboard/multiple selection, copy and context actions. |
| HIST06 | DONE | Put Back through the selected filter/current-window destination policy. |
| HIST07 | DONE | Provide explicit same-profile restoration destinations. |
| HIST08 | DONE | Restore complete archived splits with original order/orientation/proportions. |
| HIST09 | DONE | Open History through its original-profile navigation route. |
| HIST10 | DONE | Confirm profile-scoped delete/clear and preserve failures. |
| HIST11 | DONE | Remove only expired Archive records through the recovered retention cadence. |
| HIST12 | DONE | Cancel stale Library owners and original output sheets on profile/window changes. |
| HIST14 | LEFT | Finish nested archived-root reconstruction and broader restoration cases. |
| HIST15 | LEFT | Match exact search/filter/row selected-state appearance. The October 31 shell matches Archive row, filter and heading ink and drops the blue selection; remaining selected-state comparison stays here. |
| HIST16 | LEFT | Match Library/filter/preview transition and hover feedback. Hover trash and Put Back on the live record landed with the October 31 shell; preview transitions remain here. |
| HIST17 | LEFT | Complete remaining keyboard/AX/focus and original-record action comparison. |

### General navigation and gestures

Evidence: navigation.md; space-navigation.md; split-navigation.md; parity.md NAV breakdown; NativeNavigationHistory.

| ID | State | Requirement |
|---|---|---|
| NAV01 | DONE | Navigate Back/Forward on the actual selected page, split child or Peek. |
| NAV02 | DONE | Open original-entry history choosers through secondary click and the recovered hold. |
| NAV03 | DONE | Preserve genuine history/POST state during alternate duplicate-and-navigate. |
| NAV04 | DONE | Use distinct Refresh, Stop and Force Refresh commands with real availability. |
| NAV05 | DONE | Preserve pointer-down ownership and prevent a hold release from also navigating. |
| NAV06 | DONE | Keep history chooser selection/keyboard/cancellation on its original page. |
| NAV07 | DONE | Route trackpad and Magic Mouse history through actual renderer ACK/OS gates. |
| NAV08 | DONE | Preserve original history gesture cancellation and native overlay ownership. |
| NAV09 | DONE | Connect tab/Space/split selection through their original navigation owners. |
| NAV10 | DONE | Keep address/search editing and dismissal in the original command session. |
| NAV11 | DONE | Finish alternate destination foreground/background policy comparison. |
| NAV12 | DONE | Match history chooser geometry, hover/focus and motion beyond observed layout. |
| NAV13 | DONE | Match continuous swipe visuals, haptics and interruption across devices. |
| NAV14 | DONE | Finish remaining modifier-click/drag and mouse/trackpad gesture inventory. |
| NAV15 | DONE | Finish navigation focus traversal across page, controls, menus and auxiliary contexts. |
| NAV16 | DONE | Match loading/stop/refresh control states and remaining navigation feedback. |

### Command bar

Evidence: command-bar.md; CommandBar.swift; native_search.mm; CommandBar action model files; KeyboardShortcuts.swift.

| ID | State | Requirement |
|---|---|---|
| CMD01 | DONE | Enter current-address editing and empty New Tab through the original panel/window. |
| CMD02 | DONE | Use genuine native autocomplete tokens preserving POST, headers, transition and profile. |
| CMD03 | DONE | Switch to actual existing tabs without URL replay. |
| CMD04 | DONE | Dispatch real registered menu commands with current original-target validation. |
| CMD05 | DONE | Populate empty-input recent history from the actual profile service. |
| CMD06 | DONE | Preserve native text editing, selection, composition and ordinary text copying. |
| CMD07 | DONE | Restore original eligible focus on Escape and invalidate stale sessions. |
| CMD08 | DONE | Copy the highlighted result's genuine URL through the proper command. |
| CMD09 | DONE | Submit existing supported split requests through original native navigation ownership. |
| CMD10 | DONE | Enter/exit website search scopes with actual search-engine definitions. |
| CMD11 | DONE | Expose the original website-scope menu and actual profile catalog. |
| CMD12 | DONE | Focus an original Space through contextual Type Travel. |
| CMD13 | DONE | Open an original folder through contextual Type Travel. |
| CMD14 | DONE | Apply selected-result edit text and ordinary Tab behavior without executing it. |
| CMD15 | DONE | Delete eligible actual native suggestions through the provider owner. |
| CMD16 | DONE | Force-open supported results while retaining the original command panel. |
| CMD17 | DONE | Apply genuine default-result inline completion with selected suffix and composition guards. |
| CMD18 | DONE | Cycle actual result selection and preserve original-row pointer activation. |
| CMD19 | DONE | Favorite/unfavorite the original contextual item. |
| CMD20 | DONE | Pin or copy actual contextual items into an original existing folder. |
| CMD21 | DONE | Provide command-only Actions scope with recovered Tab/Backspace/Escape transitions. |
| CMD22 | DONE | Support actual extension keyword scopes without inventing URL templates. |
| CMD23 | DONE | Wait for real search-service readiness without replacing the original session. |
| CMD25 | LEFT | Finish included command coverage and remaining contextual result variants. Left after CMD29: Open Task Manager in Notes, Easels and empty windows (needs a window-level engine route; the page-tool route needs a native page), Restore Data (Parc writes no sidebar backups) and Expand/Collapse Pinned Section (Sidebar family's collapsible pinned section). Accepted by the coordinator November 1: one Pin to [Space] row per Space, Show Spelling and Grammar out (acts on the bar's own field). Join Next Meeting is excluded (calendar integration); Getting Started stays out of the command bar by the October 26 onboarding-replay direction. |
| CMD26 | LEFT | Match exact panel/row/scope/label geometry and theme treatment. |
| CMD27 | LEFT | Match hover/pressed/selection, entry/dismissal motion and haptics. |
| CMD28 | LEFT | Complete remaining IME/layout/keyboard/AX and interruption-state comparison. |

### Tab switcher

Evidence: tab-switcher.md; RecentTabSwitcher.swift; RecentTabOrder.swift; native_tab_preview.mm.

| ID | State | Requirement |
|---|---|---|
| MRU01 | DONE | Track per-window MRU order with original split groups and focused children. |
| MRU02 | DONE | Keep preview focus separate from actual selected-page/MRU state. |
| MRU03 | DONE | Use genuine original-page Chromium thumbnails with subscription lifetimes. |
| MRU04 | DONE | Use recovered delayed presentation and held-key owner. |
| MRU05 | DONE | Commit on modifier release and cancel on Escape or invalid original ownership. |
| MRU06 | DONE | Support genuine hover/click and reverse cycling without exposing the reserve item. |
| MRU07 | DONE | Maintain five visible cards and one hidden replacement. |
| MRU08 | DONE | Close through real consent, promote the reserve only after confirmed closure and preserve valid refusal state. |
| MRU09 | DONE | Dismiss for actual sheets, deactivation, transfer and other invalidation. |
| MRU10 | LEFT | Match exact card typography, geometry and material. |
| MRU11 | LEFT | Match entry/exit, card replacement and selection motion. |
| MRU12 | LEFT | Finish complete refusal/interruption and input-context comparison. |
| MRU13 | LEFT | Complete remaining keyboard/AX, hover/pressed and haptic comparison. |

### Peek

Evidence: peek.md; parity.md PEEK-01–08; PeekController.swift; native original-request routing.

| ID | State | Requirement |
|---|---|---|
| PEEK01 | DONE | Adopt genuine original foreground pages with exact parent/tab/profile/window ownership. |
| PEEK02 | DONE | Preserve explicit Shift-link navigation request fields and normal security policy. |
| PEEK03 | DONE | Open ordinary current-tab automatic Peek through the actual policy/request seam. |
| PEEK04 | DONE | Apply recovered authentication exceptions and persistent URL-lock transitions. |
| PEEK05 | DONE | Respect matched internal link routing without replacing the original request. |
| PEEK06 | DONE | Persist and connect the two actual Links preference switches. |
| PEEK07 | DONE | Target the actual unsaved Peek page for navigation, address, Find, copy, zoom and security tools. |
| PEEK08 | DONE | Close through genuine beforeunload and the recovered reason/attempt/confirmation owner. |
| PEEK09 | DONE | Preserve original native focus on refusal and guarded return on close/promotion. |
| PEEK10 | DONE | Promote the same page into Today or Split without reconstructing its URL. |
| PEEK11 | DONE | Retain accepted Peek with its original parent across tab/Space hide/return. |
| PEEK12 | DONE | Preserve recovered promotion/source return provenance. |
| PEEK13 | DONE | Retire parent/child sets genuinely and protect a Peek parent from automatic archive. |
| PEEK14 | DONE | Connect completed swipe dismissal, accessible actions and Reduce Motion handling. |
| PEEK15 | LEFT | Resolve original Links factory defaults beyond current explicit local policy. |
| PEEK16 | LEFT | Match overlay/card/control geometry, material and visual states. |
| PEEK18 | LEFT | Match continuous swipe tug/velocity, reversal and cancellation. |
| PEEK19 | LEFT | Match transition snapshots, promotion/reveal motion and haptics. |
| PEEK20 | LEFT | Finish parent physical-window transfer and missing-parent behavior. |
| PEEK21 | LEFT | Finish remaining promotion callers and cross-window creation provenance. |

### Easels

Evidence: easels.md; easel-embedded-pages.md; EaselStore.swift; EaselRichText.swift; EaselCanvasInteraction.swift; EaselCanvasView.swift.

| ID | State | Requirement |
|---|---|---|
| EASEL01 | DONE | Create, open, rename and persist local Easel documents through real tabs/Library. |
| EASEL02 | DONE | Author text, images, shapes, drawings and links on the actual canvas. |
| EASEL03 | DONE | Apply whole-object font families/sizes and native text emphasis/links. |
| EASEL04 | DONE | Persist exact selected-range rich attributes and native typing/format Undo. |
| EASEL05 | DONE | Support paragraph headings, lists, nesting and native Return/Backspace/Tab editing. |
| EASEL06 | DONE | Apply recovered typed Markdown transforms without rewriting imported/composing text. |
| EASEL07 | DONE | Copy/cut/paste the supported private rich carrier and actual RTF/RTFD/plain text. |
| EASEL08 | DONE | Keep source image bytes and supported inline-image attributes through save/reopen. |
| EASEL09 | DONE | Select canvas objects through actual marquee/content hit geometry. |
| EASEL10 | DONE | Move/nudge selected original objects with one durable shared transaction. |
| EASEL11 | DONE | Resize original groups with captured anchors and modifier-aware centering. |
| EASEL12 | DONE | Apply alignment/canvas guides through the actual original gesture. |
| EASEL13 | DONE | Manipulate arrow endpoints and original image aspect constraints. |
| EASEL14 | DONE | Duplicate original canvas objects with real document Undo/save outcomes. |
| EASEL15 | DONE | Embed genuine native webpage objects and captured PNG cards. |
| EASEL16 | DONE | Keep embedded page selection/input/navigation/security tied to the original page. |
| EASEL17 | DONE | Author embedded-page Address/Search through the original native request owner. |
| EASEL18 | DONE | Persist actual selected-page navigation without replacing another editor's live page. |
| EASEL19 | DONE | Include embedded pages in genuine beforeunload retirement. |
| EASEL20 | DONE | Move supported same-Profile Easel collections across windows with original child pages. |
| EASEL21 | DONE | Recovered image-only attachment boundary with atomic non-image refusal; external URL-only paste, selected-label linking, self-labelled replacement, plain-word fallback and exact native undo/clipboard ownership. Final SIL and fresh independent review clear. [Contract](easels.md#external-clipboard-and-non-image-boundary--easel21). |
| EASEL22 | DONE | Native glyph/attachment geometry, rounded content-hugging fill, temporary display ink, persisted whole-object style and ordered native/document Undo; secondary table resolved without invented line heights. Finished SIL and fresh independent review clear. [Contract](easels.md#content-hugging-text-fill-and-native-metrics). |
| EASEL23 | DONE | Real captured-region pages preserve original viewport/scroll/crop, Profile/window lifetime and immutable image/provenance; guarded positioning, first-use education and actual-close Snapshot restoration. Independently reviewed, with v239/overlay247 engine and dependent release app package confirmed. [Contract](easel-live-captures.md). |
| EASEL24 | DONE | Recovered prompt/point insertion, native default/word selection and spelling, focus/Escape dismissal, durable empty-text cleanup, stale/failure refusal and transfer final-edit contract; independently reviewed. |
| EASEL25 | DONE | Recovered stable selected/pressed endpoint marks and cursor-only hover, exact-only endpoint guide feedback, separate pale/blue edge and center paths, magnification-correct admission, and image/card/link intrinsic guide sizing. Final SIL and independent exact-source review clear. [Contract](easels.md#endpoint-and-guide-feedback--easel25). |
| EASEL26 | DONE | Stable native object focus/AX children, original-object and geometry actions, native control traversal and genuine embedded-page entry/recovery/return. Final SIL and independent exact-source review clear. [Contract](easels.md#canvas-keyboard-and-accessibility-ownership--easel26). |
| EASEL27 | DONE | Recovered canvas/selection contours, semantic surfaces, compact text rail, native control states and owner-bound link popovers; scale-correct pointer/AX targets and retained-action refusal preserve original editing/page/capture owners. Finished SIL and fresh exact-source independent review CLEAR. Native presentation adaptations are explicit in the [contract](easel-appearance.md). |
| EASEL28 | DONE | Recovered native pinch zoom, original-direction 100% generic haptics, 0.1-second annotation contexts and shared visible handle eligibility; interruption/retirement and live Reduce Motion preserve original document/page/capture owners. Final SIL and independent exact-source review clear. [Contract](easel-motion.md). |
| EASEL29 | DONE | Relocate included embedded objects through exact editor/native retirement and fresh destination-Profile pages; revoke stale source sessions, preserve document/capture bytes and roll back shared assets safely. [Contract](easel-embedded-pages.md#cross-profile-relocation--easel29). |

**Export as Image — November 1 (Cursor `cursor/easel-export-image`).** A
**Export as Image** (Feather save glyph, 14 points, shown on macOS 27). That
row, File → Save Page As and Command-Shift-S on the canvas render the saved
artwork across the canvas width down to the lowest object or a canvas-width
webpages and live captures drawn from their pages' real pixels (engine
overlay 296, pending build; older engines keep the card), streamed in strips
the inter-Profile move prompt now uses too. The capture editor takes the
would. [Contract](easels.md#export-as-image).

### Notes — local restoration

Evidence: notes.md; NoteStore.swift; NoteEditorViewController.swift; NoteExportArchive.swift; actual Notes/shared rich-text components.

| ID | State | Requirement |
|---|---|---|
| NOTE01 | DONE | Create real local Notes and Notes-in-Split from File and command search. |
| NOTE02 | DONE | Open/search/rename/delete actual documents through Easels & Notes Library. |
| NOTE04 | DONE | Share original document sessions across windows with field-conflict protection. |
| NOTE05 | DONE | Edit native rich body/title with genuine selection, composition and separate Undo. |
| NOTE06 | DONE | Retain failed drafts, Retry/Discard and refuse unsafe closure. |
| NOTE07 | DONE | Preserve document aliases and surviving split panes on tab close/deletion. |
| NOTE08 | DONE | Provide the twelve recovered paragraph/gutter formatting actions. |
| NOTE09 | DONE | Apply exact original native paragraph ranges, image suppression and trailing-empty-line targeting. |
| NOTE10 | DONE | Provide the recovered compact paragraph menu and emphasis expansion. |
| NOTE11 | DONE | Provide exact-range selection formatting and paragraph conversion. |
| NOTE12 | DONE | Import supported images through the actual original Note-owned picker. |
| NOTE13 | DONE | Implement recovered title/body keyboard boundary transitions and native Find. |
| NOTE14 | DONE | Use recovered document sizing/title/body typography and semantic light/dark ink. |
| NOTE15 | DONE | Use the actual native title placeholder and its editing visibility rules. |
| NOTE16 | DONE | Use recovered immediate title publication and 0.5-second latest-body throttle. |
| NOTE17 | DONE | Flush original drafts at close/export/retry and preserve stale-action guards across own saves. |
| NOTE18 | DONE | Use recovered gutter icon classification and surviving list artwork. |
| NOTE19 | DONE | Use recovered gutter/compact-menu named color and state consumers. |
| NOTE20 | DONE | Export real local rich-text/image HTML archives through an owned save operation. |
| NOTE21 | DONE | Finish historical import behavior and unclassified local save-effect semantics. |
| NOTE22 | DONE | Finish remaining historical editor/menu/keyboard discovery. Body Return is FormatMenu.didPressEnter; beginning-of-line/left-end/paragraph share the recovered five-unit prefix caret; remaining included commands are a documented negative survey. [Remaining commands](notes.md#remaining-editor-menu-and-keyboard-commands). |
| NOTE23 | DONE | Match outer compositing/theme inheritance and remaining typography/layout details. |
| NOTE24 | DONE | Match selection/gutter/link/menu pressed states and historical glyph appearance. Press is hover, not a unique fill; checked/`displayAsSelected` win; Nunito B/I/U/S, list contours, 6pt disclosure and Feather U+E981/U+E998. Independent review CLEAR. |
| NOTE25 | DONE | Complete full keyboard/accessibility/viewport-focus presentation of existing gutter, compact paragraph menu, selection menu, title/body, load-error, footer Retry/Discard, link popover and image-sheet surfaces. Pointer/gutter keeps the body responder; footer/AX focuses the menu; `selectedIndex` starts nil. Independent review CLEAR. [Keyboard/AX/viewport](notes.md#keyboard-accessibility-and-viewport-focus). |
| NOTE26 | DONE | Match original transition motion and any attributable haptics. Recovered selected-index spring (response 0.15, damping 0.825) and item opacity; present/dismiss stay immediate; helpers found no Notes haptic. Independent review CLEAR. [Format-menu motion](notes.md#format-menu-motion-and-haptic-negative-finding). |

### Screenshots and recordings

Evidence: page-capture.md; capture-library.md; [capture-capabilities.md](capture-capabilities.md); PageCaptureController.swift; PortraitCapture.swift; CaptureLibraryStore.swift; native_page_capture.mm.

| ID | State | Requirement |
|---|---|---|
| CAP01 | DONE | Capture actual original-page regions with document/geometry/security ownership. |
| CAP02 | DONE | Capture the visible viewport without substituting full-page capture. |
| CAP03 | DONE | Capture full-page output from the original native page. |
| CAP04 | DONE | Select actual elements through opaque native hover/click tokens. |
| CAP05 | DONE | Preview/crop/retake the exact captured PNG through the same capture owner. |
| CAP06 | DONE | Copy/save original or currently framed output with truthful cancellation/failure. |
| CAP07 | DONE | Insert captured output into genuine new or UUID-bound existing Easels. |
| CAP08 | DONE | Send actual captured images through the real macOS Messages sharing service. |
| CAP09 | DONE | Save captures into a local profile-owned catalog with atomic image/revision ownership. |
| CAP10 | DONE | Browse/search actual saved captures in a two-column Library. |
| CAP11 | DONE | Preview/navigate/copy/export saved originals and confirm revision-checked deletion. |
| CAP12 | DONE | Retain original source/profile/Space metadata and original-context cancellation. |
| CAP13 | DONE | Apply recovered Portrait composition and remembered Color/Page/Desktop choices. |
| CAP14 | DONE | Use the approved Parc P watermark and Parc branding. |
| CAP15 | DONE | Offer unified Portrait framing in region/viewport/full-page flows without recapture. |
| CAP16 | DONE | Keep existing output destinations attached to the currently previewed pixels. |
| CAP17 | DONE | Original Command–Shift capture drag, independently persisted gesture toggle and existing configurable Command–Shift–2 shortcut; original page/split-pane admission and post-dismissal owner checks; ordinary Visible Area replaces excluded Boosts beside unified Portion/Full Page entry. |
| CAP18 | DONE | Recovered live selection layers/cursor, original-rectangle preview and crop mapping, palette anchors/rows and light/dark interaction states; compact-pane and native drawing adaptations are explicit in [capture presentation](capture-presentation.md). |
| CAP19 | DONE | Recovered compact Portrait controls, logical-point/backing-density output, source RGB profile and exact watermark contrast; actual original-display wallpaper-window capture with permission/error/lifetime ownership. Unified reversible framing remains an explicit adaptation ([contract](portrait-capture-fidelity.md)). |
| CAP20 | DONE | Activity-ranked original-profile Easels, two-row expansion and complete current-label search retain stable UUID selection; native Messages receives the original capture URL and current image with no invented text. [Contract and adaptations](capture-destinations.md). |
| CAP21 | DONE | Recovered shared fixed-canvas Edit tools with memory-only undo, immutable original/edited-source/crop/Portrait layers; revision-bound captured-item Messages/AirDrop/source contexts. Final SIL and independent exact-source review clear. |
| CAP22 | DONE | Establish the genuine shipped recording capability, implementing a standalone producer if present; the bounded [capability investigation](capture-capabilities.md) establishes screenshot, website-stream and external-file owners without a standalone recorder contract. |
| CAP23 | DONE | Discover actual OS-folder images and recordings alongside saved captures, with native folder grants/read-only bookmarks, truthful permission/unavailable states, original-byte/revision-safe file actions, live source observation and explicit cancellation. [Contract and checks](capture-library.md#os-media-discovery-and-access--cap23). |
| CAP24 | DONE | Recovered lens/reveal/instruction/Portrait and source-thumbnail preview transitions, interruption/live Reduce Motion, native reciprocal key loops and original-window/field-editor focus return are integrated through actual editor/sharing owners. Haptics remain attributed to their real owner; no capture feedback is invented. Final SIL, 44 inert assertions and independent exact-source review clear. [Contract](capture-motion.md). |

### Extensions

Evidence: parity.md P0-13–16; Engine/ParcNative extension_*; native Browser/tab/window owners; BrowserWindowController extension controls.

| ID | State | Requirement |
|---|---|---|
| EXT01 | DONE | Connect genuine ordinary installation and permission consent. |
| EXT02 | DONE | Connect actual enterprise/supervised approval and original-owner cancellation. |
| EXT04 | DONE | Expose real toolbar action/pinning state and extension context menus. |
| EXT05 | DONE | Present genuine extension popups in original AppKit-owned windows. |
| EXT06 | DONE | Dispatch actual extension commands through the native keybinding owner. |
| EXT07 | DONE | Remove extensions through the real uninstall/policy route. |
| EXT08 | DONE | Host genuine global/contextual extension side panels. |
| EXT09 | DONE | Preserve actual tab/window API identities, events, selection and openers. |
| EXT10 | DONE | Keep permissions, unload/reload and background services with the original profile. |
| EXT12 | DONE | Recovered sidebar/toolbar surfaces, centered 16-point artwork, genuine 32-point native icon request and focused-content popup anchors are connected; native menus and popup windows retain their original geometry. The positive default-off panel boundary is resolved with an explicit current-Chromium adaptation: fitted trailing body, native close header, separate genuine page and exact panel focus scope, connected to the reviewed native close service. [Evidence, adaptations and checks](extensions-geometry.md). |
| EXT13 | DONE | Original pinned control classes and physical-key picker comparison complete; native press/hover, exact-owner event monitors, immutable gesture action leases, focus masks and policy-aware AX actions are implemented. Explicit accessibility/safety adaptations and unrun live Tab/VoiceOver acceptance remain distinguished. [Evidence and checks](extensions-interaction.md). |
| EXT14 | DONE | Popup opening, dismissal, replacement, interruption and native motion comparison is complete; Site Control Center dispatch waits behind all native closes and cancels stale actions. The positive native gate/construction boundary justifies the explicit current-Chromium panel adaptation. Real close-button/Escape dispatch, genuine host drainage and exact panel header/content focus restoration are connected and independently reviewed with EXT12’s published consumer. [Lifecycle and checks](extensions-lifecycle.md) · [Panel adaptation](extensions-side-panel-adaptation.md). |

### Media

Evidence: parity.md P0-22; media-mini-player.md; media-casting.md; MiniPlayerView.swift; native_media_controls.mm; native_cast.mm.

| ID | State | Requirement |
|---|---|---|
| MEDIA01 | DONE | Keep PiP accepted DONE under explicit user direction. |
| MEDIA02 | DONE | Expose genuine camera/microphone/sharing/captured-source state and original Stop callbacks. |
| MEDIA03 | DONE | Present actual controllable media sessions in the owning window's Mini Player. |
| MEDIA04 | DONE | Connect real play/pause, previous/next, tab mute and supported camera/microphone actions. |
| MEDIA05 | DONE | Apply supported per-page media-session volume through the native renderer owner. |
| MEDIA06 | DONE | Return to the exact original page without retargeting playback commands. |
| MEDIA07 | DONE | Hide the original Mini Player episode without stopping playback or closing its page. |
| MEDIA08 | DONE | Maintain a five-row shelf with stable original-session ownership. |
| MEDIA09 | DONE | Connect View/page-menu/command-bar Cast to genuine device discovery and Sources. |
| MEDIA10 | DONE | Expose real route status/Stop and supported route controls with original-document cancellation. |
| MEDIA11 | DONE | Keep actual router/profile/OS permission and access-code continuations authoritative. |
| MEDIA12 | DONE | Finish exact Mini Player host eligibility and producer re-admission policy. Host eligibility, privacy-domain pools and dismiss suppression remain; presentation-set producers beyond Separate (ItemSelection / Next-Prev / Return / ModalItemSwitcher / history, tab-fullscreen enter, Space switch, non-split Peek Expand) re-admit through the shared lease/fence path. Mojo refreshes still must not. Recording toggle exception and absent Chromium PiP-history consumer are explicit adaptations. [Producer evidence](media12-producer-contract.md). |
| MEDIA13 | DONE | Use the recovered stacked and expanded geometry and marquee parameters, with the default-off flag represented by a local preference; preserve native original-page actions, accessible relinking and reduced-motion behavior. [Evidence and checks](media-mini-player-presentation.md). |
| MEDIA14 | DONE | Apply the recovered two-second hover-off and 0.25/0.9 spring to the stacked cards and slider opacity, with focus-aware deferred collapse, interruption, Reduce Motion and window-transfer cleanup. No Mini Player-specific haptic is attributed by the bounded reference index; AppKit spring and focus safeguards are explicit adaptations. Final SIL, inert component checks and independent review clear. [Evidence](media-mini-player.md#motion-and-hover--media14). |
| MEDIA17 | DONE | Connect original-page tab mute and global mute/unmute commands, retain stale-action ownership, and implement the recovered sidebar speaker transitions. The Mini Player volume shortcut is delivered with MEDIA13. Whole-module SIL, native syntax, overlay replay, inert reparenting check and independent review pass; live browser and appearance acceptance remain unclaimed. [Evidence](media-interactions.md). |

MEDIA12 complete: dismissed/evicted episodes stay suppressed across temporary
native owner loss until ineligibility, primary-document replacement, or a
consumed presentation-set producer. Regular and exact-OTR pools remain an
isolation adaptation. PiP-history filter recovered but not consumed as a
Chromium Boolean. Overlay apply/build stays with the dedicated engine owner.
See [Mini Player](media-mini-player.md#media12-investigation-and-interim-correction)
and [producer contract](media12-producer-contract.md).

### Routing

Evidence: settings.md Air Traffic Control; LinkRouting.swift; native_link_routing.mm; actual original-request/window creation adapters.

| ID | State | Requirement |
|---|---|---|
| ROUTE01 | DONE | Persist ordered Air Traffic Control rules with real Save/Cancel/failure handling. |
| ROUTE02 | DONE | Match AND conditions and recovered matches/contains normalization. |
| ROUTE03 | DONE | Resolve explicit Space and profile-most-recent destinations. |
| ROUTE04 | DONE | Route external app-open URLs through eligible original-profile windows. |
| ROUTE05 | DONE | Route queued onboarding/replay and native-relaunch URLs through the same owner. |
| ROUTE06 | DONE | Edit/reorder/delete/reset real rules with original destination identities. |
| ROUTE07 | DONE | Preserve complete internal OpenURL requests across real destination profiles/Spaces. |
| ROUTE08 | DONE | Adopt same-Profile newly created pages into routed Spaces without URL replay. |
| ROUTE09 | DONE | Invalidate stale original-document/rule/destination decisions. |
| ROUTE10 | DONE | Provide actual unavailable-destination fallback without fabricating an owner. |
| ROUTE12 | LEFT | Finish remaining disposition and unavailable-destination policy comparison. |
| ROUTE13 | DONE | Match rule editor geometry, controls and commit/cancel behavior. |
| ROUTE14 | DONE | Match routing feedback, focus/keyboard/AX and transition motion. |

ROUTE11 was removed from the fixed requirements at Josh's direction on October
implementation was shipped, and the investigation is stopped. The 13 remaining
requirements retain their original IDs and states.

original split-link adapter carries a source/document and window-selection lease
through the original popup checks and adopts the real page into Parc’s split model;
its engine changes are pending overlay 261 for the dedicated engine owner. The
a weak child identity across navigation callbacks, the saved blocked-popup
continuation and private-link lifetime integration remain open. [Evidence and boundaries](settings.md#internal-original-request-routing).

### Web interactions

Evidence: parity.md P0-08/09/12/18/19/24/27; native page/presenter services; actual shell controls; [Web interactions presentation](web-interactions.md).

| ID | State | Requirement |
|---|---|---|
| WEB01 | DONE | Render genuine HTTPS pages, React/WebGL and native scrolling through the independent engine. |
| WEB02 | DONE | Preserve actual popup/new-page opener, POST and profile identity. |
| WEB03 | DONE | Use genuine per-page beforeunload and asynchronous close consent. |
| WEB04 | DONE | Present real alert/confirm/prompt dialogs and original callbacks. |
| WEB05 | DONE | Expose genuine page context-menu actions against the original frame. |
| WEB06 | DONE | Show real hovered-link destinations with original-page lifetime. |
| WEB07 | DONE | Present actual site permission and permission-element decisions. |
| WEB08 | DONE | Present real authentication, certificate and external-protocol continuations. |
| WEB09 | DONE | Expose genuine PageInfo identity, permissions, devices and cookie controls. |
| WEB10 | DONE | Expose actual blocked-popup requests without replacing their original navigation. |
| WEB11 | DONE | Connect confirmation and tab-sharing banners to real callbacks. |
| WEB12 | DONE | Preserve actual native text/input/accessibility and renderer ownership. |
| WEB13 | DONE | Show genuine renderer/hang failure state and actual recovery actions. |
| WEB14 | DONE | Match Site Control Center geometry and extension/control unification. |
| WEB15 | DONE | Match dialog, authentication, certificate and permission presentation. |
| WEB16 | DONE | Match context-menu, hovered-status and banner visual/interaction details. |
| WEB17 | DONE | Match failure/recovery surface geometry and all original context states. |
| WEB18 | DONE | Finish full webpage action/keyboard/focus/AX inventory and remaining native boundaries. |
| WEB19 | DONE | Match these surfaces' opening/dismissal motion, hover and haptics. |

### Data and credentials

Evidence: browser-import.md; internal-addresses.md; BrowserImport*.swift; native_import_*; native_password_file_import.mm; independent Keychain config.

| ID | State | Requirement |
|---|---|---|
| DATA01 | DONE | Store actual browser data in independent local profiles. |
| DATA02 | DONE | Use the independent Parc Safe Storage Keychain namespace. |
| DATA03 | DONE | Preserve genuine Chromium password/autofill/payment stores and macOS reauthentication. |
| DATA04 | DONE | Open the real profile-owned password manager and its supported import/export UI. |
| DATA05 | DONE | Discover real supported source-browser profiles and capabilities. |
| DATA06 | DONE | Choose actual source/category/extension imports in the original destination context. |
| DATA07 | DONE | Run real native source readers and import services with truthful partial outcomes. |
| DATA08 | DONE | Insert original-destination bookmark hierarchies rather than flattening them. |
| DATA09 | DONE | Own source access prompts and recoverable Safari access failures. |
| DATA10 | DONE | Persist original Safari restart/resumption intent and validate destination on relaunch. |
| DATA11 | DONE | Import explicitly selected exported Safari passwords through real native credential services. |
| DATA12 | DONE | Retain cancellation, profile removal and stale-destination guards through imports. |
| DATA13 | LEFT | Finish stable shipping-signature/Keychain continuity configuration. |
| DATA14 | LEFT | Finish source-specific import/profile-choice presentation and recovery experience. |
| DATA15 | LEFT | Resolve unsupported source credential/import capabilities without fabricating success. |
| DATA16 | LEFT | Finish remaining import selection/keyboard/AX, visual states and motion. |

### Page tools

Evidence: developer-mode.md; internal-addresses.md; actual native page tools; BrowserToolbar.swift; PageFindView.swift.

| ID | State | Requirement |
|---|---|---|
| TOOLS01 | DONE | Connect real page Find/Next/Previous/Selection and document-bound results. |
| TOOLS02 | DONE | Connect actual page zoom and its current state. |
| TOOLS03 | DONE | Connect real Translate/Revert/language/site choices and errors. Since November 1 page translation is excluded (it needs a Google API key) and this surface is removed; see [Fixed scope](#fixed-scope). |
| TOOLS04 | DONE | Connect actual reader extraction, cancel/exit and original history return. |
| TOOLS05 | DONE | Connect genuine Print/Save PDF/Save Page/View Source. |
| TOOLS06 | DONE | Connect genuine cache/cookie clearing and profile Clear Browsing Data. |
| TOOLS07 | DONE | Persist exact-host Developer Mode with recovered localhost defaults. |
| TOOLS08 | DONE | Show the original page's developer toolbar/address/security state. |
| TOOLS09 | DONE | Toggle/select real DevTools, Console, Network and Inspect against the actual frontend. |
| TOOLS10 | DONE | Preserve real dock/undock ownership and original tools focus return. |
| TOOLS11 | DONE | Connect the ordinary toolbar's navigation/address/copy/extensions/page/split controls. |
| TOOLS13 | DONE | Preserve genuine WebUI controller/security/request ownership behind public addresses. |
| TOOLS14 | DONE | Match original DevTools docking geometry/restoration and focus timing. |
| TOOLS15 | DONE | Match first-edit, toolbar tint/stripe/narrow-layout and remaining control presentation. |
| TOOLS17 | DONE | Complete page-tool keyboard/AX/hover/disabled state and motion comparison. |

### Automation and scripting

Deferred by Josh October 29 until after the working-browser priorities. Existing implementation remains in place; all remaining scripting and automation work is deferred.

Evidence: scripting.md; BrowserScripting.swift; Parc.sdef; native_applescript.mm.

| ID | State | Requirement |
|---|---|---|
| SCRIPT01 | DONE | Ship a real Cocoa scripting dictionary containing implemented handlers. |
| SCRIPT02 | DONE | Expose original window/Space/tab identities and live-or-saved metadata. |
| SCRIPT03 | DONE | Select actual tabs/split children and focus real Spaces. |
| SCRIPT04 | DONE | Create supported real tabs and normal/private windows with one-use insertion acknowledgment. |
| SCRIPT05 | DONE | Navigate Back/Forward/Reload/Stop/URL through the original native page. |
| SCRIPT06 | DONE | Execute JavaScript through actual Apple Events permission and original-page ownership. |
| SCRIPT07 | DONE | Close original tabs/windows through genuine asynchronous beforeunload consent. |
| SCRIPT08 | DONE | Reject stale moved/deleted/reprofiled locators without front-window fallback. |
| SCRIPT09 | DONE | Keep private scripting attached to actual primary-OTR contexts and memory-only app models. |
| SCRIPT10 | LEFT | Finish remaining quit/additional command/error behavior. |
| SCRIPT11 | LEFT | Finish exact collection-order and exposed-property fidelity. |
| SCRIPT12 | LEFT | Reconcile original window-state/sidebar-location mutation handlers before adding writes. |
| SCRIPT13 | LEFT | Complete remaining scripting context and failure-result comparison. |

### Windows and lifecycle

Evidence: parity.md P0-03/08/09/21 and private-window rows; WindowPresentation.swift; AppDelegate.swift; BrowserWindowController.swift.

| ID | State | Requirement |
|---|---|---|
| WIN01 | DONE | Create genuine original-profile standard and private windows through actual native owners. |
| WIN02 | DONE | Keep selection and remembered Space/split focus local to the physical window. |
| WIN03 | DONE | Adopt native-created popups/windows with actual geometry and original requests. |
| WIN04 | DONE | Connect actual minimize/maximize/restore/hide and native fullscreen transitions. |
| WIN05 | DONE | Close original pages/windows/application through genuine consent and pending-download decisions. |
| WIN06 | DONE | Cancel deferred owners on original window/security/profile retirement. |
| WIN07 | DONE | Gate startup/onboarding and queue original relaunch/external destinations. |
| WIN08 | DONE | Keep private app session/history/archive/frame state ephemeral. |
| WIN09 | DONE | Open app-owned private Settings through its real normal parent. |
| WIN10 | DONE | Expose private Downloads through the genuine OTR manager and ephemeral view. |
| WIN11 | LEFT | Finish private sidebar sharing and remaining private Library/capture/document behavior. |
| WIN12 | LEFT | Finish Dock/logout and session restoration fidelity across all window states. |
| WIN13 | LEFT | Finish activation/focus/auxiliary-window and modal interruption comparison. |
| WIN15 | LEFT | Match complete private/popup/standard-window appearance and transition behavior. The private unpinned heading uses the recovered 36-point row, section-header insets and original Profile-count indicator; popup panel class, temporary key level, minimum size, background movement, 47-point toolbar, conditional Back, Copy and enabled-extension control follow the recovered window and toolbar. The passive private indicator uses the recovered capsule, typography and spacing; the private background, Extensions menu, remaining popup chrome and window transitions remain. [Evidence](window-appearance.md). |

**WIN14 removed from active scope by Josh, October 29.** No current shutdown
defect has been established. The family denominator changed from 15 to 14
(10 DONE, 4 LEFT); the +4.8 percentage-point movement is solely a scope change.

### Performance

Evidence: parity.md Performance and explicit smoothness/large-Downloads feedback; historical HTTPS/rAF/WebGL evidence.

| ID | State | Requirement |
|---|---|---|
| PERF01 | DONE | Establish genuine HTTPS rendering through the independent engine. |
| PERF02 | DONE | Establish working renderer frame callbacks and hardware-backed WebGL in the recorded builds. |
| PERF03 | DONE | Remove the identified startup/packaging path defects already corrected in source. |
| PERF05 | LEFT | Match input, scrolling and sidebar animation smoothness under actual workloads. |
| PERF06 | LEFT | Match sustained media and long-session responsiveness. |
| PERF08 | LEFT | Close cold/warm startup and shipping-configuration performance gaps. |
| PERF09 | LEFT | Investigate and fix the queued large-download-folder freeze/slowdown problem after polish. |
| PERF10 | DONE | Josh accepted the existing Chromium AI state and closed the proposed background-overhead cleanup on October 29. The broader cleanup and CPU, memory and startup measurements were not performed. |

**Downloads merged-context delivery (DL30):** normal and live private managers now feed the same Downloads collection in regular/private windows. Private records are separate memory-only state and carry exact parent Profile/context/GUID/incarnation; refresh, file/security actions and source/help routing preserve the genuine original owner. Context death withdraws its rows and pending offers from every presentation without deleting regular history or downloaded files. The denominator remains33:27 DONE,6 LEFT; the latest movement is100/33=+3.0 percentage points from26/33. No requirement was added/reweighted. The remaining six fixed requirements retain their LEFT status; this is not whole-family completion.


**Downloads single-item/direct-action reconciliation (DL11/DL20):** the actual PageItemsContainer Binding, row ID comparison and DownloadMenu/SharedDownloads consumers establish one original selection and immediate Hide/Trash dispatch. The former AppKit range/plural and extra confirmation adaptations are removed, while Profile/context/GUID/incarnation, native policy, async outcomes and stale-menu guards remain. The fixed denominator is33:29 DONE and4 LEFT, moving by2/33×100=+6.1 percentage points from27/33. DL18 wording now reflects the recovered direct manager action. No requirement was added or reweighted; DL06/27/32/33 remain LEFT.


**Downloads filter reconciliation (DL06):** original Profile selection/removal, the shared header timing-curve consumer and stable equal-date sort are attributed and wired through the existing original-item owner. Actual native query selection, IME refusal, hidden-chip focus retirement, reversal/resize/teardown and Reduce Motion are checked independently of browser behavior. The fixed count advances29/33→30/33:90.9% DONE,9.1% LEFT,+1/33×100=+3.0 percentage points. No requirement was added or reweighted. DL27/DL32/DL33 remain LEFT; exact populated modern appearance is unobserved. See [filter evidence](download-library.md#original-filter-header-chips-and-ordering).


**Downloads entry renderer (DL27):** the original SwiftUI body, nested animation
modifiers and completion transactions are attributed and implemented. The
unrendered inferred echo is removed; actual hosting-view accessibility and
original-item/window retirement are checked. The fixed count advances from
30/33 to 31/33: 93.9% DONE, 6.1% LEFT, +1/33 × 100 = +3.0 percentage points.
DL32/DL33 remain LEFT. No requirement was added or reweighted; populated modern
comparison and remaining transition/haptic attribution remain explicit. See
[entry evidence](download-library.md#original-entry-animation-owner).
