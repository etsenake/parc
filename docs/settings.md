# Settings and application preferences

Settings is a native window whose sidebar lists your card, then General,
Spaces, Links, Shortcuts, Icon and Advanced. Back and Forward retrace the pages
you visited, and Spaces drills into an Edit Space page. Each pane retains its
scroll position and responder while owned. Ordinary Settings entry preserves the
selected pane; explicit commands can select Spaces or a particular shortcut.
A pane name saved as Profiles by an earlier version opens Spaces.
[Presentation](settings-presentation.md), [motion](settings-motion.md) and the
[local card](settings-membership-card.md) have focused guides.

## General and Spaces command inventory — SET21

| Pane | Current controls |
|---|---|
| General | Default browser, Warn before quitting, Window frame (Adjust), Previews Settings, Replay onboarding |
| Spaces | Space list (icon and name) and New Space; a Removing old data row while a background removal runs; Edit Space with rename, Share data with, search engine, suggestions and Manage search, download location, Notes folder, Archive tabs after, native data/settings destinations, Clear Browsing Data and Delete Space |
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

## Spaces and original-context ownership

The Spaces pane lists every Space with its icon and name. **New Space…** closes
Settings and then sends the app's New Space action, so the browser window that
becomes frontmost shows the creation form. Choosing a Space saves it as the editing
Space, then opens Edit Space; reopening Settings on Spaces shows the list. The
Auto-Archive education banner opens Edit Space for the Space it was shown in. The
selected pane and editing Space are session fields with backward-compatible optional
decoding. An unavailable selection falls back to the originating Space, then the
first Space. Selection saves atomically before adoption; failure leaves the old
selection.

Edit Space holds:

- **Space Name** with Rename, which follows the Space rename rules: an empty name
  returns to the positional Space N, and a competing rename or a failed write keeps
  the authoritative name.
