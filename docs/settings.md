# Settings and application preferences

Settings is a native window with a personal-name card pane followed by General,
Profiles, Links, Shortcuts, Icon and Advanced. Each pane retains its scroll
position and responder while owned. Ordinary Settings entry preserves the
selected pane; explicit commands can select Profiles or a particular shortcut.
[Presentation](settings-presentation.md), [motion](settings-motion.md) and the
[local card](settings-membership-card.md) have focused guides.

## General and Profiles command inventory — SET21

| Pane | Current controls |
|---|---|
| General | Default browser, Warn before quitting, Previews Settings, Profile Settings, Replay onboarding |
| Profiles | Create, rename, assign and remove Profiles; search/suggestions; downloads; automatic archive; native data/settings destinations |
| Links | Ordered Air Traffic Control rules |
| Shortcuts | Search, bindings, priority, conflict resolution and Reset All |
| Icon | Available application icons |
| Advanced | Restore previous windows, sidebar width, webpage window dragging, interface sounds, reorder haptics, Shared Quotes, website theme data, More Settings and Export Data |

**Replay onboarding is a protected Parc addition.** Settings → General is its
only entry point. It uses full production setup, preserves existing browsing
state, and applies explicitly chosen changes. See [onboarding](onboarding.md).

Restore-session and explicit sidebar-width changes save before publishing their
values; failure restores the previous controls and reports the error. Sidebar
drag gestures keep their separate debounced width persistence.

About Parc shows the running app version/build, the packaged full Chromium tag,
the installed system WebKit build, and WebKit/AVFoundation media information.
It refreshes the icon on opening and labels missing development metadata rather
than guessing. Project/source links refer to the actual components.

## Profiles and original-context ownership

