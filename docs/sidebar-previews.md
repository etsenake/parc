# Sidebar provider previews

Sidebar previews belong to the original sidebar item, profile, Space and window.
They are provider lists, separate from the thumbnail-backed MRU switcher. Parc
implements the local folder and recent-pages providers: Notion, Figma, Linear
and Confluence. Hovering an unrelated page does not produce a screenshot card.

The sidebar registers its actual row/button anchors. A window-owned controller
commits an eligible item after 200 ms only if the original item, anchor, selection
and pointer still agree. The card is an AppKit child view in that window, with
no independent window and no browser creation during presentation. Folder
contents use original tab IDs; recent pages query the actual profile's native
HistoryService and use its exact stored URLs. Favicons use the same profile's
local favicon database. No network fetch or page snapshot is needed.

modifier routes below through the normal original-tab selection, split, duplicate
and reveal owners. Its context menu copies the URL, opens the original tab in
Split View, duplicates it in the same folder, or archives it through shared
retirement and real beforeunload handling. Recent rows route from the previewed
tab in its original profile and Space. The folder search row keeps focus while
Up/Down move the list's keyboard selection, which scrolls into view; Return
activates it with the modifiers then held and Escape dismisses. The recents list
has no search and takes focus on explicit entry. The sidebar context menu and
accessibility custom action provide that keyboard/focus entry. Hover alone does
not steal focus or intercept page typing. Folder/recent-provider preferences
are in the sidebar's Tab previews submenu and persist locally.

The native query lease is retained until delivery and invalidated on dismissal.
The API accepts only `notion`, `figma`, `linear` and `confluence`; it queries the
last 30 days with newest-first distinct URLs and a 500 ms deadline, excludes
private profiles and performs no network work. The shell checks the provider
again for every returned URL. Unavailable history or a missed deadline presents no
card; an empty result shows the provider's empty state, never a sign-in
requirement. Re-hovering the row queries again.

Selection, source navigation/removal, profile/Space changes, a missing anchor,
sidebar motion, drag, outside click, window deactivation/closure, sheets and
actual native security reservations cancel the session. MRU activation dismisses
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
resizes or pages) to cancel a hover without a card and start no new hover session.

## Titles, grouping and badges

Recent pages show the provider's tidy title (`RecentPageText.tidyTitle`). Notion
and Figma use the deterministic `TidyTitles` rule engine; Linear uses the rules
and then removes a leading issue ID (from `/<team>/issue/<ID>/<slug>`) and trims
segment, and its space name when there are more than two parts. A rule result
that is blank after trimming falls back to the original title. The rule data is
The subtitle is "Just now" within 60 s of the visit, otherwise the full-style
relative date ("2 hours ago"), with "ENG-123 • " in front for a Linear issue.
Recent rows have no icon; the provider's favicon is in the header. The results
fetch order, deduplicated first by tidy title and then by recognized page
identity (Linear issue ID, Notion page ID), keeping the first occurrence. Every
returned URL is checked against the genuine provider before tidying.

A folder card is one flat list of all descendant tabs, newest visit first, with
sidebar order for equal dates. Its title is the tab's custom title, otherwise the
tidy title, otherwise the page title; its subtitle is the relative visit time.
Search matches the displayed title or the full URL, case-insensitively, not the
subtitle. Rows keep their favicons. The "Recently Added" badge is wired as an
always stores `isBadged = false`. Subtitles are computed when a row is drawn, so
a shown card never ages its source. A shown folder card follows the folder's
current children in place (a duplicate or a visit refreshes its rows, search and
keyboard selection carry over); any other source change still ends the session.

## Modifier destinations

option 4, command 8; the upper four bits are masked for exact comparisons). A
click acts on mouse-up over the same row, using that row rather than a selection a
Command-click may have toggled. Return carries modifiers the same way.

| Row | Modifiers | Destination | Preview |
| --- | --- | --- | --- |
| Recent page or plus button | Command (Option adds split) | New tab, referrer = previewed tab; split after the focused pane with Option | Dismissed first |
| Recent page or plus button | Otherwise (Option adds split) | The previewed tab's own navigation: in place, then that tab is selected; a policy-created tab uses the split with Option | Dismissed first |
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
view builds from the page's URL: a Linear ticket offers Copy Issue ID and
Copy Issue URL, a recognized Notion page has no menu, and any other page
offers Copy URL (evidence below).

## Presentation

