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

## Links to Markdown and text files

Clicking a page's link to a local Markdown or text file opens it as a [note](notes.md) in the
same tab. The page stays alive behind the note, hidden, with its history, scroll position and
form state, so Back (the sidebar or toolbar arrow, ⌘[ or the Go menu) puts it back exactly as it
was, and Forward then shows the note again. A new navigation on the page, a typed address or a
Back past it drops that Forward step. The tab's address, title and URL pill follow whatever
shows, and the session saves both steps: after a restart, or when the tab comes back from the
archive, it shows the note and Back loads the page with its saved history. Closing the tab asks
the hidden page before it leaves, as closing any page does. A Command-click or middle-click opens
the note in its own tab, in the background unless Shift is held. A private window hands the note
to a regular window.

An [Easel](easels.md) opened in a split pane showing a page uses the same steps, with the same
swipes, held-arrow lists, session restore, archive, closing and window moves. Notes and Easels
opened over a page stack like web history: page → note → Easel → note walks Back through each
document to the page, and Forward retraces them. A document opened partway down the stack drops
the steps ahead of it, like any new navigation, and one opened from the page replaces them all.
Web pages stay in the page's own history underneath: a typed address over a document loads in
the page behind it and drops the document steps, since Chromium's history has no entry that
stands for a document.

`TabNoteVisit` on the tab holds the page step, the document steps (note files or Easel
addresses, the newest 50 kept, matching Chromium's 50 page entries) and which step shows; the
store is the source of truth and each render covers or uncovers the tab's live page to match.
The session saves it in the tab's `noteVisit` record, which still names the shown or next
document as `note` with `showsNote`, so a record from a one-step version loads as a one-step
stack and older versions still find the shown document. If the hidden page can't stay (the tab
moves to another window or Profile), Parc closes it and keeps its history, so Back reloads it with
that history, and every Easel in the stack moves to the new Profile with its tab. Renaming a note
or Easel renames each step holding it; trashing it removes those steps, and a tab showing it moves
to the nearest step behind, down to its page.

Swipes and the held-arrow list treat each document as one more history step, through
`HistorySwipeNoteStep`. A two-finger swipe over a document moves through the documents and the
page behind them with the usual swipe indicator (`HistorySwipeNoteSource` feeds the document's
scroll events to the same recognizer, and a wide table or code block that can still scroll
sideways keeps the gesture). Swiping forward on the page reaches the documents ahead, then the
page's own Forward entries. Holding Back on a document lists the documents behind it, nearest
first, then the page and that page's Back entries; holding Forward lists the documents ahead, with
their titles and icons. Picking a page entry behind the documents steps back to the page and then
moves its history, which drops the document steps like any page navigation. A Command-click or
middle-click on the arrow or a row opens that step in a background tab: a document in its own tab,
or the page behind the documents in a new tab that keeps its history.

The file types match the note editor's. For a same-tab click, Parc's navigation throttle holds the
navigation for one task and asks the window through `openNoteFile`; for a new-tab click, Parc's
web-contents delegate asks before Chromium creates the tab. Both arrive as the same request, so
the window treats it as a same-tab click while the page is mid-navigation; a Shift-Command-click
on a page that's still loading opens the note in place too. Only user-initiated link navigations
from a page that has already loaded are offered, never history moves, reloads or form posts. A
link that opens a new window, such as `target="_blank"`, still opens a tab that turns into the
note, and so does any click while the window can't take a note, such as with a Peek or sheet open.

## Sidebar controls and URL pill

Navigation glyphs are 16 points in 32-point controls, reduced to 14 in 28-point
controls when narrow. Hover/press colors and spring feedback are separate from
loading state. Hover shows only while a control is really on top, so the URL
pill, its buttons and the Space title row stay quiet under the compact editor
and Control–Space search; see [in-window hosting](command-bar.md#in-window-hosting).
The URL pill is 36 points high with 12-point corners and a
13-point host label. An empty page shows Search or Enter URL; a note or other
local file shows its file name, and an Easel shows Easel. Share Quote occupies
the full row with its own content; toolbar mode hides the sidebar URL row.
Split views retain one URL row following the focused pane while each pane owns
its navigation controls.

Sidebar hover, floating presentation, menus and keyboard-focused controls reveal
the URL row's Site Control Center and extension buttons; the address label
itself always shows. Zero-opacity controls remain accessible and keyboard
reachable, but do not accept invisible pointer clicks. Site Control Center,
native menus, permission cards, Site Settings and Security and extension popups
opened at that row hold it revealed for their lifetime, so the pointer can move
into them without the buttons fading.

An extension popup is a child window of the browser window, whether the
sidebar, the command bar or the extension opened it. When a popup is anchored
to the sidebar's URL row, Parc holds the buttons from the moment the engine
places a new popup, while its page is still loading, so the button can't fade
between the click and the popup appearing. A popup noticed only when it becomes
key takes the same hold. The hold lasts until the popup closes, whatever closed
it: the extension closing it before it ever appears, focus returning to the
browser, Escape, navigation, the extension or the browser window closing. A
popup detached from its browser window also releases when it loses focus or
another window takes focus.
Site Settings and Security follows its own popover's close.
While VoiceOver is running the buttons stay revealed, so its cursor never
outlines empty space. Parc follows VoiceOver turning on and off, not its cursor.

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

Two-finger Back/Forward swipes use Parc's own recognizer and indicator, fed
through Parc's renderer-view delegate behind its eligibility check.
[Swipe navigation](swipe-navigation.md) owns the behavior, including windows
that aren't in focus, the look and the swipe-and-hold history list.

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
