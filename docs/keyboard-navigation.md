# Keyboard navigation and shortcuts

Parc has one native command registry. Menus, Settings, command search, tooltips
and education read that registry; each action keeps its original browser, page,
document or selected-item owner. [Settings](settings.md) describes recording,
conflict handling and priority controls. [Command bar](command-bar-results.md) covers
query editing and result submission.

## Tab selection

| Command | Default | Owner |
| --- | --- | --- |
| Next / Previous Tab | Command–Option–Down / Up | Wrapped positional traversal in the current Space |
| Next / Previous Tab (Alternate) | Command–} / Command–{ | The same positional traversal |
| Switch to Next / Previous Recent Tab | Control–Tab / Control–Shift–Tab | Held-key recent-tab switcher |
| Cycle Tab Forward / Backward | Disabled | Retained per-Space selection-history implementation |

Positional order is Favorites, root Pinned items, expanded folder descendants,
then Today. A split is one item. Current split ownership takes precedence over
saved overlapping layouts. Archived, foreign-profile and unavailable native
pages are ineligible; an unavailable split member does not silently break the
split into individual destinations. A held chord repeats and wraps. No other
item means a consumed, silent refusal. Folding Pinned doesn't change this order.

`TabSelectionHistory.isEnabled` is false: its commands are not registered and
no history stack is recorded. Saved custom bindings remain stored for possible
future use. The retained implementation stores original identities and focused
split panes, truncates its forward branch on a new selection, skips retired
items and stops at endpoints. It never reconstructs navigation from URLs.

## Saved bindings

`KeyboardShortcuts.swift` owns registration, validation and persistence in
`keyboard-shortcuts.json`. `KeyboardShortcut` formats and matches chords.
Bindings retain stable command IDs, current menu items and registry revisions.
Native editing, marked text and renderer-consumption arbitration remain in the
existing input pipeline; a presentation surface must not add another one.

Migrations preserve explicit custom/disabled chords, priorities and unknown
records. A new default cannot steal a saved chord. Early held-MRU `nextTab:` /
`previousTab:` overrides migrate to `cycleToNextRecentTab:` /
`cycleToPreviousRecentTab:`. Ambiguous legacy unbound creation commands stay
unbound until reset. Old implicit copy priorities retain their previous behavior.

Additive markers keep migrations from reapplying after a deliberate edit.
Individual Reset checks conflicts; Reset All deliberately restores current
defaults. Atomic write failure preserves the original file and reports failure.
Saved conflicts remain visible in Settings but supply no executable or advertised
binding. Registry changes invalidate retained commands and refresh live help.

## Essentials

Settings → Shortcuts → Learn Essential Shortcuts and Help → Essential Keyboard
Shortcuts share one education window owned by the originating browser. Its four
rows are New Tab, Recent Tab, Copy URL and Add Split View, using live bindings.
View All closes education and opens that browser's Shortcuts pane. Commands
retain education; Escape dismisses the browser's command bar. Closing the browser
retires education. An expired command never targets another window.

The window is 475 × 388 points, with four 73-point rows. Keycaps are passive
presentation with semantic accessibility values. The current registry receives
actual key events, including repetition and held-MRU release; education adds
neither a global monitor nor simulated input.

## Copy commands

Edit places the three commands after Copy:

| Command | Default | Payload |
| --- | --- | --- |
| Copy URL | Command–Shift–C | Current committed page URL, or highlighted command-bar result URL |
| Copy URL as Markdown | Command–Option–Shift–C | Actual title and URL as one escaped Markdown link |
| Copy URL as Quote | Command–Control–Shift–C | Original main-frame selection's native text-fragment link |

`PCNativePage(CopyLink)` retains the original WebContents, weak document, window,
selection and clipboard revision. Quote uses
`TextFragmentReceiver.RequestSelectorForSelection`, with a ten-second deadline.
Navigation, lost focus, changed selection/clipboard, retirement or a replacement
request cancels it. Failure leaves the clipboard untouched rather than reporting
a plain URL as a quote. No injected JavaScript or new page is involved.

Live-page formats pass Chromium's clipboard policy with the original document
and private identity. Policy replacement produces restricted-copy feedback.
Rejected live eligibility cannot fall through to an unloaded model-tab copy.
Command-bar result copying and unloaded model tabs retain their separate
plain-string routes. Markdown preserves query and fragment; no tracker-removal
behavior is implied. Its title follows the sidebar's
[Markdown label escaping](sidebar-selection.md#select-all-and-plural-commands).

[Shared Quote](settings.md#shared-quote-affordance)'s setting controls only its
mouse-selection affordance. It does not disable the explicit command or its
custom binding. Both paths reuse the original-document generator and policy.
Feedback uses [toasts](toasts.md), preserving focus and announcing the result.

## Sidebar keyboard focus

Control–Space and Reveal Current Tab enter a sidebar command session with a
stable-ID cursor separate from page selection. Up/Down traverse visible folders,
pages and whole splits. Crossing an endpoint clears the cursor; another arrow
enters at the opposite endpoint. Highlighting does not select or navigate.

Return on a folder toggles its persisted disclosure and keeps input open.
Return on a page/split closes input and selects the original item. Without a
highlight it simply closes. Folder persistence failure preserves the old state.
A removed target or collapsed ancestor clears an unavailable cursor instead of
retargeting it. Left/Right remain native field editing.

Typing expands the sidebar-anchored command surface; clearing the query restores
its independent cursor. Hidden-sidebar entry uses the floating sidebar and holds
it until dismissal. The session leases Space, Profile, page, view and responder;
selection change, transfer, retirement, security presentation, minimization,
deactivation or explicit sidebar hiding invalidate it.

## Cross-surface traversal and return

| Surface | Focus owner and return |
| --- | --- |
| Page and split panes | Native page-side key views, then sidebar gate; Tab does not select a different pane |
| Sidebar | Linked header/address/list/dock controls; hidden sidebar is bypassed |
| Command bar | Native field/editor; closing targets the current content's Find, else Peek, page or local document |
| Menus and popovers | Native tracking/presentation; original focus restoration only while valid |
| Sidebar preview | Card controls, then validated opener through `SavedFocus` |
| Peek | Its page and controls; sidebar remains reachable; dismissal returns to the original parent |
| Find and Library | Find returns to its original document; Library returns to selected content |
| Tab switcher and priority cue | Preserve the parent's responder |

A saved responder may return only inside the currently eligible target. A
sidebar/toolbar control or another pane's responder cannot override the
command-bar close target. A blank tab gives focus to its window. Outside-click
dismissal preserves the clicked destination. See [sidebar accessibility](sidebar-accessibility.md)
and [Peek](peek.md) for their ownership rules.

## Bulk folder disclosure

Collapse All Folders and Expand All Folders are registered commands without
default chords. They capture the original window, Space, Profile and folder
snapshot, revalidate after dismissal, then atomically persist every folder's
state, including hidden descendants. They do not change page selection, split
geometry, URLs or another Space. Stale ownership, changed folders and failed
writes cannot publish partial disclosure.

## Creation and capture default bindings

| Command | Default |
| --- | --- |
| New Note | Control–Shift–N |
| New Note in Split View | Control–Option–N |
| New Easel | Control–Shift–E |
| Capture Portion | Command–Shift–2 |
| Blank Window | Control–Command–N |
| Close Window | Command–Shift–W |
| Enter / Exit Full Screen | Command–Control–F |
| Open current Peek in its Space | Command–O |

New Folder has no default, avoiding the New Incognito Window chord. Capture
Visible Area, Portion and Full Page enter the same editor; Portrait is framing
inside that flow. Inside capture mode, unmodified E and R switch between Element
and Region, V captures the visible area, F the full page, Return the outlined
area (or the visible area) and Escape cancels. Replay onboarding remains
exclusively in Settings → General.

## Alternate navigation and page-tool bindings

Command–Left/Right navigate Back/Forward only when the original responder is
not a native text field/view descendant. Bracket navigation remains separate.
F12 is an independent Developer Tools binding using the normal page-tool owner
and Use Both priority. Only registered function keys enter priority arbitration;
printable unmodified keys and autorepeat do not gain a new interception path.

Zoom In's Command–equals and Zoom Out's Command–Shift–minus are supplemental
menu equivalents, not extra editable commands or search rows. Customizing or
disabling the parent, or assigning another command the chord, suppresses them.
Shift-produced `+`, `{` and `}` use native symbolic matching. An explicit saved
physical chord wins even when unavailable, preventing menu fallback from
bypassing it. Input-source changes refresh equivalents and invalidate tokens.
Globe/fn–F remains a fixed Full Screen equivalent outside the editable registry.

Parc names a physical key by what the current layout types without modifiers.
On layouts whose number row types accents or symbols there, such as French,
Belgian, Czech, Slovak and Lithuanian, a number-row key is instead the digit it
types with Command or Shift. Page shortcuts, the recorder and system-shortcut
conflicts then see Command-Shift-2 as Capture Portion and Command-1 as the first
item. A main binding on the key's own character still comes first, so Czech
Command-+ stays Zoom In and a chord recorded earlier as `é` keeps working. An
alternate such as Command-Shift-minus for Zoom Out keeps the key only while the
digit's shortcut is free, since alternates never take a main binding's key.

## Close the original browser window

Close Window captures the real normal, private or popup browser window. After
command-bar dismissal the same window must still be key, visible, closable and
free of sheets or a pending close. A one-use weak invocation cannot fall back
to a browser behind Settings or another auxiliary window.

`performClose` preserves Note save/composition barriers, transfer recovery,
native beforeunload consent and private-context retirement. Dispatch is not
confirmation that the window closed. It never archives tabs or forces `close()`.

## Full Screen on the original browser window

The command captures the original eligible window and calls `toggleFullScreen:`.
AppKit supplies Enter/Exit labeling; native notifications own transition state
and engine synchronization. Retired windows, sheets, pending close and changed
key ownership refuse. The command does not invent a completion or infer
auxiliary-window capability from a normal browser.

## Exit the original context

Exit defaults to Escape with Use Both priority. The current Peek takes priority
and retains its media confirmation and close consent. Otherwise a genuine
content-fullscreen token exits its original Chromium document; it cannot fall
through to toggling an ordinary window. Only an actual ordinary fullscreen
window uses that native transition.

Physical Escape remains independently available to AppKit controls, IME and the
renderer, even when the configurable Exit chord changes or is disabled. Prefer
Parc can take the existing pre-renderer route; Use Both uses the existing
acknowledgment and Press Again policy. No second raw event monitor is installed.
Accepted dispatch is distinct from completed dismissal or transition.

## Find commands and original document ownership

The registered Find group has Find (Command–F), Find and Replace
(Option–Command–F), Next (Command–G), Previous (Command–Shift–G), Use Selection
to Find and Jump to Selection (Command–J).

Web pages support Find, Next, Previous and Use Selection through Chromium's real
Find service. Replace and Jump are unavailable there. A focused original Note
editor routes all six entries to its body's native Find bar; those titles do
not imply replacement or jump behavior. An ordinary text field is not a generic
consumer. Library Find owns its Search field.

Queries are weakly stored per page/document revision. Navigation or selection
change dismisses the old field without focusing a successor. There is no
cross-Profile Find pasteboard seeding. Return/Down and Shift–Return/Up navigate
results; composition remains native. Escape returns only to the original page.

The floating `PageFindView` is nominally 300 × 32 points, ten points from the
page's top/right, contained in ordinary, split and Peek bounds. Query, document
revision, count, ordinal and completion come from the original `FindTabHelper`.
Updates are coalesced outside its observer stack; stale documents cannot update
the field. Unknown counts hide the counter; zero shows Not Found. Results do not
rewrite field selection or composition. Native focus, Tab and button behavior
remain intact; visibility changes are immediate.

### Numbered targets and native-text Find — KB04

Command–1…8 selects that ordinal sidebar item; Command–9 selects the last by
default. Favorites ordering and ninth-item settings apply first. Split groups
remain atomic; unavailable items do not shift another item into their slot.
Every Space gets a `spaceN` command; only the first nine receive Control–1…9.
Rename/reorder updates metadata, removed ordinals leave discovery, and saved
bindings survive disappearance and return. Menu tracking retains captured
identities while activation refreshes registrations.

## Text formatting menu

Edit → Format formats a Note body or an Easel text box, grouped like Apple's
Format menu: Font (Bold, Italic, Underline, Strikethrough, then Bigger and
Smaller), Heading 1–3 and Body, Bulleted and Numbered List, Indentation and Add
Link…. Every item calls the code the editor's own controls use: the Notes
selection bar and paragraph menu, the Easel style bar, and Tab/Shift-Tab for list
indent, so text and Undo match. Checkmarks show the selection's emphasis and
paragraph style, and Add Link becomes Edit Link on linked text.

One responder-chain action reaches the Note editor or Easel canvas
([menu](../Sources/ParcApp/TextFormatMenu.swift)). Items are enabled only while
that body, edited text box or its style bar has focus in the key window without
composition. Notes format every selected range, like their selection bar; Easels
use the first, like their style bar. Bigger and Smaller step Easel sizes, also for
selected text boxes, and stay disabled in Notes. Titles, the address bar, other
plain fields and web pages, including pages inside Easels, have no owner, so
every item is disabled there.

Bold ⌘B, Italic ⌘I and Underline ⌘U use the reserved chords, so they stay fixed
like Undo and no Parc command can claim them. On a page the engine's editing
bindings get them first and the menu only sees keys the page ignored. Heading 1
⇧⌘H, Body ⇧⌘B, Bulleted List ⇧⌘7, Numbered List ⇧⌘9 and Add Link ⌘K are
editable Prefer Websites defaults; a saved custom chord keeps its owner. Apple's
other standard keys belong to Parc commands and stay off: Title ⇧⌘T, Subheading
⇧⌘J, Indentation ⌘] and ⌘[, Bigger and Smaller ⌘+ and ⌘−. Strikethrough has no
standard key. Show Fonts, Show Colors, alignment, checklists, quotes, highlight,
monospace and Copy/Paste Style are omitted because these editors lack them;
Easel typefaces and text fill stay in the style bar.

Inside a note the open menu shows the note's own shortcuts instead: Heading 1–3
⌥⌘1–3, Body ⌥⌘0, Bulleted List ⌥⌘5, Numbered List ⌥⌘6 and Strikethrough ⇧⌘S,
with none for Bigger, Smaller and Indentation. Closing the menu puts Parc's chords
back, so Easels and saved custom shortcuts never change. A Format chord that the
note uses for something else gives way to the note: ⇧⌘H reapplies the last colour
in a note and does nothing when there is none, instead of making a Heading 1.
Format chords the note doesn't use, such as ⇧⌘7, still work there.

## Shortcut key text

`display` and `keyLabel` supply text labels; `symbols` supplies Settings caps;
`keycapSymbols` spells TAB for Essentials and tooltips. Space displays as ⎵,
Enter as ⌤ and Clear as ⌧, while `spokenDisplay` says Space, Enter and Clear.
Named keys, function keys and menu equivalents share one formatter, so recording
and default display agree. Passive keycaps do not add interactive accessibility
elements or change storage/matching. macOS doesn't deliver function keys past
F20, so the recorder and its labels stop at F20 by design.

### Keypad keys

Keypad 0–9, `.`, `,`, `+`, `-`, `*`, `/`, `=`, Clear and Enter are keys of their
own. The recorder reads the physical key: a keypad digit or operator is saved as
its character plus the combining keycap mark (Control–keypad 1 is `1⃣`, shown as
⌃Keypad 1), Clear as AppKit's Clear character, and Enter keeps its existing
character. The decimal key is named by what the current layout types, through
the recorder's own layout translation, so it reads Keypad , on comma-decimal
layouts while it stays saved and matched as the same physical key. Digits and
operators need Command, Control or Option like the number row; Clear, like Home,
may stand alone. Compact Essentials caps widen to fit the keypad name. Saved
records keep their exact fields; an older Parc loads a keypad digit or operator
as a valid key it can never press, so the binding stays inert there, never
clashes and survives its saves. Clear is an ordinary special key there.

AppKit menus match key equivalents by typed character and ignore the keypad
flag. Their shortcut column draws a single typed character, and an attributed
title cannot reach that column, so the menu bar and system context menus cannot
show a keypad binding. It stays off their items (Clear's character stays), while
the + menu, which Parc draws, shows it like any shortcut: modifier glyphs keep
their tracking and the key name stays untracked. Parc matches keypad bindings
itself: pages through the pre-renderer arbitration, other focus in the main
menu's key-equivalent pass before AppKit's search. A keypad press takes a keypad
binding first, even an unavailable or conflicted one that then does nothing;
otherwise it falls back to the character match, so older bindings answer both
keys. A number-row press never reaches a keypad binding, and an app-modal dialog
blocks keypad bindings as AppKit blocks menu items. With Mouse Keys on, macOS
consumes the keypad before Parc sees it.

## Complete command inventory reconciliation — KB03

The menu registry includes Blank/New/Private windows, local profiles, Duplicate,
Reveal Tab, Library/Downloads/Media/Documents, Spaces, Extensions, native Window
Zoom/Bring All to Front, Stay On Top, Task Manager, page tools, app updates and local What's
New. Manage Spaces is implemented. Notes and Easels keep their formatting bars
beside the [Format menu](#text-formatting-menu). [Typed commands](command-bar-scopes.md#typed-type-travel-commands)
add contextual operations without inventing menu command identities.

### Excluded by the ledger

A separate mini browser window, Boosts, AI commands, dedicated live integrations
and vendor account/support services remain excluded. Parc's Check for Updates, Release
Notes, Copy Parc Info and Reveal Parc Data are local product features and remain
included. Getting Started is not a second onboarding replay entry point.

## Live binding discovery and copy education — KB38

Menus, Shortcuts, Essentials, priority cues, command results, onboarding Ready
copy and tooltip keycaps read current valid bindings. `bindHelp` uses weak
control registrations and refreshes accessibility help when Reload/Stop or other
control roles change. Context menus update without replacing captured item
owners. A retired binding is not advertised; original-target dispatch still
rechecks revisions and availability.

Copying the complete current URL through the command field can show **Copy links
faster by pressing** and the current Copy URL chord. `SuperCopyUpsell` validates
the original panel/window/Space/Profile/page and records its local cooldown only
after feedback attaches. Subsequent displays require two calendar days. It
retains no copied-page history and contacts no service. A binding change,
retirement, sheet, fullscreen, scrolling or replacement retires the toast.

## Checks and remaining work

Focused suites include `tests/KeyboardNavigation`, `ContentFocusRequestTests`,
`SidebarWindowKeyLoopTests`, the shortcut/command scripts and the Find/Peek
components. Full Swift typechecking is the iteration check; finished material
Swift work also needs whole-module SIL under [the working contract](../AGENTS.md).

Frame-focus changes invalidate pending page shortcuts through a Parc-owned
subscription registry, at the focused-frame change itself. Each page owns its
subscriptions; callbacks remain safe if a shortcut closes the page.
