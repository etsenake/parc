# Address and command bar

Parc's command bar combines native navigation, exact-tab switching and validated
application commands. A separate compact URL editor serves the sidebar's
address and pop-ups. Both share the original page/Profile lease, native input
methods and dismissal owner; neither reconstructs a classified request from its
display URL.

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
palette opens centred and Return navigates the pane that was clicked.

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
`CommandBarRanking.swift`, `CommandBarNativeHold.swift` and
`CommandBarRowDiff.swift` own ordering and updates. Typed action records live in
`Sources/ParcCore/CommandBar*.swift`. Native search ownership is documented in
[`tests/NativeSearch`](../tests/NativeSearch/README.md).

## Result ownership

- Native autocomplete rows retain their actual `PCNativeSearchNavigation` token,
  including classified URL, POST body, headers, transition, Profile and one-use
  consumption. Display strings are not replacement requests.
- Open-tab rows retain the original tab ID and say **Switch to Tab**. They use
  existing Space/window selection and transfer, without reloading the URL.
- Menu-command rows retain the original menu item, owning window and registry
  revision. Availability and execution validate the real target, and the item
  remains the sender, preserving tags and represented objects.
- Typed commands retain original items, hierarchy and destination identities.
  Explicitly selected expired actions stay unavailable until the user edits or
  selects another row; Return cannot silently become a web search.

Empty input lists other open tabs and distinct recent HTTP(S) visits from the
exact Profile's Chromium history. Local history is the fallback while loading
or when unavailable. Current/already-open URLs are excluded. History activation
uses the real classifier, not a fabricated Back/Forward or autocomplete token.
History ordering is refreshed when visits change, not for every keystroke.

The session leases its original Space, Profile, tab, Peek, browser, page and
window. Transfer, navigation/selection changes, retirement, security presentation,
deactivation, lost key window or field focus invalidate it. The resident bar
outlives window events: losing key or focus, deactivation, resizing and
miniaturizing leave it in place, and an unrelated sheet or security prompt closes
only its own scope menu. An invalid owner blocks its actions until the start page
dismisses it. Favicon callbacks
also validate the exact Profile, URL and session. A dismissed session cannot
clear or update its replacement.

