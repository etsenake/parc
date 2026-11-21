# Address and command bar

Parc's command bar combines native navigation, exact-tab switching and validated
application commands. A separate compact URL editor serves the sidebar's
address and pop-ups. Both share the original page/Profile lease, native input
methods and dismissal owner; neither reconstructs a classified request from its
display URL.

The [field and results guide](command-bar-results.md) covers appearance, result
rows, ranking, completion, submission modes, learned picks and suggestion
deletion. [Scopes and typed commands](command-bar-scopes.md) covers website
search scope, the site catalog, extension keyword scopes, Actions and typed
Type Travel commands.

## Entry points and source owners

| Entry | Behavior |
| --- | --- |
| Command–T | Large palette with empty input |
| Command–L or click a page toolbar's URL | Large palette with that pane's native URL selected |
| Click sidebar or popup URL | Compact editor anchored to that control |
| Control–Space | Sidebar keyboard session, expanding results when typing |
| A Space with no open tab | Resident bar on the [start page](start-page.md), which Command–T and Command–L focus |

The compact editor offers current/recent web addresses and native suggestions,
with no application commands, document actions or Actions scope. It navigates the
original current tab. The large palette retains commands and tab switching.
Clicking the URL in a page toolbar, on a single page, split pane, Note, Easel or
Peek, first makes that pane current and then takes Command–L's path, so the
palette opens centred and Return navigates the pane that was clicked. In a
split, New Parc Note, New Easel, a note or Easel row and a typed Markdown or
text file address go to that pane too: a note opens over a web page the way a
[note link](navigation.md#links-to-markdown-and-text-files) does, so Back
returns to the page, and otherwise the pane shows the document as if its
address were typed. Outside a split they keep opening their own tab
(`PaneDocumentRoute`).

The resident bar is the large palette's session hosted in a slot the start page
provides, with the same results, commands, scopes and submission. It rests as the
64-point field with no empty-query tab or history lists; typing grows results
downward from a fixed top edge, up to five rows. Escape leaves a scope, then
clears and collapses; it never dismisses. A submission resets the bar instead,
and the start page dismisses it when a tab opens or the window closes. Outside
its card the slot passes the mouse through, so the page still drags the window.
`CommandBarResidentLayout.swift` holds its geometry and
`CommandBarResidentLifetime.swift` the lifetime rules it shares with the palette.

`Sources/ParcApp/CommandBar.swift` owns the surface/session;
`CommandBarEditState.swift`, `CommandBarScopeEditing.swift` and
`CommandBarSubmission.swift` separate editing, scope and submission state.
`CommandBarRanking.swift`, `CommandBarTitleSearch.swift`, `CommandBarNativeHold.swift`
and `CommandBarRowDiff.swift` own ordering and updates. Typed action records live in
`Sources/ParcCore/CommandBar*.swift`. Native search ownership is documented in
[`tests/NativeSearch`](../tests/NativeSearch/README.md).

## In-window hosting

Every command surface, shadow and privacy banner lives in one host view inside
the browser window. The browser stays key, so Edit Theme, History, Extensions,
Release Notes and page tools validate live. Choosing a command dismisses the
bar, revalidates and runs it; refusal beeps. An extension action opens its
popup at the sidebar's URL row while that row shows, and the row's buttons stay
revealed until the popup closes, as for one opened from the sidebar; see
[navigation](navigation.md#sidebar-controls-and-url-pill).

The host receives mouse input only over the bar; shadow/outside presses land
normally after ending the session. The field uses its own editor and undo in the
browser window. Its own site-search confirmation sheet is permitted; unrelated
sheets close it. Command–R, Back and other normal window shortcuts retain their
native behavior while the bar is open.

Escape/committed actions return focus to the focused content's open Find, else
Peek, page or local document. The saved responder can return only inside that
eligible target. Outside clicks preserve their new focus. The resident bar keeps
focus on Escape; a committed action takes focus off its field, resets it, and asks
for content focus afterwards only if nothing else has taken it.

Controls underneath a command surface stay quiet while the pointer crosses it.
Every hover-reactive control the bar can cover, in the sidebar, page and pane
toolbars, Peek, split views, the Library, Notes and Easels, lights up only while
it is the topmost view under the pointer. It checks on entry and on every move,
because the bar may cover only part of it. Most use the shared check in
[PointerCover.swift](../Sources/ParcApp/PointerCover.swift); Favorites, tooltips,
the developer toolbar, Find and the Downloads search field run the same hit test
themselves, and the sidebar's resize edge also counts child windows. A view that
lets clicks through, such as a see-through overlay, never hides hover beneath
it. The resize pointer follows the same rule: split dividers and the page's
margin grip set it from cursor-update tracking only while they are topmost, not
from cursor rectangles, so over the bar the pointer stays the bar's own. The Space
title row, extension buttons, split controls and dividers, background panes'
reveal and the resize edge have covered and uncovered checks in their suites.

## Search-suggestion privacy banner

The large ordinary palette offers an info accessory when results exist and no
site-search hint takes its slot. It explains that suggestions contact the search
engine, with Search Settings and Dismiss. Dismiss is persisted; each new session
starts with the banner hidden. Search Settings closes the bar and opens Profiles'
search preference. The compact editor has no banner.

Buttons preserve command-field focus, including Full Keyboard Access. VoiceOver
announces the notice as a single group. A visible banner remains when entering a
scope, but the info accessory is not offered there. Width changes use a condensed
layout without moving the input. No external vendor privacy-policy link is added.

## Sidebar background: window drag and double-click

Empty sidebar list space drags the window. Double-click below the last row opens
the same New Tab command session; a gap between rows, single click or Control
click does not. An empty list admits the double-click throughout. Library Space
cards retain their own owner. Inactive-window first-click behavior remains
native. This uses `SidebarTablistBackground`, not another input monitor.

## Checks

`tests/CommandBar` covers real app decisions for editing, scope, publication
identity, default ranking, row diffs, submission, menus, typed targets, the
compact editor's width, caps and column alignment, the resting Control–Space
field, permanent scroll bars and inline completion anchoring, fade and title.
Drawn without a window, the pill's and the editor's text and icon must start at
the same spot and on the same baseline, then glide only sideways, for
Control–Space, typing and a click. The command-bar scripts build focused
production components; native search has separate owner/lifecycle coverage.
Follow [the working contract](../AGENTS.md) before running checks.
