# Sidebar provider previews

Sidebar previews belong to the original sidebar item, profile, Space and window.
Parc implements the local folder and recent-pages providers (Notion, Figma,
Linear and Confluence) and, as its own addition, a tab picture card for every
other eligible loaded tab ([below](#tab-picture-card)). Private windows do not
install sidebar previews.

The sidebar registers its actual row/button anchors. A window-owned controller
commits an eligible item after 200 ms only if the original item, anchor, selection
and pointer still agree. The card is an AppKit child view in that window, with
no independent window and no browser creation during presentation. Folder
contents use original tab IDs; recent pages query the actual profile's native
HistoryService and use its exact stored URLs. Favicons use the same profile's
local favicon database. No network fetch or page snapshot is needed.

A folder card lists and searches its descendants. Activating a row follows the
modifier routes below through the normal original-tab selection, split, duplicate
and reveal owners. Its context menu copies the URL, shows the original tab's
live page in a Peek ([Peek](peek.md#peeking-at-an-existing-tab)), opens it in
Split View, duplicates it in the same folder, or archives it through shared
retirement and real beforeunload handling. Recent rows route from the previewed
tab in its original profile and Space. The folder search row keeps focus while
Up/Down move the list's keyboard selection, which scrolls into view; Return
activates it with the modifiers then held and Escape dismisses. The recents list
has no search and takes focus on explicit entry. The sidebar context menu and
accessibility custom action provide that keyboard/focus entry. Hover alone does
not steal focus or intercept page typing. The folder, recent-pages and tab
picture preferences are in Settings → General → Previews Settings (the card's
gear opens it) and persist locally.

The native query lease is retained until delivery and invalidated on dismissal.
The API accepts only `notion`, `figma`, `linear` and `confluence`; it queries the
last 30 days with newest-first distinct URLs and a 500 ms deadline, excludes
private profiles and performs no network work. The shell checks the provider
again for every returned URL. Unavailable history or a missed deadline presents no
card; an empty result shows the provider's empty state, never a sign-in
requirement. Re-hovering the row queries again.

Selection, source navigation/removal, profile/Space changes, a missing anchor,
sidebar motion, drag, outside click, window deactivation/closure, sheets and
actual native security reservations cancel the session; a Peek that is closing or
waiting for close confirmation does too, while a resting Peek leaves cards
available. MRU activation dismisses
the card and prevents another hover session until the switcher closes. Asynchronous favicon and
history deliveries also check that session. Row rebuilds with the same original
identity retain the card and move it without animation. Its hit region prevents
the existing page-click monitor from selecting a renderer underneath; an active
card, and a pending recents query (at most 500 ms), hold a floating sidebar open;
a card playing its exit animation does not. The gear opens Previews Settings in
its owner, Settings → General. Only the card's own context menu can retain
its session through menu tracking. A focused card restores a still-attached
previous responder on dismissal. A dismissed card retires at once: it cancels its
menu, releases focus, takes no clicks or hover, no longer holds the sidebar and is
removed when its exit animation completes. The owner can clear `isHoverEnabled`
(false while the sidebar animates, resizes or pages) to cancel a hover without a card and start no new hover session.

## Tab picture card

The tab picture card is a Parc feature (SIDE18). With **A picture of
other open tabs** on (Settings → General → Previews Settings, on by default),
hovering a tab with no recent-pages provider, or one whose Recents preference
is off, shows the
Recents card's chrome and header with the tab's favicon, its folder-row title
and its site (the address bar's host without "www."), an Open in Split View
button (the sidebar's own Split View action, `rectangle.split.2x1`), and the
tab's last picture below at its own aspect. When that tab can open in a Peek
right then (the same rule as a folder row's Open in Peek), an Open in Peek
button sits 26 pt to the left of Split View and shows the tab's own page in a
[Peek](peek.md#peeking-at-an-existing-tab). Every sidebar render checks the
rule again and adds or drops the button, and so does a click, which just hides
the button if the offer has lapsed; a focused button that goes hands the
keyboard to Split View. Its artwork is Parc's own, sized to Split View's weight
([sidebar preview artwork](../Resources/SidebarPreview/README.md)). The title
and site end 8 pt before the leftmost button and truncate at the tail, so
without a Peek offer they end 8 pt before Split View. Both buttons show Parc's 24 pt
hover plate, carry their name as Parc's own tooltip and VoiceOver label, and take
keyboard focus with a 5 pt ring. The picture is inset 10 pt (268 pt wide in a full-width
card) with 5 pt corners and a hairline, the card still capped at 384 pt. Chromium
captures the thumbnail at about 530–560 pixels wide, close to the 536 a 268 pt
picture needs on a Retina display, so it stays sharp; a wider picture would need a
larger engine capture. The dwell, placement, motion, hover region, aim and
dismissal are the other cards'.

The picture is the one the tab switcher uses: the page's thumbnail
subscription, for a page loaded in this window. There is no card for a tab on
screen (any selected pane), for a tab whose page isn't loaded here, or when no
picture arrives within the same 500 ms the Recents query gets. A shown card
follows newer pictures and the tab's title and address in place, and ends when
the page loads a new document, closes or the subscription is cancelled. No
page is created, selected or navigated for it; the engine owns when the
thumbnail itself is refreshed.
The card has no keyboard entry; the sidebar's Preview items stay with Recents
and folders.

## Note and Easel cards

With the same **A picture of other open tabs** preference, hovering a note or
Easel tab that isn't on screen shows the tab picture card's chrome, dwell,
placement, motion and dismissal. The header shows the tab's icon (the note's
emoji or image icon, the coral note mark, or the Easel mark), its title and
"Note" or "Easel · 3 objects". The picture is the document itself at 16:10: the
top of the note (cover, icon, title and its first twelve blocks) drawn by the
same view Notes prints with, or the Easel's objects framed to fit, both in the
Space's light or dark content appearance on white or black paper. Until a
picture is ready, or for an empty document, the same frame shows the library
snippet ("Empty note", "No objects yet"). A note or Easel that moved or was
deleted shows "This note moved or was deleted" or "This Easel was deleted" and
no buttons.

The buttons are the tab picture card's: Open in Peek, while the tab can open in a
Peek right then ([notes and Easels in a Peek](peek.md#notes-and-easels)), and Open
in Split View, with the same placement, title width and live offer rule. Copy Link stays in the folder rows' menus. The card appears when
a picture or the final text arrives, or after the same 500 ms with the snippet,
and a later picture replaces the text in place.

Pictures are drawn without a window: a detached print view cached with
`cacheDisplay`, and the Easel's own image export on a detached canvas. Unloaded
notes are read and parsed off the main thread. `SidebarDocumentThumbnails`
keeps the last 48 pictures per document and appearance, keyed by the open
note's first blocks and title, the closed file's modification date and size,
or the Easel's modification date and object count, so an edit or save makes
the picture stale. A shown card follows edits to an open note or Easel and
redraws at most once a second, showing the stale picture meanwhile. Folder
cards list notes and Easels with these icons and offer Copy Link in place of
Copy URL; their rows keep the list's 16 pt icons rather than page pictures.

While any preview card is shown, the window's other tooltips stay hidden: the
row's title tooltip waits 1.5 s and would otherwise open over a card that already
shows the title, and right after another tooltip it opens almost at once. The
card's own header buttons (Open in Peek, Open in Split View, the Recents create
button and Previews Settings) keep Parc's tooltip, shown below the button, and a
card that is leaving exempts nothing.

## Titles, grouping and badges

Recent pages show the provider's tidy title (`RecentPageText.tidyTitle`). Notion
and Figma use the deterministic `TidyTitles` rule engine; Linear uses the rules
and then removes a leading issue ID (from `/<team>/issue/<ID>/<slug>`) and trims
spaces from every issue title; Confluence splits on " - " and drops a trailing "Confluence"
segment, and its space name when there are more than two parts. A rule result
that is blank after trimming falls back to the original title. The rule data is
Parc's own (`notion.so`, `app.notion.com`, `figma.com`); it has no remote rule updater or AI renaming.
The subtitle is "Just now" within 60 s of the visit, otherwise the full-style
relative date ("2 hours ago"), with "ENG-123 • " in front for a Linear issue.
Recent rows have no icon; the provider's favicon is in the header. The results
form one ungrouped list (with no group heading), in
fetch order, deduplicated first by tidy title and then by recognized page
identity (Linear issue ID, Notion page ID), keeping the first occurrence. Every
returned URL is checked against the genuine provider before tidying.

A folder card is one flat list of all descendant tabs, newest visit first, with
sidebar order for equal dates. Its title is the tab's custom title, otherwise the
tidy title, otherwise the page title; its subtitle is the relative visit time.
Search matches the displayed title or the full URL, case-insensitively, not the
subtitle. Rows keep their favicons. Folder rows do not produce a Recently Added badge. Subtitles are computed when a row is drawn, so
a shown card never ages its source. A shown folder card follows the folder's
current children in place (a duplicate or a visit refreshes its rows, search and
keyboard selection carry over); any other source change still ends the session.

## Modifier destinations

Activation reads the modifiers then held; exact comparisons use only the
four primary modifiers. A
click acts on mouse-up over the same row, using that row rather than a selection a
Command-click may have toggled. Return carries modifiers the same way.

| Row | Modifiers | Destination | Preview |
| --- | --- | --- | --- |
| Recent page or plus button | Command (Option adds split) | New tab, referrer = previewed tab; split after the focused pane with Option | Dismissed first |
| Recent page or plus button | Otherwise (Option adds split) | The previewed tab's own navigation: in place, then that tab is selected; a policy-created tab uses the split with Option | Dismissed first |
| Folder tab | Exactly Option-Command | Mini browser window, excluded: consumed, nothing happens | Kept |
| Folder tab | Exactly Option | Reveal ancestors, then the original joins a split after the focused pane | Dismissed |
| Folder tab | Exactly Command-Shift | Duplicate beside the original with a fresh ID, opened in the background; nothing selected or revealed | Kept |
| Folder tab | Any other with Command | Reveal ancestors; nothing selected | Kept |
| Folder tab | Anything else | Reveal ancestors, select the original | Dismissed |

Shift and Control alone change nothing. The previewed tab's in-place navigation
uses the address bar's model navigation of that same tab. A pinned or Favorite
source that is not in a split keeps its current or saved host, or an unlocked
authentication flow, in place; another host creates a tab with the source as
referrer. Today and split sources navigate in place. The navigation happens only
if that tab and its split members can be selected. Splits use the command bar's
split-after-focused transaction; if no split is available (four panes, Peek,
Library, fullscreen, an inserting split), the tab opens or is
selected ordinarily. Ancestors are revealed by the sidebar's existing disclosure
transaction. The duplicate is the sidebar's own Duplicate (copied live
destination, adjacent placement, eager open); a tab inside a split group is not
duplicated from the preview. A folder row's context menu contains Copy URL, Open in
Peek, Open in Split View, Duplicate and Archive, with no Open row; Open in Peek
appears only when that tab can open in a Peek right then. A recent row builds its menu from the real URL: a Linear ticket offers Copy Issue ID and
Copy Issue URL, a recognized Notion page has no menu, and any other page
offers Copy URL.

## Presentation

The card is a child of the window's flipped root, above page content. It is 288 pt
wide; its height is the 56 pt header plus content, capped at 384, so a 16:10 tab
picture makes a 288 × 234 card and lists grow to 288 × 384. Sidebar rows place
its leading edge at row.maxX + 4, centred on the row; favorites tiles use the
diagonal location, row.maxX − 4 with its top 4 pt above the tile's bottom. The
card never comes within 18 pt of the window's top or bottom, which wins over the
row alignment; only a shorter window reduces its height. It narrows to stay 18 pt
inside the window's right edge, but never below 240 pt, and a narrowed picture
card keeps the picture's aspect. There is no leading-side flip. A window resize
keeps both clamps.

The chrome is `.popover` material, `.withinWindow` blending and
`.followsWindowActiveState`, clipped at 14 pt, inside an unclipped owner with a
black 0.4-opacity, 19 pt shadow 6 pt downward and a hairline border. It appears
over 0.1 s ease-in-ease-out, scaling 0.8 → 1 about the row edge while fading in.
Dismissal animates from the presented transform/opacity to 0.8 and 0 over 0.1 s
times that opacity, holds the end state and removes the view on completion.
Changing item plays the old card's exit while the new one enters; nothing moves one
card between rows. With Reduce Motion on, the card only fades in and out where it
stands: no scaling, with the same timing, retirement and removal.

The card appears after the 200 ms dwell; scheduling another item un-commits the
previous one immediately. Its hover region extends 40 pt toward the sidebar. While a
card is shown, rows the pointer crosses on its way to the card keep it: rightward
moves with |dy/dx| ≤ 3 (a level move always counts) for the right location, or
right-and-down moves for the diagonal one, left of 478 pt in window coordinates.
The card goes as soon as neither its row nor its region is hovered; there is no
exit timer.

The list sits 5 pt inside the card. Rows have 6 pt top, 8 pt bottom, 10 pt leading
and 8 pt trailing padding, 8 pt icon/text spacing, a one-line 13 pt title and an
11 pt secondary subtitle directly below; rows are 1 pt apart. Hover and keyboard
focus are separate: either one draws the full-opacity title colour at 0.08 in a
4 pt rounded rect, both draw 0.16; there is no system selection highlight. The
recents header shows the provider's favicon (a symbol until it loads), **Recents**,
a plus button and a gear.
The plus button's tooltip and link are New Page `https://notion.so/new`, New File
`https://figma.com/new`, New Issue `https://linear.app/new` or New Page
`https://confluence.new`; it routes like a recent row, modifiers included. The gear opens Previews
Settings in Settings → General. Empty recents read "Recent Notion docs appear here.",
"Recent Figma files appear here.", "Recent Linear projects and issues appear
here." or "Recent Confluence pages appear here." The folder header is a 56 pt search
row with a 12 pt heavy magnifying glass and the placeholder "Search" plus the
folder name. An empty search result, or an empty folder, reads "No tabs matching
that search" followed by 🤔. There is no loading card and no close or refresh
control: Escape and pointer exit dismiss.

## General Settings entry

Settings → General → Previews Settings owns Folder, recent-provider and tab-picture
preferences. Every card gear uses that original Settings entry. Turning off a
provider's Recents allows its tab-picture fallback only when the separate
picture preference is enabled. These are local preferences, not service accounts.

## Checks

Focused preview components exercise original-identity query/thumbnail leases,
modifier routes, title rules, geometry, invalidation and focus return.
`SidebarPreviewPlacementTests`, `SidebarPreviewFolderCardTests`,
`SidebarPreviewCardKindsTests` and `SidebarPreviewRowTextTests` cover placement,
aim, cards, search, menus and row text; `SidebarPreviewMotionTests` play the
entrance and exit with Reduce Motion off and on. `SidebarDocumentPreviewTests` (run by `swift test`) cover document
kinds, card text, buttons and the thumbnail cache. `SidebarPreviewHeaderTests` build tab
picture cards without a window and checks the Open in Peek button against the
Peek offer, its action, the header widths and the artwork.
