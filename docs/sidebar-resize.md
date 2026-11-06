# Sidebar edge resizing

`SidebarResizeRegionView` is the 8-point strip on the trailing edge of the locked
or floating sidebar. `SidebarResizeGesture` is the pure width model behind its
pan. `BrowserWindowController` owns the window's own width, the live layout,
the single store update and the collapse; it keeps the original window, Space
and page ownership.

Evidence labels used in this document: **[D]** bounded disassembly or Mach-O
tables; **[R]** a REA/Ghidra raw-slice decompile agreeing with it; **[O]** a
frames in pixels at the capture's 0.9905 scale; points = pixels / 0.9905) or
its accessibility tree, each use naming which; **[C]** an inert AppKit probe or
**[I]** an inference.

## Reference mechanism

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`. Addresses
belong to that artifact. Annotated llvm-objdump with Swift field metadata and
ObjC ivar lists established the mechanism; REA/Ghidra 12.1.4 decompilation of
(`ev_b180537533d57b26000bf6fbcc2d62e4919152182bdfba8ce3243e377808153c`).
Pseudocode is recovered evidence, not original source.

  `(edge.maxX − 4, container.minY + 11, 8, container.height − 22)` for locked
  and floating presentation and hides it while hidden; transitions hide it at
  their start and restore it at completion.
  pointer is unobstructed. A drag disables window cursor rects, re-sets the
  cursor on every change and re-enables cursor rects at the end.
- The indicator is a 3-point `CAShapeLayer` (`bounds.height − 8` tall) centred
  on the strip's leading edge, in a theme colour at opacity 0.5. Hover shows it
  after 0.25 s and fades it in and out over 0.2 s; resizing shows it at once.
- The pan width is `round(widthOnBegin + translation.x)`, hard-clamped to
  164–500; below 82 it becomes 0, a live hidden preview. The default is 228
  (two 8-point insets, four 47-point favorites and three 8-point gaps). Within
  14 points of 228 and below 50 points per second, moving towards it, the width
  snaps with a generic haptic and a `transform.scale.x` pulse (1 → 1.7, 0.08 s,
  autoreversing, cubic 0.215/0.61/0.355/1). The band arms only after the pointer
  has left it once; leaving a snap held longer than 0.5 s repeats the haptic.
- Releasing a locked drag at or below 82 commits the start width and hides the
  sidebar; cancel or failure restores the start width. Double-click sets 228.
  Every end sends `WindowAction.layout(.sidebarResizeGestureDidComplete(sidebarWidth:))`
  (LayoutAction case 4) with the clamped commit width, which is the start
  width after a cancel, a failure or a collapse; a collapse then sends
  the `SharedWindowFeature.WindowAction.LayoutAction` field descriptor
  search, so what it writes is untraced.
- Live layout uses a controller-local `effectiveSidebarWidth`; the store hears
  about content breakpoints and the completed gesture only. `isSidebarResizing`
  disables item-preview hover and sets resize-reason bit `0x8`, which puts every
  web content view into renderer-acknowledged throttle mode
  ([page size during a width drag](#page-size-during-a-width-drag)).
- Width is per window. Swift field metadata gives `sidebarWidth` to
  and the app-wide `sidebarViewPreferences`, a `SidebarViewPreferences
  `ev_0d743a8da86182eb118790ac677784ebb5f0bf898aec0f150c99991adc88c8db`) takes
  a mode but no width. That a new window takes the preference's width and a
  window's resize updates it is inferred from this ownership; the reducer
  writes were not traced [I]. `SidebarSpaceState` also has a `sidebarWidth`
  whose role is unrecovered.
- The stored form is `StorableWindows {version, sidebarViewPreferences?,
  windows: [CodableWindowData]?, lastFocusedSpaceID?, platformData?}`
  decoder (it also reads `LegacyCodingKeys` `focusedContentID`,
  and, when it is absent, stores a computed default into the
  favorite size and spacing of the 228 above [I], `ev_09be783ddb05937e85e4d651b2a214bc481f63e899f5cc7cd441b25f39c05cd9`
  `encodeIfPresent` [R], `ev_ed8397661f4034cb90ffa5cc51960175642ad56671f76dc2fc518141aac935af`.
  So each stored window carries its own width, and a record without one
  decodes as 228 rather than the app-wide preference [D]. That restoration
  hands it to the window's `WindowState` is inferred [I]; that path, and
  whether it clamps, was not traced.

## Parc implementation

The strip is a root subview above the sidebar and page host. Its frame and
visibility are set in the full layout pass: shown for a visible locked or
floating sidebar, hidden while hidden, during show/hide transitions, and while
Archive, a popup window or a fullscreen tab owns the window. Hiding it, window
resignation, closing or a presentation change cancels an active drag through
its single session. A press on the strip bypasses the window's page-selection
and floating-dismissal monitor.

Each pan change updates the window-local width and runs the geometry-only
layout pass used by the Cmd-S group, without native, payment or Easel refreshes.
The end of the gesture makes at most one store update (see below), then one
full pass. Floating dismissal and item previews are suspended while resizing.
The store default is 228 and its clamp 164–500; the Settings slider uses the
same range.

Each `BrowserWindowController` owns its width (`SidebarWindowWidth`, ParcCore),
seeded at creation from its saved record when Parc reopens it at launch and
otherwise from the app-wide last-used `BrowserSettings.sidebarWidth`, Parc's
`SidebarViewPreferences.sidebarWidth` (see
[Width across relaunch](#width-across-relaunch)). The model decides what an end
writes: `end(_:_:)` returns the last-used width only for a completed drag that
keeps the sidebar, and `reset()` returns 228 for the double-click; the
controller applies what it returns. Other open windows keep their widths. A
cancelled or failed drag restores the start width and a collapse keeps it;
none of them writes the last-used value [I]: no width changed, and since
kept rather than replaced by this window's start width. The Settings slider
edits the last-used value and posts `SidebarWindowWidth.settingDidChange` with its store,
so the explicit setting also applies to every open window of that store
store's value.

### Width across relaunch

Parc's per-window session record began as a minimal sidebar-width hook in
Windows and lifecycle's files (`AppDelegate.swift`, the window controller's
initializer and `BrowserStore.swift`). The Windows owner has since added
per-window identity, presentation and item activity dates; broader
multiwindow restoration remains in progress:

- The session file's `windows` is a list of `BrowserWindowRecord`
  `StorableWindows.windows`. A record always encodes its width and decodes a
  decodes with none.
- The records drive no UI, so `BrowserStore` keeps them off its published
  `state` as `windowRecords`: loading moves them out of the decoded state,
  `updateWindowRecords(_:)` replaces them and schedules only the debounced
  save, and every session write (`save()` and the profile-settings commit)
  puts them back into the file. A width commit, a reset, a Settings slider
  tick or a window close therefore renders no window.
- `AppDelegate.recordWindowSessions()` replaces the list from the main
  store's open non-popup windows (`BrowserWindowController.sessionRecord`)
  in `BrowserWindowRecord.sessionOrder`: the window that holds the shared
  `ParcBrowserWindow` frame autosave name first, then front to back by
  `NSApp.orderedWindows`, then the rest in opening order. That order is a
  Parc adaptation for the launch fallback below, whose window takes the
  autosaved frame and the first record, so its width is the same window's;
  save (a window closing included) and whenever a window's record changes
  (`onSessionRecordChange`). Unopened saved records are retained after the
  live records, with exact live IDs replacing their saved counterparts.
  Quit records once as it begins and keeps that list while its own closes
  run, so the windows open at quit are the ones saved. Unchanged records
  change nothing; a private store never persists and keeps none.
- At launch AppKit reopens saved standard windows by identifier, and
  `restoreBrowserWindow(id:completion:)` passes the unrestored record with
  that ID to `BrowserWindowController(restoredRecord:)`, so each window
  takes its own width. When AppKit restores no browser window and no other
  window is open (an early download prompt's owner aside),
  `finishInitialBrowserPresentation`'s fallback passes the first unrestored
  record instead, so that window takes the frame autosave's frame and the
  width of the same window. Seeding clamps either to 164–500. Any other
  window, and every window when there is no record, takes the last-used
  width; so does the empty owner an early download prompt seeds before that
  first presentation. A cancelled or failed drag, or a collapse, changes no
  width and so writes no record.
- With `restoreSession` off, the startup window does not consume a saved
  window record and uses the last-used width. AppKit's separate frame
  autosave remains unchanged.
- `python3 tests/SidebarResize/check.py` runs the restored seeding in its
  `width` suite and, in `session` against the real `BrowserStore`, the record
  codec, the save order (the autosave holder first while behind other
  windows, then front to back, then off-screen windows), an older session
  without records, records that publish nothing yet reach the file through
  the debounced save, save and reopen with two windows' widths beside a
  different last-used width, a later settings write keeping them, clamping,
  unchanged records, cancel and collapse writing nothing, and a private
  store. It also asserts the uncompiled restore paths: the unrestored
  records seeded at startup, the record AppKit restores by window identifier
  and the launch fallback's first unrestored record, the three
  `restoredRecord` hand-offs, the width's `didSet` that reports a change,
  the seeding, the record and quit recording before its closes. Seeding
  from the last-used width only, not decoding the records, decoding a
  missing width as anything but 228, publishing a records change, not
  saving it, dropping the holder-first rank, an AppKit-restored window
  without its record, the launch window without its record, or the width
  without its `didSet` each makes it fail.

## Page size during a width drag

page takes a new size, then keeps it until its renderer reports a frame, and
only then takes the latest size. Evidence labels are defined at the top of
this document.

### Reference mechanism


- `WindowContentsContainerViewController.contentSizeThrottleFlags`
  window resize, `0x2` split divider drag, `0x4` split interactive pane
  `mode = flags & 0x4 ? locked : flags ≠ 0 ? throttle : intrinsic` into each
  window content's `WindowContentViewController.contentResizeMode` [D].
  WillEnterFullScreen, `0x103EC4F00` WillExitFullScreen, `0x103EC4EA8`
  DidEnterFullScreen, `0x103EC4EB0` DidExitFullScreen, `0x103EC4F10`
  WillStartLiveResize, `0x103EC4E98` DidEndLiveResize, loaded at
  true and the did/end ones to false is [I].
  otherwise it cancels the renderer subscription, clears `lockedContentSize`,
  installs the subscription when entering throttle with web content, sets
  `lockedContentSize` to the web view's frame size when entering locked, and
  sends `setNeedsLayout:` [D], `ev_720cf9c9b94bffc54ee3e00df20fc6f8c4681071ec95e3241f66267fb1fd8e66`
  [R]. It never touches `pendingResizeFrames`: an offset-global scan finds that
  field only in the report sink, layout, the initialisers and the ivar
  `resizeTimer` (an analytics `PerformanceTimer`), so a released page simply
  takes its full content rect at the next layout.
  .sink(receiveValue:)` with a weak self and no other operator [R],
  `ev_36fe6b3ac19b9f38bb811d8a79916c0aa6e8dc791f1f7d997834081be3006505`. A
  `Published` publisher delivers its current value on subscription [I: Combine
  semantics], so entering throttle starts with one report.
  locked.height)` of the flipped content view while locked. Then, only in
  throttle and while not locked, it compares
  that frame size with `pendingResizeFrames.last?.size ??
  features.pendingRenderFrameViewportSize`; a difference over 1.00001 pt in
  either dimension appends `ResizeFrame(timerID, size)`, and a count ≥
  `ViewState.maxPendingResizeFrames` locks that size [D].
- `maxPendingResizeFrames` is the `max-pending-resize-frames` feature flag, an
  ViewState's field 44 is [I]. With 1 the page holds after every size the
  renderer has not drawn.
  including the first within 1.00001 pt of the reported size, or all of them,
  then always clears the lock and requests layout [R],
  `ev_1902735b6bf88b041de04fad8a18efb83b55c54fb7b5591c452e9d96decb8e78`.
- The held page keeps its top-leading corner. When the content grows its
  trailing edge exposes the content view; when it shrinks the page is clipped
  by the content view's corner mask [D for the frame and mask; the exposed
  background was not observed].
  that ADK mirrors it into `WebContentFeatures` by KVO is [I].
  SHA-256 `69276adaca785a46f2554e7fd18926e7fcdd6aba44ba64400a337427817db3dd`):
  ivar at `0xe8`). Its setter is sent from two places [D]: the web contents
  observer bridge (vtable `0xda87f58`, slot 18, `0x4413968`) divides an integer
  pixel size by a float scale from its argument, `{width, height, scale}` with a
  colour at `+0xc` that it sends to `setRootBackgroundColor:`; the initial sync
  (`0x440e9c0`) does the same with the web contents' cached scale (`+0x20c`)
  and size (`+0x210`), zeroing results at or below 2⁻²⁰. The value is in
  points. The scale-then-size order and the sibling background colour match
  `cc::RenderFrameMetadata`'s `device_scale_factor`, `viewport_size_in_pixels`
  and `root_background_color`, delivered by
  after the browser activates the frame was not found (no dispatcher of slot 18
  turned up in a bounded search). The installed 1.170 main executable still
  carries these field names and the flag [D, strings only].