The card is a child of the window's flipped root, above page content. It is 240 pt
wide; its height is the 48 pt header plus content, capped at 320. Sidebar rows place
its leading edge at row.maxX + 4, centred on the row; favorites tiles use the
diagonal location, row.maxX − 4 with its top 4 pt above the tile's bottom. The
card never comes within 18 pt of the window's top or bottom, which wins over the
row alignment; only a shorter window reduces its height. There is no leading-side
flip. A window resize keeps that clamp.

The chrome is `.popover` material, `.withinWindow` blending and
`.followsWindowActiveState`, clipped at 12 pt, inside an unclipped owner with a
black 0.4-opacity, 16 pt shadow 5 pt downward and a hairline border. It appears
over 0.1 s ease-in-ease-out, scaling 0.8 → 1 about the row edge while fading in.
Dismissal animates from the presented transform/opacity to 0.8 and 0 over 0.1 s
times that opacity, holds the end state and removes the view on completion.
Changing item plays the old card's exit while the new one enters; nothing moves one

The card appears after the 200 ms dwell; scheduling another item un-commits the
previous one immediately. Its hover region extends 40 pt toward the sidebar. While a
card is shown, rows the pointer crosses on its way to the card keep it: rightward
moves with |dy/dx| ≤ 3 (a level move always counts) for the right location, or
right-and-down moves for the diagonal one, left of 478 pt in window coordinates.
The card goes as soon as neither its row nor its region is hovered; there is no
exit timer.

Rows have 5/7/8 pt padding, 8 pt icon/text spacing, a one-line 13 pt title and an
11 pt secondary subtitle, separated by 1 pt. Hover and keyboard focus are separate:
either one draws the full-opacity title colour at 0.08 in a 4 pt rounded rect, both
draw 0.16; there is no system selection highlight. The recents header shows the
provider's favicon (a symbol until it loads), **Recents**, a plus button and a gear.
The plus button's tooltip and link are New Page `https://notion.so/new`, New File
`https://figma.com/new`, New Issue `https://linear.app/new` or New Page
`https://confluence.new`; it routes like a recent row, modifiers included. The gear opens Previews
Settings in Settings → General. Empty recents read "Recent Notion docs appear here.",
"Recent Figma files appear here.", "Recent Linear projects and issues appear
here." or "Recent Confluence pages appear here." The folder header is a 48 pt search
row with a 12 pt heavy magnifying glass and the placeholder "Search" plus the
folder name. An empty search result, or an empty folder, reads "No tabs matching
that search" followed by 🤔. There is no loading card and no close or refresh
control: Escape and pointer exit dismiss.


