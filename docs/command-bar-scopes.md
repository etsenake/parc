# Command bar scopes and typed commands

This guide covers the [command bar](command-bar.md)'s website search scope and
site catalog, extension keyword scopes, the Actions scope and typed Type Travel
commands. Ordinary results, ranking and submission are in the
[field and results guide](command-bar-results.md).

## Website search scope

A scope offer belongs to the selected result and current native publication.
Tab/the hint button uses its explicit offer, or an active template for an
eligible website/tab/history/top-domain row on the template's search host, one
of its subdomains (`www.linkedin.com` for `linkedin.com`, `en.wikipedia.org`
for `wikipedia.org`) or its parent site (`spotify.com` for `open.spotify.com`).
An exact host wins; otherwise the most specific template the row is a
subdomain of; otherwise the first template that is a subdomain of the row. A
single-label template, such as an intranet `wiki`, never claims hosts under it.
Search results still require an explicit keyword offer. Commands and
unclassified text cannot acquire one. Space enters only when the text it follows
at the end of the field, replacing any selected completion, is the engine's whole
keyword, such as `github.com`, ignoring case, and the originating Profile's
`omnibox.keyword_space_triggering_enabled` preference allows it. Only a Space
keystroke enters; deletions, pastes, Undo and marked text never do. A site name
or partial address such as `github` followed by Space stays ordinary input, so
`github some-repo` searches the default engine; Tab still enters the offer.

The active pill uses the actual engine name. Scoped results contain only genuine
keyword-mode requests: no app-side template expansion, default-search fallback,
history fallback or command dispatch. Scope changes preserve native selection
and composition. Empty Backspace/Tab and Escape use their distinct query/address
restoration rules; a second Escape dismisses the ordinary session.

### Website scope colour, pill and Tab hint

Bundled site colors or the approved favicon-derived color replace the theme pill
color; otherwise it uses the theme. Private profiles do not request favicon
colors, so unbundled engines retain the theme there. The hint says **Space or
Tab** only while Space would enter, under the keyword rule above, and otherwise
**Tab**; it follows each edit and caret move, even while earlier results stay
on screen. Remaining ties between matching engines resolve in TemplateURLService
order.

### Space entry and profile catalog

The source-owned website catalog installs missing active templates once per
persistent Profile. Existing keyword/GUID collisions, policy, user edits and
recorded deletions are preserved; installation does not change the default
provider. Private services use inherited templates without initiating writes.
Catalog readiness is prepared on a non-nestable UI task outside the service's
observer stack. Shutdown cancels preparation and settles waiting clients once,
without reviving the Profile or recursively notifying its observer list.

The catalog holds site searches, not search engines: Google Drive, Gmail, Google
Maps, Google Calendar, Google Docs, Dropbox, Amazon, GitHub, Figma, X (as
`x.com` and `twitter.com`), YouTube, Wikipedia, Reddit, SoundCloud, Asana,
LinkedIn, Apple Music and Spotify, each using the site's own search page, and
they work with Tab. Chromium also learns shortcuts from sites that advertise a
search, such as GitLab. Those stay inactive, with no Tab offer, until the user
activates or edits one in Manage search or makes it the default. An unused
learned shortcut with a catalog site's keyword gives way to the catalog entry
when it installs.

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