### Parc implementation

- `PageContentResize.swift` (ParcCore) holds the model:
  `PageContentResizeReasons` (the four recovered bits and their mode) and
  `PageContentResizeHold` (the didSet, frame, layout bookkeeping and report
  sink above, with `maxPendingFrames` 1 and the 1.00001 tolerance).
  `PageContentResizer` (ParcApp) applies it to a pane's page view in the
  content view's layout: it sets the frame itself, autoresizes only intrinsic
  pages so a held size cannot reach the renderer first, clips the content while
  holding, and keeps the renderer subscription only while throttling,
  delivering the current report first.   After the page frame is set it marks the
  hosted subtree dirty and lays it out in the same pass: Chromium's child
  sizes itself from `NSView.layout`, which a parent frame change does not
  trigger, so without that flush the compositor kept the previous surface
  web-content view; it does not walk descendants or call
  `layoutSubtreeIfNeeded`.   Parc skips that Chromium flush when this page frame was already flushed
  and hosted children (stopping at `PCNativeDevToolsPaneView`) already fill
  it, including a throttle/lock hold whose size did not change. Autoresizing
  can write the page and pane frames before `place` runs; the inspected host
  still does not autoresize, so a new page size, or a hosted child that does
  `pendingRenderFrameViewportSize`, it keeps the latest report, converted when
  it arrives, and layout compares against that value rather than reading the
  engine mid-layout.
- A page joins a held mode only once its content and its own frame have a
  size: a new pane's page view and content start empty, and `BrowserPane`
  places the page before the content's first layout. Until then the page
  stays intrinsic; locked then holds the content's size, and throttle starts
  from the renderer's latest frame. Before that first report the engine has
  laid out the page's own subtree, so the report is converted against settled
  geometry.
- `BrowserWindowController.setContentResizeReason(_:active:)` keeps the
  window's reasons. A mode change goes to the panes the split view shows;
  `render()` gives a pane the current mode when it shows it and intrinsic when
  it parks it, so the background tabs' parked pages, which never change size,
  start no renderer observation. `isSidebarResizing` sets `.sidebarResize`, so
  a drag throttles from its first event to its end, and the end's full layout
  applies the final size once the mode is intrinsic again.
- **Engine (built into engine v231):** `PCNativePage
  (RenderFrameViewport)` in `native_appkit_bridge.h`, implemented in
  `native_appkit_page.mm`: the read-only `renderFrameViewportSize` and
  `observeRenderFrameViewportSize:`, whose `PCNativeRenderFrameObservation`
  lease ends on `invalidate`, release, page close or WebContents destruction.
  It observes the primary main-frame `RenderWidgetHostImpl`'s
  `RenderFrameMetadataProvider`, follows widget swaps as the input diagnostics
  observer does, and on `OnRenderFrameMetadataChangedAfterActivation` reports
  `LastRenderFrameMetadata().viewport_size_in_pixels / device_scale_factor`
  synchronously on main. Reporting after activation is Parc's choice for
  Engine v231 was applied, built and packaged from main `12afb77`, which
  carries this overlay (receipts `work/integrated-engine231/apply.json`,
  `build.json`, `package.json`; sealed manifest
  `build/independent-v231/engine-artifacts.json` in the canonical checkout).
- Confirmed against that engine [D]: the framework the manifest lists
  (`engine_dir`'s `Chromium Embedded Framework`, SHA-256
  `bede9bcd…c17c8c`, matching the manifest) and the packaged app's copy
  (`development-app-12afb77`, `42a20467…cda88`) both define
  `-[PCNativePage(RenderFrameViewport) observeRenderFrameViewportSize:]`,
  `-[PCNativePage(RenderFrameViewport) renderFrameViewportSize]`, the
  `PCNativeRenderFrameObservation` class and its `invalidate`, and the
  `RenderFrameViewportObserver` with
  `OnRenderFrameMetadataChangedAfterActivation` (`nm -m`). Engine v230's
  packaged framework has none of them. `PageRenderFrames.swift` asks
  `responds(to:)` for exactly these two selectors, so on v231
  `observeRenderFrameViewport` returns a lease and a drag's page joins
  throttle; `PageContentResizer.join()` falls back to intrinsic only when no
  lease comes back, which an engine before v231 gives. Locked mode needs no
  report. `python3 tests/SidebarResize/engine_report.py <manifest or
  framework>…` repeats this check with `nm` only (a manifest's framework must
  match its SHA-256); it fails for v230's framework. That a v231 page in a
  running app actually holds during a drag is the runtime acceptance step
  below.
- Adaptations: Parc holds `PCBrowserView`, not the renderer's view. The
  renderer fills the page host's content view: below the host's infobar shelf,
  which is inside the page's native view, and beside docked DevTools, which
  frame that native view only in their own layout. Each report therefore adds
  back the difference between `PCBrowserView` and the host's content view,
  measured when the report arrives, outside layout, where the engine has
  pane's white backing [I]. No analytics timer.
- Known limits: a hold assumes the renderer's size follows the page view's.
  Where it does not (for example if docked DevTools take a size change
  instead of the page [I]), a held page waits for some other report or the
  drag's end.
  A page moved to another pane mid-drag keeps the old pane's subscription
  until that pane's next mode change, which ends it without a new one;
  meanwhile its reports only relay out the old pane. If the page comes back,
  rejoining drops the hold it left with.
- **Contract for the Windows and lifecycle owner:** set `.windowResize` with
  `setContentResizeReason(.windowResize, active:)` from
  `windowWillEnterFullScreen`/`windowWillExitFullScreen` and
  `windowWillStartLiveResize` (active) and from
  `windowDidEnterFullScreen`/`windowDidExitFullScreen` and
  active/inactive split [I].
