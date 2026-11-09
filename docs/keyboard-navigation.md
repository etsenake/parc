# Keyboard navigation, copy commands and shortcut education

Tab selection has three independent owners. The command registry stores their native menu selectors and current bindings; the browser controller performs a real selection using existing tab and page identities.

| Command | Default | Selection owner |
| --- | --- | --- |
| Next / Previous Tab | Command–Option–Down / Up | Wrapped positional traversal in the current Space |
| Switch to Next / Previous Recent Tab | Control–Tab / Control–Shift–Tab | Existing held-key MRU switcher, preview and release/commit owner |


Selection history is transient window state, partitioned by Space. Re-selecting its current item refreshes focus without appending. An ordinary different selection truncates the forward branch and appends; cycling first moves the cursor and then uses the same production selection path. Missing or unavailable entries are skipped; endpoints stop. A refused selection restores the cursor. History stores original identities and split focus, never URLs or navigation reconstructions. Native modal, keyboard-lock, fullscreen, transfer, close and Peek gates remain authoritative.



## Saved bindings

The current `keyboard-shortcuts.json` separates command identities. Parc previously named held MRU selectors `nextTab:` and `previousTab:`. Version-one overrides, including explicitly disabled shortcuts and priorities, move to `cycleToNextRecentTab:` and `cycleToPreviousRecentTab:`. A new default is disabled if it would steal a saved custom chord. The atomic migration preserves the original file on a write failure and reports the failure. Reset uses the existing conflict checks; Reset All deliberately restores all current defaults. Native editing/IME, renderer consumption and per-command priority dispatch continue through the original menu item and revision validation.

## Essentials


The installed reference is 475 × 461 points with five 73-point rows. Parc preserves its row spacing and width and removes the excluded row, producing a 475 × 388-point window. The fixed light/dark popover palette, Marlin heading, shared keycap face and native View All control follow the attributed owners below. The parent reducer determines command retention, Escape and the Settings destination. The included-only outer frame and explicit native Copy command-window capability are Parc adaptations; exact repeat, focus/AX and motion comparison remains recorded in the parity ledger.

## Reference mechanism




## Copy commands

Edit places Copy URL, Copy URL as Markdown and Copy URL as Quote immediately after Copy. Each retains its own native selector, current menu key equivalent and configurable priority; the existing plain command keeps `copyCurrentURL:` when moving from Tabs to Edit.

| Command | Default | Payload owner |
| --- | --- | --- |
| Copy URL | Command–Shift–C | Current committed native page URL; the command bar instead supplies its genuine highlighted result URL |
| Copy URL as Markdown | Command–Option–Shift–C | Current native page title and committed URL, serialized as one Markdown link |
| Copy URL as Quote | Command–Control–Shift–C | Chromium generates a text-fragment selector for the original main-frame selection and appends it to the source URL |

The native `PCNativePage(CopyLink)` category keeps the original WebContents, weak document, window, selection and clipboard revision. Quote calls `TextFragmentReceiver.RequestSelectorForSelection`; the context menu's preemptive `RequestSelector` is not suitable for a global command. A hidden, retired, destroyed, navigated or unfocused page, changed selection, changed clipboard, or unavailable generator cancels the request. A second request replaces the first. No JavaScript is injected and no new page or navigation is created. The current Chromium main-frame eligibility and a ten-second generation deadline are explicit implementation choices. Selection-link failure leaves the clipboard unchanged; it never substitutes a plain URL and reports success.


Version-three shortcut storage introduces recovered browser priority for the three copy selectors. Old files omitted Prefer Websites even when explicitly chosen; migration therefore records that old behavior for the existing plain command. New commands default to Prefer Parc, while existing custom or disabled chords and explicit priorities are preserved. Newly introduced chords cannot steal saved custom bindings. Explicit reset adopts the current recovered default. The existing IME, native editing, renderer-consumption and menu-revision pipeline remains the sole key dispatcher.


### Copy evidence





## Sidebar keyboard focus

Control–Space and Tabs → Reveal Current Tab enter a sidebar command session. The original active tab remains selected while an independent stable-ID cursor outlines an eligible sidebar item. Up/Down traverse visible typed folder/page/split items; positional tab navigation retains its separate selectable-only list. Crossing either endpoint clears the highlight; another arrow enters at the opposite endpoint. Return on a folder toggles disclosure and keeps input open. Return on a page/split closes the input and selects the original item through the existing native selection owner. Return without a highlight closes without creating a tab. No preview arrow writes browser selection or reopens a URL.

The existing command panel anchors its empty native text field over the sidebar address placeholder. Typing expands the sidebar-anchored result surface and uses the existing Chromium omnibox tokens, exact-tab targets and validated menu commands. It does not install another global key pipeline. Native field editing and marked-text handling remain AppKit-owned. Emptying the query restores the independent sidebar cursor. Hidden sidebar entry uses the existing floating presentation; active input holds that presentation until dismissal.

The session retains its original Space, profile, selected page, native view and responder. Escape restores that responder only while the original owner remains valid and active. Closing, minimizing, deactivation, security presentation, transfer, selection changes, library/native-fullscreen changes and explicit sidebar hiding invalidate or dismiss the session without activating another owner. Page/split Return revalidates the real browser window after removing the child panel. A newly available Control–Space default cannot take a saved custom chord; explicit custom/disabled focus bindings and existing priorities remain intact. This additive collision protection preserves the current shortcut document version.

### Sidebar reference attribution





## Folder Return in the sidebar keyboard session

The sidebar input's Up/Down list includes ordinary and empty folders in the actual mixed hierarchy, with expanded descendants and one entry per whole split. This list is separate from positional tab navigation, whose commands skip folder rows. Original typed IDs keep the highlight stable across reorder; disappearance or a collapsed ancestor clears an unavailable child rather than selecting a neighboring item. A split with an unavailable original member is omitted as a whole. Highlighting never changes the page selection, native focus or multi-selection.

Return on an ordinary folder toggles only its disclosure and retains the command input, folder highlight, active page and Space. The exact folder/Space/Profile is validated and the new disclosure persists before publication. A stale target or failed save cannot publish a partial change. Page/split Return retains the existing close-and-select owner, and empty-highlight Return closes. A separate noninteractive outline overlays the original folder/split/tab row without replacing its active or multi-selection border. Favorites use their original tile view.




## Cross-surface traversal and return

