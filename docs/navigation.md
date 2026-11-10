# Navigation controls and history

Back, Forward, Reload and Stop act on the selected native page, including an
active Peek. Back and Forward expose history through secondary/control click,
a 300 ms hold, or their accessibility action. Command-click and middle-click
request an alternate destination. Refresh is Cmd-R, Stop Loading Cmd-. and
Force Refresh Cmd-Shift-R.

## Original page and history ownership

`PCNativeNavigationHistory` captures the original page, weak WebContents and
document, parent window, current index, pending entry ID and ordered entry IDs.
Its immutable rows retain actual entry IDs, titles, display URLs and cached
favicons. URLs describe entries; they are never replayed to simulate history.

Selection consumes the snapshot once and requires the same row, original live
document/history, selected shell page and native active tab, registered window,
and no retirement, transfer, security reservation or attached sheet. Ordinary
selection uses Chromium `GoToIndex`; alternate selection uses
`NavigateToIndexWithDisposition`, preserving native history, POST and navigation
policy in the actual page clone.

Pointer-down captures the source, history snapshot and alternate flag. Opening
history consumes that press before mouse-up, so one press cannot both open the
chooser and navigate. Keyboard and accessibility activation start a fresh
ordinary interaction. A delayed hold cannot retarget a newly selected tab.

Document/history changes, tab or Peek selection, sidebar hiding, window close
or minimization, a sheet, security reservation and app deactivation dismiss the
chooser. Losing its key status also dismisses it. Escape restores the saved
responder only while the original page and window remain eligible. Selection
runs after key focus returns to the parent, with identity checks repeated.

The chooser holds a floating sidebar open and cancels competing hover previews.
Page metadata updates never request native selection. After an existing selection
request finishes, navigation state refreshes again to reflect the native tab.
A selected page whose retained renderer is hidden behind an error surface can
still navigate; parked pages cannot. Navigation clears only the shell error,
while Chromium owns renderer-failure recovery.

## History chooser presentation

The chooser is a borderless key child window with a 220-point card, 12-point
corners and a shadow. It sits 4 points below the arrow, centered on it and clamped
to the parent and visible screen. A long list scrolls rather than running below
the screen; at least one row remains visible.

Rows are 40 points high with 8-point edge/horizontal insets, a 16-point favicon,
6-point spacing and a 13-point medium title. Missing favicons use a neutral globe
without a network request. Pointer and keyboard focus share the same rounded
highlight. The first row starts focused; Up/Down wrap, Return selects, Escape
cancels, and Command-Return or middle-click selects an alternate destination.
Native accessibility selection follows the focused row. The menu resolves its
palette against AppKit's default app appearance, including over private windows.

Dragging from the opening arrow can focus and select a row on release. A release
elsewhere generally leaves the chooser open. The original arrow's press remains
consumed when its final release is returned to AppKit tracking.

Opening scales 0.95 to 1 over 0.1 seconds and fades over 0.05 seconds. Closing
uses the current presentation values over 0.07 seconds. Both use the cubic curve
(0.215, 0.61, 0.355, 1). Reduce Motion skips these animations; parent destruction,
minimization and sheets dismiss immediately.

## Alternate destination policy

| Action | Selection and placement |
|---|---|
| Alternate Back/Forward | Foreground tab at the top of Today; original tab is the referrer. |
| Alternate Reload | Foreground tab after the source and its existing referral run. |
| Alternate history row | Background tab after the source and its referral run. |

Shift does not change these policies. The engine attaches a one-page receipt to
the exact same-Profile clone only when the source was active and exactly one
page was inserted. `alternateNavigationSourcePage` and
`alternateNavigationPlacesAtTop` carry the source and insertion policy to shell
adoption; Chromium's disposition determines selection. Peek arrow navigation
has no sidebar referrer, while Peek Reload/history use the parent item.

## Sidebar controls and URL pill

Navigation glyphs are 16 points in 32-point controls, reduced to 14 in 28-point
controls when narrow. Hover/press colors and spring feedback are separate from
loading state. The URL pill is 36 points high with 12-point corners and a
13-point host label. An empty page shows Search or Enter URL. Share Quote occupies
the full row with its own content; toolbar mode hides the sidebar URL row.
Split views retain one URL row following the focused pane while each pane owns
its navigation controls.

Sidebar hover, floating presentation, menus and keyboard-focused controls reveal
the URL row. Zero-opacity controls remain accessible and keyboard reachable,
but do not accept invisible pointer clicks. Site Control Center, native menus
and permission cards hold the row revealed for their lifetime.