- **Contract for the Split views owner:** set `.splitDividerResize` while a
  Delivered in SP10 through `ParcSplitView.onDividerPanActivity` and
  `onInteractivePaneEditing`
  ([split mechanism](split-groups.md#divider-regions-pane-input-and-content-resize-reasons)).
- `python3 tests/SidebarResize/check.py` runs the model and the production
  `PageContentResizer` in an off-screen window with a fake page that emits
  reports: live resizing without reports, one size per report, top-leading
  hold, clipping, any-size release, the drain on subscription, page
  replacement, locked mode, a page placed before its content has a size and a
  page that comes back after leaving a held pane.
  Its `frames` suite also compiles the production `PageRenderFrames.swift`
  against `EngineStub.swift`, a stub of the engine's view tree (a DevTools
  pane that frames the page host only in its own layout, a host with an
  infobar shelf above its content view by constraints): with docked DevTools
  and a shelf the first step holds and its own report releases it, a shelf
  alone does not hold a static page, a page moved mid-drag holds its new size
  until its renderer draws it, and an older engine stays live [C].

## Adaptations and remaining work

- Translation is measured in the window's root view. Parc's hidden preview
  gives the same deltas without that displacement.
- The collapse from a hidden preview settles without animation because the
  out and only then sends `hideSidebarWithGesture`; whether that relayout
  so Parc avoids restoring the old width under the pointer first. This needs a
  visual comparison.
- A Settings edit during a drag sets the window's width but not the live drag
  would replace it. Another window's commit no longer reaches this window.
- Relaunch restores the reopened window's own width
  window; Parc reopens one, so the remaining records wait for multi-window
  restoration. **Contract for the Windows and lifecycle owner:** the list
  order is Parc's adaptation for the single reopened window and carries no
  window identity, so a multi-window restorer must not pair records with
  windows by position: it adds an explicit key to `BrowserWindowRecord`,
  such as a stored window ID or the frame, and matches by it, or replaces
  `sessionOrder` with its own. If the window holding the frame
  autosave name closed before quit, the reopened frame is that closed
  window's while the first record is the frontmost open window's. A crash
  keeps the records of the last save, which a width change, a window close or
  field.
- The indicator path uses radius 1.5 (a capsule) because CoreGraphics requires
  primary foreground until the exact theme role is compared. Its initial
  opacity is 0.5, and the pulse is skipped under Reduce Motion.
  ([sidebar chrome spacing](#sidebar-chrome-spacing)); the icon, title and
  control insets inside a row and a Favorite tile stay with their row and tile
  presentation.

## Sidebar chrome spacing

(`4e452201…9547`): annotated disassembly, the constant initializers and REA/Ghidra
accessibility frames served only as a cross-check. `SidebarChromeLayout` holds
the pure geometry; `SidebarView.layout()`, the list outline built by
`SidebarView.render` (`SidebarOutlineView`) and `BrowserWindowController`
apply it.

|---|---|---|

and the toggle at 77 on macOS 26 and later (1.170's 9-point spacing), or 13…67
and 71 before. It places Back, Forward and Reload at width − 106, − 72 and − 38
(y 8), the field at x 8…220, y 46…82, and the dock buttons 41 points above the
bottom. The 1.170 frames on this OS agree within a point: lights ≈ 12.1/35.3/57.5
(AppKit's 16-point accessibility frames, 1 point outside the 14-point widgets
at 13/36/59), toggle ≈ 76.7, Back/Forward/Reload ≈ 122/156.5/190, field top ≈
45.5, dock buttons at height − 41.5, and a list top ≈ 87 = 82 + 5 with an empty
App Tray, consistent with the 5-point inset.

tab, an unlabelled separator, New Tab and four Today tabs, and its geometry
still has an empty App Tray [O]. For that sequence the model puts the 2-point
pinned header at 87, the pinned cell at 90 with its visible row at 92…128, the
24-point divider cell at 131, New Tab's cell at 156 (visible 158) and the
Today cells at 197, 238, 279 and 320 (visible 199…). The captures agree:
outline at 87 (86 pixels), 41-pixel rows (≈ 41.4 points) holding 40-pixel
buttons (≈ 40.4 points), separator rows 3 and 25 pixels tall, icons at x ≈ 17 (the 16-point favicon's 18-point frame around
8 + 6 + 4 = 18) and titles at x ≈ 43 (Parc's row title at 8 + 36 = 44). The
tree has no row for the zero-height pinned footer, which NSTableView would
reject as a row [C]. One row of Favorites puts the App Tray at 82…145 and the
list at 145.

### Parc adaptations

  [traffic lights](sidebar-motion.md#traffic-lights)) with 1.170's spacing:
  60 points from x 13 on macOS 26 and later (54 before), centred in the
  40-point row, with the toggle at 77 (71). Both centre at y 24, so the lights
  and toggle are level, and they move with the sidebar surface.
  the More slot after Back and Forward, so a pointer control still hides or
  adds the 14-point width constraint only on macOS 26 and later (1.122
  size, and Parc centres it on its 14-point slot. With 60-point lights, a
  regular row below 217 whose toggle would crowd Back, counting the 2-point
  spacing after it, keeps all four controls at the narrow 28-point size. A
  narrow row whose Back would reach the lights gives up Forward before the
  widths was not captured. `python3 tests/SidebarChrome/check.py` checks every
  width from 164 to 500 against several light widths and heights, that the
  lights stay centred and that a toggle is always shown.
- The field background spans the container, with the page actions inside it;
  the address button starts 1 point inside it and still stops before those
  actions' hit targets. The command field opened from the sidebar is its
  superview's width − 18 wide (`CommandBar.position`), so anchoring at x 9
  command bar owner's width − 16 in the same change.
- Shared-quote mode keeps Parc's earlier pill: the background shrinks to the
  `CommandBarPlaceholderView` was not compared.
- **Contract for the Downloads owner: delivered (DL33, October 27).** The
  Downloads button (formerly x width − 73, y height − 45, 28 × 29) with
  `SidebarLibraryEntry` in that 32 × 32 slot at x 8, y height − 41
  (`SidebarChromeLayout.dockLeadingButton`). The Space strip now runs
  ([keyboard side](sidebar-accessibility.md#downloads-entry-downloads-owner),
  [entry details](download-library.md#original-library-entry)).
  and elasticity whose document holds the Space buttons at the recovered
  frames (the whole item is the click target) and, per item, its own hover
  background and centred dot. Only the background's opacity changes with
  separate selection fill square is gone and the selected Space is its icon
  at full alpha: the recovered background follows hover only, and that no
  other selection indicator exists is inferred from the traced item-view
  paths [I]. The creating button is the selected item.
- `SidebarView.render` keeps each Space's button by Space ID and updates its
  title, image, font, tag, state, enabled state, action and accessibility
  (`SidebarAccessibility.configureSpace`) in place, so the strip's items change
  item views. The strip applies only the values that differ from an item's
  last style: a store update, a layout pass or an unchanged style never cuts
  a cross-fade short, and a new item takes its style directly. Document
  subviews run backgrounds, buttons in item order, then dots, so the
  accessibility children follow the visual order with the creation button
  last; reordering moves the buttons without removing them, so each keeps its
  accessibility element. When the items change, the selection and hover follow their
  never restyles the selected one or re-centres the scroll; when the selected
  item itself leaves (creation ends, the active Space is deleted), its
  successor still cross-fades.
- The active icon colour: a Space whose theme has a primary colour (and is
  valid) tints its icon with that theme's `maxContrastColor`, computed like
  the window's own palette (`ThemeChromePalette(theme:appearance:)`), while it
  is selected or highlighted; a Space without one, Parc's counterpart of
  image per Space, so the button's alpha is the active plus inactive alpha
  and its tint switches to the active colour while the active view would be
  creation view's draft theme.
  (sRGB black or white at 0.5); `GrayA4` reuses `SidebarRowAppearance.controlFill`.
  The theme appearance (`palette.isDark`) stands in for the effective
- The relayout and restyle groups use AppKit's default duration: none is set
  in the recovered blocks, so the 0.25 s default is an inference, as is
  group so a Space switch between light and dark themes keeps its cross-fade,
  and the first selection is placed directly like its scroll [I]. Reduce
  Motion skips them and the 0.16 s scroll.
- The Space buttons and the creation item take no keyboard focus, Parc's
  so only the pointer highlights an item. Parc adaptations: resigning key
  clears the hover, and so does the sidebar leaving (hidden, or unhidden
  off-screen after ⌘S through `SidebarView.isPresented`), whose return re-tests
  it; hit-testing also requires the visible strip; no scroller is shown. Not
  Spaces paging selection factors, `SidebarDockItemTooltipView` and drag
  reordering. `python3 tests/SidebarChrome/check.py` sweeps the layout model
  and checks the production strip in an off-screen window that is never key:
  frames, alphas, tints, dots, per-item backgrounds, hover within the visible
  strip, hit-testing, no keyboard focus, accessibility values and order (with and without the creation button, and
  across a reorder), no alpha re-set for the same items, a layout pass or an
  unchanged style during a switch, a selection that follows its item when an
  earlier one is removed, and scrolling. The selected and hovered
- The hidden page inset is the recovered 10 (the earlier 9 was a still estimate).
  That the `Edge.Set` is `hiddenScrimEdges` and that a locked sidebar replaces
  the leading inset are inferences consistent with the 1.170 still. The page
- `SidebarChromeLayout.tablist` models the outline: an item (tab, split,
  folder or New Tab) is its 36-point visible row 2 points inside a 40-point
  cell, an accessory fills its cell, and every row is followed by the 1-point
  intercell gap. The 40-point cell is recovered for all four, the 36-point
  visible row only for tabs: the New Tab and folder cells were not traced, so
  theirs is Parc's model [I]. `SidebarChromeLayout.tablistSlots` fixes the
  order in which `SidebarView.render` places its views, and the list's
  accessibility outline (`SidebarOutlineView`, [item list
  outline](sidebar-accessibility.md#item-list-outline-delivered-row-folder-and-split-view-owners))
  lays each slot out as one row: the row is the cell and the gap below it
  (`cellHeight` plus 1), the cell starts 16 points in per level, the view sits
  at its `viewSpan` in the cell, and the outline ends with the bottom inset.
  Parc's item view is the visible row, as the in-row geometry already
  assumed, so ordinary and split rows go from 35 points 38 apart to 36 points
  41 apart, folder rows from 30 (their chevron and name now centre in the row:
  a minimal shared-scope edit to the folder owner's `SidebarFolderRow.layout()`
  in `SidebarItemDrag.swift`, which keeps the label 2 points below the
  chevron's top as before)
  and New Tab from 34. Each level indents 16 points (was 10) and keeps the
  (the 1.170 tree reports 226 × 40-pixel buttons, ≈ 228 × 40.4 points) [O]. Parc's row view is only the
  visible row inside the list's 8-point inset, so the 5 points between rows
  and the side margins do not hover or click; a drop between two rows still
  position; Parc draws the cue on the row boundary in the middle of the
  intercell gap, 2.5 points outside a visible row
  (`tablistRowBoundaryOutset`), so the cues after one row and before the
  next coincide, and the end of the pinned section is the boundary above the
  divider cell.
  pinned footer is left out: the 1.170 tree has no row for it [O], NSTableView
  rejects a 0-point row [C], and whether 1.122's root items include it was not
  cell at 24 points, the height the 1.170 still shows (a 25-point row); the
  gives Clear, created hidden at alpha 0, the cell's height in one stack, and
  reveals Clear while the sidebar is hovered and Today has items
  ([Today divider, Clear and New Tab](parity.md#today-divider-clear-and-new-tab)).
  Parc draws that row with the SidebarSeparator border 10 points inside its
  trailing edge. The divider is listed only while Today has items, as in
  row, so a drag on New Tab's upper half ends Pinned and its lower half
  sits, goes to the pinned section, so an empty pinned section still takes
  drops between the outline's top and that line (Parc's rule [I]). New Tab
  private-window heading takes the 36-point unpinned header cell.
  can scroll the last one 120 points above the dock; a list that fits with the
  inset does not scroll, matching the probe's max(clip, rows + 120). The
  `adoptTablistScroller`): overlay scrollers float over the rows, and with
  legacy scrollers a list that overflows only with its inset gives 8 points
  (the sidebar width − 16) while its legacy scroller sits 8 points in from
- The App Tray starts at 82 (was 90) and the list follows it with no gap.
  dismisses it, and the list starts below it with the header inset 0; a
  dismissed profile's empty tray takes no height and the list starts at 87,
  which the 1.170 still's 87 = 82 + 5 matches [O]. See
  [App Tray empty state](#app-tray-empty-state). A drag into a collapsed tray
  targets the header's 5-point inset (82…87), or with the Space header shown
  its 8-point top padding (82…90); the pinned header below belongs to the
  pinned section. Private windows give the tray no height. Two or more
  show the [Space header](#space-header), which drops the inset.
- `python3 tests/SidebarChrome/check.py` checks the model's constants, the
  row order (`tablistSlots`), the cue boundaries and the 1.170 sequence
  above (3-, 41-, 25- and 41-point rows, the capture's pixel heights within
  its 0.9905 scale) [O]. Without a window it compares
  the model with an NSOutlineView set up like `TablistView`, with
  `TablistOutlineView`'s overrides, for every sequence of up to four rows and
  the production slot orders (cells, the gap below each, the height with the
  inset, cells at 16n per level), lays the production `SidebarOutlineView`
  out for the same rows and levels against AppKit's row rects, cells and
  view spans, and checks the scroller in the overlay and legacy styles, once
  more with legacy scrollers taken from the process's argument domain. It
  also asserts that `SidebarView`'s list is that outline, placed by
  `tablistSlots` and positioned with `tablistTop`, that it adopts the
  scroller and that the empty-tray drop band ends at the outline's top, or
  at the Space header's top while it shows. No running app was compared, so
  on-screen row spacing still needs a visual check.
- Unrecovered: the field's text and icon insets beyond its frame.

### Space header

`SidebarSpaceViewController`'s view; the paging container's items are only
`appTray` and `page` (`SidebarPagingContainerViewController.ItemType`, field
address is named; REA/Ghidra raw-slice decompiles checked against bounded
disassembly, Mach-O ivar lists, field descriptors and key-path patterns.

#### Reference mechanism

  the view's leading (priority 750) and trailing edges with
  shows the header and replaces `tabListTopConstraint` with
  `tablist.top == header.bottom` when shown, else `== view.top` [R]; the
  (`77be289e…c52d`) builds the same constraints: `≥ 36`
  `displayHeaderView` from `SidebarSpaceState` field 20 and sets
  `requiresTopPadding = !hasTopApps` (field 30) [R]. The state builder
  when the editing state its witness (`+0x560`) returns names this Space in a
  mode other than 2 [R], read as the Space's own header being edited [I]. `hasTopApps` is the count of
  so it is read as "the profile has Favorites" [I].
  setting `showSpaceHeaderOnSingleUnnamedSpaces` is on, when the window's
  sidebar container has two or more Spaces, or when the current Space record
  has a title (`+0x18`) or a custom icon (`+0x38` ≠ `0xff`). The incognito
  `standard` whose `StandardWindowState.sidebarContext` (its first field;
  `SidebarContext` cases `global`, `standalone`, `incognito`) is 2, the byte
  `Dependencies.DependencyValues`, value `UserDefaultsClient.UserDefaultsClient`
  `showSpaceHeaderOnSingleUnnamedSpaces`, and its `rawValue` switch
  count is the third word returned by `SidebarData`'s first requirement on
  (`OrderedDictionary<Identifier<SpaceModel>, SpaceModel>`, field descriptor
  dictionary to the client's `registerDefaults` (offset `0x100`, called at
  Space menu's toggle sends `MainMenuAction.onSpaceHeaderVisibilityToggled`
  calls `setBool(!boolForSetting(0x4d), 0x4d)` (client offsets 0 and `0x90`)
  `ContextMenus.SpaceMenu.ViewState` (5 of 7, after `spaceID`, `sidebar`,
  `focusedProfile`, `allProfiles` and `newFolderShortcut`) [D].
  the description of (index + 1) to "Space " in place
  space"), or localizes "Space" without an index [D].
  of the header's `charactersToTrim` ivar, or "" for none), then its
  nil or empty, nil otherwise [D]. So an untitled Space's "Space N" is an
  AppKit placeholder: drawn in the placeholder colour, with an empty
  accessibility value [C]. The value of `charactersToTrim` was not traced.
  chevron container, icon, name container and edit button [R], pinned inside
  `ev_077807e8…`) hides the icon when the Space has none (tag `0xff`) or the
  chevron replaces it, outside icon editing and drag highlight [R]. The edit
  button is 24 tall, its width 24 (30 while editing) when
  `(isEditing || hovered) && canShowHeaderButtonsIfPossible`, else 0 at alpha
  0, and it stays arranged [D] (Edit button, below). An inert
  probe of that stack puts the name field 4 after the icon and 4 before the
  zero-width button: 42…210 at 228 points, 14…210 without the icon [C].
  name field) is the fileprivate `SectionHeaderHoverableButton`, an
  `ev_3a1ea552…`): `mouseEnteredAndExited | mouseMoved | activeInKeyWindow |
  inVisibleRect` [D], button type momentary change, borderless, its own
  tracking area, corner radius 6 with continuous corners and border width 0
  [R]. Its image is the SF Symbol "ellipsis" with accessibility description
  "" and a 13-point semibold symbol configuration, its `contentTintColor`
  `FontSet.sectionHeaderButton` (value not recovered; it only draws "Done")
  `Assets.car`, read with `assetutil --info`) gives `GrayA11` as sRGB black
  at 0.565 or white at 0.592 and `GrayA4` as black at 0.071 or white at
  0.077 [O]. Its target is the header with `didClickEditButton:`, its
  accessibility identifier `sidebarSpaceEditButton` (case 19), and no label
  or tooltip is set [D]. It is the stack's last arranged view, 24 tall
  [D]. Nothing calls `setHidden:` on it: alpha 0 and width 0 hide it [D], so
  the 4 points after the name stay [I].
- Edit button visibility. `show = (isEditing || header.isHovered) &&
  tracking area, so only a key window hovers [D]; its `mouseExited:` clears it
  [R]. `canShowHeaderButtonsIfPossible` starts false and is bound from
  `SidebarSpaceViewController.ViewState.displayHeaderButtonsWhenPossible` (key
  `SidebarSpaceState` `+0x10`, `windowLayoutPresentation` (cases `home` = 0,
  `spaces` = 1) [D]; it is read as true for the `.spaces` presentation [I],
  and it is no user setting. `isEditing` follows the name container's
- Edit button timing. The header's hover sink is
  `DispatchQueue.main.asyncAfter` with now + 0.1 s when hovered and now + 0
  `pinnedSectionExpansionState` 0 [D]. The block reads the hover again, so a
  width constant directly, lays the stack out, then sets the alpha to 1 or 0:
  constant set directly [D]. The non-animated re-evaluations are init, the
  `collapsePinnedSectionEnabled` [D].
  the image and sets the title to `NSLocalizedString("Done", comment:
  "Sidebar space header done button")`; leaving sets the title to "" and
  the ellipsis again [D]; while editing the hover fill is clear and the width
  `ev_5430d196…`) fills the layer with `hoveredBackgroundColor` when
  (`isHovered` or `forceHoveredAppearance`) and enabled, else
  `backgroundColor`, with the radius and curve above [R]; no pressed fill and
  no fill animation were found [R/I]. A click (`didClickEditButton:`
  `window.makeFirstResponder(nil)` while editing, else pops up
  `menuProvider(event)`, the header's Space context menu, with
  `NSApp.currentEvent` for the button (`popUpContextMenu:withEvent:forView:`)
  [D/R]. Installed 1.170 still has `SectionHeaderHoverableButton`,
  `didClickEditButton:`, the "Done" comment and
  `displayHeaderButtonsWhenPossible` [D, strings only]. Not recovered:
  `FontSet.sectionHeaderButton`, HoverableView's vtable `+0xe8` hover
  the constraints override) and what `.home` presents in 1.122.
  `NSFontWeightSemibold`, GOT `0x103EC4D28`) [D], single line, not bezeled,
  clear background, not editable or selectable, tail truncation, compression
  resistance and hugging 250, identifier `sidebarSpaceName` (case 16,
  header's init sets its colour to
  black or white at 0.45) [D]; `boldSectionHeader` (13 bold) replaces the
  ABC Favorit font set replaces the system set at runtime was not traced. The
  insets at 0 and AppKit exposes the field's cell as an `AXStaticText` [C].
  clear and black (`CGColor`s), start (0, 0.5) and end (1, 0.5); `layout`
  locations [0, 16 / width], inside a `CATransaction` with actions disabled
  true, `isMaskingEnabled`, `isEditable` and, with a field editor, the
  editor's `visibleRect` starts right of 0 or, without one, the cell's
  `expansionFrameWithFrame:inView:` is not zero (the text does not fit);
  re-evaluates it with "has text", the `isMaskingEnabled` setter with "a mask
  not traced) on the main queue with "has text"; `textDidEndEditing:`
  field is not editable, so it masks only while editable, read as an inline
  rename [I].
  palette at `+0x70` when the window's theme belongs to this Space
  [D].
  `didClickPinnedTabsExpansionToggler` (SidebarSpaceAction case 7) only when
  that flag is `SidebarSpaceState.collapsePinnedSectionEnabled` and the
  `didBeginEditingSpaceName` (4) and `didClickEditableIcon` (2) (thunks
  "Edit Theme Color…", "Set Profile", "New Folder", "Live Folders", "Share
  Space Header", "Delete Space" and "Manage Spaces…" [R, strings]. The
  header's provider passes the builder's seventh argument `w6` = (context ==
  "sidebar" compared) [D]. With that flag set (`[sp, #0x7c]`, stored at
  repeats the visibility rule on the menu's copied state: a flag at `+0x78`,
  not one Space, a title or an icon [D]; with one untitled, icon-less Space
  only the flag remains, read as `SpaceMenu.ViewState`'s
  `showSpaceHeaderOnSingleUnnamedSpaces` [I]. The item has the comment "Menu item to
  toggle space header visibility" and no image, and its action is
  menu for the dock's Space items ([Dock Space menu](#dock-space-menu)), the
  sidebar view itself, over the list's empty area
  ([Sidebar Space menu](#sidebar-space-menu)), and one unidentified
  surface. The menu's separators and item order beyond the builder's code
  order were not traced. The hover background (inset 8,
  `SidebarItemBackground`) and the chevron show only with
  for drags; `draggingEntered:` sets the controller's `isDraggingOverHeader`
  and returns Move, and `performDragOperation:` calls the controller's
  (the conformance's witnesses are `swift_deletedMethodError` because those
  calls are devirtualised [D]); its destination was not named.
- Accessibility. The header view sets no role or label; the name field is
  its element, with the identifier above [R]. The edit button carries
  inert probe of that configuration shows AppKit exposing the button's cell
  as an `AXButton` even at width 0 and alpha 0, labelled with the "ellipsis"
  symbol's own description ("More" on the test system) because the empty
  description falls back to it, and "Done" while editing [C]. The icon's
  "Edit Space icon" tooltip applies to icon editing [R].

#### Parc implementation

- `SidebarChromeLayout.SpaceHeader` is the geometry and the rules:
  `isShown(spaceCount:titled:customIcon:privateWindow:showOnSingleUnnamedSpace:)`
  (the setting, two or more Spaces, a titled Space or one with a custom icon;
  `toggleTitle(spaceCount:titled:customIcon:showOnSingleUnnamedSpace:)`,
  `placeholderTitle(position:)`, `top(trayHeight:hasFavorites:)`,
  `frames(width:icon:titleHeight:editButtonWidth:)`, the edit button's
  rules (below), and `pageTop`/`tablistTop` with the
  header. With two Spaces and a dismissed empty tray the header spans
  90…126 and the list starts at 126 (87 without the header); with one row of
  Favorites 145…181 and 181; under the empty state at 228 points
  196…232 and 232.
- `SpaceHeader.content(spaces:activeSpaceID:privateWindow:showOnSingleUnnamedSpace:)`
  (`SidebarSpaceHeader.swift`) is the render-side decision `SidebarView`
  calls: whether the header shows, the field's text (the title, or "" while
  untitled), its placeholder ("Space N" while untitled, else nil) and the
  menu's toggle title. Every Parc Space stores a name and the first is
  placeholder for the Space's position counts as untitled, so a fresh single
  misreads.
- The setting is `BrowserSettings.showSpaceHeaderOnSingleUnnamedSpaces`, an
  app-wide optional in the session store (`nil`, as in older sessions, is
  sidebar that call, so every window follows it. Shared scope: these two
  bounded, commented hooks in `BrowserStore.swift` and
  `BrowserWindowController.swift`.
- `SidebarSpaceHeaderView` (`SidebarSpaceHeader.swift`) is the view: the
  icon (a Space's `customIcon`, a symbol at 14 points or an emoji at 16 in
  the 24-point slot; the glyph sizes are Parc's [I]) tinted with
  `headerTintColor`, the window palette's `maxContrastColor` (read as
  `+0x70`, as in the dock [I]) while the active Space's stored theme has a
  colour, so the icon follows the header's own Edit Theme Color… preview
  live; else `ForegroundTertiary`. A Space stored without a theme colour
  keeps `ForegroundTertiary` during a preview until it commits [I]. The name
  `SidebarForegroundDarker` (the theme's darkness stands in for the
  effective appearance, so the header takes the matching aqua or dark aqua
  appearance [I]), no focus ring and `sidebarSpaceName` on the field and its
  exposed cell. An untitled Space's "Space N" is the field's AppKit
  placeholder, so it draws in `placeholderTextColor` with an empty
  accessibility value and the placeholder as `AXPlaceholderValue` [C]. The
  is neither editable nor selectable). `SidebarView` keeps it in the content
  surface before the list, so it reads after the address and before the
  list, and places it with the model.
  same `leadingMask` gradient, its layout (bounds, locations [0, 16 / width],
  no implicit animation), the install rule and the clear on end of editing,
  and `isMaskingEnabled` set by the header. The field is layer-backed, as the
  sidebar's views are. Because the header's field is never editable in Parc,
  rename. Not built: the vtable `+0xa0` main-queue re-evaluation (its callers
  were not traced) and `shouldDisableWritingTools`, which only configures a
  field editor the header never has.
- Controls, wired to Parc's actions: the context menu (`SidebarSpaceMenu`,
  "Rename Space…" (Parc's rename prompt, `onRenameSpace`), "Edit Theme
  Color…" (`onEditTheme`) and "New Folder" (`onNewFolder`) and, for one
  untitled Space without an icon, "Hide Space Header" or "Show Space Header"
  last (`onToggleHeader`), repeated as accessibility custom actions on the
  `collapsePinnedSectionEnabled`; Parc has no collapsible pinned section, so
  there is no chevron or hover background.
- Delivered: the header's own menu shows the toggle only while the setting
  shows the header, so it can hide the header but not show it again. As in
  the list's empty area) carry the same menu with the toggle, so Show Space
  Header is offered there ([Dock Space menu](#dock-space-menu),
  [Sidebar Space menu](#sidebar-space-menu)).
- The edit button is `SidebarSpaceHeaderEditButton` (`SidebarSpaceHeader.swift`),
  "ellipsis" symbol at 13 points semibold with an empty description and an
  empty title, borderless, momentary change, centred, zero alignment
  colours like the header's other colours) in every state,
  `sidebarSpaceEditButton` on the button and its exposed cell and no label
  or tooltip of its own.
  `SpaceHeader.frames(width:icon:titleHeight:editButtonWidth:)` places it
  24 tall and centred at the trailing inset with
  `editButtonWidth(shown:editing:)` (0, 24, or 30 while editing), and the
  name ends 4 before it: at 228 points
  the button spans 190…214 when shown and the name 42…186 with an icon
  (14…186 without), 184…214 and 14…180 while editing. It is never hidden:
  alpha 0 and width 0 hide it. `showsEditButton(editing:hovered:canShowHeaderButtons:)`
  0x223 options, so only a key window hovers; a change of the header's hover
  re-evaluates the button on the main queue after
  `editButtonHoverDelay(hovered:)` (0.1 s in, 0 out), reading the hover
  again, animated while the header shows no custom icon (Parc has no
  collapsible pinned section, so its expansion state is always 0); the width
  snaps and the alpha fades in an ease-out group of
  `editButtonFadeDuration` (0.1 s) or is set directly. The button's layer
  takes `GrayA4` (`SidebarRowAppearance.controlFill`, the 1.170 values) at
  radius 6 with continuous corners while the button itself is hovered and
  enabled, else clear. A click pops up the header's Space context menu, the
  same `makeMenu()` right-click shows, with `NSMenu.popUpContextMenu` for
  `NSApp.currentEvent` at the button,
  and does nothing without a current event.
- Edit button mapping: `canShowHeaderButtonsIfPossible` starts false as in
  `.spaces` presentation and Parc has no `.home` one [I].
  `SidebarSpaceHeaderView.isEditing` reproduces the editing states
  without hover, no hover fill, an animated re-evaluation, and a click that
  ends the rename with `makeFirstResponder(nil)`. Nothing sets it until the
  Inline rename contract lands; "Done" keeps AppKit's button font because
  `FontSet.sectionHeaderButton` was not recovered.
- Edit button adaptations: it refuses first responder and is no keyboard
  stop, Parc's choice for a control only the pointer reveals (the name's
  custom actions carry the same menu; see
  As in the dock strip, resigning key and hiding the header clear both
  hovers, because a hidden view gets no `mouseExited:` and the tracking areas
  stop in a background window. The header keeps taking every other pointer
  event; a shown button takes its own clicks.
- Not built: inline rename, icon picking, the profile indicator and the
  title's `charactersToTrim`. The shown header is a drop target for sidebar
  item drags (below); the empty-tray Favorites band ends at the header's top.
- `python3 tests/SidebarChrome/check.py` checks the visibility cases with
  the setting, the toggle's conditions and titles, the placeholder rule, the
  constants, the header and list positions above and the frames in the
  layout suite. The header suite runs `SpaceHeader.content` on Space
  fixtures (a fresh Space, adding and removing a Space, renaming to and from
  "Space 1", an empty name, "Space 1" in the second position, a custom icon,
  a private window, the setting on and off, no active Space, and the lone
  "New Space" and "Space 2" cases) and the production view in an off-screen
  window that is never key: frames against the model, font, colours and
  appearance in light and dark, the placeholder drawn pixel-for-pixel in
  `placeholderTextColor` in both and its accessibility value, the mask's
  gradient, layout and install rule, symbol and emoji icons, a long name,
  the two exposed elements and their identifiers, the menu's titles and
  actions with and without the toggle, the custom actions, hit testing and
  no keyboard stop. The edit button's checks (layout suite: its widths,
  frames at rest, shown and editing, the visibility rule and the delays;
  header suite, with hover delivered as AppKit's entered and exited
  messages): its image, title, button type, insets, tint in light and dark,
  target and action, the 0x223 tracking areas in the never-key window, the
  gate holding it hidden while hovered, the frames against the model at
  rest, shown, with an icon and editing, hover-in showing it no sooner than
  0.1 s later, hover-out dispatched to the next main-queue turn, a hover
  shorter than 0.1 s never showing it, the ease-out 0.1 s opacity animation
  without an icon and none with one, the `GrayA4` fill only while hovered
  and enabled with radius 6 continuous corners, editing ("Done", width 30,
  no fill, Done ending the rename without a menu), the click's menu for the
  current event at the button with the right-click items and actions (the
  menu is captured, never shown), resigning key and hiding clearing the
  hover, the shown button taking its clicks, its accessibility element and
  default, both toggles, a relaunch and an older session. It asserts
  `SidebarView`'s placement, its call to `content`, its wiring and the
  header-buttons gate, and the controller's hook. Negative controls rebuild
  the suites with the two-Space rule at three, the header inset kept at 5,
  the setting dropped from the visibility rule, the toggle offered for more
  than one Space, the cell's identifier removed, the name frame moved, the
  placeholder put in the field's text, the mask's editable gate removed, the
  toggle dropped from the menu, the store's toggle made one-way, the editing
  width at 24, the header-buttons gate dropped, the 0.1 s delay at 0 in the
  model and in the header, the edit button's identifier removed, an empty
  menu from the button, tracking active outside the key window, the hover
  fill shown unhovered, the button hidden with `isHidden` and the shown
  button not hit-tested, and require each to fail. A visual comparison with

#### Dock Space menu

Mach-O ivar lists, field descriptors and key-path patterns, and the
builder's earlier REA/Ghidra decompile (`ev_140c383f…`).

- The item. `SidebarDock.SidebarDockItemView`'s `menuForEvent:`
  has `mouseDown:`/`mouseUp:` but no `rightMouseDown:` [D], so the menu comes
  through AppKit's `menuForEvent:` handling for a right-click or
  Control-click [C, AppKit's contract].
- The provider. `SidebarViewController` (ivars `store`, `viewStore`) builds
  menu while `SidebarViewController.ViewState.isCreatingNewSpace` holds (key
  metadata byte `0x34`, index 9 of its 17 fields) [D]. It builds
  with (2, 1, 1, 1, nil, nil, 1, rename closure); the header's provider
- The arguments. The first is `ContextMenuUtils.SpaceMenuContext`
  `sidebarDockContextMenu`, `clickableIcon`), so the dock passes
  `.sidebarDockContextMenu` and the header `.spaceHeaderContextMenu` [D]; the
  read as `SpaceAction.onWantsToChangeSpaceIcon` [I]. `w2` gates Change
  the item whose comment is "Menu item to manage which profile is assigned
  nil, Edit Theme Color…'s action is built from the menu's Space ID
  first field, `spaceID`, with its `newFolderShortcut` on the item
  items, its toggle and Manage Spaces… always allowed, all for the item's
  own Space.
- Rename. With a closure (`x7`) Rename Space… runs it, else it sends a Space
  item's ID equals `SidebarViewController.ViewState.focusedSpaceID` (key path
  the header and the others through the store [R].
  context (4, past the enum's four cases) and `w6` = 0 [D], so its menu has
  neither the toggle nor Manage Spaces…; its surface was not identified.

Parc implementation:

  titles in its code order, an item without its action disabled, and the
  same entries as VoiceOver custom actions. The header's menu and custom
  actions come from it.
- `SidebarSpaceMenu.dock(spaces:spaceID:activeSpaceID:creatingSpace:showOnSingleUnnamedSpace:…)`
  is the dock's decision: no menu while a Space is created or for a Space
  the window lacks; Rename Space… renames the item's Space through Parc's
  Space waits for the inline rename contract below); the toggle is
  `SpaceHeader.toggleTitle` for the item's own Space and flips the
  app-wide setting through `toggleSpaceHeaderOnSingleUnnamedSpaces`.
  but Parc's theme editor previews and edits the window's active Space and
  its folder prompt creates in the active Space, so only the active Space's
  item enables them; another Space's item shows them disabled. Whether
- `SidebarDockItemMenu` puts that menu on the Space button as its `menu`:
  AppKit's `menu(for:)` returns it for a right-click or Control-click, and
  the button's exposed cell then offers Show Menu (`AXShowMenu`) [C]. It
  rebuilds its items as it opens (`menuNeedsUpdate`), so they follow the
  store, and removes the menu while a Space is created. `SidebarView` keeps
  one per Space by ID, as it keeps the buttons, and installs it on each
  render and when creation starts or ends. The creation item has no menu.
- `python3 tests/SidebarChrome/check.py` runs the dock menu suite: the
  production `SidebarDockItemMenu` and `SidebarSpaceMenu.dock` on the
  production `SidebarDockStrip` in an off-screen window that is never shown
  or key, with a real session store. A new session's lone Space offers
  menu offers Hide Space Header as it next opens, and choosing that turns it
  off. A right-click and a Control-click get the item's menu from the
  button and its cell offers Show Menu. With two Spaces there is no toggle,
  even with the setting on; each item keeps its own menu, renames its own
  Space, enables theme and folder only for the active Space, and nothing
  switches Space. The toggle follows the item's Space (an untitled, titled,
  custom-icon, empty-named and lone "Space 2" Space), a Space the window
  lacks has no menu, and creating a Space removes every menu and Show Menu
  until it ends. The script also asserts `SidebarView`'s wiring and the
  header's use of the shared builder. Negative controls drop the toggle
  item, its action, the creation rule, the item's own Space for Rename, the
  active-Space rule for the theme editor, the item's own Space for the
  toggle, the menu's removal and its rebuild on opening, and require each to
  fail the suite.

#### Sidebar Space menu

Mach-O ivar lists, field descriptors, protocol and conformance descriptors
(`ev_529ab8e4…`) and its helpers.

  `menuProvider`, `subscriptions`, `userInteractionEnabled`,
  `trailingEdgeFeedbackView`) is `SidebarViewController`'s root view: its
  requirement with a nil item ID (`x0` = `x1` = 0) and returns that menu
  to itself when the event's flags hold Control (bit 18) and otherwise calls
  `userInteractionEnabled` holds [D]. The class has no accessibility
  override [D].
- Reaching it. A right-click goes to the view under the pointer; a view
  whose `menuForEvent:` gives no menu passes `rightMouseDown:` up the
  responder chain, and so does its `mouseDown:` for a Control-click [C,
  AppKit; an off-screen probe sent both to a stack view, a clip view, a
  scroll view, a label and the standard close button, and a right-click to
  a button, and each reached the parent; the list menu suite below repeats
  it on the list's own views].
  `TablistOutlineView` overrides neither `menuForEvent:` nor
  and tablist code) refers to `setMenu:`, `clickedRow` or `menuNeedsUpdate:`
  in the index [D], so a right-click on the list's empty area (below
  the rows, the 120-point bottom inset, the gaps between rows and cells
  without a menu) reaches `SidebarView` [I]. Item cells keep their own
  button's `menuProvider` [D]; `ListHeaderCellView`, `TabGroupHeaderCellView`
  and `SidebarSectionHeaderView` override `menuForEvent:` [D]), as do the
  dock's items and the App Tray (`AppTrayView`, `AppTrayItemWrapperView`)
  [D]. "Matches no sidebar item" is therefore every right-click that reaches
  the sidebar view: it always passes no ID [D].
  `WindowState`) first reads `commandBarIntegrationPresentationInfo` (witness
  `+0x198`, field at `0x290`) and, while it is set, sends a window action
  (payload not decoded) [D], read as dismissing that presentation [I]. With
  field at `0x308`), when `style` is other than `.standard` with
  than `.spaces` (witness `+0x168`, `ldrb` at `0x38`; `.home` gives none)
  [D]; the field offsets follow WindowState's field order and types
  (`id`, `appearancePhase`, `initialAppearanceActions`, `initialAnimation`,
  `isKey`, `isMain`, `focusedSpaceID`, `layoutPresentation`) [R]. Then it builds
  `SpaceMenu.ViewState` for `WindowSidebarStateProviding`'s Space ID
  calls the builder with (`.sidebarContextMenu`, 1, 1, 1, nil, nil, 1, no
  rename closure) [D]: Set Profile, Change Space Icon… and Edit Theme Color…
  allowed, the header toggle and Manage Spaces… allowed, Rename Space…
  sending the store's rename for the focused Space.

Parc implementation:

  `SidebarView` event handling: `menu(for:)` returns its `spaceMenu`'s menu,
  and `mouseDown(with:)` sends a Control-click to `rightMouseDown(with:)` and
  anything else to super. AppKit's own `-[NSView mouseDown:]` already opens
  the receiving view's menu for a Control-click (a sampled off-screen run of
  the surface without the forwarding entered `_showMenuForEvent:` and menu
  only which method opens the menu. `SidebarView` subclasses it, so its list's empty
  area and any other view in the sidebar without a menu of its own get the
  menu, while rows, folders, splits, Favorites tiles, the App Tray empty
  state, the Space header and the dock's Space items keep theirs. It is no
  actions through the header's custom actions and the dock items' Show
  Menu ([accessibility](sidebar-accessibility.md)).
- `SidebarSpaceMenu.sidebar(spaces:activeSpaceID:creatingSpace:privateWindow:showOnSingleUnnamedSpace:…)`
  is the decision: no menu while a Space is created, in a private window
  `focusedSpaceID`); otherwise the active Space's dock item menu (`dock`):
  that Space. Rename Space… opens Parc's rename prompt for the active
  nothing to test. `SidebarView.sidebarSpaceMenu()` calls it with the
  header's and the dock's actions.
- Every view Parc's sidebar holds that has no menu of its own now reaches
  the menu on a right-click, through AppKit: Clear, New Tab, the Today hint,
  the private heading, the address button, the toolbar's and bottom bar's
  other classes (`HoverableButton`, `TranslucentButton`, `SidebarClearButton`
  traced one passes no menu its right-click reaches the same menu
  (`HoverableControl` with no `menuProvider`, the `HoverableView` Clear)
  its own handler without super [D] and which sidebar controls use it was
  swallow overrides this per control. A Control-click on a button stays the
  button's click: `NSButton` tracks its own `mouseDown:` [C].
- Not built: the command bar presentation's dismissal before the menu
  (Command bar owner) and the Space menu items in the contracts below.
  Excluded, as in the header: Share Space… and Live Folders.
- `python3 tests/SidebarChrome/check.py` runs the list menu suite: the
  production `SidebarSpaceMenuSurface` (recording the right-click it
  receives in place of opening the menu) and `SidebarSpaceMenu.sidebar`,
  holding the production `SidebarOutlineView` in a tablist scroll view with
  New Tab, two Today items), in an off-screen window that is never shown or
  key, with a real session store. AppKit's own `rightMouseDown:` from the
  view under the point carries a right-click in the bottom inset below the
  last row, below the outline, in an intercell gap, in a cell's margin, on
  the pinned header row, on New Tab and on Clear to the sidebar, and its
  `mouseDown:` carries a Control-click there (not on the buttons) to the
  surface's `mouseDown:`, which opens the menu; a plain click opens none. On
  each row the row's own menu is asked and opened and nothing reaches the
  Header; choosing it turns the setting on, the next menu offers Hide Space
  Header and choosing that turns it off; the items act on the active Space.
  With two Spaces there is no toggle, even with the setting on, Rename
  Space… names whichever Space is active and nothing switches Space. The
  toggle follows the active Space (untitled, titled, custom-icon,
  empty-named, one of two), and there is no menu without an active Space,
  for a Space the window lacks, while a Space is created or in a private
  window. The script asserts `SidebarView`'s superclass, its
  `sidebarSpaceMenu()` call and that `SidebarView` overrides none of the
  surface's event methods. Negative controls drop the surface's menu, the
  private-window gate, the active Space, the creation gate and the toggle's
  action, and require each to fail; no control drops the Control-click
  forwarding, whose removal AppKit's own Control-click handling covers (its
  mutant opens a real menu and waits in menu tracking). The runner counts a
  mutant that does not finish within 60 seconds as failing.

#### Contracts for the Spaces and profiles owner

The Spaces and profiles family is unowned (Available) in `docs/parity.md`;
SPACE02 and SPACE18 are its nearest rows. Each contract below is open; the
Sidebar owner wires the header once the interface exists.

- **Titles.** Owner: Spaces and profiles. Interface: `BrowserSpace` gains an
  that reads a stored name equal to the Space's placeholder as no title.
  Behaviour: an untitled Space shows "Space N" by its position; the sidebar's
  rule becomes "has a title" and `SpaceHeader.isTitled` goes. Until then a
  name equal to the position's placeholder counts as untitled, which misreads
  two cases: `BrowserStore.createSpace` names a Space created without a name
  is deleted the surviving "Space 2" sits at position 0, whose placeholder is
  untitled Space would not. Status: open.
- **Inline rename.** Owner: Spaces and profiles (model), Sidebar (header).
  Interface: a rename session for a Space in the store (begin, commit,
  `didCancelRenameSpace`) and its editing state. Behaviour: the header shows
  editable (the `SidebarMaskedTextField` fade then applies), Rename
  Space… starts it in place of the prompt, from the header and from the
  follows it, which turns the edit button into "Done" (built; its font,
  `FontSet.sectionHeaderButton`, still needs tracing). Status: open.
- **Icon picking.** Owner: Spaces and profiles. Interface: setting an
  `didClickEditableIcon` opens the icon picker from the header's icon, and
  "Change Space Icon…" joins `SidebarSpaceMenu`, the header's, the dock's
  and the sidebar's menu. Status: open.
- **Profile indicator.** Owner: Spaces and profiles. Interface: the Space's
  `ProfilesUI.ProfileIndicatorHostingView` in the stack when the window has
  more than one profile (`shouldShowProfileIndicators` is `1 < profiles` in
  menu; its geometry is in ProfilesUI and was not traced. Status: open.
- **Space menu.** Owner: Spaces and profiles. Interface: Set Profile,
  Delete Space and Manage Spaces… actions callable for a Space, and theme
  editing and folder creation for a Space other than the active one.
  Behaviour: each joins `SidebarSpaceMenu` (the header's, the dock's and
  Edit Theme Color… and New Folder for their own Space once tracing shows
  Folders stay excluded. Status: open.
- **Collapse Pinned Section.** Owner: whoever builds it (no ledger row
  names it). Interface: a per-Space collapsed pinned section
  (`SidebarSpaceState.collapsePinnedSectionEnabled`, and a
  `spacesWithCollapsedPinnedSections` field read by its name [I]).
  Behaviour: the header's click,
  chevron (24 points, before the icon, which it replaces while shown) and
  hover background follow it, and the visibility predicate above also gates
  the `collapsePinnedSection:` menu item. Status: open.
- **Drops on the header.** Owner: Sidebar, with the move owners. Interface:
  accessory: the top of Pinned. Status: covered by SP23 for every item kind,
  with the dock's Space items ([split groups](split-groups.md#whole-split-copy-and-external-drags--sp23)).

## App Tray empty state

main executable (`4e452201…9547`); REA/Ghidra raw-slice decompiles with the
disassembly and Mach-O tables (ivar lists, key-path patterns) named here.

### Reference mechanism

  `ev_c6c129ea…`) creates `_emptyStateView` the first time the tray has no
  items, pins its top, leading and trailing edges to the tray's view and adds
  `emptyStateConstraints`. On every update it hides the view exactly when the
  tray has items, activates the constraints exactly when it has none, and
  sets the view model's `hasDismissedEmptyState` from its input [R]; the
  Mach-O ivar lists.
- The tray's input is the profile's presence in
  the view-state builder) [D]. The sidebar separately computes, for each
  profile group of `SidebarPagingContainerViewController.ViewState`,
  container, false when the container has items, else whether the profile is
  it as the group's `appTrayDisplayMode` [R]; the field metadata names
  `ViewState.Group {id, profile, pages, appTrayDisplayMode}` and
  `AppTrayDisplayMode {always, onDrag}` [D], so true is `onDrag`.
  with its `@Published isDraggingNearAppTrayRegion` and rebuilds its
  lists a group only when its mode is present and is `always` or the flag is
  initialisers, the deinit and the update's `projectedValue`, and its storage
  `__text` and the key-path patterns]. So in 1.122 a dismissed profile's empty
  tray never shows, and the Dismiss-less card below is unreachable. The
  Whether 1.170 sets the flag was not checked.
  `.system(size: 16, weight: .medium)` in the theme's maxContrast and
  minContrast colours, then the title over the subtitle, 4 apart, at most
  [R]. Its action and the tray menu's Hide item send AppTray action 6
  subtitle kerned −0.2, both centred): "Drag to add Favorites" and
  "Favorites keep your most used sites and apps close". The tray's menu
  carries both strings, `sidebarFavoritesEmptyStateDismissButton`,
  `topAppsEmptyStateDismissedForProfiles` and `star.circle.fill` [D, strings
  only].
  `FavoritesEmptyStateView.applyStyle` with their palette roles [R].
  symbol is a plain `Image(systemName:)` [R], which SwiftUI exposes as an
  image. Its description, and the reducer of AppTray action 6, were not
  traced.

### Parc implementation

- `SidebarChromeLayout.showsAppTrayEmptyState(favorites:dismissed:privateWindow:)`
  shows it for a Space whose profile has no Favorites and has not dismissed
  it; private windows have no tray. `appTrayHeight(gridHeight:emptyState:)`
  gives the tray the grid's height, else the view's fitting height but at
  least 63, else 0, and `tablistTop` puts the list directly below a tray
  with height and 5 points below the header without one.
  `AppTrayEmptyState` is the body's geometry: card at (8, 8) to
  (width − 8, height − 4), content padded 10 and centred, text wrapped at
  min(150, width − 36), Dismiss 14 × 14 at 8 from the card's top-trailing
  corner. At the default 228 the view measures 86 (with a 16-point title
  and a two-line 30-point subtitle) plus the symbol image's height: 106,
  with the list at 188, for the 20-point symbol first measured, and 105 and
  187 for macOS 27's 19-point one. Below 177 the title wraps to two lines,
  and at 164 the subtitle takes three: 117 plus the symbol (137, list at
  219; 136 and 218 on macOS 27) [C]. Both labels wrap by word within the
  text width, as SwiftUI's `Text` does in its frame.
- `FavoritesEmptyStateView` (`SidebarFavoritesEmptyState.swift`) draws the
  card in AppKit: the radius-12 continuous fill, the inner 1-point gradient
  stroke at opacity 0.3, the outer 1-point radius-13 stroke dashed [5] (solid
  while dragging), the palette symbol, the two labels and the Dismiss button
  corners are circular because CoreGraphics has no continuous rounded-rect
  path (adaptation). The symbol's layout size is AppKit's symbol image size,
  which SwiftUI's may not equal [I].
- The view owns its sidebar entry points, which `SidebarView` only calls:
  `update(favorites:profileID:settings:privateWindow:dismiss:)` from
  `render` for the active Space's profile, `trayHeight(gridHeight:width:)`
  from `layout()`, and `showsDrop(_:)` from the drop handlers. Dismiss or
  Hide calls `BrowserWindowController`'s hook,
  `BrowserStore.dismissFavoritesEmptyState(profileID:)`, which appends the
  profile once to `BrowserSettings.topAppsEmptyStateDismissedForProfiles`
  Every window of that profile renders from the store and collapses its
  tray; other profiles keep theirs. Parc keeps the list in its session file
  never shows in 1.122, Parc shows the view only while undismissed and its
  Dismiss button is always present.
- Drops: the whole empty state is the Favorites drop target, as the tray
  no insertion cue [I]: whether `AppTrayCollectionViewLayout`'s drop
  indicator still draws over an empty tray was not traced. Leaving, ending or
  concluding the drag restores it. Dropping makes the first Favorite, which
  replaces the view with the grid. A collapsed tray keeps the header's
  5-point band as its target.
- Accessibility: the symbol as an image (its description, AppKit's default
  for an undescribed symbol, is for the runtime comparison), two static
  texts and the Dismiss button, in that order; the card is not an element.
  The button joins the sidebar's Tab chain with the Favorites
  (`SidebarAccessibility.keyViewChain`), is skipped while hidden, and draws a
  round ring over its frame: AppKit gives a borderless image button no ring
  Dismiss hides the view, AppKit moves focus to Dismiss's next valid key view,
  which the sidebar's linked chain makes the list stop or whatever follows
  the Favorites; it falls back to the window only when no valid key view
  follows [C, inert probe: linked → next stop; unlinked or invalid next →
  window]. Under Full Keyboard Access, the only way Dismiss takes focus, the
  dock's buttons always follow, so the place in the chain is kept.
- `python3 tests/SidebarFavoritesEmptyState/check.py` runs the production
  view in off-screen windows that are never key (strings, fonts, kern,
  frames against the model, wrapped labels that hold all their text at 228
  and 164, fitting height above 63, accessibility children, label and
  identifier, Dismiss's focus ring, Hide, the dragging style and its
  return). Through a real store's profile in two windows it checks the tray
  height and list top (86 plus the system symbol's height, the list directly
  below; the grid with Favorites; none in a
  private window), a keyboard Dismiss that collapses both windows to the 87
  list top and leaves focus on the next stop that
  `SidebarAccessibility.link` placed after Dismiss, and another profile
  keeping its card. It also runs the dismissal through the real store (one profile,
  older sessions) and asserts `SidebarView`'s and
  `BrowserWindowController`'s calls. Reverting the visibility rule, the
  title's wrapping, the star's AX image, the solid dragging border, the
  Dismiss identifier, its ring, the store write or the tray height each
  makes one of these checks fail, and so does Dismiss without a linked next
  stop.
  `python3 tests/SidebarChrome/check.py` checks the visibility rule, the
  tray height and list position and the body geometry.

## Runtime acceptance

The row's acceptance compares a running Parc built from this source with
accessibility, focus and motion inspection (no page loads or form input).
Capture both the way the 1.170 reference was captured
(`work/claude-sidebar-rea/appearance/arc1170-sidebar-geometry.md`): a
window-scoped screenshot and AX frames of the same 1470 × 831-point window on
the same display, converting pixels to points with that capture's scale (the
reference used 0.9905). Unless stated, the sidebar is locked at the default
228 points, the window is not full screen and the OS is macOS 26 or later.

Tolerances: ±1 point for a static frame edge (the reference's own edges are
read to the nearest pixel) and ±0.5 point for a repeated pitch. The two
vertical offsets the reference showed are explained under the table: the
static trace places the controls [D], and the capture's differences are
attributed to how it was read [I].

|---|---|---|
| Header row | 40 tall from y 4; lights, toggle and navigation centred at y 24 | lights centred at y ≈ 24.2 (AX 16.2 + 8.1); toggle and navigation centred at ≈ 23.2 (top 7.1 + 16.2) |
| Traffic lights | 14-point widgets at x 13, 36, 59 (9 apart); AX frames 16 × 16 at 12, 35, 58, y 16 | AX 12.1, 35.3, 57.5; y 16.2 |
| Toggle | 32 × 32 at x 77, y 8 | x 76.7, y 7.1 |
| Back, Forward, Reload | 32 × 32 at width − 106, − 72, − 38 (122, 156, 190), y 8 | x 122.2, 156.5, 189.8; y 7.1 |
| Address field | x 8…220, y 46…82 (36 tall) | ≈ 8.1…220.1, 45.4…80.8 (35.3 tall) |
| Page | x 228 (locked) with 10-point top, trailing and bottom insets | AXWebArea x 228.2, y 10.1 |
| List top, dismissed tray | outline at y 87 | 86.8 |
| Row pitch | 41 (40-point cell + 1); visible row 36, 2 below the cell top; pinned header row 3, divider row 25 | 41.4 per row (41 px), separators 3 and 25 px |
| Row content | favicon frame x ≈ 17, title x ≈ 43–44 | 17.2, 43.4 |
| App Tray, one Favorite row | tray 82…145, tiles 47 × 47 from x 8 every 55, list at 145 | not captured |
| Dock | 50 tall; + button 32 × 32 at x width − 40, top at height − 41 | + at 187.8, top at height − 41.5 |
| Two Spaces, one Favorite row | Space header at 145…181, outline at 181 | not captured |

and the remaining capture differences are attributed, not measured, so a
capture of the unlabelled containers must still confirm them:

- The toggle and Back/Forward/Reload read 0.93 point higher in 1.170 (top
  7.07, centre 23.2) than Parc's 8 and 24, while the lights agree (24.2).
  1.170 lays the row out as 1.122 does: `SidebarHeaderView`'s setup
  gives `BrowserNavigationButtons` 8 + 5 leading, −6 trailing and a 40-point
  every button 32 tall and centres it on its own centre-Y
  buttons at 8…40, centred at 24 with the lights [D], and Parc keeps them.
  The capture's frames are accessibility frames rounded to the still's
  pixels, and each of these buttons is a pair, an unlabelled container and
  the labelled button inside it [O]; the 0.93-point difference is attributed
  to the recorded labelled SwiftUI button not reporting its 32-point host's
  frame [I], while the plain AppKit lights on the same centre read 24.2.
  Acceptance measures the unlabelled container.
- The field's bottom read 80.8 against Parc's 82. 1.170 keeps 1.122's field:
  field is 36 tall at priority 750 and at least its text + 20
  under the 4 + 40 row [D]. The capture's field edges were read by eye from
  the translucent pill ("≈"), not from an accessibility frame [O], to which
  the 1.2-point difference is attributed [I]; its text's
  frame (y 54, 18 px) centres at 63.6 points, within 0.4 of the field's
  centre 64. Acceptance measures the field's own frame. Parc's geometry is
  unchanged.

Behaviour to observe in the running Parc:

1. **Empty state.** In a disposable Parc profile (`--parc-profile <dir>`)
   after onboarding, or any Parc profile without Favorites that has not
   dismissed it, the tray shows the card with the measures above in light
   and dark themes. Hovering a tab drag over it fades the text and turns the
   dashed border solid in 0.18 s with no insertion line; the drop makes a
   Favorite and the grid replaces the card. Dismiss (or Hide from its
   context menu) collapses the tray to the 87 list top in every window of
   that profile, a second profile still shows its card, and the collapsed
   state survives quitting and relaunching. Dragging a tab over the
   VoiceOver reads the star image, the title, subtitle and "Dismiss"; compare
   Dismiss after the address and page-action controls, and Space on it moves
   focus to the next stop.
2. **Width after relaunch.** Drag the edge of the window Parc opened at
   launch (the one holding the shared frame autosave name) to 300 and of a
   second window (⌘N) to 260, quit with ⌘Q and reopen Parc: the reopened
   window has the first window's frame and a 300-point sidebar (exact;
   widths are whole points), and a new window takes 260, the last completed
   drag. A drag cancelled by resigning the key window mid-drag, or a
   collapse below 82, changes neither value.
3. **Page hold during an edge drag.** Record the screen at 60 frames per
   second while slowly dragging the edge from 228 to 300 and back over a
   page with fixed-width content in both apps. Expected in Parc on v231:
   the page keeps the size its renderer last drew, anchored at its top-leading
   corner; growing exposes at most a renderer frame's worth of the pane's
   white backing at its trailing edge, shrinking clips the page under the
   pane's rounded edge, content never reflows between two renderer frames,
   show the same stepping; a page that reflows on every pointer event means
   the hold is not active (check `engine_report.py` against the running
   app's framework).
4. **Drag feedback.** Over the trailing edge the resize cursor appears only
   when nothing covers the strip; after 0.25 s a 3-point indicator fades in
   over 0.2 s, centred on the strip's leading edge, 4 points inside the
   sidebar's edge (the strip spans edge − 4 to edge + 4), and 30 points
   shorter than the sidebar container (the strip's 22 plus 8), and fades out
   over 0.2 s on exit; it shows at once while dragging. A slow drag through 228 snaps there with a haptic and a
   horizontal pulse (scale 1 → 1.7 → 1 in 0.16 s); dragging below 82 previews
   hidden and releasing there collapses the sidebar; double-click sets 228.
5. **Space header.** With one untitled Space and no icon there is no
   header and the list starts at 87; a second Space shows the header in both,
   where a Space still named "Space N" for its position shows that in the
   placeholder colour (VoiceOver reads an empty value) and any other name in
   `SidebarForegroundDarker`;
   right-clicking the header of a lone untitled Space shown by the setting
   offers Hide Space Header last, which hides it in every window, and
   right-clicking (or Control-clicking) that Space's dock item then offers
   Show Space Header, which brings it back, as does right-clicking (or
   Control-clicking) the list below its last row; with two Spaces a dock
   item's menu renames its own Space without switching to it, the list's
   empty area offers the active Space's menu without the toggle and a row
   still offers its own menu; Edit Theme Color… from the header recolours a
   custom icon live.

The row is accepted when every measure is within tolerance, the header
two-Space header, which the reference lacks, are compared with the
recovered geometry above until a capture of them exists.

### New Tab foreground (October 29 polish)

localized "New Tab" string to that field. Its plus image is configured at
`work/native-analysis/theme-picker/resources/base-assets.json` gives
`SidebarForeground` as black at 0.30 in Aqua and white at 0.45 in Dark Aqua;
`ForegroundSecondary` is black/white at 0.5. This asset lookup uses the
installed version only for its catalog, not a second code trace. Parc uses the
corresponding contrasting content appearance for the New Tab text and image,
including theme changes. Since October 31 the row is `SidebarNewTabRow`, with
visually compared. An isolated preview using the published component displays
black-on-light and white-on-dark New Tab labels; corrected packaged-app and

Space, while v240 Parc displayed the selected named Personal Space as a green
Space) still showed Library and + with nothing between them; Parc kept drawing
the selected 8-point iconless indicator. The collection is now empty for one
iconless Space and appears once there are two Spaces, a custom icon, or a
Create Space item.

iconless `circleFilled` item when no custom icon is present. Its original Space
button remains the action and accessibility owner; the dock draws the recovered
8-point `ForegroundSecondary` indicator separately when the collection is shown.
Explicit custom icons and other legacy symbols retain the existing icon
presentation.
