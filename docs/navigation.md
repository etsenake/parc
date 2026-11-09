# Navigation controls and history



## Original page and history ownership

`PCNativeNavigationHistory` records the original `PCNativePage`, weak WebContents/document, parent window, current index, pending entry ID and complete ordered NavigationEntry ID list. Its immutable rows contain each actual entry ID, title, display URL and cached favicon. A URL is presentation data only. Selection requires the same row object from that snapshot, the original live document/history, exact selected shell page and native active tab, registered window, no retirement/transfer and no security reservation or attached sheet.



The chooser holds a floating sidebar open and cancels competing sidebar hover/MRU previews. Ordinary page metadata never creates a native selection request. Button state is refreshed again after the existing selection request completes, so it does not remain stale while the native active tab catches up with a shell selection.

The selected page's navigation commands remain available when its retained renderer view is hidden by an existing navigation or renderer-failure surface. That exception requires the same native active tab and shell selection; it does not make parked pages command targets. A successful navigation request clears only the shell navigation error. Actual SadTab recovery state remains owned by Chromium.

## Reference and adaptations




## History chooser presentation




## Alternate destination policy


The engine keeps Chromium's original clone and history paths: `GoBack`/`GoForward`/`Reload` with `NEW_FOREGROUND_TAB`, and `NavigateToIndexWithDisposition` with `NEW_BACKGROUND_TAB`. Chromium's `GetTabAndRevertIfNecessary` appends the clone of the active tab. The native layer gives that exact new `WebContents` a one-page receipt naming its live source page and whether it goes at the top: `PCNativePage.alternateNavigationSourcePage` and `alternateNavigationPlacesAtTop`. The receipt is attached only when the source was the active tab and exactly one same-Profile page was inserted. Adoption in `BrowserWindowController` turns the receipt into the creation referrer and the Today insertion. The disposition the engine reports decides selection, so a background clone never takes focus. Older engine packages lack the receipt and keep the earlier behavior: a foreground tab with no referrer.


  - `webContentFrameIdentifier`: a fresh UUID;
  - `presentationDisposition`: the constant;
  - `source`, `customToastAction` and `tabId`: nil.




## Sidebar header glyphs



Every path takes its font from one per-size table, [16, 16, 16, 14, 14, 12]:





- At rest the glyph is `GrayA11` (sRGB black at 0.565 in Aqua, white at 0.592 in Dark Aqua) on a clear background.
- Disabled, it is `GrayA8` (black 0.220, white 0.249) on a clear background.
- Hovered, the background is `GrayA4` (0.071 / 0.077).
- Pressed, the background is `GrayA5` (0.090 / 0.103) and the glyph `GrayA12` (0.910 / 0.923).