KB25 closes the browser window's keyboard and accessibility map. Each surface has one native owner; no surface adds another key pipeline, and selection stays separate from every keyboard highlight.

| Surface | Entry | Tab / Shift-Tab | Return when it closes |
| --- | --- | --- | --- |
| Sidebar | Tab from the page side, Control–Space session, list stop | Linked chain, gate → header → address → … → "+" → page side; hidden sidebar bypassed ([sidebar accessibility](sidebar-accessibility.md)) | Session Escape: command-bar rule below; a hidden sidebar never receives restored focus |
| Popovers (theme editor, Site Control Center, permission card, pickers, history chooser) | Their own window becomes key | Native, inside the popover | Parent window key again with its responder unchanged [C]; close delegates post no focus request [D]; history chooser and previews use `SavedFocus` |
| Sidebar preview cards | Keyboard-opened card owns its controls | Card controls; cards are off the page side | `SavedFocus` restore of the opener |
| Peek | Original Peek page (`PeekFocusReturn`) | Peek controls and page are the page side; the dimmed pane is not; Tab past the Peek page goes to the sidebar gate, Shift-Tab from the sidebar's first stop to the Peek's last | Dismissal: original parent; expansion/split: same child; refused close keeps the control |
| Find, Library, tab switcher, priority cue | Find field; Library content; switcher and cue never take focus | Native | Find → its page; Library → selected content; switcher keeps the parent's responder |

Selected page versus keyboard highlight: the Control–Space cursor, the list stop's HighlightRingView and the held switcher's focused card each move without selecting a page; only Return, release or click selects through the existing native selection owner.

### Command-bar close target


### Traversal evidence


Checks: `tests/ContentFocusRequest` 29 assertions (7 new close-target cases plus source wiring), `tests/SidebarWindowKeyLoop` 46, `tests/SidebarAccessibility` 83, Peek focus 32, whole-module typecheck and SIL with zero diagnostics. No functional browser, Tab-walk or Full Keyboard Access test was run.

## Bulk folder disclosure

Collapse All Folders and Expand All Folders are real native commands available
to command search and custom shortcuts. Neither receives a default chord. A
command captures the originating physical window, Space, profile and exact
folder snapshot. It revalidates after command-bar dismissal and native security
checks, then changes every folder in that Space, including descendants hidden
under a collapsed parent. It leaves tab selection, page ownership, split
geometry, URLs and other Spaces unchanged. A changed owner, profile retirement,
folder edit or already-completed target makes the retained command unavailable.

The model writes the complete disclosure change atomically before publishing.
A genuine save failure preserves the previous state and presents its error in
the original window. The existing per-Space persisted `BrowserFolder.isExpanded`
selected-folder ancestor presentation.

with the exact labels, selectors and key-binding identities, with no default key.
`ev_9148aab02e7344e06ba5c28d9839927021eeb72857436080a9d494d1c04c0505`
and full-image instructions establish the state operation. The collapse branch
also consults selected-item ancestry; its exact highlight/ancestor effect
remains a separate reconstruction task. It is not replaced with page navigation.

without executing a command or navigating. The inspected Space had no visible
named folder, so modern command availability and folder motion were not
observed. Parc registers hidden real View-menu entries for discoverability and
custom binding; their placement is an explicit adaptation, not inferred from
the newer Collapse Pinned Tabs command. No new animation or haptic is claimed.


