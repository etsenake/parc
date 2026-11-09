# Native settings shell

Settings-wide control-state and transition attribution is retained in
[Settings motion](settings-motion.md). Ordinary pane switches are immediate;
specialized Icon/Shortcuts feedback and native modal/action owners remain separate.

Settings now uses a fixed native preference window with an icon-and-label
toolbar and a first personal-name card pane, followed by separate General, Profiles, Links, Shortcuts, Icon and Advanced panes. Each pane retains
its scroll position while the window remains owned. General opens Profiles
through its real Profile Settings action. A native engine request to show
Profiles selects that pane directly; ordinary Settings entry preserves the
current pane. The window uses system appearance and native keyboard/accessibility
behavior. Closing cancels an outstanding download-folder panel.

Parc's Onboarding box with Replay onboarding, the only way to replay setup. Keep
preferences belong to the selected profile in Profiles.

Advanced → **More Settings…** opens the genuine `chrome://settings/` WebUI in
the original Settings window's Space/profile. The actual browser window is
activated before its normal native navigation/security admission. A deleted,
retiring or busy original context refuses the action; another frontmost window
does not become the destination. An eligible existing Settings tab in the same
Space/profile is selected without resetting its subpage or unsaved edits. A tab
owned by another physical window is not taken over. Settings closes only after
successful dispatch; refusal keeps it open with feedback.

`ev_057671376bbc5c99000e9d92f037db666e30e3b819ffe8febf0ff85668ded393`
is a bounded raw slice; external imports and globals are resolved by the retained
annotated full-image instructions, not invented pseudocode names. Appearance-only
reference tab was closed and the original page restored; no preference or data
action was taken. Parc's current 130-point button and same-Space tab reuse are