Extension popups and site-settings bubbles do not hold the sidebar's Site
Control Center and extension buttons revealed after the pointer leaves.
VoiceOver highlighting alone also does not reveal those buttons; keyboard focus
does. The address label itself remains visible.

## Loading, Stop and Refresh feedback

`NavigationControlButton.setLoading` follows the actual selected page. Loading
shows Stop; Refresh remains a distinct command. Developer mode adds a compact
reload/chevron menu with Reload, Refresh Ignoring Cache and Clear Cookies. The
first two can become the stored reload default; clearing cookies does not change
that default.

`PageLoadingIndicatorHost` belongs to each side-by-side pane, or the first pane
of a vertical split. Popup/fullscreen windows omit it; Peek owns its indicator
above the card. A 48 × 4 pulse transitions into a 128 × 4 sweep with a 1.125-second
cycle. It uses near-black in light appearance and white in dark appearance,
rather than the Space accent. Reduce Motion keeps a static 48-point indicator.
Hidden, occluded and minimized hosts pause work, and closing resets it. Sidebar
rows do not add another loading spinner.

## History swipe

Page history gestures stay in Chromium's `HistorySwiper`. The renderer receives
the gesture first; an unconsumed acknowledgement and CSS overscroll policy decide
whether history navigation can begin. The shell does not add a competing page
recognizer.

A gesture retains its original page/document/window and selected-pane identity.
Navigation, transfer, selection, security or window eligibility changes cancel
it. Delayed Magic Mouse work checks the same generation. The overlay remains
inside the original renderer's clipped pane, including Split and Peek. Reduce
Motion keeps static edge feedback; no additional haptic is synthesized.

## Focus traversal across page, controls and auxiliary contexts

Each window has a `PCNativeFocusManager`. Shell owners request an exact page,
field or control, and saved responders return only through `SavedFocus.mayReturn`.

- The key-view loop visits page-side toolbars/renderers, then the sidebar gate,
  header controls, URL pill, list stop and dock. A hidden sidebar is bypassed.
  See the [window key-view loop](sidebar-accessibility.md#window-key-view-loop).
- Explicit selection focuses the active Peek, selected page/error surface, or
  local Note/Easel only when content or no responder held focus. Sidebar keyboard
  selection, command bar, Library, capture, switcher, sheets and unrelated fields
  retain their responder. A blank tab returns focus to the window.
- A not-yet-visible selected renderer is retried at idle run-loop boundaries for
  at most two seconds. Changed selection, owner, focus or expiry cancels the
  request without choosing a substitute page.
- Closing the command bar focuses the open Find field, otherwise current content.
  Its saved responder and text selection return only if already inside that target.
- History Escape, Find close and Library close use their original eligible owner.
  Peek delegates entry/return through `PeekFocusReturn`; its non-key host admits
  Tab/Shift-Tab into the ordinary window loop.
- DevTools focuses its actual tools page in its own window. Popup chrome and page
  form a loop without sidebar controls.
- Native menu tracking preserves the first responder. Popovers return key status
  to their parent; saved-focus owners still validate identity before restoration.

## Mouse and trackpad gesture inventory

| Gesture | Current behavior |
|---|---|
| Mouse buttons 4/5 | Back/Forward over the presented sidebar; Chromium handles unconsumed page events. |
| Middle-click sidebar tab | Executes that row's captured Close/Archive action. |
| Sidebar horizontal two-finger swipe | Tracks half the horizontal delta, ignores momentum, and commits at most one adjacent Space. |
| Sidebar horizontal wheel/tilt | Accumulates within 0.05 seconds; threshold 1 and 0.25-second cooldown prevent repeated paging. |
| Legacy horizontal swipe | Chooses previous/next Space without wrapping. |
| Page pinch or smart zoom | Remains Chromium-owned. |

`SidebarSpacePager` uses the last 100 ms of movement to choose a release direction
at a velocity of at least 5 strip points/second, otherwise the nearest page. A
0.4-second critically damped spring settles the strip; refused switches spring
back, and Reduce Motion places it directly at rest. Neighbor pages are visual
only during tracking. The window and floating sidebar share the same theme
transition; see [Space paging](space-theme-rendering.md#space-paging).

## Sources and validation

Implementation lives in the native navigation/history bridge and
`BrowserWindowController`, `SidebarView`, navigation controls, focus owners and
`SidebarSpacePager`. Focused coverage includes `tests/NavigationLoading`,
`tests/SidebarSpacePaging`, `tests/ContentFocusRequest` and native focus tests.
