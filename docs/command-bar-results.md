# Command bar field and results

This guide covers how the [command bar](command-bar.md) looks, what its rows
hold, how they rank and complete, and how a chosen row opens. Website and
extension scopes, Actions and typed commands are in
[scopes and typed commands](command-bar-scopes.md).

## Result ownership

- Native autocomplete rows retain their actual `PCNativeSearchNavigation` token,
  including classified URL, POST body, headers, transition, Profile and one-use
  consumption. Display strings are not replacement requests.
- Open-tab rows retain the original tab ID and say **Switch to Tab**. They use
  existing Space/window selection and transfer, without reloading the URL.
- Archived-tab rows say **Archived · 3 days ago** and Put Back through Library's
  path into the current Space; they never split or open in the background.
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
dismisses it. Favicon callbacks also validate the exact Profile, URL and
session. A dismissed session cannot clear or update its replacement.

Command–Shift–C copies the highlighted row's actual URL; it is unavailable for
commands or unresolved input. Command–C remains ordinary native selected-text
copy. See [copy commands](keyboard-navigation.md#copy-commands).

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
Cut-off left-to-right text fades over its last 24 points, 17 inline, inside the
field and clear of its controls, until it fits or is scrolled to its end. An
empty ordinary field keeps its search icon despite selected rows or late
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

Page rows show their title, then a dash and just the site, as in
`Dashboard — fullscript.okta.com`. An empty or address-only title gives way to
the address, shown once without scheme, `www.`, query, fragment or trailing
slash, as in `fullscript.okta.com/app/UserHome`. Only the host is lowercased;
escapes become readable only where Chromium's display rules allow, and hosts
stay ASCII without a user name. Paths are cut from the end and an over-long host
shows its end, so the real site always shows. Typed words are drawn slightly
brighter. VoiceOver reads the plain subtitle without the dash.

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

When the input has no spaces, is still a prefix of a site's host (with or
without `www.`) and that default is a deeper page on the same site, such as the
page a sign-in service forwards every login to, the site's root takes the
default's position and the default follows it. The root is that site's top-domain
row, or Chromium's own row or an open tab for the root when one covers it. With
none of these the default keeps the lead: Parc never invents a root request.
Return uses the root row's own request or address; typing a `/` or more of the
path hands the lead back to the default.

When Chromium's default is a search, words also match titles of open tabs, the
1,000 latest archived tabs and 1,000 latest pages of Parc's newest 5,000 visits;
each must start a title or site word, and order, a leading match, whole words,
recency and visits score higher. Up to three follow the default, above
suggestions. A cached index built off the main thread per archive or history
change bounds each keystroke; new matches wait while a row is picked.

Other commands, native results, tabs, local documents and top domains interleave
using Parc's scoring and native order. Ordinary results cap actions and tabs at
five each, documents, archived tabs and past pages at three, native rows at eight
and top domains at one. Duplicates of a page, and rows with its title and path
under another query or fragment, merge into one row, preferring an open tab, then
an archived tab, then Chromium's row at the best merged rank, here and in the
empty list, but two open tabs never merge; configured title/host sites use their
own key. Notes come from the Space's Notes folder: titles match like any document,
and from three letters on, words in a note's text find it too, ranked below title
matches. A note already open in a tab shows once, as that tab. Private and pop-up
windows offer no notes. Top domains come from that Profile's history, calculated
off the main thread per history revision, one per host and port, opening the root
with the latest visit's scheme. A root page title names the row; without one its
address shows once. Search keys use terms, not URLs with changing query metadata.

Ranking never substitutes a host allowlist, dot detector or reconstructed GET for
Chromium classification; regression suites cover each case above.

## Highlighted result text and ordinary Tab

The typed query is distinct from displayed completion. Explicit native selection
can project `fill_into_edit` and a selected top-domain row its domain. Automatic
default completion uses only the native default match's actual inline suffix,
except that a leading site root fills in just the domain: `fullscript.ok`
completes to `fullscript.okta.com`. Commands, tabs and local documents never
acquire completion, including a tab leading for a site root.

End-of-field insertion may complete; deletion, mid-string edits, explicit caret
selection and marked text suppress it. Unchanged publications preserve the
caret. Deleting a suffix keeps literal input; later insertion may complete again.
Tab prioritizes an actual website scope offer, otherwise accepts completion
without submission. Up/Down wrap query results and keep input focus. Pointer
hover has a separate row highlight and does not change the Return/Copy target;
activation retains the original publication and payload.

An untouched completion keeps the typed text in view, from its start or, if
longer than the field, its end, then about a dozen completed characters trailing
off under the fade, through publications, arrowed rows, resizing and the first
keystroke. After you move the caret, select or scroll, and for marked text, Tab
and right-to-left text, the field scrolls natively until the next fill. The
row's page title follows an inline completion in the secondary text colour and
field font, as in `fullscript.okta.com — My Apps Dashboard`, outside the value,
selection, copy, undo, submission and Tab. It hides for searches, address-only
titles, suppressing edits, caret moves, marked text, Tab or under four ems of
room, else truncates. VoiceOver reads it separately, without the dash, and
announces it quietly when it changes.

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
Notes open by file and Easels by exact ID. Typed commands usually retain ordinary
action/dismissal; Pin to Folder has the dedicated
[copy behavior](command-bar-scopes.md#typed-type-travel-commands).

## Learning what you pick

As in Chrome, the bar teaches Chromium's shortcuts provider which page you pick
for what you type, so `okta` soon brings back the page you always choose. Native
rows carry the text typed when they were published; rows the bar classifies
itself, such as typed input, top domains and open tabs, carry the current query.
Return, a chosen row, Command–Return, Option–Return, Add Split and Peek record
the pair through `ShortcutsBackend::AddOrUpdateShortcut` once the page commits
with a 2xx, 401 or 407 response, unless the network diverted it to its own
search page, as Chromium's intranet redirect detector reports. Failed, aborted,
same-page and empty-input picks don't count, nor do extension keyword actions,
tab switches, commands, documents, pop-up windows, a Profile being removed or
private windows, whose Profile has no shortcuts backend. Learned rows always
offer Delete Suggestion, and deleting a suggestion or history removes their
shortcuts.

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
