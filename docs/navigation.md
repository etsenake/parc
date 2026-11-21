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
was, and Forward then shows the note again. A new navigation on the page, such as a link or a
typed address, drops that Forward step. The tab's address, title and URL pill follow whatever
shows, and the session saves both steps: after a restart, or when the tab comes back from the
archive, it shows the note and Back loads the page with its saved history. Closing the tab asks
the hidden page before it leaves, as closing any page does. A Command-click or middle-click opens
the note in its own tab, in the background unless Shift is held, and a Shift-click opens it in a
new window. A link that opens a new window, such as `target="_blank"`, opens the note straight in a
new tab without a page tab first. A private window hands the note to a regular window.

An [Easel](easels.md) opened in a split pane showing a page uses the same steps, with the same
swipes, held-arrow lists, session restore, archive, closing and window moves. Notes, Easels and
web pages share one history: web A → note → Easel → web B → note → web C walks Back through every
step to A, and Forward retraces them. Each document sits over the page entry it was opened from,
and a step to it or past it first moves the hidden page to that entry, so the page comes back as
Chromium kept it, from its back-forward cache when it could. A typed address over a document loads
in the page behind it and keeps the documents behind the new page; until the new page commits,
Back returns to the document it left. Opening a document, or following a link or typed address
from a page, drops every step ahead, like any new navigation, including the page's own Forward
entries; only entries the page can't drop at that moment, such as during a history move still in
flight, stay after the new document.

`TabNoteVisit` on the tab holds every step in order: each of the page's Chromium history entries,
by an identifier the engine keeps on the entry, with the documents opened over it right after it
(note files or Easel addresses, the newest 50 kept), and which step shows. The engine reports each
change to the page's history, and the store rebuilds the steps from the page's entries: documents
stay with their entry, a shown document whose entry was replaced stays over the page's current
entry, and documents over entries Chromium no longer has go with them. The store is the source of
truth; each render covers or uncovers the tab's live page to match. The session saves the steps in
the tab's `noteVisit` record, which still names the shown or next document as `note` with
`showsNote` for older versions, and a record from before page tracking attaches its documents to
the page's current entry on the page's first report. After a restart the page keeps Chromium's six
saved entries either side of where it stood, so documents over older pages go with those pages.
If the hidden page can't stay (the tab moves to another window or Profile), Parc closes it and
keeps its history, so a step to it reopens it at the right entry, and every Easel in the history
moves to the new Profile with its tab. Renaming a note or Easel renames each step holding it;
trashing it removes those steps, and a tab showing it moves to the nearest step behind, down to
the page under it.

Back and Forward (the arrows, ⌘[ and ⌘], the Go menu and the mouse's Back and Forward buttons),
swipes and the held-arrow lists walk the same steps, through `HistorySwipeNoteStep`. A step
between two pages with no document between them stays Chromium's own Back or Forward, so pages
that manipulate history keep Chromium's skipping, and page scripts move only through the page's
own entries. A two-finger swipe over a document, or over the page when a document lies that way,
moves through documents and pages with the usual swipe indicator (`HistorySwipeNoteSource` feeds
the document's scroll events to the same recognizer, and a wide table or code block that can still
scroll sideways keeps the gesture); with no document that way, the page's own swipe runs
unchanged. Holding Back or Forward lists every step that way, nearest first, documents with their
icons and pages with their titles and favicons. A Command-click or middle-click on the arrow or a
row opens that step in a background tab: a document in its own tab, or a page in a new tab that
keeps its history, at that entry.

The file types match the note editor's. Every request reaches the window through `openNoteFile`
with the click's disposition: in place, foreground tab, background tab or new window. For a
same-tab click, Parc's navigation throttle holds the navigation for one task and asks in place.
For a modified click, Parc's web-contents delegate asks before Chromium opens the tab or window.
For a link that creates a new page, the delegate asks before the new page joins the window and
drops it when the window takes the note, so no raw-text page shows. `NoteLinkDisposition` maps
each disposition to its routes; only an in-place request may cover the page, and it falls back
to a foreground tab when the page can't take the note. Only user-initiated link navigations from
a page that has already loaded are offered, never history moves, reloads or form posts. A click
while the window can't take a note, such as with a Peek or sheet open, still opens a page tab
that turns into the note.

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