Selecting a Profile for editing does not reassign a Space. **Use for this Space**
uses the explicit, always-confirmed reassignment transaction for the originating
Space. New Profile follows its create-and-assign flow; app-owned Settings with
no regular Space can create an unassigned Profile. See
[Space management](space-management.md#profile-assignment-dependency).

The selected pane and editing Profile are session fields with backward-compatible
optional decoding. An unavailable saved selection falls back to the originating
Space's Profile, then the first available Profile. Selection saves atomically
before adoption; failure leaves the old selection.

Rename retains UUID, native storage path and all references. It trims outer
whitespace, rejects empty names and compares the original name before commit,
preventing a concurrent rename from being overwritten. Return saves; Escape,
window closure or Profile loss cancels. Failed writes preserve the draft.

### Profile removal

Only nondefault Profiles with no assigned Spaces can be deleted. The default
Profile is identified by immutable UUID, not its editable name. The confirmation
shows the original Profile's saved-tab/history counts and explains permanent
browser-data removal in a standard Delete/Cancel dialog; no name is typed.
Downloaded files and app-global Easel documents remain.

`ProfileRemovalController` owns the process-wide operation; Settings owns only
its confirmation. Before native preparation, the store atomically records operation and
Profile UUIDs. Pending Profiles cannot be renamed or assigned, and their native
preference controls stop requesting the retiring context.

The native lease binds exact storage/default paths and operation identity. Its
last revalidation checks the current Profile/name and absence of assigned Spaces.
Only a native `removed` receipt permits metadata deletion. `failed` releases an
operation only before irreversible cleanup; `pending` retains it for retry.
Committed cleanup and restart recovery outlive the sheet. A failed final metadata
write preserves the operation so retry can consume the same native receipt.

Completion removes the selected Profile's tabs, local history, download records
and related selection/split references, then selects Default. It preserves other
Profiles, downloaded files, routing destination UUIDs and app-global Easels.
See [removal presentation and recovery](settings-profile-removal.md).

### Unused-profile cleanup

Bulk cleanup fixes a UUID/name set of eligible nondefault, unassigned Profiles.
Later-created Profiles are not added, and a changed name, assignment or failed
durable save rejects new authorization. Settings has no bulk entry point yet.

All new operation records stage atomically, then each Profile uses the same
native removal/recovery transaction. Results stay per Profile: one failure does
not hide or undo another success. Retry reuses operation IDs and skips completed
members.

## Profile search and navigation

Profiles reads the native search engine list/default and suggestions preference.
Snapshots bind the weak Profile, revision, real search GUIDs and managed/extension
control state. Mutations revalidate, save through the native preference owner,
and refresh from its observer. No parallel Profile manager is created.

Downloads uses the selected Profile's real native preferences. The location
picker offers its folder, Other… and Ask every time. Choosing Other… sets the
folder, then turns prompting off. Managed values disable the picker. Changing
selection/removing a Profile cancels the original folder panel; callbacks validate
window, Profile and preference identity. Unavailable contexts show an explanation.
See [downloads](download-library.md).

Automatic archive retains its per-Profile policy, application-to-all-Profile
scope and new-Profile default. Education is consumed by actual automatic archival;
its Settings link selects the original Profile. See [archive](archive.md).

| Profile action | Native destination | Reuse policy |
|---|---|---|
| Privacy and Security | `parc://settings/privacy` | Exact subpage |
| Passwords | `parc://password-manager/passwords` | Keep existing credential detail/authentication |
| Credit Cards | `parc://settings/payments` | Exact subpage |
| Notifications | `parc://settings/content/notifications` | Exact subpage |
| Clear Browsing Data | `parc://settings/clearBrowserData` | Exact dialog; opening erases nothing |

Each action resolves an existing Space in the selected Profile, preferring the
originating Space. Missing, retiring or unassigned Profiles refuse. The original
Settings/browser owner remains the destination when another window becomes
frontmost. Normal security, close/transfer and sheet gates still apply. Success
closes Settings; refusal leaves it open with feedback.

Advanced's **More Settings…** opens the genuine engine Settings page and can reuse
any existing Settings subpage in that Space without resetting it. Neither route
takes a tab from a different physical window. There is no translated-site reset,
AI/cloud account control, native blocker placeholder or external New Documents
provider picker. Local Notes, extensions and native security controls remain.

## Application Settings from Incognito

Private-window Settings belongs to the application and uses the actual regular
BrowserStore and explicit normal parent Profile. It survives closure of that
private window. Private tabs/history/session remain memory-only. No private
Space is offered for assignment; replay uses a real normal Space of the parent.

Native page actions revalidate that normal destination and reuse/create a regular
browser only when requested. A missing/retiring Profile or unavailable owner
refuses; the private UUID never becomes a persistent Profile. New Window from a
private browser similarly uses its real regular parent and opens the new window's
command bar, while startup restoration keeps its own page/launch focus policy.

## Links and Air Traffic Control

The ordered routing editor and native request routes are documented in
[routing interaction](routing-interaction.md) and [private routing](private-route-lifecycle.md).
The first matching rule wins; all its conditions must match. Destinations are a
Space, a Profile's most recent Space, or the most recent Space overall. Little

`LinkRoutingStore` atomically stores `link-routing.json`. The editor owns a draft,
saves on close, omits incomplete conditions and does not write unchanged sessions.
Unreadable data is preserved until explicit Reset Routes. Write failure or a
concurrent update retains the draft with explicit discard, never overwriting the
newer rules. Missing destinations retain their UUIDs and fallback policy.

### Internal original-request routing

External app-open URLs resolve an eligible regular window/Space and open directly;
startup and replay queues use the same path. Native page requests retain their
request, source document, opener, profile, POST/referrer and callback ownership.
Existing WebContents never change BrowserContext and are not replaced with a
URL-only recreation to satisfy a rule.

Matched new pages can adopt another Space in the same Profile through a one-use
lease revalidated at first shell adoption. Changed source/rules/destination fall
back to the same ordinary page. Existing Peek precedence remains. Cross-Profile
routing of an already-created page is not supported; it is an explicit excluded
requirement, not permission to discard opener/security semantics.

<a id="internal-current-tab-routing"></a>

Current-tab routing uses the original-request owner and its document/security
lease. The routing guides describe authentication continuation and private-link
ownership. Do not derive browser request behavior from the external URL entry
point.

## Shortcuts

Shortcuts edits the real registry used by menus, the command bar and browser
priority arbitration. It exposes registered actions only. Assignment changes,
explicit removal and Reset All use the existing atomic store; errors do not
silently replace the last saved value. Existing custom and unknown saved records
survive compatible migrations.

The recorder owns first responder, current keyboard-layout translation and the
pending chord. Escape cancels unfinished input; forbidden editing chords beep.
Focus loss, hiding, disabling, detachment or window resignation ends capture and
its passive halo. Modifier previews update detail keycaps without saving or
rebuilding the selected row.

### Context exceptions — KB17

Bindings select Prefer Parc, Prefer Websites or Use Both. Native text fields use
ordinary AppKit menu order. Renderer arbitration requires the selected browser
page and its key window; editable webpage content uses the same binding priority.
Reserved editing characters continue to the page. Separate DevTools windows and
non-browser windows have their own native paths.

Chromium owns actually locked keys. Otherwise eligible unlocked keys retain their
configured priority even when another key is locked. Escape exclusive-access,
Peek and window-Undo gates remain intact. A consumed Use Both Exit chord queues
no action while a modal is presented or fullscreen is outside its settled state.

### Saved conflicts, system warnings and reset

Duplicate chords are saved as conflicts and remain inactive until one owner
remains. The red conflict control scrolls to the other owner without changing
query, selection or first responder. Removing other assignments is explicit;
stale context/menu tokens refuse. Enabled macOS symbolic shortcuts produce an
advisory warning only; Parc reads them without modifying system shortcuts.
Reset All acts immediately without a confirmation sheet, but its atomic save can
fail truthfully. Detailed behavior is in [keyboard navigation](keyboard-navigation.md).

### Press Again presentation and original-window lifetime

Use Both retains the five-second, hover-aware native queue and exact document,
Profile, binding and security ownership. The shared [toast](toasts.md) presenter
shows a non-key child attached to the originating window without stealing the
renderer/editor responder. Edit the shortcut appears after 0.5 seconds and opens
that exact command in Settings without starting recording.

Dismissal revokes command identity and input synchronously; passive exit cannot
remove a replacement cue. Key loss, sheets, closure, hidden/detached ownership
retire it immediately. Scroll/vertical dismissal consumes the queue without
running a browser command. Another toast replaces it.

### Essentials education window

Essentials retains its original browser and reads current live bindings. Missing
bindings remove their rows. New Tab, Recent Tab, Copy URL and Split dispatch
through that exact owner; View All opens its Shortcuts pane. Retired or hidden
owners cannot fall through to another browser. Plain URL copy uses the original
page's native clipboard/security lease, including when education is key.

### Shared shortcut keycaps

Education, command results, menu helpers and Settings use the shared binding
projection and keycap renderer. Disabled/conflicted bindings cannot advertise an
active shortcut. Detail keycaps update during recording without replacing input.

### Shortcuts Settings composition

Search, selected row, detail column, recorder and priority controls retain their
own focus. Native key-view traversal follows visible enabled controls. Row
selection and search must not cancel a valid owner by rebuilding unrelated views.
Long custom chords fit within the recorder's measured text bounds.

## App icon

The Icon pane selects an available bundled icon through the native application
icon owner. The running app/Dock image and Finder icon update under validated
ownership; the Dock plugin restores the persisted icon when the app is closed.
Its atomic shared preference is separate from disposable test-profile choices.
The main/Alerts helper bundle icon stays the approved Original `Parc.icns`.
See [availability](app-icon-availability.md), [picker](app-icon-picker.md) and
[fixed UI marks](app-icon-marks.md).

## Ordinary Toolbar appearance

Address presentation formats display text only. Copy, navigation, accessibility
and document identity retain the complete native URL. Pane title/control geometry
is owned by [split groups](split-groups.md#original-pane-title-presentation),
with per-window appearance in [window appearance](window-appearance.md).

## Warn before quitting

The application-wide default is enabled, preserving explicit saved choices.
Quit presents **Quit Parc?** on the eligible key/main/ordered browser owner.
Cancel changes no close state. Quit continues Notes saving and aggregate native
close consent. **Quit, and don't ask again** saves suppression first; a page
refusing close does not reverse that preference. A second Quit dismisses the
warning and follows ordinary termination. Approval is once-only.

## General preview preferences

Previews Settings controls folders, recent pages on supported sites, and **A
picture of other open tabs**. All three default on. Each checkbox saves and
refreshes previews immediately across existing windows; Done/Return closes the
original-window-owned sheet. Sidebar/Site Control Center preview actions share
the same values. Retired sheet callbacks cannot mutate later controls.
See [sidebar previews](sidebar-previews.md).

## Default browser

Make Default and the app-menu action share one application-owned controller.
It passes the running bundle URL to macOS for HTTP, then HTTPS on success. A
failed/canceled first request stops the sequence. Duplicate prompts and stale
callbacks are rejected. Closing Settings does not discard an accepted operation.
Status reads actual ownership of both schemes and compares bundle URLs, so a
same-named development copy cannot count as the running app. Activation refreshes
status without polling or navigating.

## Interface sound and reordering feedback

The application-wide sound and reorder-haptic preferences default on. Malformed
or future records are preserved and disable their controls/consumers. Native
capture plays its bundled sound at volume 0.7 only after successful acquisition,
while active and enabled. Cancel, crop, framing and output reuse do not play it.
Onboarding music, page audio and error beeps are separate owners.

Sidebar reorder feedback emits generic native haptics for accepted insertion
index changes. Repeated equal indices are deduplicated; disabled output retains
the latest index. Menus, accessibility moves and unrelated split gestures do not
manufacture reorder events. See [Settings motion](settings-motion.md).

## Webpage window dragging

The application-wide preference enables eligible arrow-cursor drags from the top
of a webpage with no modifiers or Option alone. `WebpageWindowGrabber` preserves
the original mouseDown and passes the original drag event to `NSWindow.performDrag`.
It never fabricates a click or moves a renderer. Native security, document,
geometry and ownership loss cancel the sequence. Peek, fullscreen, capture,
popup chrome, blank/local pages and infobar space are excluded from admission.

## Shared Quote affordance

The preference controls the selection-driven sidebar Share Quote affordance;
Edit → Copy URL as Quote remains available when it is off. `SharedQuoteSession`
owns gesture/release tracking and a 200 ms debounce. The displayed token binds
the actual document, window and selection; text remains native. Revocation on
navigation, selection, focus or visibility prevents stale copying. The native
text-fragment generator and enterprise clipboard policy remain authoritative.

## Website theme data

The application-wide preference defaults on, including private windows. Each
window publishes its actual Space palette and background through twelve existing
`--arc-palette-*` compatibility variables, under owned key `__parc_theme_css`.
No browsing history, account identity or theme image is sent to a service.

Saving precedes delivery. Theme preview, appearance and attachment changes
republish to the actual pages. Renderer document and attachment tokens reject
late former-window writes/removals; navigation/restoration uses the current theme
without waking cached documents. Opt-out removes only Parc's style, preserving
page-authored CSS. Invalid/future preferences withhold sharing without destroying
the saved record. [Theme rendering](space-theme-rendering.md) owns the palette.

## Local browser data export

Export Data captures the normal-store snapshot before its save sheet opens,
then writes `Parc Data Export.md` atomically off the main thread. It includes
ordered Spaces, Profile Favorites, pinned/Today saved URLs and folder hierarchy.
Split children retain their order; saved destinations are not replaced with live
navigation or custom labels. Archived tabs and local Notes/Easels are excluded
from this link export; Notes has its own export. Cancel writes nothing; an
approved write survives Settings closure and reports actual errors.

## Settings responder ownership and interruption — SET26

The native toolbar owns pane navigation and cannot be hidden. Selecting the same
pane preserves its responder. A sheet disables toolbar actions; refused changes
leave the old pane intact. Controls follow their visible group order and native
keyboard eligibility; labels are not extra key stops.

Each pane remembers a weak original responder; Profiles includes its UUID and
text fields retain their native selection. Sheet return restores only the same
eligible context. Removed Profiles return to the list. Hidden, disabled, detached,
closed, non-key or inactive owners cannot steal focus. Closing cancels unanswered
panels, input/preview subscriptions and old callbacks; approved exports and
committed removals keep their established operation lifetimes.

## Focused checks

Existing checks include `test-settings-commands.sh`, `test-quit-warning.sh`,
`test-default-browser.sh`, shortcut component scripts, `tests/WebsiteTheme`,
`tests/SettingsFocus`, and the file-backed store/controller suites. Follow
[AGENTS.md](../AGENTS.md) before running them. Profile-removal fixtures use native
boundary doubles and disposable stores. Concrete routing work belongs in the
[routing guide](routing-interaction.md) and [backlog](backlog.md).