Shared Quote's Advanced switch governs only its mouse-selection sidebar affordance.
The existing explicit Copy URL as Quote command, its custom binding/priority and
native original-page generator remain independent. Affordance actions carry an
opaque original-document selection token and reuse the same copy completion and
policy path; stale tokens cannot retarget a newly selected tab or document. See
[Settings](settings.md#shared-quote-affordance) for gesture and preference ownership.


## Creation and capture default bindings

The existing **New Note**, **New Note in Split View**, **New Easel** and
**Capture Portion…** commands share recovered defaults across their real menu
items, Shortcuts rows and command-search snapshots. They use Control–Shift–N,
Control–Option–N, Control–Shift–E and Command–Shift–2 respectively. The registry
applies these defaults to the existing action identities; it does not install
another input handler or invoke a different page/document owner. Note commands
retain their recovered Use Both default; the existing Easel/Capture priority,
native editing, IME and availability checks are unchanged. The four-row
Essentials lesson retains its separately recovered action set.

Existing shortcut files keep their saved custom/disabled bindings and priorities.
Before these chords were introduced, an explicit clear of a custom binding
removed its override because the command's default was also nil. Absence in an
old file therefore cannot distinguish an untouched command from a deliberate
clear. An additive `creationShortcutDefaults` marker preserves those ambiguous
legacy values as unbound. New settings and explicit individual/Reset All use
the recovered defaults; Reset still refuses an existing custom-chord conflict.
The marker prevents later loads from re-pinning an explicit reset. Migration
uses the existing atomic writer and retains usable in-memory bindings on save
failure. This conservative compatibility rule is a Parc adaptation, not a

The shipped MainMenu records 690, 1220, 1263 and 263 contain the original
selectors and keys/masks. Uppercase `N`/`E` add Shift to the serialized Control
mask; the split Note has lower-case `n` plus Control/Option. Capture records
`2` plus Command/Shift. REA's static `decodeNibArchive` parses the actual
MainMenu hash `c05560f6665c062b78dd326c4ce56307154010f981a45f4959671fb460ab1963`
preserving its original window state owner. The existing independent local
Note/Easel/capture implementations provide those action destinations.

Window and the corresponding surrounding commands without executing them. Its
native screenshot was unavailable and the AX output omitted key equivalents;
this observation establishes labels/availability only, not rendered keycaps or
an applied personal shortcut default. Native Cancel restored the original page.
No new motion or haptic is attributed to these registrations. New Folder's
serialized Command–Shift–N duplicates Incognito's record and needs its actual
runtime/context resolution; the observed unbound state and separate ownership
of Back/Forward arrow, Zoom and F12 equivalents are described below. No global
New Folder alias is inferred from that serialized collision.


## Alternate navigation and page-tool bindings

Go Back (Alternate) and Go Forward (Alternate) are distinct configurable commands,
with Command–Left/Right defaults. Their real menu targets keep arrow navigation
out of an original responder that is an NSTextView, NSTextField or descendant.
The browser's existing navigation eligibility and original page/history owner
remain authoritative. Bracket navigation is a separate command; arrow handling
does not intercept native field editing, marked text or renderer editing keys.

Developer Tools has an independent F12 binding with Use Both priority. It uses
the original page-tool menu action and the existing native renderer-acknowledgment
pipeline, including Press Again's exact menu-item/revision owner. Only actually
registered function-key commands enter that pipeline; printable unmodified keys
and autorepeat remain excluded. Parc preserves the existing Command–Option–I
command identity and calls F12 “Developer Tools (Alternate)” for saved-binding
an explicit adaptation, not a claim about its current Settings ordering.

Zoom In's Command–equals and Zoom Out's Command–Shift–minus are supplementary
real menu equivalents, not separately editable command identities. They use
the same original target and priority as the primary Zoom command and add no
duplicate Actions-search results. In Parc, a supplement is suppressed whenever
the primary is customized/disabled or another command owns that chord. This is
Zoom entries have no binding ID and its initial registration skips them.

The symbolic Zoom In primary also accepts an actual Shift-produced `+` through
its original menu item. Physical-key recording still captures the unmodified key
and Shift separately. Exact saved physical chords win before symbolic matching,
even when their action is unavailable; the live `+` menu equivalent is suppressed
for that collision so AppKit fallback cannot bypass it. Current ASCII-capable
layout translation establishes the physical keys and the actual selected-input-
source notification refreshes the menu and invalidates retained command tokens.
Clearing the conflicting chord restores the symbolic menu equivalent. This
bridges native AppKit menu-symbol behavior into Parc's existing priority query;
falls back to native `performKeyEquivalent:`.

An additive version-three marker protects existing explicit parent customizations
and disables new alternates that would take a saved chord. Untouched legacy
commands receive the newly introduced alternates; existing chord, priority and
unknown records are retained. Subsequent alternate edits are independent. Reset
uses normal conflict checks; Reset All adopts the recovered defaults. Declared
source defaults are retained separately from the live NSMenuItem equivalent,
which AppKit can clear when inserting a conflicting key. Fixed supplements also
retain their declared key so clearing a later conflict restores the actual alias.

### Alternate-binding evidence

MainMenu SHA-256 `c05560f6665c062b78dd326c4ce56307154010f981a45f4959671fb460ab1963`
supply objects 361/1447 (`goBack_Alternate`/`goForward_Alternate`), 285/1473
(the F12 and Command–Option–I Developer Tools entries), and 1051/93 plus
2070/2083/1881 (primary and supplemental Zoom entries). Original registration
duplicate IDs and maps absent priority to the low/default path. REA evidence
`ev_50d79ed045cee813bffca2f65cf0d95e312fbc9ad2c653248dfccb700bb8f0a8`
is corroborated by complete original-image assembly and imported-symbol mapping.

exclude NSTextView/NSTextField before normal navigation. Bracket wrappers use
original sender/window action owners; no duplicate page or URL reconstruction
is introduced.

and Prefer Websites; F12 and Use Both; and only the primary Zoom rows. New Folder
was unbound with its Reset button disabled. The conflicting serialized
Command–Shift–N records therefore do not justify adding a global New Folder
alias over New Incognito Window. Its exact runtime override remains unattributed.
The inspection changed no binding or priority and executed no browser command.
Parc's hidden menu entries, duplicate-search suppression and supplementary-key
compatibility policy are explicit adaptations. Complete keyboard-layout,
auxiliary-window, hover/pressed, motion and accessibility comparison is separate.


## Close the original browser window

File → Close Window uses Command–Shift–W and Prefer Parc. The same registered
menu item appears in Shortcuts and Actions search with its current binding.
This is a physical browser-window command, separate from Archive/Close Tab and
its sidebar selection. Normal, private and native-created popup browsers use
their actual existing controller and native binding.

Validation creates a weak original-window invocation. An owned command panel
can offer the command, but execution first dismisses that panel, then checks
the same visible, closable, key window and live controller again. An attached
sheet, another foreground window, lost owner or pending whole-window close
refuses the request. A consumed invocation cannot replay; fresh validation can
retry after refusal. It never brings a different browser forward or falls back
to the last active browser behind Settings or another auxiliary window.

The action calls `performClose`, preserving the existing `windowShouldClose`
Note-composition/save barrier, transfer recovery, native `requestClose`, genuine
beforeunload approval and private-context retirement. It does not archive tabs,
change sidebar selection, force `close()`, or turn an accepted request into a
claim that the window has already closed. No new key monitor, native input
pipeline, webpage reconstruction or text-editing shortcut is introduced.

This command did not previously exist in Parc's registry. Untouched legacy
files receive its recovered default, while an additive marker disables it if
another saved command already owns that chord. Explicit custom/disabled or
forward-compatible records and saved priority are preserved. Reset uses the
existing conflict transaction; Reset All deliberately adopts the default.
The earlier ambiguous legacy priority migration remains unchanged.

### Close Window evidence

plus Command and `overrideWebView`, separately from Archive Tab. MainWindowController
owner checks closing state and explicitly ignores duplicate pending requests
`ev_ffde3f1210108a2af540bdd04631bbda16fc2082a64b4526605cc72f97f0520e`
analyzes the exact retained function bytes; original-image assembly/imports
corroborate addresses and strings. The carve's external protocol witnesses and
the initial guarded branch's full policy are not reconstructed by this command
wiring; Parc reuses its already implemented whole-window lifecycle.

Archive Tab. The screenshot service omitted the open menu, so it supplies no
pixel-level menu or keycap evidence. No command was executed. Auxiliary-window
Close Window policy, complete dynamic menu coverage, exact unavailable/pressed
appearance, motion and accessibility comparison remain separate from this
original-browser-window owner. Native AppKit menu styling and Parc's weak
one-invocation token are explicit implementation adaptations.


## Full Screen on the original browser window

View → Enter Full Screen uses Command–Control–F and Use Both. The registered
command appears in Shortcuts and Actions; AppKit validation supplies the current
Enter/Exit title. It holds the original browser NSWindow weakly, including
normal/private/popup windows where the actual native capability permits the
transition. An owned Actions panel is dismissed before execution; the same
window must still be key, alive, ready and free of a sheet or pending close.
A stale invocation never targets another browser behind Settings or tools.

The action calls that window's `toggleFullScreen:`. It does not fabricate a
fullscreen completion, alter page selection or construct a second transition
state. Existing native window notifications continue to update the independent
engine's actual fullscreen controller. Native validation remains authoritative
for unavailable capabilities and transition state. Saved custom/disabled chords
and explicit priorities survive. Newly introduced defaults use an additive
migration that disables this default when another saved command owns its chord;
Reset uses the existing conflict transaction.

Command–Control–F and `promptAfterConsumedByWebView`. Original normal-window
will/did phases. Retained REA `ev_d796c262aa907e192651650247a3f7053361f85cb70f340d639d889fabf844db`
and the original image's annotated assembly establish those endpoints. The
existing fullscreen integration owns the richer page/browser restoration model;
Screen at the end of View. No transition was executed, so exit-state pixels,
overlapping-transition timing and full native motion comparison remain open.
Parc's explicit browser-window invocation token is an ownership adaptation;
auxiliary fullscreen eligibility is not inferred from the normal-browser entry.

explicitly disables File → Close Window while Settings is active. Retained
establishing that every auxiliary class shares that policy. DevTools retains its
separate recovered toggle-close owner. These findings do not justify routing
Close Window to a background browser or adding a generic auxiliary closer.

## Exit the original context

Exit is a registered Shortcuts/Actions command with the recovered Escape default
and Use Both priority. A custom chord uses the existing renderer/menu priority
pipeline. It captures the actual modal or fullscreen context in the original
browser window. The owned command panel may return focus to that window; a
changed target, page, binding, window, sheet, composition or closing/transfer
state refuses instead of finding a replacement.

The current Peek has priority, including a fullbleed Peek. Explicit Exit uses
its existing `exit` dismissal mechanism, media confirmation, native close
consent and retirement. Without a modal, a genuine content-fullscreen token
holds weak browser/page/window identities and the original Chromium document.
It revalidates the selected contents and actual content-fullscreen mode before
`FullscreenController::ExitFullscreenModeForTab`. Chromium therefore preserves
its existing page-to-browser-fullscreen restoration. An unavailable token
remains a content target; it cannot fall through to an ordinary window toggle.
Only an actual ordinary fullscreen window uses its existing native fullscreen
command, and it is checked again to prevent entering fullscreen accidentally.
Accepted dispatch is distinct from native transition/close completion.

Physical Escape has a separate owner. AppKit controls and text/IME retain
first refusal; renderer Escape retains its delivered acknowledged heuristic.
The original raw consumed-key producer recognizes physical Escape before its
modified-command queue. Accordingly, changing or disabling the configurable
Exit chord does not remove native Cancel or renderer Escape. Default Use Both
and Prefer Websites keep that path; an explicit Prefer Parc default uses the
existing pre-renderer command route in page content, editable or not, as
consumed Use Both Exit chord arms Press Again only with no Peek/Space-creation
modal and an expanded fullscreen phase. Custom modified chords use the
existing complete priority policy.
There is no additional raw key monitor. The default menu equivalent is
suppressed so AppKit cannot preempt the original Escape producer; Shortcuts
and Actions retain the actual Escape metadata. This transport separation and
hidden registered menu item are Parc adaptations to its current native host.
The generic priority description does not replace Peek's actual confirmation
owner. Native responder Cancel also reaches the same contextual Exit target
only after excluding renderer descendants and native text.

A new additive migration preserves saved custom/disabled entries, priorities
and any explicit conflicting owner. Reset uses the normal conflict transaction;
Reset All deliberately restores the reference default. The recorder continues
to treat Escape as cancellation rather than assigning it while recording.

### Exit evidence

renderer heuristic. The complete 608-byte function, freshly analyzed by REA
`ev_aa950eb7348337a9bbfdbfea2ce51e3ceebbbb0ca46db8866acdea49dfb9c64e`,
compares actual modal identity before dismissal. Without a modal, mechanisms 2…7
inspect the expanded fullscreen phase: an associated content owner invokes
state. External Swift witnesses are attributed using the retained original
image and fullscreen metadata, not inferred from headerless pseudocode alone.

from the reserved editing commands.

and “Exit the current context. Such as closing a Peek window or exiting
fullscreen.” Its reset button is disabled at default. The search was cleared,
original Settings pane restored and Settings closed without changing bindings
or executing Exit. Peek/fullscreen execution, transition pixels, auxiliary
modal coverage and all focus/AX/animation comparisons were not established by
this appearance read. No new visual timing or haptic is attributed.


## Find commands and original document ownership

Edit → Find registers Find (Command–F), Find Next (Command–G), Find Previous
(Command–Shift–G) and unbound Use Selection to Find in the actual menu registry.
The existing `find:` identity is preserved. These entries supply the shortcut
editor, custom/disabled bindings, current keycaps, Actions results and existing
renderer priority arbitration. The additive version-three
`findShortcutDefaults` migration disables only a new default that would take a
saved custom chord; Reset keeps its existing conflict transaction. No explicit
priority attribute exists for these records, so the existing website-first
policy remains.

A menu command retains its original physical window and page/document or native
text owner through validation, command-panel dismissal and execution. Browser
queries are stored weakly per original page and reader document revision in the
window. A selected-page change or document replacement dismisses the old field
without focusing a successor. Closing the field stops only its original page;
reopening that same document retains its query. There is no cross-Profile Find
pasteboard seeding. The real selected renderer frame supplies Use Selection;
Chromium's existing Find service performs matching. Capability and invocation
recheck the genuine page binding, selected contents, Profile/browser retirement,
security sheet, active window and composition state. No JavaScript selection
reader, URL replay or replacement page is introduced.

A focused Note editor forwards all six menu items to its own native Find bar,
with original Note/editor identity, deleted-state and marked-text guards.
Find retains its actual search field. Page Find handles Return/Shift–Return and
Down/Up as next/previous match, while composition and other native field commands
remain with AppKit. Escape dismisses the original field and returns through the
native page-focus owner only while that document still owns selection.

sends the original WebContentFrame action; tag 7 reads its real selected text.
Escape and Shift ownership. The shipped MainMenu records 487/799/926/1254 supply
the four labels/defaults; installed1.170 Edit/Find confirms their visibility and
empty-state availability. Its empty Find field was also inspected without a
query or result action: a compact top-right floating panel with a focused text
field and Close. The original state is per WebContentFrame; weak page/revision
storage and the current Chromium binding are explicit ownership adaptations.
The browser dispatcher ignores Jump to Selection tag 0 and Find and Replace
tag 12. Their recovered Note responder mapping is completed in KB04 below;
no browser alias is manufactured.


### Numbered targets and native-text Find — KB04

Command–1 through Command–8 select the corresponding sidebar item; Command–9
selects its last item by default. The hidden menu entries use `item1`…`item9`
and appear in Shortcuts and Actions. They use the actual Sidebar hierarchy:
Favorites, visible pinned/folder descendants, then Today, with a split as one
item. The global Favorites-ordering and ninth-item preferences apply before
selection. Missing or unavailable destinations leave the current selection
unchanged; unavailable pages never shift another item into their numbered slot.
Selection stays in the existing original-window/tab owner, including Profile,
transfer, sheet, popup and Peek restrictions.

Every Space has an ordinal `spaceN` command carrying that Space's current name.
The first nine default to Control–1…9; later Spaces remain customizable without
an invented default. Menu entries carry the original browser, Space and Profile
identities. Space changes and browser activation refresh the registrations
without requiring the menu to be opened; tracking retains the captured entries
until it ends. Rename/reorder updates the ordinal metadata, removed ordinals
leave discovery, and saved custom or disabled bindings survive disappearance
and return. The additive `numberedTargetShortcutDefaults` migration protects
existing chord owners. Reset reads the recovered defaults even when AppKit has
cleared an equivalent on the current menu item.

Edit → Find now contains all six shipped items in order: Find, Find and Replace
(Option–Command–F), Find Next, Find Previous, Use Selection to Find, and Jump to
Selection (Command–J). Find and Replace and Jump to Selection retain native-context tags 12
and 0. A focused original Note editor consumes every Find item by showing its
body's native Find bar with tag 1; these menu titles do not manufacture replace
or jump behavior. The browser rejects 0/12. The Note route rechecks its rendered
pane, Profile/document identity, retirement/transfer state and both editors'
composition before dispatch. An ordinary text field does not become a generic
Find consumer.

keys and tags. The four custom-selector implementations are MainWindowController,
FindInPageView, CommandFTextField and TextEditorViewController. The two
constructs native tag 1. This closes the earlier unattributed generic-text gap.

The menu registry's weak invocation records, refresh subscription and Parc's
flat-state hierarchy adapter are explicit implementation adaptations. Existing
native menu/control presentation and selection motion remain the owners; this
row introduces no new key monitor or renderer path. Focused model and inert
AppKit checks cover numbering, split order, migrations, dynamic rename/retirement,
custom binding restoration and the actual conditional Settings controls. The
finished integrated source passes whole-module SIL with warnings as errors.
Functional browser tests remain prohibited and are not claimed.

### Floating Find presentation and genuine result ownership

`PageFindView` floats over the original selected native page rather than reserving
renderer height. The actual page bounds supply the anchor in an ordinary pane,
split or Peek: nominal 300 × 32 points, ten points from top and right. The
26-point controls and three-point outer padding. The 13-point field and 12-point
Original PopoverBackground, ForegroundPrimary, FindInPageError, separator and
resource is consulted by Parc. Narrow-page containment is an explicit adaptation.

An immutable native result carries the actual query, document revision, count,
active ordinal and completion flag from the original `FindTabHelper`. The native
observer rejects another query/document and publishes on a coalesced non-nestable
main task, so AppKit is never called from Chromium's observer delivery. Navigation,
empty-query, stop and owner destruction invalidate that result. Unknown state
hides the counter; genuine zero displays the original “Not Found”; positive
counts expose the actual ordinal/total and Previous/Next controls, following
result arrives, preserving selection and composition. The current Chromium
counts-only response may report ordinal zero; Parc displays the supplied value.

Buttons retain the native momentary-change press owner recovered from
The Find factory leaves its optional mouse-down callback empty, so
hover/focus surface uses original GrayA4 (sRGB black alpha .071 in Aqua,
white alpha .077 in Dark Aqua) only while hovered and enabled. Tracking uses
original bits `0x223`: enter/exit/move, active in the key window, visible rect.
The actual current content-view hit must be the original button or descendant;
hide, detach and window changes clear hover. Parc also explicitly clears on
original key-window resignation. Effective appearance supplies the layer color.
The no-hit-test counter keeps its native readable accessibility label.

AppKit owns Tab/Shift–Tab, Full Keyboard Access, native pressed drawing and the
rounded focus mask; there is no custom closed focus loop. If a genuine result
removes a focused match button, the same native query field receives focus.
Escape, Return and arrow direction keep the original command ownership above.

Find transitions are immediate native updates. The original controller
`setHidden`; they do not wrap visibility in an animation. Result replacement
the original child and constraints immediately, avoiding replacement for the
same identity. Parc preserves this path and adds no haptic or cosmetic motion.

its populated hover/pressed pixels were not exercised. The populated contract
production captures cover light/dark empty, positive and Not Found states with
native AX controls; 61 AppKit assertions cover tracking identity, current-hit
occlusion, native press configuration, disabled/appearance/focus masks,
key/hide/detach cancellation, passive labels and preserved native selection/IME.
A full source check covers the integrated app; no functional browser test is
claimed. The separate legacy Chromium FindBar adapter retains its fallback
owner; this is the application Find command surface.

### Essentials command education owner

Help and Shortcuts settings share the original browser's retained education
controller. Its displayed chords update from the same registry, including
customization, reset and explicit disable; it does not install another global
key monitor. The education window is floating/fullscreen-auxiliary and has its
own native close owner. View All and command callbacks require the actual
visible key education window and its captured live browser with no sheet.
Commands retain education; View All closes it and opens the original Shortcuts
owner. Escape only dismisses that browser’s command bar. An expired education
command never falls through to another browser. Closing never targets a tab.
See [Essentials education](settings.md#essentials-education-window) for source
attribution and the explicit native capability/presentation adaptations.


The education keycaps are passive shared presentation with the shortcut editor;
their semantic accessibility values follow the registry while pointer and key
input continue to the actual native controls. View All uses the recovered
native SwiftUI Button and decorative border, retaining the visible/key/no-sheet
owner check and weak callback. The inherited command callbacks and original
parent reducer mapping remain the boundary described above; this presentation
change does not reinterpret held modifiers or manufacture another key pipeline.

The Essentials native key-equivalent route does not add a repeat filter: every
matching delivered key-down uses the same current registry and original owner.
education window inherits `NSWindow`, while the shared controller selector
ownership contract is distinct from the remaining cross-context hold, reversal
and interruption comparison. See the Settings mechanism above for evidence
and the explicit no-browser-test boundary.

### Shortcut detail state and passive artwork

The detail column distinguishes no action, a genuinely unassigned action and a
bound action. The introduction uses the original Command/smiley artwork;
unassigned actions use two faint empty caps. An interactive recorder preview
can replace the displayed symbols, but priority controls still require the
actual saved binding. Selection, reset and search update this presentation
without taking first responder from the native recorder or list.

The 200-point column, count-sensitive cap width, title/description spacing and
unassigned priority omission are attributed to the original Preferences view
producers described in [Settings](settings.md#shared-shortcut-keycaps). The
bundled vector artwork plays once and resets on detach, respecting Reduce
Motion. It is decorative and contributes no duplicate accessibility element;
the passive native cap group exposes the semantic chord or state. There is no
new keyboard monitor, dispatch path or preference writer. Focused recorder
transition and wider visible-state comparison remain tracked in KB09/KB11.

## Shortcut key text

Every visible chord comes from `KeyboardShortcut`'s one formatter, split the
[M] measured, [I] inference.

  (U+23B5), 4 shows Tab (`\t` or ⇥) as the localized word "tab". Every other
  key passes through unchanged. The reference bundle has no English
  `Localizable.strings`, so these resolve to "F1"… and "tab".
  End ↘, Page Up ⇞, Page Down ⇟, arrows ↑ ↓ ← →, Tab ⇥, Help ?⃝, keypad Clear ⌧,
  keypad Enter ↩︎ (U+21A9 U+FE0E), keypad × 𝗑 (U+1D5D1), other keypad keys as
  their plain characters and F-keys as U+F704…. Menu key equivalents
  (`\t`, `\r`, U+F700…, U+F728…) are normalized to the same glyphs through
  default and a recorded key read alike.
  pass the same two options, then `localizedUppercase`. Tab stays ⇥.
  uses the word-key font for F-keys and Tab only; Space is not a word key.
  equivalent and AppKit draws it. Parc's `\t`, `\r`, space, U+F700… and U+F704…
  equivalents draw as the same AppKit glyphs [I].

Parc's `display` and `keyLabel` are the text form (the + menu, command bar,
recorder, conflict text, toasts, the Use Both hint and capture/copy menus).
`symbols` feeds the Settings detail keycaps; `keycapSymbols` feeds Essentials
and Parc's tooltip keycaps ([tooltips](tooltips.md#keycaps)), so both spell
Tab out. Storage and matching are unchanged.

Parc keycaps use the word-key font for multi-character labels (TAB, F-keys).
the normal size. Accessibility values (Settings detail and Essentials keycaps,
the Essentials instructions, the recorder, the conflict warning button's label
and the accessibility help of controls with Parc's tooltip) use
`spokenDisplay`, which says Space where the visible text shows ⎵; VoiceOver
otherwise reads the symbol's name. The conflict warning's tooltip keeps the
visible ⎵ text.

Remaining differences, all outside display:

- Parc's layout translation stores keypad Clear as Escape (U+001B) and keypad
  is not necessarily keypad ×: French-PC (key code 42) and Turkish-QWERTY-PC
  or Kurdish-Kurmanji (key code 27) type it unshifted on a main key.
  Distinguishing either keypad key needs a storage change.
  whatever the layout; Parc records the active layout's character (KB07). The
  label follows Parc's stored key.
  record them (physical capture stops at F20).

`scripts/test-keyboard-navigation.sh` runs `KeyLabelTests` over every named
key, both keycap forms and the spoken form; the Settings detail, Essentials
and recorder component checks assert ⎵, the per-surface Tab and the spoken
Space.

## Complete command inventory reconciliation — KB03

1.170). Every one of the nib's 219 non-separator `NSMenuItem` records was decoded
as data (title, key, mask, action, `arcKeyBindingID`, `arcKeyBindingPriority`),
together with the programmatic "Hidden Shortcuts" submenu that
the reducer's `SharedWindowFeature.WindowAction.MainMenuAction` case list
Git in `work/claude-kbd-rea/kb03/` (`menu-items.json`, `dump-menu.py`,
`fn-10003ebec.txt`). The table below is the complete reconciliation; each command
is implemented through an existing owner, already present, owned by another
family whose feature does not exist yet (contract below), deferred to a named
keyboard row, or excluded by the ledger.

### Added in this delivery

| --- | --- | --- | --- |
| 1485 / 85 `newBlankWindow` | File → Blank Window | Control–Command–N (none → Prefer Websites) | `createStandardWindow(showCommandBar: false)` |
| 393 / 22 `newProfile` | File → New Profile | — | Settings → Profiles' existing local profile sheet |
| 566 / 14 `duplicate` | Tabs → Duplicate | — | the sidebar's original Duplicate transaction for the focused multi-selection, else the current split or tab |
| 752 / 79 `revealTabInSidebar` | Tabs → Reveal Tab in Sidebar | — | `revealSidebarItem` (expands and scrolls; never selects or focuses, unlike Control–Space) |
| 451 / 59 `viewLibrary` | Window → View Library | Command–Shift–L (none) | the Library entry's toggle (`showLibraryFromEntry`) |
| 442 / 80 `renameFocusedSpace` | Spaces → Rename Space | — | the Space menus' existing rename owner |
| 978, 1232 / 75, 74 | Extensions → Manage Extensions…, Add Extension… | — | the Site Control Center's extension destinations |
| 1726, 1732 | Window → Zoom, Bring All to Front | — (no binding ID) | AppKit `performZoom:` / `arrangeInFront:` |
| hidden `nextTab` / `previousTab` | Next/Previous Tab (Alternate) | symbolic Command–} / Command–{ (none) | the positional Next/Previous Tab actions |

Duplicate record 566 has a binding ID but no `arcTypeTravelID`, so the menu item
separate typed candidate 19 ([typed commands](command-bar.md#typed-type-travel-commands)). Reveal record 752 has both;
its original selected item admits prospective availability through the owned
command panel, then rechecks the item/Space/Profile and native presentation
after dismissal. New Profile similarly requires the genuine browser or its
owned command panel, no originating sheet and no existing Settings sheet; it
rechecks after returning focus before opening the existing Profiles sheet.
lifetime behavior.

`nextTab`/`previousTab` differ from the menu's `selectNextTab`/`selectPreviousTab`
AppKit when Shift produces it, so the existing symbolic bridge is generalized to
`+`, `}` and `{`: native priority arbitration finds the original hidden item for
a Shift-produced glyph, and an explicit saved physical owner of the same chord
wins and suppresses the symbolic equivalent. Parc's "(Alternate)" titles keep
Settings rows distinguishable, as for F12. The Blank Window mapping is inferred:
(source only), beside case 5 `onCreateNewWindow(WindowCreationOptions)` whose
options carry `showCommandBar`; the standard-window creation sites in the

New defaults use an additive `inventoryShortcutDefaults` marker: an older file
keeps any saved custom chord that equals a new default and the new command
starts unbound; otherwise the default applies. Reset keeps normal conflict
checks.

### Placement reconciled to the reference

Open Command Bar moves to File (240), Reveal Current Tab to View (778), New
Folder… and the hidden Collapse/Expand All Folders to Tabs (959, 134/164); View
Downloads, View Media (Saved Captures) and View Easels & Notes join View
Library in Window (150/668/1516); Archive orders View History before View
Archive and titles Clear Archive without an ellipsis (1144/935/1171). Command
identities and saved bindings are unchanged; only Settings groups follow the new
menus. The order within each menu is inferred from the nib's records and is not
New Folder retains the already observed unbound default with Reset disabled
([prior appearance receipt](#alternate-binding-evidence)); its serialized
Command–Shift–N collides with New Incognito Window. This delivery changes its
menu placement only. The exact original runtime override remains unattributed,
so the observed default is not presented as a recovered override implementation.

The nib's File and Tabs New Tab records 830/1693 both use `newWindowForTab:`
and Command–T; Parc keeps its existing New Tab owner and one editable identity.
Container records and unnamed connection placeholders are not additional
commands. Native text submenus remain with their actual responder owners; the
Format/Font exception is explicitly handed to Notes below.

### Already present

application menu (Hide, Hide Others, Quit, Settings, Set as Default Browser,
Import), File (New Tab, New Window, New Incognito Window, Close Window, Archive
Tab, Reopen, Share, Capture…, Capture Full Page, Save Page As, Print, New
Note/Note in Split/Easel), Edit (copy and paste commands, Find group), View
(Sidebar, Toolbar, refresh/stop/cookies/cache, split commands, Zoom, Full
Screen, Exit, Cast, Developer submenu, appearance), Spaces (New Space, Edit
Theme, Next/Previous Space and the Space list), Tabs (Pin, Rename, Reset Tab,
Reset all tabs, Clear Today, positional/linear/recent traversal), Archive (Back
and Forward with arrow alternates, View/Clear Archive, History), Window
(Minimize) and Help (Essential Keyboard Shortcuts and Release Notes, which opens
the bundled What's New page; Export Notes is in File). The
hidden Paste and Match Style and Open Extensions items were already delivered.

### Numbered execution ownership

- **KB04 (complete):** hidden "Go to Sidebar Item N" / "Go to last Sidebar Item"
  (`switchToTab:`, MainMenuAction 2), Spaces menu Space N bindings
  (`SpacesMainMenuProvider` holds a `keyBindingsClient`) and Find and Replace
  (822, Option–Command–F) / Jump to Selection (543, Command–J). The split
  numbered/adjacent items are already registered. See the completed
  [numbered targets and native-text Find contract](#numbered-targets-and-native-text-find--kb04).

### Contracts for owners whose feature does not exist yet

Each needs its feature before a command can have an actual owner; register it

- **Notes / native text formatting:** Edit → Format → Font, Bold (1839,
  Command–B), Italic (2139, Command–I), Underline (1797, Command–U). These
  have no binding IDs. The existing [WEB18 Notes contract](web-interactions.md#contracts-for-other-families)
  records `NSFontManager.addFontTrait:` tags 2/1 and native `underline:`; the
  Notes owner must reconcile these with its existing emphasis controls and
  the Easel/native-text owners before adding menu equivalents. Page editing
  keeps Blink's existing contenteditable chords.
- **Spaces and profiles:** Spaces → Manage Spaces… (554, `openSpaceManager`,
  and Change Profile (84, MainMenuAction 1, no ID). These are the open Space-menu
  contracts in [sidebar resizing](sidebar-resize.md#space-header).
- **Sidebar / Today owner:** View → Expand Pinned Section / Collapse Pinned
  Section (617/840, cases 57/58, no ID); the open "Collapse Pinned Section"
  contract in the same document.
  MainMenu record1495, selector `openInCurrentSpace:`, binding `openTabIn`,
  Command–O, priority `promptAfterConsumedByWebView` (Use Both), with no
  `arcTypeTravelID`. Fresh action attribution corrects the earlier assumed
  missing chooser: the current-modal resolver includes sidebar-sourced Peeks,
  and the menu calls the same Expand helper as the control. Parc registers the
  remains excluded. See [Peek command attribution](peek.md#open-in-current-space-command).
- **Onboarding:** Help → Getting Started (787, `showWelcomeToArc:`, WindowAction
  81 creates the `welcomeToArc` sidebar item).
- **Performance / Data and credentials:** Help → Troubleshooting → Open Task
  (1504, `RestoreDataWindowController`).
- **Windows and lifecycle:** the Window menu's injected Stay on Top toggle
  (MainMenuAction 73 `didToggleStayOnTop`, persisted `WindowState.stayOnTop`;
  `WindowMenuProvider.ViewState.canStayOnTop` gates it and its producer was not
  traced). No binding ID.

### Excluded by the ledger

Command–Shift–O), Boosts (Boost Gallery, New/Edit/Legacy Boost, View Boosts),
filtering). Capture in Portrait Mode (914) is superseded by the
and Capture in Portrait Mode are command-bar commands
([command bar](command-bar.md#mainmenu-type-travel-data)).

Checks: whole-module typecheck and SIL with warnings as errors; the new
`InventoryCommandTests` (23 assertions: defaults, priorities, symbolic dispatch,
physical-owner suppression and restoration, independent identities, no-steal
migration) joins `scripts/test-shortcut-alternates.sh`; existing alternate,
creation, migration, copy, paste-style, Full Screen, Clear Today, recorder and
keyboard-navigation components pass unchanged. No browser functional test ran.


## Live binding discovery and copy education — KB38

The implemented discovery surfaces read the registry's current **valid** binding.
KB38 includes the recovered Peek Open in command and its Expand-control binding;
its current-modal/current-Space attribution is recorded below.
A saved conflict is visible in Settings but contributes no executable/menu or
advertised shortcut. Changing, removing, resolving, resetting or translating a
binding refreshes presentation without changing the original action target.
Main-menu references and command-search snapshots retain their established
revision/owner validation; contextual labels do not register duplicate commands.

binding as keycaps each time it shows ([tooltips](tooltips.md)).
`KeyboardShortcuts.bindHelp` keeps the same text ("Go back ⌘[") as each
control's accessibility help, saying Space where the keycap shows ⎵: it holds
weak references to real controls,
replaces an old registration when a control changes role (Reload/Stop/Force
Refresh), and prunes retired controls. Context-menu bindings are also
weak and update in place: folder/split menus may be constructed during a sidebar
rebuild and survive until the user next opens them. Neither registration retains
a window, installs an event monitor or changes command dispatch. A committed
registry notification updates every bound accessibility help, Site Control
Center and the onboarding Ready message, and retires a toast that shows a
shortcut. Open command search
uses its existing revision subscription.

Included production consumers are:

- Main menus, Shortcuts rows/recorder/conflict presentation, Essentials and the
  website-priority cue use the existing registered menu command and keycaps.
  Command search rebuilds its menu-command snapshots after the committed
  revision, renders each snapshot's active chord, and refuses stale execution.
  Numbered Space command ownership and dynamic name/order/removal remain KB04.
  The contextual Favorite rename result also reads Rename's live chord;
  contextual Space/Folder/Favorite actions omit a chord as their reference
  candidate producer does.
- Sidebar and toolbar Back/Forward, Reload/Stop/Force Refresh, Show/Hide Sidebar,
  Clear Today, ordinary/split Close, Reset Tab and Copy Quote controls show
  their actual command binding as tooltip keycaps and in their accessibility
  alone carries Focus Address's and New Tab's bindings. Reset Tab's tooltip and
  help disappear when its command has no valid chord, matching its recovered
  producer. Popup navigation and Peek Close use the same shared controls and
  original commands.
- Developer Mode Copy URL, Capture, Console and Inspect controls bind to those
  real menu identities. Site Control Center's Copy/Capture/Full-page Capture
  values update while its original popover remains open.
- Tab/Favorite/split/folder Rename, tab Copy Link and pane Copy URL, folder/selection
  Duplicate and New Folder entries display current bindings while preserving
  their captured item actions. Contextual New Nested Folder… uses the New Folder
  binding with the original folder destination. Duplicate uses KB03's
  `duplicateCurrentItem:` identity; it remains absent until that command is
  actually registered and shows no invented default chord.
- The Library button's tooltip shows View Library's current chord as keycaps
  each time it appears; a binding changed while it is shown appears at the
  unbound clauses instead of advertising default keys that no longer work.
  Onboarding updates its message in place without rerendering a step or
  changing focus.

The command field reports an actual successful native Copy of its selected text.
When that text equals the original current page's absolute URL and Copy URL has
a valid binding, `SuperCopyUpsell` shows “Copy links faster by pressing” followed
by that chord. The original command panel, window, Space, Profile, selected tab,
native page and current URL remain authoritative. A dismissed/replaced panel or
changed owner cannot deliver it. The cooldown is recorded only after the passive
feedback surface attaches: first presentation is eligible; subsequent
presentations require at least two calendar days. It uses a local UserDefaults
([toasts](toasts.md)): it preserves first responder and closes on a binding
change, window close or minimize, a sheet, full screen, scrolling, replacement by
another toast, or after five seconds.

### Reference and adaptation boundary

SHA-256 `4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
identify 69 call sites; retained annotated functions and the command-name map
are in `work/claude-kbd-rea/kb38/`. Nearest exported-symbol names in that map
are only index labels, not attribution of every intervening function.
beside its title. Relevant consumers are:

  Folder and Favorite/Unfavorite return no shortcut; Rename Current Tab case18
  therefore advertise the same Rename binding as its menu counterpart.
  admits no saved date or a day difference at least two at
  key is `superCopyUpsellLastSeen`. The retained toast content supplies the
  “Copy links faster by pressing” text.

Parc's AppKit tooltip suffix, native equivalent rendering, weak registration
see [toasts](toasts.md)), its location inferred; recording the cooldown only after actual presentation is an explicit
implementation choice. These are source implementations, not pixel/motion or
runtime acceptance. No haptic is invented. Static evidence establishes the
producers, not an observed physical shortcut/clipboard/browser session.

The fixed Delete Suggestion chord belongs to its command-field input path and is
`openInCurrentSpace:` menu command and the existing Peek Expand control. The
menu validates the original modal and current window Space/Profile, presents
“Open in [Space]” with its 12-point icon, and hides without a destination. Its
tracked command cannot retarget a replacement modal, Space or window. Both
active promotion routes preserve the original page and use the validated current
Space; parent-destruction preservation keeps its separate source-Space policy.
Command–O and Use Both have their own additive migration marker; explicit
customizations/disables and another saved Command–O owner survive. The record
has no Actions identity, so it introduces no command-search candidate. The
previous missing-chooser claim was disproved by the [exact action trace](peek.md#open-in-current-space-command).

### Checks

The final delivery receipt records the whole-module warnings-as-errors SIL pass
and matching input hashes under `work/claude-kbd-checks/kb38-recovery/`.
Focused inert AppKit checks exercise actual registry/control/menu mutation,
conflict suppression, reset, weak lifetime, committed change signaling, copy-hint
eligibility/cooldown, the upsell toast's attachment, and visible Library tooltip
replacement. Peek checks cover the hidden native menu becoming available,
Command–O/Use Both, additive no-steal/custom/disabled migration, live Expand
binding, captured-target refusal and single dispatch. Actual model promotion
also covers a global Favorite displayed in another current Space while preserving
its original Profile/referrer. Existing shortcut search, copy, Essentials, cue, suggestion deletion,
split appearance, toolbar, Developer Mode, sidebar accessibility and Library
checks cover the affected consumers. No functional browser tests ran; physical
keyboard, renderer execution, actual Copy invocation and final visual/motion
comparison are not claimed by these checks.