Command–Shift–C copies the highlighted row's actual URL; it is unavailable for
commands or unresolved input. Command–C remains ordinary native selected-text
copy. See [copy commands](keyboard-navigation.md#copy-commands).

## In-window hosting

Every command surface, shadow and privacy banner lives in one host view inside
the browser window. The browser stays key, so Edit Theme, History, Extensions,
Release Notes and page tools validate live. Choosing a command dismisses the
bar, revalidates and runs it; refusal beeps. An extension action opens its
popup at the sidebar's URL row while that row shows, and the row's buttons stay
revealed until the popup closes, as for one opened from the sidebar; see
[navigation](navigation.md#sidebar-controls-and-url-pill). Obsolete key-panel
availability snapshots are no longer used.

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
it. The Space title row, extension buttons, split controls, background panes'
reveal and the resize edge have covered and uncovered checks in their suites.

## Appearance and theme

`CommandBarAppearance.swift` centralizes palette, typography, surface, shadow and
hairline. The large palette is at most 765 points wide, with a 64-point header,
50-point rows and up to five visible rows in its nominal 326-point height.
Containment follows the owning window.

The compact editor is 450 points wide from the sidebar and 350 from a pop-up's
address, capped to its window and screen with 8-point margins so a narrow
sign-in pop-up never cuts it off. It opens at its control's left edge and slides
back inside the window when it would overhang. Its address row's icon, text,
scope label and trailing edge sit on the result rows' icon, title and badge
columns, with the text line centred on the icon. The resting Control–Space field
covers the sidebar's address field with its icon and text already on those
columns and centred on the field. The typing panel and the editor a click opens
rise until their address row is centred on the address they came from, six
points for the sidebar's, so icon, text and baseline stay on the sidebar pill's
line and the first keystroke moves nothing; a pop-up's editor centres on the
pop-up's address the same way. Opening from an empty pill, the editor's
magnifying glass, which is the pill's own glyph, and its placeholder start where
the pill drew them and glide sideways onto the columns in 0.15 seconds. Reduce Motion
skips the glide, and a pill showing a page's address has none, since its text
changes anyway. The pill keeps its own spacing: moved onto the editor's columns,
its placeholder would be cut off at the default sidebar width.
`CommandBarCompactLayout.swift` holds these numbers.

Floating panels and the resident card follow the window's appearance, which
View → Appearance sets; the empty inline sidebar input takes the Space's content
appearance, falling back to the window. The popover material blends within that
window, with a light/dark wash, decorative border and masked shadow outside the
surface. It is not forced dark. The resident card sits flat on the page at the
mark's level: the sidebar field's soft fill, with no border or shadow. The
inline sidebar input has its own plain fill before there is a query.

The field is single-line native text: 18 points centered, 13 inline. Selection
uses the theme subtitle role; caret and input indicators stay system-owned.
An empty ordinary field keeps its search icon despite selected rows or late
favicons. The divider is one device pixel, inset 12 points.

Rows use a theme focus layer rather than table selection. Highlight/hover changes
fade without moving rows. Selected text is white, secondary text half-opacity;
selected favicons and command glyphs use their accessory tiles. Shortcut badges
read the live registry. The table fits its complete document to the clip width,
including native style margins, resets horizontal offset and preserves vertical
scroll position. With permanent scroll bars, set to always show or shown for a
connected mouse, both bars keep the scroller's width reserved whenever their
list shows, so rows, badges and highlights stay put when typing takes the list
past five rows and the scroller appears. Both bars end their address row that
much further in, so its trailing edge, site-search hint and info button stay on
the badge column. The header follows each re-tiling of the list, including a
change to the system's scroll bar setting while the bar is open.

## Result row content

History/navigation rows combine title and subdued display URL; tabs, commands,
searches and typed input retain their own presentation. Titles truncate at the
tail, URLs in the middle, without wrapping. Display-only URL cleanup preserves
underlying requests; file paths retain case and large data URLs are bounded.
VoiceOver receives the plain URL subtitle without decorative punctuation.

Calculator results show the input and answer; Return searches the original
expression and Tab fills the answer. Public internal addresses display `parc://`
without changing a native token's privileged origin. Current native result type
and publication revision remain part of presentation identity.

## Typing stability and ranking

Previous native results remain visible while the next query is pending. An
unanimated row diff keeps unchanged row views and reloads only changed cells.
Unselected Return or Tab first uses the current query's rows; an explicitly
chosen valid row retains its original request. A silent provider falls back to
current input after two seconds. Engine revisions, publication revisions and
row identity have distinct purposes and must not be conflated.

Actions whose label/target begins with the query lead. Chromium's genuine
default has the next preferred position, including when dedup merges it into an
open-tab row. The default survives display-type filtering. Identical-looking new
publications still replace request payloads and scope/deletion offers; retaining
a row view cannot retain stale actions.

Other commands, native results, tabs, local documents and top domains interleave
using Parc's scoring and native order. Ordinary results cap actions and tabs at
five each, documents at three, native rows at eight and top domains at one.
Page duplicates keep the open-tab action; configured title/host sites use their
specialized dedup key. Top domains come from that Profile's history, calculated
off the main thread per history revision. Search keys use terms, not URLs with
changing query metadata.

The domain regression suite covers native defaults merging with existing tabs,
search defaults, current publications, varied URLs and explicit user selection.
Ranking must not substitute a host allowlist, dot detector or reconstructed GET
for Chromium classification.

## Highlighted result text and ordinary Tab

The typed query is distinct from displayed completion. Explicit native selection
can project `fill_into_edit`; automatic default completion uses only the native
default match's actual inline suffix. Commands, tabs and local documents never
acquire completion from their titles.

End-of-field insertion may complete; deletion, mid-string edits, explicit caret
selection and marked text suppress it. Unchanged publications preserve the
caret. Deleting a suffix keeps literal input; later insertion may complete again.
Tab prioritizes an actual website scope offer, otherwise accepts completion
without submission. Up/Down wrap query results and keep input focus. Pointer
hover has a separate row highlight and does not change the Return/Copy target;
activation retains the original publication and payload.

## Split submission

Option–Return or Option–keypad Enter opens an eligible native request or original
tab immediately after the focused split pane. Existing tabs retain exact
identity; a tab already in the split receives focus. Current-Space tabs,
same-profile Favorites and tabs in another Space of that Profile are eligible
through the existing [split owner](split-groups.md).

The original session, selection, panes, Profile and native window/security
capabilities are rechecked after dismissal and before commit. Classification is
canceled by owner or document change. No URL-only substitute, placeholder or
partial transaction is created on refusal. Commands and extension keyword
actions have no split destination. Existing four-pane, popup, Peek, Library,
fullscreen and transfer restrictions apply.

## Force-open while keeping the command bar open

Command–Return, Command–keypad Enter and Command–Option–Return open an eligible
web result in a distinct background Today tab, preserving the query, highlight,
editor selection and original selected page/split. Repeated opens create fresh
identities. Native creation copies the full immutable request into each new
operation without consuming the displayed result's ordinary navigation token.
An existing web-tab result is classified into a new page, not transferred.

Only one operation may be pending. Editing, changed selection/scope, retirement,
transfer or replaced documents cancel it. Private requests keep the actual OTR
Browser; popups refuse. Failure keeps the original request for explicit retry.
Local Notes/Easels keep exact-ID switching. Typed commands usually retain ordinary
action/dismissal; Pin to Folder has the dedicated copy behavior below.

## Suggestion deletion

Eligible native rows offer **Delete Suggestion** on hover,
Command–Option–Delete and the matching accessibility action. The live provider
must identify the original primary match as deletable. Removal consumes that
exact deletion token and calls `AutocompleteController::DeleteMatch`; it never
deletes history globally from a displayed URL. New query/publication, Profile,
document or scope state revokes old offers.

The field/query stays open, completion clears and the adjacent surviving row is
selected while the provider republishes. Acceptance means provider invocation,
not guaranteed remote deletion. Commands, tabs and local history fallback rows
do not become deletable by their labels.

## Website search scope

A scope offer belongs to the selected result and current native publication.
Tab/the hint button uses its explicit offer, or a host-matched active template
for an eligible website/tab/history/top-domain row. Search results still require
an explicit keyword offer. Commands and unclassified text cannot acquire one.
Space entry additionally requires the exact preceding query plus one space and
the originating Profile's `omnibox.keyword_space_triggering_enabled` preference.

The active pill uses the actual engine name. Scoped results contain only genuine
keyword-mode requests: no app-side template expansion, default-search fallback,
history fallback or command dispatch. Scope changes preserve native selection
and composition. Empty Backspace/Tab and Escape use their distinct query/address
restoration rules; a second Escape dismisses the ordinary session.

### Website scope colour, pill and Tab hint

Bundled site colors or the approved favicon-derived color replace the theme pill
color; otherwise it uses the theme. Private profiles do not request favicon
colors, so unbundled engines retain the theme there. The hint says **Tab** or
**Space or Tab** from the native preference. Several matching engines resolve in
TemplateURLService order.

### Space entry and profile catalog

The source-owned website catalog installs missing active templates once per
persistent Profile. Existing keyword/GUID collisions, policy, user edits and
recorded deletions are preserved; installation does not change the default
provider. Private services use inherited templates without initiating writes.
Catalog readiness is prepared on a non-nestable UI task outside the service's
observer stack. Shutdown cancels preparation and settles waiting clients once,
without reviving the Profile or recursively notifying its observer list.

## Website scope menu

The pill's click, secondary click and accessibility action share Remove, Change,
Manage and Learn More. Change uses enabled templates from the same Profile.
Remove uses `KeywordEditorController` and its current policy/confirmation gates;
cancel preserves query and selection. Retired owners close only their own sheet.
Private sessions may change scope but cannot mutate the regular Profile's engine
list or open its management page. Extension keyword labels have no website menu.

## Native extension keyword scopes

Extension suggestions carry actual omnibox event tokens, distinct from URL/POST
requests. Synthetic provider URLs cannot be loaded or copied. Return sends
`omnibox.onInputEntered` before canceling the producer: Command–L requests the
current tab; Command–T a foreground tab; Command–Option–Return a background tab
while retaining the bar. Event dispatch does not guarantee an extension's result.
Split submission is unavailable because the extension API has no such target.

Actions retain the exact Profile/OTR permission, registration, page, weak
document, window and publication. Disable, navigation and late callbacks cannot
retarget them. Deletion uses the original extension content. A Note, Easel or
blank tab without a selected native page cannot start an extension scope;
Parc creates no dummy active-tab owner.

## Actions scope: command-only Type Travel

Tab on genuinely empty ordinary input opens Actions, with up to 100 registered
and typed commands and no search/navigation fallback. Empty Tab toggles out;
empty Backspace exits; Escape first returns to empty ordinary input. Nonempty
Tab and marked text remain native editing. Actions changes do not start native
autocomplete; exiting starts a fresh ordinary request in the same valid session.

## Typed Type Travel commands

| Command | Existing action owner |
| --- | --- |
| Focus on Space | Original Space/Profile selection; same-named Spaces show their position |
| Open Folder | Expand ancestors, reveal sidebar row and attention highlight; no page selection |
| Favorite / Unfavorite | Atomic original-item membership transaction |
| Pin to Folder / Space | Original sidebar collection move, retaining pages and saved homes |
| Pin to New Folder | Folder creation, Undo and rename |
| Duplicate Current Tab | Sidebar duplicate transaction and its Undo |
| Replace Pin with Current Page | Keep identity, replace saved home |
| Undo / Redo | Current window undo stack |
| Add/Convert Split | Existing split insertion and orientation owners |
| New document | Creation URL in original Space/Profile, offered from that Profile's visits |
| Search Settings / Air Traffic Control | Native search settings / local Links editor |
| Settings panes / Appearance | Existing Settings and appearance actions |

Pin to Space includes Spaces with different data and uses their existing
confirmation/move transaction; same-named Spaces show their position. Folder moves stay within the original Profile. Favorite/Unfavorite
requires uniform membership and preserves current page owners. Unsupported
collections do not fall back silently to the current tab.

Command–Option–Return on Pin to Folder copies the captured collection with fresh
item/folder/split identities in one save. Copies use original live addresses or
saved homes, not navigation histories or POST replay. Local document aliases
retain their existing document IDs after actual store validation; they do not
clone document bytes. One window Undo step takes the copy back; see
[folder commands](folder-commands.md#duplicate-undo-and-redo).

### MainMenu Type Travel data

`CommandBarMenuItemInfo` supplies titles, trigger phrases, icons and ranking
bumps, including Check for Updates and the bundled What's New page. Copy Parc
Info, Reveal Parc Data and Open Task Manager are local typed commands. Page tools
validate against the real key window, including after dismissal. Task Manager
can open for a crashed page because it does not require a live renderer.

Open Task Manager is offered in every ordinary window, including Notes, Easels,
the start page's bar and an empty window. With a web page showing it opens
through that page and isn't offered if the page refuses. Otherwise the window
opens Chromium's Task Manager with no page or Profile, as Chromium's own main
menu does, while the window is key, visible, unminimized and free of sheets.
Pop-ups list no typed commands. Window → Task Manager takes the same route, has
no default shortcut and can be assigned in Settings → Shortcuts; it stays out of
the bar's menu rows so the typed command is the bar's only Task Manager row. The
app offers the window route only when the engine provides it.

View → Collapse Pinned is one menu row whose title follows the window's active
Space, so the bar offers Collapse Pinned or Expand Pinned and only the phrase
that applies matches. Show or Hide Collapsed Pinned Icons switches every
window's folded header between its icon stack and a plain count. Neither has a
default shortcut; both can be assigned in Settings → Shortcuts. See
[the Pinned section](sidebar-resize.md#pinned-section).

Settings destinations cover Membership, General, Spaces (Open Space Preferences;
Profile stays a hidden keyword), Shortcuts, Links,
Icon and Advanced. Appearance switches reuse window Undo. Getting Started is
intentionally absent: Replay onboarding belongs only in Settings → General.
AI, a separate mini browser window, vendor account support/services and live
integrations remain excluded; local diagnostics and Parc updates do not inherit those exclusions.

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

## Checks and remaining work

`tests/CommandBar` covers real app decisions for editing, scope, publication
identity, default ranking, row diffs, submission, menus, typed targets and the
compact editor's width, caps and column alignment, the resting Control–Space
field and permanent scroll bars. Drawn without a window, the pill's and the
editor's text and icon must start at the same spot and on the same baseline,
then glide only sideways, for Control–Space, typing and a click. The
command-bar scripts build focused production components; native search has
separate owner/lifecycle coverage. Follow [the working contract](../AGENTS.md)
before running checks.

Current source still has these separate limitations, tracked in [the backlog](backlog.md):
Restore Data has [backups and a startup rescue](windows-lifecycle.md#saved-sidebar-backups-and-startup-rescue)
but no window to browse and restore them.