Parc uses `SidebarChromeLayout.navigationGlyphPointSize` (16, or 14 on the narrow row's 28-point buttons) for the toggle, the arrows and the sidebar `ReloadGlyph`. Previously the toggle and arrows took AppKit's symbol at the button's 12-point font and Reload used 13 points. AppKit's 16-point medium symbol image fits the glyph into its whole-point size and draws it smaller than SwiftUI does: `arrow.clockwise` is 26 × 32 pixels at 2× rather than 28 × 34. `NavigationControlArtwork.symbol(_:pointSize:)` therefore rasterizes `Image(systemName:).font(.system(size:weight: .medium))` through `ImageRenderer` at 1× and 2×, as `DownloadArrival` does for its glyph, and caches the result as a template image. `ReloadGlyph` draws the force-reload artwork at its natural size and clips every glyph to the button's bounds with a 6-point radius. The radius is circular rather than continuous; at rest no glyph reaches the corners.




- It fills `GrayA4` while enabled and hovered, and is clear otherwise.
- It tints the image `GrayA12` while pressed and `GrayA11` otherwise.

Parc's `NavigationControlButton.windowControlStyle` draws exactly this: the unconfigured symbol scaled down proportionally into the inset frame, as `NSImageView` does, with the same named colours.



## Sidebar URL bar




- **Revealed.** When the predicate holds, every button shows.



Parc's `SidebarAddressPillView` reproduces the surface, fill, hover and corner radius, following the palette's darkness.

full 36-point URL pill with continuous 12-point corners behind both text lines
and the action buttons. The host uses the ordinary 13-point address styling;
**Share Quote** is 13-point semibold below it, and both quote affordances take
the Space's maximum-contrast tint. Their existing original-selection lease and
copy-text-fragment action remain intact. The prior 18-point/7-corner adaptation
is superseded. Parc maps the reveal predicate as follows:

- `isSidebarHovered` is the pointer inside `SidebarView`.
- `!isSidebarAnchored` is the floating sidebar.


Each held popover registers itself with `SidebarView.setAddressPopover(_:open:)`, so its arrow never points at a faded button:

- The Site Control Center popover holds the reveal from its request until it closes, which also covers refused and delayed shows, or until it detaches.


- **Focus reveals.** `SidebarView` observes its window's first responder (key-value observation). The bar reveals while the address button, the Site Control Center button or anything inside the pinned-extension toolbar has keyboard focus. A VoiceOver cursor that moves without keyboard focus does not reveal them, because the app is not notified of it.
- **No invisible clicks.** At zero opacity, the Site Control Center button and the extension toolbar pass clicks through (`hitTestsWhenTransparent = false`), so an invisible button never takes a click.

Two anchored surfaces cannot hold the reveal yet:

- **Extension popups**, anchored to a pinned extension.
- **The Site Settings bubble**, anchored to `pageControlsAnchor`.

Both are owned by the engine and report no open or close to the app, so their buttons fade as the predicate implies when the pointer leaves the sidebar.


- The text colour is a black overlay of 0.61.

## Loading, Stop and Refresh feedback






`PageLoadingIndicatorHost` applies the same rule. It shows nothing in popup windows; it shows one indicator over each side-by-side pane, or over the first pane of a stacked split; and each indicator is driven by its own pane's loading state, focused or not. Each `PageLoadingIndicator` reproduces the recovered constants:

- While loading, `pulseProgress` follows an undamped spring with a 3.2 s response around 0.5. The 48-point track breathes between scale 0.88 and 1, and its fill opacity runs from 0 to 0.92.



Josh reported the former indicator as barely visible on a mint-to-pink Space. Parc had tinted both layers with the Space's `foregroundPrimary` and kept the 0.46 branch, so the bar was a luminance-0.5 green on the light band. In an offscreen render of the real indicator mid-sweep, contrast against the band rises from 1.12:1 to 8.83:1 on his band, from 1.32:1 to 9.85:1 on a light blue Space and from 1.61:1 to 11.76:1 on a pale pink Space; bar against track rises from 1.03:1 to 5.13:1 on his band. On dark Spaces the white at 0.8 measures 4.6:1 to 9.8:1 against the band, slightly below the former opaque near-white.



**Adaptations.**

- Reduce Motion keeps a static, fully shown 48-point track while loading and never sweeps; track and bar changes then apply without the spring.
- Indicator timers pause while the window is occluded or minimized; window close stops and resets them.
- The thin-Reload/chevron spacing is unrecovered; Parc abuts them as a pair.


## Trackpad and Magic Mouse history

CEF's native Mac WebContents delegate inherits Chromium's `ChromeRenderWidgetHostViewMacDelegate`. Parc wraps that delegate while retaining its one real `HistorySwiper`; there is no shell scroll-event recognizer or independent page-capture transition. The renderer receives scrolling first. Only its actual unconsumed gesture ACK and propagating CSS overscroll permit a history gesture. Plain wheel events and momentum cannot start one. The macOS `swipeTrackingFromScrollEventsEnabled` setting, natural-direction flag, normalized touch movement, vertical cancellation and Magic Mouse direction lock remain authoritative.

`PCNativeHistorySwipeDelegate` identifies the original primary RenderWidgetHost by its process/routing IDs. At recognition it captures the existing `PCNativeNavigationHistory` lease: weak exact page/document/window, ordered entry IDs, current index and pending entry ID. Every tracking/commit operation rechecks the live native attachment, selected shell page (including selected split pane or active Peek), native active tab, key visible window, renderer focus, retirement/transfer state, sheet/security authority and competing shell navigation UI. A background page cannot become a gesture target by URL or by whichever tab happens to be selected later.

The completed gesture invokes the same genuine Back/Forward command as ordinary navigation. The snapshot is a stale-history guard; it does not choose an adjacent raw index in place of Chromium's skippable-entry policy. Original POST state, beforeunload/repost and navigation policy remain owned by Chromium. Navigation, main-document replacement, hiding, deactivation, transfer, window close/minimize/key loss, app deactivation and security presentation cancel. A session is consumed once. Cancelling retains the observer through the active callback stack and does not destroy its own observer while executing.

The cancellation hook also owns the Magic Mouse tracking generation and overlay. AppKit may retain that tracking block beyond the native page interaction, so a stale block stops and cannot navigate or remove a newer overlay. Trackpad progress/reversal and Magic Mouse dampening remain the existing producer's behavior. The overlay is clipped to the original renderer; its position uses the parent's local bounds, including split/Peek offsets. Reduce Motion uses a stationary edge indicator with opacity feedback, suppresses the completion size change, and removes it without the exit fade. This accessibility behavior is a Parc adaptation.

### Recovered default swipe mechanism



The default overlay is `HistoryOverlayController`, constructed at `0x635c6c0` and updated at `0xa4c4fbc`. Original constants establish a 70-point radius, 140-point height, 150-point completed height, alpha 0.25–0.65 or 0.75 when finished, normalized touch completion distance 0.08, and 0.4-second dismissal at `0xa4c5204`. The pinned independent Chromium implementation has the same geometry/progress mechanism. Full Mach-O mappings, method metadata, literal bytes and annotated assembly corroborate the raw-slice REA result; its external call/global names are not independently resolved by the raw provider.

### Continuous visuals, haptics and interruption






## Focus traversal across page, controls and auxiliary contexts


- **Page ↔ sidebar ↔ navigation controls.** Tab and Shift-Tab follow the linked window loop: page-side key views in geometric order (pane toolbars, popup chrome, renderers), then the sidebar's gate, header controls (toggle, Back, Forward, Reload), the URL pill, list stop and dock ([window key-view loop](sidebar-accessibility.md#window-key-view-loop-delivered-with-side17-window-owner-informed)). Chromium's F6 pane rotation enters the same loop (`rotateFocusForward`). Control–Space opens the sidebar command session and Escape restores its original responder ([sidebar keyboard focus](keyboard-navigation.md#sidebar-keyboard-focus)). A hidden sidebar is bypassed and never receives restored focus.
- **History chooser, Find and Library.** The chooser's Escape restores the prior responder while the same page and window remain eligible, and selection runs after popover teardown returns key focus. Find focuses its field, and closing it returns to its original page through the focus manager. Closing Library restores the selected content.
- **Peek.** Entry, refused close, dismissal, expansion and split hand focus through `PeekFocusReturn` to the exact original page ([peek](peek.md#original-responder-entry-and-return)). The Peek's host takes first responder only for Escape and is not a key view. Tab and Shift-Tab from the host now enter the window loop where it crosses into the Peek, at its first key view or last going backward, through AppKit's `selectKeyView(following:)` and `selectKeyView(preceding:)`, so the renderer receives the usual selection direction.

### Focus reference and adaptations





## Mouse and trackpad gesture inventory (NAV14)



|---|---|---|
| Mouse buttons 4/5 over the page | Chromium `WebContentsImpl::HandleMouseEvent` navigates the outermost contents on an unconsumed back/forward mouse-up. | Unchanged engine behavior. |
| Middle-click a Back/Forward arrow or history row | Recovered earlier (see above). | Done (NAV01–NAV06). |
| Trackpad/Magic Mouse page history swipe | `HistorySwiper` (above). | Done (NAV07–NAV08); visuals are NAV13. |