translation is excluded because Chrome's translate service needs a Google API
key (Josh, November 1), so there are no translated-site choices to reset. The
Advanced pane ends with **More Settings…** and **Export Data**. See
[engine flags](engine-flags.md#page-translation).

`translateSourceLanguagesAlwaysOrNever` and `translateNeverHosts`. REA evidence
`ev_6e98a53683b8d09d5f9dfa3d762e409f615ed6a08a0bad18a24c1faeaa6406f4`
is a bounded raw slice; original annotated instructions establish both stores.
The installed Advanced button was inspected without activating the reset.

Profiles has an independent editing selection. Clicking a profile does not
assign a Space to it or change that profile’s native preferences. The list shows its name and Space
count, refreshed with the store. **Use for this Space** explicitly invokes the
shared, always-confirmed Profile reassignment operation for the originating
Space. The header, Library manager and Settings retain the original Space,
Profile and membership through genuine page retirement and typed Note/Easel
storage relocation. New Profile retains the explicitly confirmed create-and-assign
flow, persists its identity atomically and selects the result. The source-owned
retirement, rollback and migration logic remains in BrowserStore; see
[Space management](space-management.md#profile-assignment-dependency).

The selected pane and independently selected profile are saved with the local
session, using optional fields that preserve existing session decoding. An
unavailable saved profile falls back to the originating Space’s profile and then
the first available profile. Pane/profile changes commit atomically before the
window adopts them; write errors retain the previous selection. This durable

Rename opens an app-owned sheet with the current name selected, native keyboard
focus, Return to save and Escape to cancel. It preserves the profile UUID,
engine storage path, Space names and all browser/library/routing references.
The store trims outer whitespace, rejects an empty name and compares the
original name before committing, so another window’s rename cannot be silently
overwritten. Atomic session replacement precedes publication. A write error
keeps the sheet and draft available for correction or retry. Closing Settings
or losing the profile cancels the sheet without a write.

preselected name, pencil footer action and Cancel/Save order. Parc uses native
system colors/buttons and a 496×276 sheet with reserved inline-error space;
1.122 metadata identifies ProfileNameChangeState and loading/error processing,
separately explains that Default cannot be deleted and that only profiles not
cookies, history, preferences and logins are permanent removals and requests the
the native profile-destruction implementation. Profile removal must coordinate
actual native context lifetime before removing data or publishing model changes;
ordinary Clear Browsing Data is a separate operation.

### Profile removal

The Profiles footer enables Delete only for an existing nondefault profile with
no assigned Spaces. Default is an immutable UUID, independent of its editable
name; older sessions use their original first profile and persist that identity
with the first removal operation. The confirmation names the actual source
profile’s saved-tab and local-history counts. It explains permanent browser-data
removal and preserves downloaded files and app-global Easels. A profile route
keeps its original destination UUID and existing unavailable-destination fallback.
Other profiles, Spaces, tabs and library documents retain their identities.

`ProfileRemovalController` owns the operation for the process. Settings owns only
its sheet. The store atomically records an operation UUID and profile identity
before calling the native preparation API. Pending profiles cannot be renamed
or assigned to a Space; an assignment already awaiting native retirement loses
its final approval gate. Search and download preference entry points stop
requesting the pending context. Closing Settings cancels preparation when it is
still reversible; committed cleanup continues under the process owner.

The native lease binds the exact profile path, protected default path and
operation UUID. Its synchronous revalidation gate checks the current app record,
profile/name/default identity and absence of assigned Spaces immediately before
commit. Only `removed` permits the atomic app metadata change. `failed` means
the native operation never crossed its irreversible journal boundary and permits
releasing the app record. `pending` leaves the profile blocked for retry. An
existing committed journal reported during preparation goes to recovery even
if Cancel was queued. Startup recovers saved operations; a missing native
journal must report a safe failure without deleting any data. Final metadata
write failure retains the blocked operation so retry can finish from the real
native receipt. The native transaction never depends on the sheet remaining open.

Completion removes only the selected profile and its saved tabs, local history
and download records, cleans their selection/split references and returns the
Settings selection to Default. It does not remove downloaded files, rewrite
routing rules or erase app-global Easel documents/assets. The wider local-record
cleanup and saved recovery record are explicit Parc adaptations of the native
profile boundary. The [shared removal presentation](settings-profile-removal.md) uses the recovered
450-point width, typography and palette, and preserves complete progress/error
text in bounded scrolling sections.

requires that Boolean and Delete’s default-key action reads the same state at
validation. The previously traced default/unused guard and native-success gate
inferred from an indirect Boolean callback.

### Unused-profile cleanup

The Profiles footer's separate trash action reviews every currently eligible
nondefault profile with no assigned Space. The sheet lists the original names
and requires `CONFIRM`, using Foundation's case-insensitive equality without
trimming. The source review is a fixed UUID/name set: opening the sheet never
authorizes deletion, and profiles created afterward are never added to a retry.
A rename, new assignment, duplicate target or failed durable save prevents the
entire new authorization set from reaching native preparation.

The store stages all new per-profile operation records in one atomic save.
`ProfileRemovalController` then uses the same real preparation, lease,
revalidation, commit and recovery path as individual removal. The native owner
already keys operations by exact profile path. Native results remain per
profile: successful removal is not undone or hidden by another profile's
failure. The sheet shows each original profile's progress/result, permits
retry of unsuccessful members and skips completed members. Retry recovers an
existing operation UUID instead of issuing a new deletion. Closing cancels only
preparations that remain reversible; committed operations outlive the sheet
and retain their durable restart recovery. Individual removal remains available
for inspecting a pending profile after the bulk sheet is closed.

`ev_38d298c7a4ec210ccf98a9e5a75e7a4b2b64737de31568f2292ce4d1f4bcfc06`
covers the bounded callback. Full-image annotated assembly supplies import
names and original addresses that the raw slice cannot resolve. The separate
`onDeleteUnusedProfilesConfirmed` delegate and sheet presentation state are
retained in the preferences metadata. The individual native-success gate
native deletion scheduler have not been recovered.

profile or preference. Its one-default-profile footer showed Add, disabled
Remove and Rename, but no bulk cleanup button. Parc's separate trash entry,
atomic multi-record staging and per-profile result display remain explicit
adaptations. The [SET23 presentation contract](settings-profile-removal.md) now
recovers the shared 450-point dialog geometry, content, colors, controls and
keyboard confirmation behavior. The reference feature-flag availability does
not remove Parc's explicitly included cleanup operation.

`scripts/test.sh` includes the real file-backed profile-removal model suite and
the production controller with isolated native-boundary doubles. They cover
stale selection, atomic failure, exact original targets, partial completion,
pending preparation cancellation and recovery identity. They do not execute
Chromium or establish actual native profile destruction or browser acceptance.

Archive retains the original four visible intervals, legacy-value display and
profile-wide policy. Its compact info/picker row, original All Profiles / Only
this Profile scope sheet, durable error handling and new-Profile fallback are
implemented in the [AUTO11 contract](archive.md#automatic-archive-settings-and-education--auto11).
The genuine new-user education card is consumed by automatic archival, and its
Settings link selects the original Profile. Downloads read and write the genuine native preferences
for the selected profile, preserving managed-control guards and errors,
"Other…", a divider and "Ask every time"; "Other…" sets the chosen folder and
then turns asking off, and a managed folder or prompt disables the picker
([details](download-library.md#original-download-prompt-default-and-download-location)).
A selection change or removal retires the outstanding folder panel before its
callback; completion checks exact window, selected profile and native preference
identity. The selected profile need not be the one assigned to the originating
Space. A profile without an active native context keeps the existing unavailable
explanation instead of displaying a working-looking download control.

Search Settings and the five **Your Data and Settings** commands resolve an
existing Space in the selected profile at action time, preferring the originating
Space. The shared callback validates that exact Settings/window/Space/Profile
and opens the genuine profile WebUI. A profile without an assigned Space keeps
its controls disabled with an assignment explanation. See the
[complete command inventory](#general-and-profiles-command-inventory--set21).
All setting changes continue through the existing store/native paths.

## Reference and adaptation

no preference or profile was changed. Its General pane routes search, archive
and download management to Profiles. Profiles uses a list beside grouped rows.
its card, Shortcuts and Advanced panes): 684×562 content, the 562-point height
margins and 556-point sections. The 206-point Profiles list and 336-point
detail column remain appearance-based adaptations.

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`
supplies the architecture evidence. SettingsWindowController initializer
NSToolbar with customization disabled, icon-and-label display mode 1 and a
updater controls. This does not exclude the local membership-card experience.
Josh explicitly included that card on October 28: its pointer-responsive motion,
regenerated designs, names, persistent local configuration and associated local
interactions belong in the first Settings page under SET27. The earlier
whole-account-pane omission supplied no card-specific justification. Recover the
reference contract and document honest local adaptations for account-derived
fields while preserving Parc branding and the service exclusions. Only connected
production behavior counts as implementation.

The local restore/sidebar/replay controls, explicit Space assignment and the
account-free setup behavior are Parc adaptations. The parity ledger owns
progress, validation results and remaining reconstruction work.

## Profile search and navigation

Profiles reads the real TemplateURLService engine list/effective default and
PrefService suggestions value. Snapshots retain the exact weak Profile, model
revision, genuine sync GUIDs and management/extension control state. Mutations
revalidate those identities, write the native preference and refresh from its
observer. Selecting a profile can initialize that registered context; it does
not create a separate profile manager. General routes search to Profiles.

The command bar owns a real AutocompleteController and preserves its navigable
result ordering. Local commands and same-profile tab choices retain their own
shell actions. Profile destruction and dismissal cancel the native session;
query generations reject older results. Existing pages use their actual Profile,
including private browsing, instead of re-resolving the persistent parent's path.
New pages retain the same original Profile and Browser binding. Navigation copies
the actual classified URL, transition, headers and POST content; it never turns a
POST search into an initial GET. Pending input is tied to its original tab/Space
and cannot navigate a replacement document after ownership changes.

REA of retained Arc1.122 Core establishes profile-preference boundaries at
`getSearchEngines` (`0x68cbfd8`), `setDefaultSearchEngine:` (`0x68cc378`) and
`searchSuggestEnabled` (`0x68ccda0`). The first wraps returned shared engine
objects; the setter retains the supplied engine's native payload through the
same preference implementation. Evidence `ev_ba37fa19f3cddf9585c8c5eeebab510b31687d22f5ce3fc515b733d08b0272d4`,
`ev_6e54e2e3a1e2b9ae7c9cda269e30184294728b9192ec7d92f8b960d8c41d5a54`
and `ev_0b7b9308cd5e904a4a63cb9095e88d83b9b30b7e61aede94c8f47b6916e0f53c`
bind those bounded observations. Current Chromium services adapt that ownership;
policy is retained. Legacy BrowserSettings.searchEngine remains for saved-state
decoding/model-only fallback and does not override native profile preferences.

## Shortcuts

The native Shortcuts pane customizes the app's actual menu commands. A registry
owns each stable action selector, its shipped default, and weak references to
all matching menu items. It discovers commands where the application constructs
them, including recreated Space and Easel menus; newly added page tools therefore
participate without a separate list of fake actions. Responder-chain Edit commands
stay native and are excluded from customization. Dynamic individual Space/Easel
entries, extension commands and actions not yet implemented are not invented.

Custom bindings are stored in `keyboard-shortcuts.json` under the selected Parc
application data directory, independently of browsing/session state. Writes are
atomic and precede menu changes. Clearing a binding, restoring one default and
resetting all bindings update the real menus immediately. A conflicting edit is
saved and names the other owners. Every conflicting menu key equivalent is
cleared, while the stored choices remain visible. More and the row context menu
expose Remove Conflicting Shortcut(s); resolving checks the exact revision and
owners, then disables those other assignments in one durable write. A failed
save leaves all assignments and actual dispatch unchanged. Individual Reset
restores the default chord and priority, including any resulting visible
conflict; Reset All restores the whole default set directly. Leaving the pane,
searching or selecting another command preserves saved conflicts. The original
setter and menu projection are now attributed below; they supersede the earlier
provisional-edit/confirmation adaptations.
Unreadable settings preserve the file and use defaults until an explicit reset.
General Replay, profile settings and native menu validation remain independent.

The search accepts action names and modifier names/symbols. Custom and default
commands are grouped separately. The recorder owns a local event monitor only
while first responder, consumes command keys before they execute, previews held
modifiers, uses the current ASCII-capable keyboard layout, allows Tab traversal,
and cancels on Escape, focus loss, pane change, window deactivation or removal.
A completed, reserved or unsupported key attempt relinquishes first responder;
reserved input beeps and retains the old binding. Modifier-only changes update
both the recorder and selected large keycaps without writing a binding. Recorders
retain the existing chord when capture begins, distinguish conflict/hover/selected
states, and reject accessibility activation when disabled.
Unmodified Delete clears a binding. Modifier-free ordinary text is rejected;
function/navigation keys remain available. Accessible buttons name each command.
The Essentials window reads current bindings from the same registry.

`UCKeyTranslate`. The forbidden editing shortcuts are constructed at
restrictions and existing native Edit bindings. Recovered machine code is
reference evidence, not original Swift source.

uses system red for conflict and accent color for focus/selection/hover. The
Shortcuts pane retains a separate `interactiveShortcut`; KeyBinding.State has
valid/conflict/unset cases, with shortcut and conflictingActions in its conflict.
This supports clearing the other assignments only after an explicit action.

changing its preferences; reserved Command–Z retained Command–T and ended
recording. That observation did not create a personal conflict or reset any
preferences. The focused conflict/reset producer trace below supplies those
contracts; explicit menu removal's separate native effect is also attributed.
The parity ledger tracks feature coverage and comparison results.

### Numbered sidebar shortcut settings — KB04

“Include Favorites in ordering.”, enabled by default. Item 9 shows “Switch to
ninth tab.”, off by default; enabling it reveals the Favorites checkbox beneath
it. Switching back hides that checkbox without clearing its saved value. The
current description follows both preferences, while Space commands use their
actual ordinal description. Custom/disabled binding and priority controls keep
the same registry owner.

The shipped keys are `switchToNinthSidebarItemEnabled` and
`excludeFavoritesInSwitchToNthTab`. Parc retains these in its own defaults domain,
with native AppKit checkboxes in the existing detail column as the presentation
adaptation. Additional controls leave the status field visible. Inert production
component checks cover persistence in a disposable defaults suite, visibility,
order, updated descriptions, untouched saved choices and the longest priority
explanation; they do not exercise a running browser.

### Keyboard priority

Each modified command supports Prefer Websites, Use Both and Prefer Parc. The
preference is saved atomically with its binding; old shortcut files keep their
existing renderer-first behavior. Reset restores both binding and priority.
Unmodified keys and native AppKit editing and composition retain their existing
routes; page content uses the same priority whether or not it is editable (KB17).
A native pop-up and explanation are attached to the same selected action and
registry. A saved conflicting chord keeps its priority; unsupported bindings
disable the picker and genuinely unassigned actions omit it.
names its actual visible-hint lifetime; it does not promise an unrecovered timeout.

### Shipped command priority defaults

MainMenu to the existing Parc command owners. The following additional defaults
apply to fresh settings and an explicit individual or global Reset:

| Existing commands | Default policy |
| --- | --- |
| Back / Forward; positional, linear-history and MRU tab commands; Open Command Bar; New Tab / Window / Incognito Window; Reopen Last Closed Tab; Hide / Quit / Minimize | Prefer Parc (`overrideWebView`) |
| Add Split View / Close this Split Pane; New Note / New Note in Split View; Print; Show/Hide Sidebar; Pin/Unpin Tab; Reveal Current Tab | Use Both (`promptAfterConsumedByWebView`) |

Copy/Close Tab and Developer/Toolbar defaults keep their existing mappings.
Commands without a shipped default chord remain unbound: this table governs
priority when a valid chord is assigned, and does not invent a shortcut. The
same registry supplies Settings, menu dispatch and the native priority DTO;
there is no second key handler or change to IME, editing, validation, native
consumption acknowledgment or Press Again ownership.

Version-three files retain their schema and add `menuPriorityDefaults: 1`.
The previous writer omitted any priority equal to its default, so an absent
entry cannot distinguish an untouched website-first default from an explicit
Prefer Websites choice. The migration conservatively stores website-first for
these 24 absent legacy entries, preserving explicit values, disabled and
custom chords, and unknown saved command records. This matches the earlier
migration claim. New files use the recovered defaults; Reset removes the chosen
overrides and writes the marker so reload cannot pin them again. A migration
write failure retains the effective old values and reports the existing save
error; unreadable/future schemas remain untouched.

Evidence is the exact shipped MainMenu nib SHA256
`c05560f6665c062b78dd326c4ce56307154010f981a45f4959671fb460ab1963`,
parsed as data by REA 6.7.0 and independently checked with the original ordered
NIB arrays. Objects 61/946, 172/871, 240, 678/830/1029, 717, 194/228,
690/1220 and 901 bind the initial named actions and priorities. Ordered-array
records additionally retain 33/181/778 (Sidebar/Pin/Reveal), 852/1402
(positional tabs), 207/1018 (MRU), and 477/988/999 (Hide/Quit/Minimize); the
Reset disabled; no reference preference or command was changed. The decoded
resource establishes factory configuration, not every dynamic menu/runtime
policy. Original code continues to establish the arbitration described below.

The native BrowserWindow hook runs after Chromium exclusive-access handling
for events not bypassed by its per-key keyboard-lock policy.
Prefer Parc dispatches the actual validated menu item before the renderer;
Prefer Websites and Use Both first send the key to the renderer. Unhandled
commands continue to the same menu item, with original sender and validation.
Only a consumed main-thread renderer acknowledgment can arm Use Both. A second
non-repeating press of that command, while its visible Press Again hint remains,
invokes the original menu action once. Ordinary post-renderer DevTools and
extension dispatch retains its existing ordering and single dispatch site.

Each transaction belongs to its real Browser/Profile, selected native page,
focused frame/document/node, editable state, physical NSWindow, weak menu item
and binding revision. Ownership, navigation, focus, another key or pointer
interaction, deactivation, close and binding changes invalidate
it. Late callbacks cannot replay a menu against a replacement document/window.
Keyboard-lock activation alone does not cancel the queue: unlocked keys keep
their policy, while Chromium's `skip_if_unhandled` bypass keeps actually locked
keys with the page and prevents them from invoking the shortcut hook.
The hint does not take keyboard focus. Its non-key original-window child
exposes only the cue body and delayed accessory to view hit testing; the body
supports the original vertical dismissal gesture and never executes a command.
Visible presentation is acknowledged before the second-press queue remains armed.
The Edit accessory consumes that exact queued command,
and opens its original binding in Shortcuts settings. No action is executed and
recording does not begin. A stale cue, detached menu item or changed binding
cannot reveal a replacement command. Private windows use their existing normal
parent Settings owner; the temporary private store never owns shortcut settings.

The retained Arc1.122 priority enum is `low`,
`promptAfterConsumedByWebView`, `overrideWebView`. Native
`webContents:didConsumeKey:withModifierFlags:underlyingEventType:` at
`onDidConsumeModifiedKeydownEvent`. The frame path requires a modified keydown.
WindowState stores `queuedHotkey` as an optional NSMenuItem, and the toast
checks `promptAfterConsumedByWebView`, compares the queued NSMenuItem, clears it
before dispatch, or stores it and emits `ToastType.webContentConsumedHotkey`
item. Parc retains command/page identity on both dismissal and accessory use so
an old callback cannot clear a replacement cue.

REA evidence `ev_79b955df4c76532e6e47d5c4064e622a146347a5a5533fd1be6aa6c5e5c556f1`,
`ev_eaa007f20e15329c84c96f7f651a667d76653c41a216286acc9a17ac6b187f29`
and `ev_a0a680591b623a158abe298feb1b8dd1301316a7785e974abafd34dd44073f23`
is bounded to exact raw function slices; external/indirect targets and Swift
calling convention are resolved only where corroborated by metadata/assembly.
on the first tick with no hover. Hover does not restart a five-second deadline.
Parc's original native shortcut router owns that timer and queries only the
matching visible cue. Its existing focus/document/security cancellation still
wins over hover.

The cue uses the actual shortcut followed by “again to [command title]”. The
`ToastHotkeyPillView`: system 13 semibold, horizontal padding 8, minimum height
27, continuous corner 6 and the conditional horizontal −2 adjustment. The
HStack spacing, horizontal/vertical padding 12/10, minimum height 42, continuous
corner 12 and black 0.2 shadow with radius 16 and y offset 6.

### Context exceptions — KB17

The per-command default table above is the complete shipped policy for every
unrecognized attribute is `low` (Prefer Websites). All 41 serialized priority
records (40 distinct actions) are reconciled: 37 map to registered Parc owners
with the recovered policy (both Developer Tools records cover the primary and
command, including Next/Previous Space (records 808/1108), Find, JavaScript
Console and the arrow/Zoom supplements, has no attribute and stays website-first.
Dynamic per-Space/Easel entries are not registered and receive no invented policy.

is a `KeyboardShortcutInterceptionView` whose `shortcuts` field is fed from
`keyBindingsState.priorityToShortcuts[.overrideWebView]` (scope closure
registered chord, so the page never sees it and the menu runs it, unless the
event's typed characters form one of the nine reserved editing chords
is an assertion path only. Contexts follow from that ownership:

| --- | --- | --- |
| Editable page content (text field, contenteditable) | Same priority as any page content; no editable exception | Same; the renderer's editable state no longer filters arbitration |
| Typed characters form a reserved chord on another physical key | Page receives it | Page receives it (`typesReservedCharacters`) |
| Native text fields, command bar, sidebar rename | AppKit menu equivalents precede the field editor | Unchanged native AppKit order; the renderer hook is not involved |
| Sheets, Settings, Essentials and other non-browser windows | No interception view | Hook requires the browser window to be key with its selected page |
| Separate DevTools windows | Outside the browser content view | DevTools contents have no native page; Chromium ordering unchanged |
| Keyboard lock | No lock predicate in the recovered interceptor; complete locked-key delivery remains untraced | Unlocked keys retain their selected priority; Chromium bypasses the hook for actually locked keys |
| Autorepeat | Menu equivalents only | Excluded, as before |

The consumed-key reducer has one command-specific exception. Its predicate
`FullscreenState` (witness `+0xa8`) must be case 1, `expanded`. Parc applies
that in the original Press Again owner: a consumed Use Both Exit chord shows no
cue and arms no queue while Peek or Space creation is presented or the window
is outside, entering or leaving full screen; the page keeps the key. All other

The KB17 follow-up (overlay 242) removes Parc's blanket refusal of all
registered shortcuts whenever a page holds any keyboard lock. The complete
`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`)
contains chord-set and reserved-character decisions, with no explicit lock
predicate. This supports removing the extra global condition; it does not

Retained KB26 adaptation: Chromium's Cocoa `isKeyLocked:` applies the requested
key set (excluding Escape) and marks those events `skip_if_unhandled` before
delivery. `RenderWidgetHostImpl` then skips the pre-handler and unhandled
fallback, and Parc's `ShortcutRouter::Pre` also rejects the flag. Thus only
otherwise eligible **unlocked** keys regain Prefer Parc / Prefer Websites /
Use Both processing while some other key is locked. Chromium's Escape
exclusive-access handler still runs first; the Peek Escape and Window Undo
routes retain their existing global lock refusals. Lock activation alone no
longer cancels an already queued Use Both command, but the actual locked key
cannot trigger its second-press route. Original document, focus, security,
binding and visible-cue checks remain authoritative.

The follow-up also repairs the cue component's source dependencies and current
child-window API. Its 16 registry/editor/ownership assertions and the separate
35 inert cue-presentation assertions pass; the final native unit compiles with
the pinned engine flags and the full overlay reconstructs read-only. Receipts
are retained in `work/claude-kbd-checks/kb17-recovery`. No browser or renderer
engine apply/build/package remains with the engine owner.

### Press Again presentation and original-window lifetime

section's window, timer and ownership rules stay specific to it.

`addChildWindow:ordered:`. `floatingTopRight` is placement 3: a 600×600 clear
child at `(parent.maxX−600, parent.maxY−600)`, not a page-content inset. The
8-point top/trailing padding. Parc follows that original-window geometry and
keeps the real renderer/native editor first responder; the child cannot become
Toasts module's only `setFrame:display:` and the module observes no window
changes ([toasts](toasts.md#placement)). The child moves with its original
window; resizing does not re-place it. A full-screen transition consumes the
cue through its normal dismissal. The cue is one of the window's toasts: it
replaces an open toast, and a new toast consumes it.

The main and accessory colors come from the window's theme context: the
current Space's background, or in an incognito window the static incognito
theme's basic colour ([private window theme](window-appearance.md#private-window-theme)).
0.4 below saturation 0.3, 0.2 below 0.7, none from 0.7 or below 0.1; and a
lightness step that is, below lightness 0.1, 0.3 (saturation below 0.2) or
0.15; −0.05 below 0.45 or above 0.95; 0.1 below 0.8; and −0.25 from 0.8 to
black/white 0.2/0.4 gradient, black 0.3 one-device-pixel border and the original
contrast threshold/0.3 blend; the accessory omits that extra gradient/border.
Parc's uncolored Space resolves its existing native window background before
these adjustments; this fallback is an adaptation, not a remote palette.

Pre-show/show/post-show map to opacity 0/1/0 and scale 0/1/0, anchored at
identity synchronously, then lets only that child's passive presentation
retire. Replacement cues cannot be removed by an old completion. Key loss,
sheets, close, hide/detach and invalid original ownership retire immediately.
Reduce Motion removes the scale/exit delay; it is an accessibility adaptation.

horizontal/vertical padding 8/3, continuous corner 12, trailing inset 13 and
outer horizontal padding 8. It aligns below the body through the **optional
with `arrow.up.right`. The original binding ID still reaches the `keyBindings`
without entering recording. The animator initializes a 10-point DragGesture at
Scroll/vertical dismissal consumes only the same native queued command; neither
gesture runs a browser action. A scroll event that moves nothing (a resting
finger) is ignored. VoiceOver reads the accessory as “Edit the shortcut for
[command title]”; that label is Parc's, not recovered.

The original five-second hover-aware native queue, renderer acknowledgment,
repeated-press dispatch, document/profile/security cancellation and Settings
ownership are unchanged. Existing raw REA receipts are
`ev_7eedc7ced04cf549d2bbb663e8ac98d63101707bffa68c2022d2f7660f6d581e`
(duration), `ev_c42c8ef8994141b10e0e3efee902b334f1f40c2adf758c358c49593426df88e8`
(queue), and `ev_f6d685addc36d74483a2717428e6044aff8f3d5d249730b781191fda281c3abf`
1.122 ARM64, with field metadata and constants corroborating the assembly.
prohibited. Actual light/dark inert Parc captures and 35 native assertions cover
child geometry, original responder, delayed accessory alignment, passive exit,
replacement, move, hide/detach and key loss. Those checks do not establish a
current-version website interaction or a cue haptic; no haptic producer was
found or invented. The complete command/context matrix remains separately open.

## App icon

Icon presents all ten approved P variants from the bundled catalog. The first
six follow the visible reference order; Hologram, Early Birds, Canary and Dev
remain available as explicitly requested Parc choices. Native radio buttons,
artwork previews and a current-icon marker share one observable app-wide owner.
The 81-point outer rows retain the earlier appearance measurement; the 64-point
preview frame, stationary title/current-marker arrangement and disabled hover
completed mouse/keyboard/AX activation and cancellation; only a successfully
saved selection updates its radio value. [Picker contract and native
adaptations](app-icon-picker.md) record the reference and focused checks.
This adds no artwork or account-based unlock gate.
account-date/referral conditions and reward discovery banner against Parc's
explicit offline catalog. All ten choices remain available immediately.

The selection is atomically saved in `app-icon.json` beside the normal session.
A failed save leaves the previous choice and live icon intact. A valid saved
choice is restored after application launch, before first browser/onboarding
presentation. Selecting Original restores the approved common default; debug
builds do not select Dev automatically. A missing selection leaves the packaged
Original identity alone. An unreadable selection is preserved until a user
explicitly chooses a replacement.

The app applies the choice to its application image and live Dock tile, then
uses `NSWorkspace.setIcon` on its own bundle for Finder identity. A Finder
failure is visible and retryable; it does not falsely report the saved Dock
choice as lost. A source-owned `NSDockTilePlugIn` reads the same normal-session
preference and bundled ICNS image when macOS installs the non-running Dock tile.
It removes its distributed notification observer whenever that tile is released
or replaced. Notifications contain only the target app path and trigger a fresh
validated preference read. The plugin has only system framework dependencies;
its principal class, compilation and inner-before-outer signing are in the
is involved. A disposable `--parc-profile` instance saves locally and changes
only its running app/Dock image, leaving Finder and the normal persistent Dock
choice alone.

The main and Alerts helper `CFBundleIconFile` remain `Parc.icns` with the approved
Original artwork. The icon action does not rewrite those resources, helper
identifiers, notification settings or the helper's independent notification
identity. The Finder custom icon is the native workspace mechanism.

and `NSWorkspace.setIcon:forFile:options:` with option zero at
cached icon/environment choices at `0x40b0` and installs/removes its notification
observer in `setDockTile` at `0x1a3c`. Parc uses one atomic shared file instead of
reply diagnostics and analytics. Native SDK `NSDockTile.h` documents the plugin's
local atomic-file adaptation; the included unlock/discovery reconciliation is
recorded in the availability contract above.

Delivery checks, reference comparison results and remaining icon work are tracked
in the parity ledger.

The selected app tile remains separate from Parc's fixed UI marks. Welcome/import
branding uses the approved Original P without its tile, and portrait exports use
the same silhouette as a monochrome template. All ten tile masters retain their
approved interior pixels after deterministic outer-alpha cleanup. See
[UI mark provenance and consumers](app-icon-marks.md).


## Links and Air Traffic Control



Settings and its owning browser or application prepare the editor before closing; failed saves leave the sheet and owner available. Native empty-window retirement keeps the owner alive when Settings is visible, since its original empty-binding notification cannot safely be replayed after a delayed sheet dismissal. A later explicit window close goes through the native close transaction. Quit or native-close refusal restores Settings that the owner closed during preparation.

The inline editor preserves a focused condition and its selection by rule and condition identity, restores surviving controls after rebuilding, and maintains a native key-view order. Destination refresh waits while a text editor, menu or nested sheet owns input. Failed writes are announced and have a selectable Details sheet for the full message; repeated failures remain announceable. A newly inserted rule scrolls toward the top using the recovered 0.3-second ease-in-out, or immediately with Reduce Motion. The AppKit focus and error behavior are Parc adaptations. The [interaction evidence](routing-interaction.md) separates recovered facts from adaptations; keyboard and VoiceOver runtime acceptance remains unclaimed.

The app-open URL path resolves a destination, finds an eligible regular window or creates one, selects the Space, and opens the supplied URL directly. Its missing-explicit-Space branch chooses the eligible ordered window before determining its fallback Space, as described below. Startup and onboarding replay queues use the same path. This avoids asynchronous omnibox classification dropping earlier URLs when a batch changes Spaces. Native popup/new-content ownership remains with the engine; this entry point never converts a page-created native request to a URL string. External links keep this explicit app-open path; original page requests use the separate native route below.







The native removal owner uses Chromium's `DeleteProfileHelper` so sign-out,
extension cleanup and profile preferences follow the engine's actual lifecycle.
It releases the retained CEF context and defers physical profile/cache deletion
until `ProfileManager` reports destruction complete. A loaded fallback profile
is retained during this operation; deletion cannot create a replacement window.
The native UUID journal blocks new owners, including background profile loading.
Only confirmed absence of both profile/cache directories and a durable completed
receipt permit model removal. Access or I/O errors remain recoverable pending
state. The journal, asynchronous completion and destruction adapter are current

### Internal original-request routing


After normal Chromium OpenURL security validation consumes the one-use document token, destination preparation obtains the real Profile and existing or empty native Browser. The genuine `BrowserWebContentsDelegate::OpenURLFromTab` receives the complete original request and once callback. Chromium retains its cross-profile opener/source/referrer rules. The source WebContents is not transferred and no replacement GET is constructed. The created page carries the exact target Space before shell adoption; the hint does not override later explicit transfers.

Source document, URL, query epoch, selection, rule, destination and Profile-removal state are revalidated after asynchronous preparation and app callbacks. Stale operations cancel without replay. Failure closes only a newly created destination that remains empty. Native pending-creation accounting protects shutdown/removal while Profile acquisition is in flight. `NotifyNativeDeferredOpenURL` supplies the original source's actual `DidOpenRequestedURL` observation once after deferred preparation, independently of the navigation-handle callback; it never starts navigation or calls another delegate.











The 1.122 Core renderer entry `0x537df90` calls `0x691faac` at `0x537e3bc` and branches on its Boolean result, then invokes its frame delegate at `0x537e66c`. The genuine WebContentsImpl `+0x28` delegate vtable `0xbb8b7d0` points through thunk `0x548e6a0` to `0x548d794`. The earlier permission callee's source-Profile input and background/popup branches closely match [Chromium 142 CanCreateWindow](https://raw.githubusercontent.com/chromium/chromium/142.0.7444.176/chrome/browser/chrome_content_browser_client.cc); its popup predicate `0x5c00730` and blocking callee `0x5c00740` are supported by the original disposition comparison and popup-blocker strings. This concrete permission path yields no destination Profile. The matching [Chromium 142 blocked-window carrier](https://raw.githubusercontent.com/chromium/chromium/142.0.7444.176/chrome/browser/ui/blocked_content/blocked_window_params.cc) constructs a separate URL-based navigation with `is_renderer_initiated = false` and no POST body or content type; it does not provide the complete renderer creation request. This comparison does not prove absence of an unrelated higher-level producer.



The pinned CEF `OnBeforePopup` callback is another pre-popup surface, but its interface supplies URL, frame name, disposition, features and gesture rather than the original POST body/content type or a destination request context. Its success and abort notifications are part of the popup lifecycle. CEF consumes the pending popup when the actual child exists; its host creation can replace a mismatched request context with the context derived from that child, then associates the opener and child before adoption. That context reconciliation does not select or create a destination child or carry the original request. An early `kIgnore` invokes `CreateWindowResult(false)` before `WebContentsCreated`, cancelling the still-pending popup and potentially calling `OnBeforePopupAborted`; the normal suppressed-success path calls `OnAfterCreated` first and reports false only afterward. Deferring creation past that reply therefore changes a concrete terminal lifecycle, not just timing. Parc's pending popup platform delegate retains the source native route (`CefBrowserInfoManager::CanCreateWindow`). If CEF takes the separate Browser-creation branch, `ChromeBrowserHostImpl::AddNewContents` supplies that route and `PrepareBrowserWindow` rejects one that differs from the actual Profile's registered route. Parc's normal native setup instead requests default Browser creation, which can bypass that separate branch; its platform delegate still uses the retained route's provider for owner-change notifications. A destination child therefore needs an audited destination route/client and any required window reservation as well as a destination RequestContext; context reconciliation alone does not establish correct ownership.


- Admission would require HTTP(S), an actual suppressed opener, an empty source clone ID, an ordinary non-guest background tab, a live source document and a materialized, eligible destination Browser and Profile. No window or Profile creation, UI, waiting or nested renderer work is permitted in the query. Foreground requests keep their existing child-dependent Peek path. Source file-chooser, guest, creation-override, sandbox, popup, URL and upload-body checks remain authoritative; their precise ordering must be retained, not rerun after activation is consumed.
- The destination page would need its own Profile, SiteInstance and empty session namespace, while carrying the original creation features, initiator snapshot, form body and content type, download and ad policy, gesture and suppressed-opener state. The existing OpenURL-to-Navigate carrier omits some of these and its normal creation path starts navigation before insertion; adding fields alone does not preserve the creation sequence. A destination-specific continuation would need the source `WebContentsCreated` and observer sequence, destination CEF ownership/adoption, then original load, with the source/destination lifecycle checked at each reentrant boundary.
- Empty clone ID is necessary but insufficient: Blink can request a source storage clone before COOP or credentialless policy later suppresses the opener. Even a genuinely fresh namespace still needs a destination-owned creation and cleanup contract. `WebContentsImpl::CreateWithOpener` copies sandbox and creator-origin state and retains an original-opener relationship when scripting is suppressed; Chromium also uses that chain for COOP reporting, DevTools opener IDs, fullscreen blockers and popunder activation. For a LINK navigation with no usable previous top-level URL or direct opener URL, pinned Chromium's `HistoryTabHelper` can use the original-opener chain's source URL as the destination history/visited-link top-level attribution. This is a conditional source-level data flow, not a runtime leak or exploit claim. Its safety across BrowserContexts and equivalence to Chromium's cross-Profile source sanitization are unresolved; retaining the relationship may affect another Profile, while dropping it changes those behaviors. Until those questions and the exact notification, failure and teardown behavior are answered, this interface is a design boundary, not a safe production route.


## Application Settings from Incognito

Settings opened from a private browser is owned by the application and backed
by the actual regular BrowserStore. Its initial profile is the private context's
explicit normal parent, never the temporary private profile UUID. The window
remains usable after that private browser closes. No private Space is supplied
for assignment: Use for this Space stays unavailable, while an explicit New
Profile creates a regular unassigned profile. Profile preference writes and
pane/profile selection use the existing normal persistence path; private tabs,
history and session state remain memory-only. Replay uses an actual normal
Space belonging to the parent when one exists.

Page-opening actions retain the exact Settings controller and revalidate its
normal store, profile and Space. More Settings uses the original parent; Manage
Passwords uses the selected real profile. Parc reuses an eligible regular
browser in that profile or creates one only when the page action is requested.
It retains an existing same-owner WebUI subpage and uses normal native security
and selection admission. A missing/retiring profile or busy owner refuses the
action. Regular-window arbitration is an explicit Parc adaptation: the ordinary

which sends application action 7 with zeroed optional payload through the
application store; this entry has no incognito/window branch. Focused REA
`ev_c91a66dd79017e35080cd1f45257e040b5a6cf49e3e1fd915ab13fa4a5589c97`
covers that 184-byte raw slice. External type/import names come from the retained
shows Cmd-comma from an empty Incognito window opening ordinary Settings with
the real Default profile and its existing Space count/preferences. No preference
or WebUI action was executed in that reference.

New Window from private creates a standard window through the exact regular
parent and opens that new window's command bar. A missing/retiring parent or a
parent with no normal Space is rejected rather than silently using another
profile. Startup restoration has a separate entry which keeps its restored
page or pending launch request focused. Existing command-bar dismissal,
selection and navigation owners remain responsible for the new window.

payload: it creates `Style.standard` (tag 1), empty initial items, zero optional
payloads, and `WindowCreationOptions` with `showCommandBar=true`, then emits
show-command-bar argument. Fresh REA
`ev_5f7ed6b0ecb6f0a5ac096f6ce52a527ea486d235454fbd6893714125158ce58c`
covers the original 12,352-byte reducer; the mapped image and original table
establish dispatch and external identities. This proves the standard-window
and command-bar entry, not a modifier-specific incognito gesture. Installed
executed for this reference. The retained action itself supplies no explicit
Profile, so regular-parent arbitration remains a Parc adaptation rather than
WebUI destination policy remain unresolved.

## Ordinary Toolbar appearance


Each visible native page owns its Toolbar strip. Navigation uses the existing original-page history/navigation objects, address entry uses the existing command-bar session, and copy uses the existing native clipboard policy. Extension buttons retain original native action leases and popup anchoring follows the selected Toolbar. Site Control Center and Split View Menu use existing page/split command owners. Split and Peek controls revalidate the exact original page, document revision, window and selection before dispatch. Hidden, retired or obstructed owners cannot dispatch; hiding a focused strip returns focus only to its still-current native page. Developer Mode keeps its existing separate strip. Blank tabs, Easels and native popup windows retain their existing chrome.

Address presentation never constructs navigation URLs. Ordinary HTTP(S) titles use the original native URL host without a leading `www.`; full display follows the recovered display-only suffix/prefix trimming and lowercase formatter, then separates an actual host prefix from its lighter suffix. Copy, accessibility, command-bar entry and page identity retain the complete original URL and native source objects. The shared [title control](split-groups.md#original-pane-title-presentation) now uses the original fonts, light/dark ink, padding, truncation branches and hover/press transitions. The original 32-point centered row and five-point side padding are attributed through the [top-bar container](split-groups.md#original-top-bar-container-placement). Non-split control sizes, available-width allocation and compression thresholds, native button focus rings and retained sidebar keyboard/payment region remain explicit Parc presentation choices.


## Interface sound and reordering feedback

Advanced contains “Play Parc sound effects” and “Haptic feedback when reordering
tabs.” `InterfaceFeedbackPreferences` owns both application appearance values in
the versioned local defaults record `parc.interfaceFeedback.v1`; normal and
private windows share that owner without changing profile/session data. Invalid
or future records are preserved and disable these controls and consumers.
An absent record enables both values. That fallback follows the observed enabled
choice, not a recovered factory-default registration.

`InterfaceSoundEffects` caches one bundled native `NSSound`. A successful,
still-owned native capture plays it at volume 0.7 immediately before presenting
the captured pixels, provided Parc is active and the sound preference is enabled.
Preload is silent; a missing cache entry may be loaded at the next eligible play.
Native `play()` owns overlap/refusal. There is no stop/restart, loop, fade,
deferred cue or fallback beep. Cancelled, stale and failed capture results never
reach this call. Retake can produce another genuine acquisition; cropping,
Portrait framing and output actions reuse pixels without another cue. Parc's
unified capture flow deliberately applies the same completion cue to Full Page
and cues Portrait after successful acquisition. The older reference's separate
full-window button starts its sound effect earlier, and its separate full-page
completion does not directly reach either recovered play task in the bounded
reducer. Onboarding music, webpage audio and native error beeps remain separate.

`SidebarReorderingFeedback` belongs to each sidebar. Accepted original-item drag
proposals publish their child insertion index, or -1 for an on-item proposal.
Consecutive equal indices are removed before combining with the live enabled
preference. Each enabled emission requests native `.generic` feedback at `.now`.
Changing a row identity or parent without changing the numeric index does not
emit another event. Disabling filters output while retaining the latest index;
enabling after a proposal re-emits that index through `combineLatest`. Leaving
or cancelling a drag does not reset the stream; releasing the sidebar cancels
its subscription. Menu/AX moves, arbitrary pointer movement, Easel interactions
and unrelated split controls do not manufacture reorder cues.

whose original key-name table resolves to `playUserInterfaceSoundsDisabled`.
then sets volume 0.7 and invokes `NSSound.play`. `CaptureAction.willDisplayCapturedImage`
is the retained data asset, SHA256
`015fb8f94bf601192d7f4e62afd044d1e74547e2403862cfc1623db06e72a2f3`.

the same child index supplied to `setDropItem:dropChildIndex:`. Its native sink
(generic/now). BoolKey 124 resolves to `tabReorderingHapticsDisabled`. Focused
REA `ev_3fd83c93924697b9dca75090e2272712ab0dee86e260bf58f1d297d1c64b6553`
covers that 84-byte sink. Its raw-slice pseudocode has unresolved external calls
and a tail-call truncation warning; original image imports/selectors and complete
assembly supply the native call identity. These are static mechanism references,
not an observation of sound output or trackpad feedback.

## Webpage window dragging

Advanced’s “Allow window dragging from the top of webpages” uses an independent
application preference shared by regular and private windows. Reading it never
writes a profile or private session. A malformed or future record remains intact
and makes the control and consumer unavailable. Parc explicitly uses enabled as
factory registration has not been established.

Each visible original browser pane owns a transparent `WebpageWindowGrabber`.
Its rectangle starts below the pane’s top strip and ends 60 points from the top,
with a 14-point right gutter. The original native page host’s managed content
bounds also exclude its infobar shelf. Blank tabs, Easel views, Peek, capture,
popup chrome and fullscreen do not acquire this gesture. Native security,
retirement, transfer, document and window gates remain authoritative. Parc’s
extra lifecycle and unavailable-window gates are explicit safety adaptations;

A normal mouseDown passes into the original webpage. Arrow-cursor drags begun
with no modifiers or Option alone can call `NSWindow.performDrag` with that same
original dragged event. The view does not focus/select a tab, manufacture a click,
replay a URL or move the renderer. Pinned Chromium’s native Cocoa mouse-event path
re-hit-tests its actual window content hierarchy for each event, supplying the
same boundary used by the recovered grabber. There is no separate mouse pipeline.
The committed sequence’s local monitor handles only drag/up events in its original
window. It accumulates absolute movement per axis, consumes drag events, and
consumes mouseUp only when the vector length exceeds one point. Removal, hidden
content, changed document/geometry or lost ownership cancels the sequence.
Keyboard focus, accessibility window movement and other pointer events retain
their native owners; no timing delay, cursor override, animation or haptic is added.

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`)
resolves BoolKey 60 to `contentWindowDraggingEnabled`. Controller setter
in the original visible controller collection, and accepts no modifiers or Option.
`ev_bb040d1faaf8ce3c475c12ed05bbf134484165600f05b502ab1f975e5534548e`
covers the complete 1012-byte hit-test function. Raw-slice calls remain unresolved;
original mapped instructions/imports/selectors establish their identities. These
static references do not establish observed window-drag feel or all mode behavior.


## Shared Quote affordance

Advanced's **Enable Shared Quotes when highlighting text** is an application
appearance preference shared by normal and private windows. It controls the
selection-driven sidebar Share Quote subtitle and Copy Current URL as Quote
button. The explicit Edit → Copy URL as Quote command remains available when the
setting is off. Its helper refers to the menu command so customized shortcuts stay
truthful. `SharedQuotePreferences` preserves unreadable/future records.

`SharedQuoteSession` owns gesture tracking, release and a 200 ms main-queue
debounce. The native observation publishes opaque tokens for one original
primary-frame document, window and selection; selected text remains native.
Tokens are revoked on selection, navigation, focus, visibility and lifetime
changes. Only the token actually displayed can act. Copy uses the existing real
text-fragment generator and enterprise clipboard policy, preserving private
context identity. Capture and command-bar ownership suppress the affordance.

sidebar appearance establish the labels and controls. Parc's enabled fallback
matches that installed value; original factory registration is not established.
that case, so both visible entries share exact-selection copy. KB38 now projects
the live Copy Quote binding into these tooltips and implements the separate
command-field URL-copy education described in [keyboard navigation](keyboard-navigation.md#live-binding-discovery-and-copy-education--kb38).
Alternative Toolbar placement and a separate quote-specific upsell are not
asserted. No theme-data or sharing-service preference is implied.

## Website theme data

Advanced → **Allow websites to get your theme data** controls an application-wide
`themeToCSSSharingAllowed` true; Parc preserves that default, persists explicit
changes, and preserves an unreadable/future saved value while withholding sharing.
services. The registered default is established by the original startup literal,
not by a checkbox in an existing user's profile.

The owning browser window publishes its actual Space theme and semantic palette
when the Space, live theme preview or effective appearance changes. Its stylesheet
contains twelve `--arc-palette-*` variables and either a simple background color
or zero-based base/overlay gradient colors. These existing CSS names are a website
itself is owned under `__parc_theme_css`. No page URL, user identifier, account,
browsing history or theme image is sent to a service.

The palette exports foregroundPrimary/Secondary/Tertiary, maxContrastColor,
minContrastColor, backgroundExtra, background, focus, hover, cutoutColor, title
and subtitle. Native Display P3 conversion, eight uppercase hexadecimal digits
and nearest-integer component rounding follow the recovered converter. Dynamic
system colors resolve in the window palette's actual light/dark appearance;
extended components are bounded to CSS bytes. The background projection uses
Parc's existing renderer: two base stops, then transparent/opaque third-color
overlay stops. Uncolored windows use the semantic background. That projection is
an explicit adaptation to Parc's source-owned theme representation, not a claim

### Settings theme inventory and default

state and action types. `PreferencesFeature.PersistedPreferencesState`
receives its Boolean through case 9 `onToggleThemeToCSSSharingAllowed`.

exact key. The 37-entry startup defaults literal in AppReducer stores key 104
passes it to `registerDefaults:`. Existing explicit false values therefore win
over the registered true default. Retained Sidebar registration evidence plus
the components, type, cross-reference and annotated-function helpers resolved
this inventory without a new decompilation or another reference version.

Automatic, Light and Dark are the application appearance parent, exposed by
View → Appearance and the Space theme editor. They are not another Settings
pane preference. Their actual consumers, native reset, persistence and Undo
remain the completed [appearance owner](space-theme-appearance.md); theme
material and semantic text colors remain the completed
[renderer owner](space-theme-rendering.md). SET22 adds no duplicate control or
alternative preference record.

The Settings switch uses the shared `WebsiteThemePreferences` owner. Saving
precedes its published value; every open browser uses that emitted value rather
than rereading the old value during Combine's `willSet` publication. New
consumers receive the current value immediately. The original window's palette
callback also republishes for Space/theme preview and effective-appearance
changes. `PCNativeWindowBinding.setWebsiteThemeStylesheet` stores that value and
publishes it to each exact owned browser; newly attached native browsers receive
the stored value. The existing native document/attachment leases below own
navigation, parked pages and transfer. Opt-out passes nil, removing only Parc's
stylesheet, and does not alter a Space palette, application appearance or
website-authored CSS. No new native interface or engine rebuild is required.

`tests/WebsiteTheme/check.py` compiles the real preference and color-projection
owners with warnings as errors. Its isolated UserDefaults suite covers the
registered default, read-only construction, persistent explicit choices,
idempotence, publication to multiple/current and newly attached consumers,
persistence before delivery, and malformed/future-value preservation. The same
component covers all twelve public palette names, light/dark semantic resolution,
P3 conversion and the single/two/three-color background projections. It opens
no browser, changes no personal preference and does not claim engine/runtime
acceptance. Shared pane appearance, motion and focus belong to SET24–SET26.

The finished suite passes 56 assertions. Whole-module SIL with warnings as
errors passes with zero diagnostics. Fresh independent `set22_review` cleared
the complete intended source and tests; the engine-package ledger fast-forward
changed no checked source. Receipts are retained under
`work/settings-coordination/set22` and `work/claude-split-checks/set22-final`.
SET22 is complete under the current source/component completion rule.

### Recovered native boundary

The retained Arc1.122.0(71105) main executable is SHA-256
`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`;
Core is `97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`.
(REA `ev_eec52c2f32207ccb4d50681856190ba350a3201a44177d6cfe816c46ad21422e`).
The bounded raw decompilation requires full-image assembly for external symbols,
multiplies RGBA by255 and uses `#%02X%02X%02X%02X`.

requires real web content and retains its original frame identifier, loading
calls `insertStylesheet:stylesheet:` with the stylesheet identity; it does not
execute JavaScript or reconstruct a page. Core `0x68e6978→0x685d8a0` routes the
original WebContents to an associated `arc.mojom.RenderFrameAgent` service;
`0x68e6a7c→0x685d99c` is its separate removal route. Renderer-side internals were
not recovered in this bounded trace. The independent implementation uses the
pinned Blink stylesheet API through a typed associated renderer service, with
original window/document ownership checked on delivery. Each actual attached or parked
page receives a per-attachment owner token. The native renderer rejects a different
document token, and removal additionally checks the current owner token so a late
former-window clear cannot erase the destination's style. Detachment revokes the
lease before callback-capable teardown; a destination attachment receives the
new window's current value. The outgoing primary document is revoked while still
active, and navigation/restoration publishes the current theme without waking a
cached frame. Only the owned stylesheet key is removed/replaced; page-authored
styles and browser selection remain intact.

this trace does not establish removal of an already applied stylesheet. Parc
explicitly revokes its current owned style on opt-out. The exact first-paint
timing and reference background enum remain comparison work; compiler and
isolated color/preference checks do not establish browser runtime parity.
Settings geometry and native control motion are covered by the completed
[presentation](settings-presentation.md) and [motion](settings-motion.md) contracts.
## Local browser data export

Advanced → **Export Data** saves the current Spaces and saved tab links as
`Parc Data Export.md`. The normal application store is copied before the native
save sheet opens. Cancelling leaves no output; accepting writes that exact
snapshot as UTF-8 Markdown with Foundation's atomic replacement, away from the
main thread. Later navigation, reordering or deletion cannot change the captured
input. Closing Settings cancels an unanswered sheet; an approved write completes
and reports real file errors through the native application error presenter.

Spaces retain their stored order and use level-one headings. Empty names become
`Space N`; newline-separated heading text is joined with spaces. Each Space
includes the Favorites of its own profile, then its pinned and Today containers.
At each level, ordinary saved URLs come before nested folder headings, whose
depth caps at six. Split children retain their stored order without an invented
group heading. Tab titles, custom labels and live pinned-tab navigation do not
replace the saved destination. Archived tabs and native Note/Easel documents are
not exported as browser links. Notes retains its separate HTML archive command.

`77be289e16a139056dd9d0bf145ad4707d4e217289bb279a333949dcfd39c52d`.
`NSApplication.presentError:`. REA
`ev_57cf948e7a2dc8c20fc52ba5ef3501bd19261fbf9c9191a1c4929b3614f5cd10`
is corroborated by current-image imports, selector stubs and function boundaries.

`ev_5030d6f48f4ec605056710c4b85086f78fb4be8caba106da2097bce3f9a6908f`
and `ev_29ef1e07afd7c69a1a31e639bbfba07cd5058cc13f301c23ef65147826887b9b`
are checked against original instructions and typed metadata: only SidebarTab
payloads emit their `savedURL`; list/tab-group payloads emit folder headings.
Raw-slice external labels are not original symbol names or recovered source.

Parc's existing pinned/Today hierarchy projects the reference's ordered
remains unestablished. Folder cycle protection, typed local-document exclusion,
Parc naming, duplicate-sheet prevention and the current Advanced button layout
inspected and cancelled without exporting personal data. No functional browser
test or whole-Settings appearance/motion acceptance is claimed.

## Warn before quitting

General → **Warn before quitting** is an application preference shared by regular
and private windows. Enabled Quit selects the real browser window in key, main,
then ordered-window order and presents its owned **Quit Parc?** sheet. **Cancel**
changes no session or close state. **Quit** closes the sheet and continues the
existing Notes-save and Chromium aggregate close-consent/drain path. **Quit, and
don’t ask again** saves the disabled preference before that continuation; a
webpage declining close does not reverse the user's setting. A second Quit while
the warning is present dismisses it and follows ordinary termination. Repeated
approval, stale buttons and original-owner closure cannot approve twice.

`77be289e16a139056dd9d0bf145ad4707d4e217289bb279a333949dcfd39c52d`,
REA evidence `ev_280cac1997071a95aecf2aaf6152e84f5a68cdb9bb15efcfd1f1cf69e8a4ae2e`
and `ev_17e35144bf3423d2faae429828886660ca8822627dacc13e17fc7250e3acf099`
are corroborated by current-image instructions, selectors and metadata.
false preference write for key40, `shouldWarnBeforeQuitting`, then ordinary
termination. The custom dialog uses a 62pt app image and a native sheet;
case. Parc uses its own current application icon.

The installed General checkbox was observed Off, which establishes that saved
record now uses that factory default; existing explicit choices remain intact.
Versioned local policy preserves unreadable/future bytes, retains confirmation
and disables only policy mutation. Existing modal ownership is preserved. Current AppKit
380×300 layout, typography, button spacing, Return/Escape, error handling and
once-only approval scheduling are adaptations; exact historical/current sheet
appearance and motion remain comparison work. No functional
browser test or real application quit was performed. The reusable
`bash scripts/test-quit-warning.sh` checks actual preference persistence and
native decision controls without displaying a window.


## General preview preferences

General → Previews Settings opens a native sheet for **Parc Folders** and **Recent pages on Notion, Figma, Linear, and Confluence**. Each checkbox updates the existing application-wide preference immediately; Done/Return closes the sheet. The sidebar menu and Settings share the same saved values and defaults. A change retires active previews and refreshes the preview actions in every existing browser window. The original Settings window owns the sheet; closing it retires its controls and observers, and late callbacks cannot change a new sheet or its preferences. No mail/calendar live-service control is present.


Parc preserves existing UserDefaults keys and fallbacks; installed checkbox values are user state, not evidence of factory defaults. Its smaller two-row sheet, native AppKit material/bezel/accent, Escape dismissal, retained Confluence history provider and omitted vendor Learn more link are explicit adaptations. Original provider/data ownership remains in [sidebar previews](sidebar-previews.md). Native sheet motion and shared original-responder restoration are covered by SET25–SET26; whole-product visual polish remains separate. This delivery changes no engine source.

## Default browser

The Parc application menu's **Set as Default Browser** and General's **Make Default** share one application-owned controller. An explicit action passes the running app bundle URL to the genuine NSWorkspace setter for HTTP, then HTTPS after the first completion. macOS owns required consent. A failed or cancelled first request stops the sequence. One pending request prevents duplicate prompts; original request/scheme tokens reject repeated or obsolete callbacks. Both outcomes refresh actual system ownership. Closing Settings does not discard the pending system operation.


The actual original status predicate queries the handler of `http://`, resolves its display name and compares it with the current bundle's display name. Parc deliberately compares the resolved application URL for **both schemes**, so a different installed development copy with the same name cannot falsely count as the running app, and partial system changes remain visible. Querying uses LaunchServices through NSWorkspace; it does not navigate or fetch a webpage. App activation, General-pane entry and Settings activation refresh the result without polling. No saved Boolean substitutes for system status.


### Essentials education window

The education window keeps the original browser controller and reads current
custom/default/disabled chords from the shared shortcut registry. Its fixed
light/dark PopoverBackground and PopoverMessage colors are independent of the
Space theme. It uses the bundled MarlinSoftSQ-ExtraBold 20-point heading with
−0.8 tracking, 15-point row titles, 12-point descriptions and native dividers.
A separate floating, nonopaque, full-size-content window retains its native
close/minimize controls and may accompany fullscreen. The original physical
browser window supplies initial placement; View All still opens that owner's
Shortcuts settings. Inactive/hidden education controls cannot dispatch commands.

installed 1.170 confirms the education window and View All destination. The
remove their complete row and reflow the remaining rows; the fixed outer frame
and AppKit row measurement remain adaptations.

and stores five optional chords in education state (metadata field offset
branches retain education for New Tab, Recent Tab, Copy URL and Split. Recent
emits adjacent-recent action35; Copy and Split emit original-window MainMenu
clear education. Full-image instructions and field/tag mapping resolve these
branches; fresh REA `ev_db55aee95531cbf34622dfbb3883e9a39f3c20936da021922baafb94ef99a20f`
corroborates the procedure/computed-dispatch boundary, with bounded decompilation.

Parc preserves that original controller and passes the actual key event into
the existing held-MRU owner. Menu forwarding requires the exact available
education/browser pair and cannot fall through to another front window after
expiry. Copy retains education focus through a narrow plain-URL native
command-window capability: exact selected page, binding/client, original
physical window and actual key auxiliary window. The existing Chromium
clipboard policy, weak document/URL/clipboard revision and completion remain
authoritative. Both windows, security, selection or document loss invalidate
the operation; ordinary focused Copy/Markdown/Quote admission is unchanged.
This explicit capability is a Parc adaptation to the recovered logical-window

The original education window inherits `NSWindow` with no local key-equivalent
or key-down override in its Objective-C method table. Its Copy/Recent/Split
including a repeated event, through the same live education/browser admission.
It passes the original event to the existing held-MRU session. Disabling,
customizing or resetting a binding changes repeated delivery through the same
registry. No repeat timer or synthetic key-up/modifier stream is introduced.

This establishes the education boundary, not OS repeat generation cadence or
all browser/modal context exceptions. The original superclass/selector trace
and an inert actual AppKit menu component support it; no live-browser shortcut
was exercised. Broader hold/reversal/refusal comparison remains a separate
requirement; the bounded Essentials focus/AX and native presentation completion
is documented below.

### Shared shortcut keycaps

Essentials and the Shortcuts detail/recorder display share one passive
`ShortcutKeycapView`. The registry still supplies the actual current symbols;
recording, conflict resolution and keyboard dispatch retain their existing
owners. In Settings, a native static-text accessibility element exposes the
semantic chord; Essentials combines its passive rows as described below. The
decorative SwiftUI subtree is hidden from accessibility and cannot
accept first responder or pointer hits. Long customized Essentials chords widen
their trailing area and reduce adjacent label width instead of clipping keys.

shading, continuous inset white faces and highlight strokes. Small caps are
27 points. Large face padding/corners and rounded semibold glyph sizes depend
on chord length and whether it contains a word key. Conflict red comes from the
and key count, using the shared spacing and the stored maximum dimension.
layout uses a 24-point gap below the caps, a 14-point bold title, eight points
before its natural-height 12-point description and 24 points before the divider
modifier-only preview does not manufacture a stored binding.

No selection displays the Command cap and a 50-point accent-masked smiley;
an unassigned action displays two empty caps at 0.3 opacity. These are distinct
The bundled Preferences `smiley.json` supplies the actual three stroked paths,
parent transforms and five-second keyframes. Parc's small source-owned vector
reader handles this asset rather than adding a general animation dependency.
preserves that lifetime with an exact-window/timer guard and no input owner.

The installed intro, unassigned and two-/three-key states were visually compared
with an inert production component. Selection, clearing, reset, filtering and
passive accessibility were checked through the real settings/registry owners.
The focused recorder/detail transition is now implemented and compared as
described below. The stored frame consumer is attributed in the next section.

`arrow.up.right` glyph, two-point label padding, NeutralButtonForeground and a
four-point continuous GrayA7 border. The border never receives input; the weak
inert native production component were visually compared. No bespoke press,
hover, spring or haptic is introduced. Parent action mapping, absent-binding rows and delivered held/repeated events
retain the command owners above. Essentials uses the same native control and
window focus/motion owners, with the comparison below; broader browser-context
traversal remains separate.

### Essentials interaction and accessibility

element, interleaving each visible title, chord and description. The heading
and actual View All button are separate; there are no per-row controls.

Parc now projects the same ordered visible content through one stable passive
accessibility element. It weakly belongs to the original surface/window, uses
its current native row rectangles for screen geometry and AX hit testing, and
exposes no Press action or child controls. Empty/hidden/detached content revokes
that element. Customization, conflict, disabling and reset update the same
projection and notify visible layout changes without claiming focus. Settings'
individual keycap accessibility is unchanged. This virtual element is the
explicit AppKit representation of the original SwiftUI VStack grouping.

View All remains the actual SwiftUI Button from the recovered header at
accessibility behavior are retained. The complete native show/close paths at
`close`; they supply no custom animation. The controller factory positions its
window synchronously. Parc therefore keeps native presentation and motion,
without an invented spring, row hover action, focus ring or haptic. Original
command/Escape/View All state semantics and owner refusal remain as above.

The installed reference and actual inert production window were compared for
appearance and AX grouping. In the component's verified active/key state,
Tab/Shift-Tab retain window focus under the unchanged current macOS keyboard
navigation setting; the native View All action reaches its original callback
and closes that component. An earlier background launch reached the callback
with `key=false, active=false` and was correctly refused; showing the fixture
after native application readiness established the positive owner. This was a
fixture timing correction, not a production activation change. The actual
native component passes 60 assertions covering ordered live bindings, conflict
and disabled omission, stable AX identity/hit testing, hidden/detached lifetime,
no Press action, no focus takeover and the existing repeated/menu dispatch.

KB37 is complete under the current source/component and appearance protocol.
adaptations. Screen-reader voice output, alternate OS keyboard-navigation
settings and functional browser commands were not exercised; no personal
binding or preference was changed. General contextual traversal, held-input
comparison and other surfaces remain in their fixed Keyboard requirements.

### Shortcut row menus and removal effect

Shortcut, then Reset Shortcut to Default. The remove callback
selected detail identifier before showing the effect. It then clears the
confirms both entries and that right-clicking an unselected row leaves the
detail introduction unchanged; its default reset is disabled. The menu was
canceled without changing any reference binding.

an actual key window, flips the stored rectangle, converts it to screen
coordinates, and invokes `NSAnimationEffect.poof` (SDK enum value 10) at its
not a generic animation for every registry change.

Parc's native row menu retains command ID, registry revision and a weak original
window. Filtering, other row selection or menu tracking cannot retarget its
action to a different command. Stale revisions, detached/hidden panes, a lost
key window or an attached sheet refuse the action. Reset uses the existing
durable transaction and preserves the actual detail selection. A resulting
conflict remains visible on both original commands until explicitly resolved.

For an explicit removal of the selected command, Parc captures the actual
count-sensitive keycap content rectangle and invokes the native macOS effect.
It rechecks the exact view/window, geometry and Reduce Motion immediately
before presentation. The file write precedes the effect because a Parc durable
reducer. No effect is added to recorder Delete, reset, conflict cleanup, another
row's removal or passive registry refresh. The OS owns the effect's timing and
completion; Parc adds no timer, spring, haptic or completion-side model change.
The deprecated-but-available AppKit effect is retained deliberately to match
the actual reference mechanism rather than substitute a cursor or custom flash.

Focused inert AppKit checks exercise actual row-event/menu dispatch, original
target persistence, reset/disabled state, revision/window/detach refusal, failed
binding was changed and no functional browser test was run. The removal effect
presentation is described below; the later conflict/reset section completes
that bounded visible-state contract.

### Recorder focus and detail transitions

row selection, hover, binding conflict and enabled state. The application’s
explicit Dark Aqua setting is distinct from named colors resolved in the
view’s effective appearance: the default application branch uses a white fill,
Gray4 outline and Gray10 text; the explicit-dark branch uses translucent white
fill/text and Gray7 or selected-white outline. Focus uses the actual accent or
Gray4/7/10 assets supply the sRGB light/dark values. Its focused recorder was
observed without entering a new binding, then canceled with Escape.

0.5 seconds later, run for 1.5 seconds and repeat, using timing control points
1.175/1.4, opacity falls from one to zero and radius changes from six to seven.
Reduce Motion bypasses the original animation. These values come from the
retained native implementation, not measurements inferred from a screenshot.

Parc’s existing first-responder recorder keeps ownership of input and commit.
The passive native label returns pointer hits to that recorder and is excluded
from its accessible children, leaving one actual button/value. The layer halo
cannot receive input. Original focus loss, hiding, detachment, disabling or
window resignation ends both capture and motion. Parc skips invisible animation
work outside focus and preserves an existing pulse phase across modifier-only
updates; these are bounded lifetime adaptations. The existing narrow-row font
fitting remains a layout adaptation for unusually long custom chords. It now
measures the actual native cell, including its text insets and size-dependent
glyph metrics, within the existing 8–12-point range; this prevents complete
Space chords from clipping without changing recorder bounds or input ownership.

Held modifiers update the existing passive detail caps without replacing the
original row or moving focus. One through four held modifiers keep the same
200-point detail column; Escape restores the saved chord and no binding write
occurs. The invented recording instruction line has been removed; native
accessibility help still explains cancellation and removal. The focused
component checks exercise focus, short/long previews, cancellation, exact layer
values, Reduce Motion, size changes and retirement. This closes KB11’s detail
geometry/focus requirement. The following conflict/reset delivery completes
KB09; remaining whole-family requirements are still counted separately.


### Saved conflicts, system warnings and reset

`KeyBindingAction.onShortcutUpdated`. Preferences case 45/action 0 reaches
and modifier mask for nonvalid states. Parc now retains those saved choices,
projects conflicts into actual menus/native priority queries, and uses the same
active-binding projection for held-MRU entry, Essentials and command-search
keycaps. Native editing restrictions and existing saved-choice migrations remain.

The conflict row has a red 16-point `exclamationmark.circle.fill` button
the other row nor supplies an animation. Parc preserves the query, detail
selection and native first responder while scrolling. More and row context menus
call the same explicit removal owner; no separate detail button is invented.
Revision, original window, visibility and attached-sheet guards reject stale
menu/reveal actions. Three-way conflicts remain inactive until only one owner
is left, including across reload and failed writes.

The separate orange 16-point `exclamationmark.triangle.fill` is advisory. The
enabled records, translates physical codes with the current ASCII-capable
layout, maps Carbon modifiers and omits unmodified records. Parc uses this real
read-only API. A browser conflict takes visual precedence. The help reads
“System shortcuts may take priority over this shortcut.” Refresh on app
activation and keyboard-layout change is a bounded cadence adaptation; this
never changes system shortcuts or intercepts them.

Parc's actual atomic file commit remains authoritative and can fail truthfully.
Reset and conflict cleanup do not acquire the selected Remove action's poof
motion or a new haptic. Recorder capture cancellation still discards only an
unfinished preview, not a completed saved chord.

Bounded REA carves and annotated original instructions establish this chain;
recovered pseudocode is not original source. Focused checks cover actual AppKit
menus/native command queries, durable reload, multi-owner conflict removal,
old-token refusal, failed writes, native focus and warning geometry, OS record
translation, original-window reset and Essentials live projection. The actual
inert production component is inspected with disposable bindings and a supplied


### Native Shortcuts search header

medium magnifying glass, Gray9 ink and the feature/shortcut placeholder; its
native field is framed to 24 points with no focus ring. The actual factory
removes the border/background and retains single-line native editing. The
provides white in light appearance and white at 0.1 opacity in dark appearance;
the containing list has continuous radius 8 and a one-point Gray7 border.
an early-cached semantic color from another appearance.

Parc uses that native field and a separate clear button. Selection, marked
text and Undo stay with its original AppKit field editor. A deliberate clear
replaces text through that editor while preserving its focus; a delayed action
cannot mutate a detached, hidden, non-key or sheet-covered owner. Filtering,
selected-command state and saved bindings keep their existing owners. Header
layout and appearance changes do not assign the input or select another row.

structure and focus retention after clearing. An inert native Parc component
confirms the real text field, clear button, query/result update and retained
caret. Focused native checks cover selection, IME, refusal after owner loss and
actual light/dark drawing at the window's backing scale. No browser action or
personal shortcut is exercised. This closes the concrete search alignment and
focus-ring mismatch; the composition delivery below completes its group/banner,
clear hover-opacity and native-context work. The SwiftUI-to-AppKit layout
adaptation is explicit. Original 1.122.0 producer
REA evidence is `ev_7d6a9e07b0ee20e15d2501fcabc88c8450105f546acbbda7a5a9a3caa787f55c`.


### Shortcuts Settings composition

The Basics callout uses the actual `PreferencesFeature.CalloutWithButton`
16-point horizontal padding, continuous radius 6 and two black shadows
(0.15/radius 2/y 1 and 0.05/radius 10/y 2). Its real prominent button contains
the 10-point `command.circle.fill` symbol and 13-point label at 0.85 opacity.
1.170's named background asset is white in light appearance and sRGB
101/96/104 in dark appearance. Parc uses those resource values with the actual
SwiftUI button, not a generic full-width AppKit banner.

button, using `xmark.circle.fill` and Gray9. Its opacity starts at zero,
appears at one, changes to 0.3 on hover and returns to one on exit. The original
spring is response 0.28, damping fraction 0.63, blend duration zero. The
retained host removes the subtree when empty or detached; original key-window,
visibility and sheet changes retire hover state. Reduce Motion omits animation.
The action still inserts empty text through the existing native field editor,
so caret, marked-text and Undo ownership remain native. The Basics callback
similarly requires its original visible, key, sheet-free window.

uses ordinary body text, a 200-point maximum title and full-title help. Its
selected original ID receives a 40-point continuous-radius-8 shape: accent at
0.1 opacity, or red at 0.2 for the actual saved-conflict state. Unselected rows
are clear. Parc retains its native table, separators and stable command IDs;
installed appearance supplies the 29-point section row, 10-point initial
section inset and subsequent 48-point command cadence. Native section rows
stay named and nonselectable rather than acquiring command actions. This is
an explicit AppKit representation of the original SwiftUI List, with the
included-command inventory determined by the actual registry and exclusions.

The final actual component comparison exposed a first-selection wrapping
defect in Parc's retained NSTextField detail cells. Measuring the field with
its current preferred wrapping width and `sizeThatFits`, then laying out the
same field, restores complete description and priority-help lines on first
selection and short-to-long transitions. No responder, command or field is
replaced. The regression check compares actual native text drawing on first
selection and reselection while preserving the original editor.

cover the section/selected-row composition, native button roles, clear and
first-selection detail state. No personal binding, priority or Reset action,
browser function or system preference was exercised. The component uses three
disposable commands, so it is not an inventory-completeness claim. Focused
checks pass 39 search/control, 92 detail and 91 recorder assertions; the full
app receives the exact current-source WMO check. KB27 is complete. Press Again,
MRU, global contextual traversal and the remaining command
inventory retain their separate fixed requirements. Bounded REA receipt:
`ev_4d9e105e5d387b77269145c659c163a6bd541224291a974af44c6163a38c279a`.

### Clear Today command and contextual Find boundary

Clear Today is registered in Tabs with Command–Shift–K. The same real command
appears in Shortcuts and command search, including Actions, with its current
binding. It invokes the existing Today clear/retirement transaction. Its receipt
binds the original browser window, native binding, Space and Profile; menu
tracking retains that receipt. Execution consumes it before dismissing an owned
command panel, then rechecks the original context and key window. Sheets,
composition, retirement/transfer and lost owners refuse the request. No later
front window is substituted. Native before-unload, local document save refusal,
Archive persistence and Reopen Closed Tab remain the existing transaction's owners.

A new `clearTodayShortcutDefaults` marker preserves an explicit saved owner of
Command–Shift–K by disabling the new binding in that file. Existing custom or
disabled Clear Today choices and priorities survive. Unassigned files receive
the recovered default; explicit Reset follows the normal visible-conflict policy.
The retained menu item has no explicit priority override, so this addition keeps
the existing Prefer Websites fallback; it does not claim a newly recovered
command-specific priority.

`clearExplore:`, uppercase K plus Command, Type Travel ID `clearUnpinnedTabs`.
`CloseContentAction.didTapClearUnpinnedItems` (tag 7). The primary reducer is
and source. REA evidence `ev_7984ffe473d577728be811523d3f385796ec05831349502768280282e713607b`
current Clear Today label; only the menu was opened and cancelled. No clear or
navigation action was executed, and no menu pixel/chord measurement is claimed.

uses Parc's existing visible-Today policy and does not close manual/archive
eligibility parity; that gap remains with Today/Archive behavior. The Clear
Tab/Clear Tabs Undo recovered above is now registered on the window's Undo, with
This addition changes no background cleanup or automatic archive rule.
The isolated command component covers original-window retirement, reentrant
panel dismissal, native marked text, actual menu/native registration and saved
binding migration; it does not exercise a browser or archive personal tabs.

The adjacent native-text Find investigation is bounded: browser validation at
CommandFTextField and FindInPageView forwarders establish only their show-Find
path. KB04 completes that mapping: the focused original Note handles every
Find item by forwarding tag 1, while browser aliases and an unattributed generic
native-text consumer are absent. See [numbered targets and native-text Find](keyboard-navigation.md#numbered-targets-and-native-text-find--kb04).


## General and Profiles command inventory — SET21

The active General inventory is Replay onboarding, Profile Settings, warn before
quitting, Previews Settings and the genuine system default-browser action; the
its value. The same explicit-save boundary covers Advanced's sidebar width; a
failed save restores the prior control value and reports the failure. Sidebar
drag gestures retain their established debounced last-used-width path. The
recovered warning default is true, with saved user choices preserved.

Profiles retains its independent editing selection, confirmed original-Space
assignment, atomic new-Profile/rename paths, exact native search/suggestion and
download preferences, per-Profile auto-archive policy, typed removal and unused
Profile cleanup. Search Settings and **Your Data and Settings** now expose the
remaining included commands:

| Command | Actual destination | Reuse policy |
|---|---|---|

The selected Profile resolves an actual existing Space, preferring the original
Space when it uses that Profile. A missing, retiring or unassigned Profile
refuses. The originating regular browser owner retains the request even if
another window became frontmost; app-owned Settings from private browsing uses
its existing explicit regular-Profile destination owner. Window closure, native
sheets, transfer/close activity and stale Settings selection refuse. The browser
activates its real window and passes its normal space/navigation admission before
dismissing that window’s Library overlay and selecting or creating the tab. It never takes a tab held by another physical
window or redirects another Settings subpage. A successful command closes
Settings; refusal keeps it open with an actionable error. The existing
Advanced More Settings command continues to preserve any current Settings
subpage instead of resetting it.

case 6, passwords 7, privacy 8, notifications 9 and credit cards 10.
settings/password-manager subpages. Both reference privacy and clear-data rows
send the privacy case; Parc deliberately makes Clear Browsing Data open the
current Chromium confirmation route directly. This is a current-engine
adaptation, with no data erased by the Settings command itself. The retained
installed Profiles image independently supplies the five visible titles and
order; it was inspected without changing reference data.

cloud/sync, telemetry/update services, AI and live integrations. The reference
external **New documents** provider picker is not exposed over Parc's restored
local Notes implementation. `NoteDocumentType` distinguishes `arcNote` from
`webDocument`; `WebDocumentType` carries an external new-document URL and
service-engagement domains. Existing native New Note and New Note in Split View
continue to use the actual local document owner. Reference native-adblock
controls require `nativeAdBlockAvailable` plus their actual backend state; the
retained installed General image contains none. Parc has no such native
capability and adds no inert blocker switch or invented working-looking action.
Ordinary extension management and Chromium privacy/security controls remain
available through their real owners.

SET24 owns the final native command-row appearance, SET25 owns interaction
presentation, and SET26 owns Settings-wide focus/AX/interruption. Their shared
interface is `profilePageButtons`, `profilePageButton(_:)`,
`onProfileSettingsPage` and `permitsProfilePage`; command acceptance, saved state
and browser ownership stay in the SET21 paths. Those separate rows retain their
own completion requirements.

`bash scripts/test-settings-commands.sh` exercises the file-backed production
store and real destination policy: atomic write failure/retry, fresh readback,
original versus independently selected Profile, unused/retiring targets,
credential-detail preservation and wrong/subpage/credential-bearing URL refusal.
The existing inert quit-warning suite exercises the recovered factory default,
explicit saved choice, suppression and future-format preservation. These checks
never create a browser, run Chromium, erase a real profile or change system
preferences. Whole-module compiler receipts and the independent review/publication
record are retained under `work/settings-coordination/set21`.

## Shared pane presentation

The [SET24 presentation contract](settings-presentation.md) records the shared
section colors/geometry, included toolbar order and native asset provenance,
General/Profile control composition, Advanced glyphs and preserved native
selection. Its dedicated native command buttons use the existing selected-Profile
dispatcher and the reviewed Settings hover owner. Completed Icon and Shortcuts
surfaces retain their prior contracts.

## Settings responder ownership and interruption — SET26

The native preference toolbar remains the pane-navigation owner. Its real
selectable items expose the selected pane and use native toolbar keyboard/AX
behavior; selecting the already-visible pane preserves its responder/recorder.
Settings does not intercept typing or invent pane shortcuts. A sheet
disables toolbar actions, and a refused pane change leaves the prior title,
selection and content intact. General/Profiles/Advanced/Links traverse actual
native controls in their visible group order. Labels and table-cell descendants
are not additional key stops; enabled/hidden state and the macOS keyboard
navigation setting still decide native eligibility. Icon's selected radio row
and Shortcuts' search/recorder retain their completed input owners.

Each pane remembers its original weak native responder. Profiles adds the
selected Profile UUID to that context, and text fields retain their native
field-editor selection without copying or rewriting the draft. Returning from
a sheet restores that context after its completion refresh. A deleted original
Profile returns to the surviving profile list. Hidden, disabled, detached,
closed, non-key or inactive owners cannot take focus; a replacement sheet also
blocks queued restoration. Settings never activates another browser or changes
its selected Space to repair a responder. Closing retires bookmarks, recorder,
preview/popover and download/export requests, cancels remaining platform/Links
sheets from the innermost outward, and rejects a delayed create-profile callback
or profile-assignment callback from an earlier presentation. Committed profile removals and approved exports
retain their existing operation lifetimes. Links releases its draft/subscriptions
when its original parent ends the sheet, including parent close.

for `Settings.SettingsWindowController` stores its tab controller;
`Settings.ToolbarItemStyleViewController` builds real labeled/image/target/action
behavior so pane navigation cannot be hidden. These findings came from the
retained component/type/xref indexes and annotated functions; no new decompilation
was required. Explicit weak per-pane bookmarks, grouping-based key chains,
original-context failure fallbacks and cancellation generations are Parc's
AppKit adaptations of the source-owned native surfaces, not recovered custom

The [inert component runner](../tests/SettingsFocus/README.md) uses real AppKit
fields/shared field editors and button actions with simulated availability,
without ordering a window, driving a browser or touching real profiles. It
checks restoration, native field selection, invalid-owner refusal, key links,
disabled dispatch, nested cancellation and toolbar-hide refusal. The unshown
field reports `AXUnknown`, so this establishes configured native labels and
input/lifetime behavior, not VoiceOver or Full Keyboard Access acceptance.

The SET23 sheet controls own their internal confirmation/Retry/Done focus and
announcements; their unchanged native begin/end-sheet callbacks feed this shell.
SET24's native command buttons/switches follow the same geometry-derived chain.
SET27 separately owns card internals: persistent native controls can change
visibility/enabled state, while any added/removed card controls must reconnect
its dedicated personal-name pane’s key chain after layout. Its native sheets use this same original
parent restoration; decorative pointer motion adds no keyboard or AX owner.


## Local personalized card — SET27

The personal-name item is the first Settings page. Its complete local card,
configuration lifetime, name/design controls, native sharing/export, pointer
motion, accessibility and explicit account-free adaptations are documented in
[Local membership card](settings-membership-card.md). General retains its
existing controls. The card restores the included local portion of the former