- **Share data with**, a menu of every other Space plus Keep separate. Checkmarks
  mark the Spaces that already share data with this one. Choosing what the Space
  already has does nothing. Anything else asks the same confirmation as the Space
  menu and moves the Space; see
  [Space management](space-management.md#sharing-data-between-spaces).
- **Search engine**, **Manage search** and **Include search engine suggestions**, and
  **Download location** with Ask every time and Other…, and **Notes folder** with
  Other… and Show in Finder, for this Space's data. A note under them names the
  other Spaces they also apply to.
- **Archive tabs after** for this Space alone, with no all-Spaces question.
- Privacy and Security, Passwords, Credit Cards and Notifications, which open the
  edited Space's browser settings, and **Clear Browsing Data…**.
- **Delete Space…**, the same flow as the Space menu (see
  [Delete Space](space-management.md#delete-space)); the last Space cannot be
  deleted. The confirmation appears over Settings, then the browser window comes
  forward for the retirement.

While old data is being deleted in the background after a share, Keep separate or
Space deletion, the Spaces pane shows **Removing old data…**. If it stops, the row
offers **Retry**, and a failure is reported once in a Parc dialog. Closing Settings
never cancels the removal.

### Background data removal

Data left without a Space is removed through `ProfileRemovalController`. Before
native preparation, the store atomically records the operation, picks a surviving
data set that still has a Space (the default first, then the active Space's), and moves
the default and Settings selection to it when they pointed at the removed one.
Pending data cannot be renamed or assigned, and its native preference controls stop
requesting the retiring context.

The native lease binds the removed and the recorded survivor's storage paths
and the operation identity; preparation and restart recovery pass the same
survivor path, because the native journal stores it. Its
last revalidation checks the current name and absence of assigned Spaces.
Only a native `removed` receipt permits metadata deletion. `failed` releases an
operation only before irreversible cleanup; `pending` retains it for retry.
Committed cleanup and restart recovery outlive the sheet. A failed final metadata
write preserves the operation so retry can consume the same native receipt.

Completion removes the data's tabs, local history, download records and related
selection/split references, then selects the survivor. It preserves other data sets,
downloaded files, routing destination UUIDs and app-global Easels. See
[removal presentation and recovery](settings-profile-removal.md).

Bulk cleanup of several unused data sets shares one survivor and fixes the set up
front; later-created ones are not added. Settings has no bulk entry point.

## Search and downloads

The search engine, search suggestions and download location (including Ask every
time) belong to a Space's data, not to the app. They live in Edit Space under
**Search** and **Downloads** and read and write that Space's own engine settings
directly, so another Space on separate data keeps its own. When other Spaces share
the data, one small note under the rows reads "Also applies to <Space names>." The
rows load when Edit Space opens and reload when its Space changes, when a Space's
search preferences change and when the window becomes key. An old settings file that
still carries the retired app-wide key loads normally and ignores it.

The **Search engine** menu lists Chromium's built-in search engines, any an
organization recommends and the current default; an engine an organization
enforces is the only row. Site searches such as YouTube or GitHub, and shortcuts
Chromium learned from visited sites, stay out because each searches one site; see
[site searches](command-bar-scopes.md#space-entry-and-profile-catalog). Manage search can
still make a hand-added engine such as Kagi or a learned shortcut the default, and
the menu shows it as the current default. Parc's catalog site searches are never
the default: a Space whose default is one of them, including one just picked in
Manage search, goes back to Google, Parc's normal default, without asking. Engines
that share a name each keep their own row.

Values an organization or extension controls cannot be changed and say so in the
control's tooltip or the Downloads note. **Manage search** opens the search
shortcuts page for the edited Space; custom shortcuts remain that Space's data. The
location picker offers its folder, Other… and Ask every time. Choosing Other… sets
the folder, then turns prompting off. Managed values disable the picker. Callbacks
validate window and preference identity, and leaving Spaces or closing Settings
cancels an open folder panel. See [downloads](download-library.md).

**Notes folder** sits under its own **Notes** heading after Downloads, with the same
picker look: the folder with its Finder icon, Other… (a folder sheet that can make a
new folder) and Show in Finder, which creates the folder first if it isn't there yet.
The line under it reads "New notes land here. Notes saved anywhere else still open
fine." `NoteFolderPreferences` keeps the choice per Space data in user defaults, with
Documents/Parc Notes as the default, and forgets it when that data is removed.
Changing it only moves where new notes go and what Library lists; existing notes stay
put and keep opening from wherever they are.

Automatic archive is a per-Space interval saved when chosen. Education is consumed
by actual automatic archival; its Settings link opens Edit Space for the original
Space. See [archive](archive.md).

| Space action | Native destination | Reuse policy |
|---|---|---|
| Manage search | `parc://settings/searchEngines` | Exact subpage |
| Privacy and Security | `parc://settings/privacy` | Exact subpage |
| Passwords | `parc://password-manager/passwords` | Keep existing credential detail/authentication |
| Credit Cards | `parc://settings/payments` | Exact subpage |
| Notifications | `parc://settings/content/notifications` | Exact subpage |
| Clear Browsing Data | `parc://settings/clearBrowserData` | Exact dialog; opening erases nothing |

Each Edit Space action acts on the edited Space. Missing or retiring Spaces refuse. The original
Settings/browser owner remains the destination when another window becomes
frontmost. Normal security, close/transfer and sheet gates still apply. Success
closes Settings; refusal leaves it open with feedback.

There is no translated-site reset, AI/cloud account control, native blocker
placeholder or external New Documents provider picker. Local Notes, extensions
and native security controls remain.

## More Settings

Advanced's **More Settings…** opens Chromium's own Settings page and can reuse
any existing Settings subpage in that Space without resetting it. Neither route
takes a tab from a different physical window.

The page hides what does nothing in Parc, misleads, contradicts Parc's own
controls or needs Google. `Engine/ParcChromium/parc_settings_page.cc` holds three
lists: Chromium's own section and row hide list, Chromium's per-row switches, and
Parc's rows by name, each a page element with selectors for the rows it hides. A
Parc subclass of Settings' registration adds them to the page's load-time data
right after Chromium builds the page, before its frame exists; a guest profile
keeps Chromium's own section list. The `native-settings-visibility` patch reads
them: each settings section and subpage hides its page's named rows as it
appears, search skips them, and the page's home falls back to Your saved info
while You and Google is hidden. Two startup feature defaults turn off what kept
the AI page ([engine policy](engine-flags.md#runtime-features)).

- **Hidden:** You and Google (profile, Sync and Google services with Make
  searches and browsing better, Import bookmarks); On startup (Parc resets it on
  every profile load; Restore previous windows is the control); the AI page;
  Privacy Guide and its promo card; the sign-in promo and Allow sign-in toggle;
  Autocomplete searches and URLs (each Space's suggestions switch is the
  control); enhanced Safe Browsing unless it's the current choice, extended
  reporting and the Advanced Protection Program link; Appearance's theme, home
  button, bookmarks bar, Mode, Customize toolbar, tab strip position, glass,
  Ctrl+Tab order, tab scroll buttons, everything menu, organizer button, tab
  group, hover card and side panel rows, split view and Warn before quitting
  (General has Parc's own);
  Performance's alerts, inactive tab appearance and hover card link; the Google
  Translate card and its translation note under each language; Show downloads
  when finished; Google Wallet, Google Account, Google Pay, card benefits, pay
  over time and Wallet shopping and pass detection; the Autofill settings card
  (enhanced autofill), identity documents and travel, which need a Google account;
  autofill's Gemini suggestions; Offer writing help; System's Relaunch button;
  Safety Hub's version card; About's update status (Parc updates through
  Sparkle); Accessibility's copy confirmations (Chromium's toasts never show in
  Parc), Google image descriptions and Live Caption with its Live Translate
  (signed Parc can't load the speech library Chromium downloads for it); and the
  Reset dialog's report checkbox.
- **Kept**, because they work: privacy, cookies, security, Standard and No
  protection, HTTPS-First, Secure DNS, certificates, site settings, passwords,
  addresses, local cards and their device-lock check, languages and spell check,
  Memory Saver, Energy Saver, preloading, hardware acceleration, proxy, fonts,
  page zoom, Tab highlights links, delete browsing data, Reset settings,
  extensions, Safety Hub, and the search engine, default browser and download
  location rows, which stay in sync with Parc's own.
- **Still shown:** the Related Google services heading above the local Password
  Manager, and the identity documents and travel pages, which only a typed
  address reaches; search skips them.

Reset settings never sends Chromium's settings report to Google: the dialog's
checkbox starts unticked and hidden, and Parc's Settings controller turns the
report choice off before Chromium's reset handler sees it. Parc's browser client
also sets Chromium's brand override to no brand at startup, so Chromium never
reads Google Chrome's brand files: opening Settings never fetches a Chrome
partner's reset defaults from Google, and component updates and RLZ carry no
brand. RLZ, Chromium's install-tracking store, lives in Parc's own data folder,
so Parc never reads or writes the one Google Chrome shares. With no brand and an
empty store,
a visit to Google's home page carries no RLZ header and Parc sends no RLZ ping.
Protected video's device ID doesn't use the store and is unchanged.

Someone who chose enhanced Safe Browsing keeps it, shown and selected. The patch
ties the row's visibility to the Safe Browsing choice, so it disappears once they
pick Standard or No protection; nothing changes their protection for them.

Every Parc link into the page (Privacy and Security, Credit Cards,
Notifications, Manage search, Clear Browsing Data, site and pop-up settings, More
Settings itself and download warnings' Safe Browsing link, which opens Security)
lands on a section that stays. The engine build runs `settings_page_contract.py`,
which stops by name if Chromium renames or drops a key, switch, feature, named row
or its page, a hook point, the home fallback, the reset handler's report choice,
the Enhanced row's binding, the brand override, or RLZ's store-folder override,
empty-header rule and ping gate;
`tests/EngineSource/test_settings_page.py` checks the lists and the guard.

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
Space or the most recent Space overall; the menu lists Spaces by name. A rule stored
with a Profile destination shows as the first Space that uses it. A separate
mini browser window is not a destination; the default is Most Recent Space.

`LinkRoutingStore` atomically stores `link-routing.json`. The editor has no Save
button: it saves each change as it happens, whether that's choosing a matching
style or destination, adding, removing or reordering a route, or leaving a
pattern's text field. A field still being typed in keeps its last saved pattern
until editing ends, so half-typed text never routes links; closing the editor
ends editing and saves. Empty conditions are left out, a route with no filled
condition is not saved, and unchanged edits do not write. Unreadable data is
preserved until explicit Reset Routes. Write failure or a concurrent update
keeps the unsaved edits with an explicit Discard Changes, never overwriting the
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

The sidebar owns pane navigation and cannot be collapsed; the toolbar holds Back,
Forward and the title and cannot be hidden. Selecting the same pane preserves its
responder, and choosing a page from the sidebar keeps focus there. A sheet
disables Back and Forward; refused changes leave the old pane and sidebar
selection intact. Controls follow their visible group order and native
keyboard eligibility; labels are not extra key stops.

Each pane remembers a weak original responder; Spaces includes its UUID and
text fields retain their native selection. Sheet return restores only the same
eligible context. Removed Spaces return to the list. Hidden, disabled, detached,
closed, non-key or inactive owners cannot steal focus. Closing cancels unanswered
panels, input/preview subscriptions and old callbacks; approved exports and
committed removals keep their established operation lifetimes.

## Focused checks

Existing checks include `ProfileSettingsTests` (Swift package), `test-quit-warning.sh`,
`DefaultBrowserTests`, shortcut component scripts, `tests/WebsiteTheme`,
`SettingsFocusTests`, and the file-backed store/controller suites. Follow
[AGENTS.md](../AGENTS.md) before running them. Background-removal fixtures use native
boundary doubles and disposable stores. Concrete routing work belongs in the
[routing guide](routing-interaction.md) and [backlog](backlog.md).