`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
These are binary metadata/disassembly observations, not recovered original source.

  recentPages, Outlook mail/calendar, folder, Google Calendar, Twitter and
  WhatsApp. It does not establish an arbitrary-page screenshot provider.
  Atlassian hosts; Confluence additionally requires a `wiki` path component.
  Calendar is dispatched separately. Provider preferences are checked at
  `ev_bbea9fc729aede35ad81305a52f43624a9a0e8459977bf6c8006b3d3d3817dfa`.
  the pending task: `ev_b16978d05a3a416a972d9104de0b0461c604378d1de500854ff135c48b810873`.
  and frame. The tracker owns menu tracking, committed/current hover, task and
  extended-presentation identities. PreviewView owns tracking and provider state.
  `notion.`, `figma.com/`, `linear.app/` and `atlassian.net/wiki/`, duplicate policy
  context's `searchHistory:completion:`. Its timeout is 500 ms; mapped rows retain
  title/tidyTitle, URL and lastVisitDate. The precise historical integer-0 policy
  identity is not asserted; current Chromium's URL-deduplicated query is explicit.
  each item stores sidebar identity, title, URL, favicon, visit date and badging.
  appear, Escape/outside click, Copy URL, Split View, Duplicate and Archive.
  github, linear, googleDocs, googleCalendar, googleMeet, zoom; tag byte & 0x1c,
  ID) then Copy Issue URL; any other recognized page gives nothing; no match
  exactly: github.com, linear.app, notion.so, docs.google.com,
  matches `([a-fA-F0-9]){32}$` on the last path component. Parc ports the
  Linear and Notion rules (`RecentPageText.rowMenu`); a recent page on a
  GitHub, Google or Zoom host, possible only when its address also contains a
  `ItemView`'s own menu also sits inside the folder row's menu; which one
  SwiftUI shows for a folder row was not determined, and Parc shows the folder
  menu.
  with leading, required top ≥ 18/bottom ≤ −18 and priority-250 centerY (right) or
  vertical constants from HoverMetadata's frame (REA
  `ev_73118f7fefd984a4e23a19394135b54577f47a82cdc948861d45962c2a361bae`).
  StandardPreviewView/FolderPreviewView use width 240 and the 48 pt header.
  blending 1, state 0, radius 12 and ShadowConfiguration black/0.4/16/(0, 5).
  0.8 scale, 0.1 s ease-in-ease-out timing, opacity-scaled exit, forward fill and
  completion removal.
  `ev_d7f36d92335769cf16887f79d8085fffce6ace5b06c06422146e60dbb43a850b`) returns
  true for a level rightward move before its 478 pt reach test.
  and empty states.
  units style 0.
  "Recently Added" emphasized only when badged, else the relative visit time,
  `url.absoluteString` with `localizedCaseInsensitiveContains`.
  selects disposition 0x43 and Command the TabCreationOptions path with the
  bounded `llvm-objdump` disassembly of the same executable, not REA pseudocode.

Parc adaptations: the solved constraints are a frame computation, because the
host lays out its chrome by frame; the card re-solves on host resize from the row's
PreviewBackgroundColor asset, so recents use the palette's content surface, and the
highlight uses the palette title colour. A missed 500 ms deadline shows no card.
The aim test also bridges gaps between Parc's sidebar rows. The plus button is an
ordinary navigation, not a live service integration. Inferred: favorites tiles
own the diagonal location; the gear destination; the hairline border; the 16 pt
beyond its 48 pt height; the 4 pt list inset; selecting the first match while
recovered empty branch.

Title, grouping and modifier adaptations: Parc keeps recent rows whose page
such row (all Figma and Confluence pages) into the first. Newest-first recent
order relies on the native history query's order. Equal folder visit dates keep
title). The recents list keeps Parc's keyboard entry, arrow selection and Return,
which passes whatever modifiers reach Return. Command alone on a folder row never
data). Parc's source policy is its existing current-link host and
not applied to this shell route, so it never leaves the source's Space or
Option on an in-place navigation changes nothing; after a policy-created tab Parc
is untraced). A Command-click recent tab opens in the foreground through Parc's
unknown. Page identity is inferred: Parc recognizes a 32-hex Notion page suffix on
notion.so, *.notion.so and *.notion.site and any host ending in linear.app, while
Notion identifier parser is undecoded. The current-link host classification used
for the source route is a second copy of the page-link route's check; sharing one
owner with that route is a follow-up. A
split that cannot be made falls back to an ordinary tab or selection. The
reducer clears only the hovered flag). Extra-rounded corners remain unresolved.
Matched appearance is unverified: no hover screenshot was available through the
permitted pointer-control surface, and another tooltip/card was not used as visual
evidence. The native security gate is shared with MRU but no thumbnail
lease is acquired. Folders retain existing cross-window transfer/retirement
semantics. The user excluded dedicated live service integrations on October 25.
Provider-specific mail/calendar/social fetchers are therefore outside scope;
the historical provider inventory above remains reference evidence only.
The existing local-folder and native recent-history previews remain included.

The card's anchor is its row's own visible part.
`SidebarPreviewController.anchorRect` intersects the anchor's `visibleRect` with
its bounds before converting it: on this OS a non-clipping view's `visibleRect`
(an `NSView` or `NSButton`, neither of which clips by default) is its clipping
ancestors' visible region in its coordinates, not intersected with its own
bounds ([C], asserted in `tests/SidebarAccessibility`; see
[accessibility](sidebar-accessibility.md#recovered-facts)). Without that, a list
row's rect was the list scroll view's visible area, so `SidebarPreviewPlacement`
centred the card on the list's mid-Y and took the list's trailing edge, and a
favorites tile's was the window content's region. A row scrolled wholly out of
the list gives no anchor. `tests/SidebarPreview` places cards from given rects;
its `check.py` asserts the intersection in the controller's source.


## General Settings entry

General → Previews Settings now exposes the same two application preferences as the sidebar's Tab previews menu. It applies changes immediately and reconciles all existing preview controllers, folder menus and accessibility preview actions; Done closes the original-window-owned sheet. Existing saved values, defaults, local folder contents and exact-profile native history sources remain intact. See [General preview preferences](settings.md#general-preview-preferences) for the original REA/UI contract and explicit presentation adaptations.
