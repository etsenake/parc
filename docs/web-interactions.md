# Web interactions

Native page surfaces use the original Chromium page, document, Profile and
request lifetime. The app owns presentation and local product choices; native
security decisions and callbacks remain authoritative. This guide describes
current source behavior. The [product guide](product.md) keeps product decisions
and scope; [the backlog](backlog.md) carries unfinished work.

## Site Control Center — WEB14

`Sources/Parc/SiteControlCenter.swift` and its browser-window presenter own one
card used by the sidebar URL bar, toolbar, split-pane bars, popup chrome,
Developer Mode and the hidden Command–E extension picker. Pinned extension
strips remain separate controls. A committed navigation/document change closes
the original card.

The card uses the Space's colors and the shared menu chrome: 12-point corners,
8-point insets, 48 × 32 tiles with 8-point spacing and a 232-point total width.
Settings rows have no resting plate. Section headings use plain black or white
for contrast, including hover. Full-strength glyphs and shared tooltips preserve
live shortcuts and accessibility help. This is Parc's own presentation choice.

### Page actions and settings

- Share uses the real page URL and native sharing picker.
- **Blocked** lists the page's blocked pop-ups and redirects with Open, Open All
  and Always Allow; see [blocked pop-ups](#banners-and-blocked-pop-ups).
- Visible Area, Portion and Full Page enter the shared capture editor, with
  optional Portrait framing. Without capture, the Share/Copy URL pair remains.
- Extensions use actual toolbar-action leases for run, pin and menu commands.
  Manage Extensions, Add Extension and site settings open their real destinations.
- Developer Mode and Preview use existing preferences. Developer Mode can toggle
  while the card is open; capture and Clear Cache retain their admitted owner
  through dismissal. See [Developer Mode](developer-mode.md).
- Secure HTTP(S) permissions come from the genuine headless PageInfo session in
  `Engine/ParcNative/native_page_info.mm`. Changes go through its presenter and
  `OnUIClosing` lifecycle, including reload consequences.
- When a site's location, camera, microphone, notifications or clipboard access
  is allowed but macOS blocks it for Parc, its row reads **Off in macOS** with a
  **Settings** capsule for that System Settings pane; the row still toggles the
  site. The card rechecks macOS as it opens and when Parc becomes active. The
  security popover adds **Open System Settings…**; Settings' site pages update
  their macOS warning live (Chromium words it only for location, camera, mic).
- Automatic Picture-in-Picture uses PageInfo's item or the Profile's real content
  setting, with ASK treated as on. Managed/compound permissions display without
  exposing an unsupported toggle.
- Clear Cache and Clear Cookies use existing page tools and are disabled off
  HTTP(S). Security opens the visible entry's actual certificate viewer when a
  certificate exists.

Boosts and their controls are excluded. Parc has no built-in content blocker, so
it does not expose a fake Content Blockers toggle. The Preview switch uses the
single recent-pages preference for supported providers. Picture-in-Picture stays
an implemented feature; this card does not redefine its ownership.

The footer hides on `chrome://` and `parc://` pages. Extension, file and other
non-secure pages can show an Insecure footer without a certificate action.
Developer Mode keys committed web hosts or extension IDs; hostless/internal
pages omit it. PageInfo is admitted only for visible committed HTTP(S) pages:
WebUI, DevTools, view-source, extension, about/data/blob and unsupported schemes
cannot be passed to Chromium's ordinary PageInfo session. The card can still
show non-PageInfo actions there.

### Anchoring, detach and dismissal

The attached child card centers on its button and stays within the part of the
window on that display. It flips above if necessary, then falls back to screen
space; growing content recomputes placement. Its tail follows the button.
Private windows retain their dark appearance. Hosted buttons have native
keyboard focus and the card announces its popover role.

Escape, navigation, document retirement, parent close/minimize, sheets,
deactivation, resize and lost key ownership close an attached card. A closing
press on the entry button does not immediately reopen it. Sidebar hiding closes
a card anchored to its URL pill. Deferred shows carry tokens so an older request
cannot reopen a dismissed surface.

Dragging the background detaches the card, removes its tail/parent link and adds
a window shadow. It then survives outside clicks, resize and deactivation.
Escape, its owner closing/minimizing, a sheet, navigation, changed Space/Profile
or its entry button still close it. A detached card has no close button. It no
longer holds sidebar controls revealed or defers the owner's other surfaces.

Actions that require the browser key run after dismissal and revalidate the
original page, document, window, Space and Profile. A stale action cannot use a
replacement page. Secondary click/Control-click/VoiceOver Show Menu on an entry
button opens Parc's existing page menu.

### Extension menus

An extension tile's context menu keeps the card open and draws the engine's
built menu in the Space's colors. It hangs beside the card aligned to the tile;
the tile stays lit. Pinned sidebar/toolbar buttons use the same themed menu and
leave an open card open. Open or Close Side Panel is the exception: choosing it
closes the card before the engine toggles the panel. A disabled row's
engine-supplied reason appears in the tooltip and accessibility help.

Placement considers the entire submenu chain and available window/screen space,
opening left when the chain cannot fit right. Native-style event tracking keeps
arrows, Return, Escape, outside dismissal and pointer submenu traversal together.
The selected item runs after menu close, inside the engine's synchronous show,
so its original model lease remains valid. Card or engine cancellation cancels
the menu. Older engines without the presenter hook use their native menu without
closing the card; this is compatibility behavior, not a pending current overlay.

Badges keep the extension's own colors at the icon's top right, clear of the
bottom-right pin badge. The extension's 32-point image canvas contains its
16-point action icon and is not incorrectly squeezed to half size. Pin/unpin,
picker movement and release-to-select use their existing extension owners; see
[extension interaction](extensions-interaction.md).

## Dialogs, authentication, certificates and permissions — WEB15

These are page-bound native presentations. No request may be reattached to an
unrelated page or answered after its original owner retires.

| Surface | Behavior and owner |
| --- | --- |
| JavaScript alert/confirm/prompt | Parc dialog sheet with Chromium's origin-aware title, OK/Cancel and a rounded prompt field |
| Before unload | Original close/reload consent; OK leaves, Cancel stays; no suppression checkbox |
| HTTP authentication | Page-owned Parc dialog, original authority/trust text, labelled rounded username/secure password fields and Cancel/Sign in |
| External protocol | Origin/application-aware Parc dialog with the app's icon, Open, policy-eligible Always open and Cancel |
| Site permission | Original request popover anchored to that page's controls, with Not Now/Allow |
| Server certificate | Chromium's certificate viewer sheet for the visible certificate; while Developer Tools are open on the page (or in their own window), any certificate the Security or Network panel asks for |
| Client certificate | Genuine Chromium `SSLClientCertificateSelector` |
| Screen/window/tab sharing | Genuine Chromium/system picker, attached to the sharing page and holding the window's security reservation while it shows |

Page dialogs use the engine's shared Parc dialog (`dialog_style.mm`): Parc's
mark, the bold title, the page's text (scrolling when very long), key-badged
**Cancel** (Escape) and **OK** (Return or keypad Enter). A prompt's field is
the app dialog's tinted rounded card ([dialogs](dialogs.md)): 16 points below
the text, 36 points tall with 12-point padding and no focus ring. OK stays inert for
half a second after the sheet appears, and a held Return or one pressed before
then never accepts, so a page cannot time a dialog under a keystroke. An input
method composing in the field keeps Return and Escape. A plain alert still has
only OK and ignores Escape.

The notifications-permission sheet (**Open System Preferences**, or **Never
Mind** with Escape) uses the same dialog. So do the browser's decision sheets
for active downloads, caret browsing and private-window data, where the
Return button carries the primary face.

JavaScript prompts offer **Don't show this again** from the sixth page dialog.
Suppression returns the native cancellation result; primary-page change resets
count and block. Programmatic handling does not pretend the checkbox was shown.
Inherited frame origins remain part of the dialog title. Beforeunload retains
whole-window/tab consent rather than using ordinary alert suppression.

The resource-bundle delegate supplies Parc’s version-page title, licence links
and logo text. A Parc WebUI configuration serves the licence page, which
remains available to internal-address completion through the retained host list.
Chromium’s pages show Parc’s mark in both appearances; see
[Parc’s mark on Chromium’s pages](app-icon-marks.md#parcs-mark-on-chromiums-pages).

HTTP authentication uses the actual authority, including proxy text, and the
native trust explanation. Return submits and Escape cancels. Native secure text
fields, original callbacks and sheet lifetime remain authoritative. Parc supplies
Chromium’s HTTP-auth coordinator and main-frame tab helper; a narrow credential
validation hook rejects peer credentials while a stale sheet closes.

External-protocol remembering uses Chromium's per-origin policy. Its input
protection gates both buttons and Return. Missing origin/application information
keeps the native fallback text; it does not fabricate a trusted site/app name.

Permission requests anchor to the visible page's toolbar, sidebar or popup
control, otherwise its top-leading page corner. The sidebar control remains
revealed until the prompt and any successor popover close. Escape/outside click
means Not Now. A second prompt in the same window refuses rather than stacks;
a competing sheet ends it neutrally.

Ordinary permissions use the two-action card; permission-element stages keep
their native titles and choices. During a macOS handoff the card shows progress.

While macOS hasn't decided whether Parc may use location, the engine waits
silently. Chrome asks macOS from its location-bar icon, which Parc lacks, so the
page observer in `site_permissions.mm` asks when a page starts using location
(after Allow on the card or on an allowed site), once the page is visible in the
active window: one request at a time, none after macOS decides. Allowing hands
the waiting `getCurrentPosition`/`watchPosition` its position; refusing gives
the page a permission error. Location retains the engine's initial accuracy.
Notifications ask macOS after Allow on the card or at an allowed site's first
notification; one macOS drops meanwhile reappears within a minute of Allow unless
closed or replaced (a page's own close is unseen). Chromium's media handler asks
for camera and microphone as capture starts. Request type supplies the title and
symbol, including protocol-handler and combined camera/microphone wording.
Security warnings are Chromium's interstitials under Parc's skin; see [failure and recovery](#failure-and-recovery-surfaces--web17).

## Context menus, hovered status and banners — WEB16

### Webpage context menu

The actual Chromium menu retains its native presenter, validation and lifetime.
Parc adds its link split action after Open Link in New Window and places
**Add Image to Easel…** after Save Image As. Image search uses the configured
search engine. Selected-text search precedes the ordinary selection actions.
Excluded AI, Lens, QR, translation and vendor-specific items are not exposed;
empty/repeated separators are removed.

Open Link in Split View uses the original source page and split owner to insert
a pane after it. It requires an eligible HTTP(S) link in a normal browser with
capacity; a fifth pane reports **Cannot Add New Pane**. Peek, embedded Easel and
popup owners do not offer this context-menu route. The menu asks the window
whether the page is showing as a Peek right now (`isPeekPage`), so a Peek
expanded or added to a split offers it like any other tab.

Docked Developer Tools aren't a Parc page, so the same presenter shows their
menu through the tools' docked lease, and the menu closes when that lease ends.
Docked or not, the DevTools items (Edit attribute, Copy, Store as global
variable…) appear as in Chrome, with the same excluded items removed and none of
the webpage additions above. Any other web content Parc hosts outside a Chromium
window gets the same treatment wherever Chromium would otherwise show nothing:
extension popups and side panels, embedded extension options and the device
toolbar of undocked tools keep Chromium's own menu, Inspect included. Each such
menu is bound to the window showing that content.

### Split View from link clicks

Option-click and Option–Command-click open an HTTP(S) link in Split View, in a
pane after the clicked page, when the window can take a split right now: a real
click in the selected page of a normal key window, with no Peek, pop-up, sheet,
command bar or Library in the way and fewer than four panes. The click's press
comes first and focuses the pane it lands in and closes an open command bar, so
a link in another pane of the split, or clicked while the command bar is open,
still splits. Links inside the page's embedded frames split the same way, except
isolated fenced ad frames, which keep Chromium's behaviour for both modifiers.

Chromium's own policy turns a plain Option-click into a download. Parc's
renderer link policy (`parc_native_link_policy.cc`) instead sends it through the
existing native link query, `PrepareNativeOptionLink` gives it a one-use token,
and the browser then opens it exactly as an Option–Command click, so no Chromium
file changes. The two modifiers share one fallback: when no split is possible
the link opens in a background tab, and at the four-pane limit Parc also says
**Cannot Add New Pane**. Chromium still waits half a second before acting on an
Option-click, so an Option-double-click keeps selecting a word in the link.
Non-web links keep Chromium's save-the-link behaviour, and **Save Link As…**
still downloads any link.

### Hovered-link status

`Engine/ParcNative/status_text.mm` draws a 24-point capsule ten points from the
page's bottom/leading edges, using window material/theme and a subtle border and
shadow. Text is 12-point medium, with 9-point side padding and a 6-point icon gap.
Compact width caps at 400 points; expansion stays inside the page.

Plain display removes the scheme prefix/trailing slash for readability, with
insecure/mail icons where appropriate. Modifier descriptions explain background
or foreground tabs, Peek, the same Peek, new-window and Split View destinations
without changing the link. **Open … in Split View** (Option, Option–Command),
**Open … in Peek** (Shift) and, inside a Peek, **Open … in this Peek** (Shift)
appear only when the click would do that from the hovered page. The app answers
read-only, for the pane under the pointer as the click's press leaves the
window: that pane focused and the command bar closed (`canSplitLinkFrom`,
`canPeekLinkFrom`), or for a Peek, that Peek shown and interactive in the key
window (`canNavigatePeekLinkFrom`). Links in fenced ad frames never
promise any of these, and links in a Peek never promise Split View or a new
Peek; Parc's engine tells a fenced frame apart by which frame
Chromium sends the pointer's events to, noted with each address the page
reports, so an address still trailing the pointer out of an ad keeps its answer.
An ad link the pointer only grazes can flash a promise for a moment, because
Chromium doesn't say which frame an address came from. Otherwise Option keeps
the plain address and Shift says a new window. Links in ordinary embedded frames
open in Split View and Peek like the page's own, so they get the same answer.
Inside a Peek, Shift over an embedded frame sandboxed against navigating the page
says a new window, because that is where its click goes: the engine reads the
sandbox of the frame the pointer is over, noted with each address like the fenced
check. A sandboxed frame allowed to keep its own origin and from the same site as
the frame around it runs inside that frame, and Chromium doesn't say which of the
two the pointer is over, so the capsule gives the surrounding frame's answer
there. Sandboxing never changes Split View, which opens a new pane instead of
navigating the page; see [Peek](peek.md#links-inside-a-peek).

While text shows, the answer is asked again once after the current event when
the window gains or loses focus (a sheet opening takes it), a sheet ends, the
window refreshes its navigation state (panes, selection, Peek, closing), or the
pointer moves between the page and an embedded frame Chromium draws separately,
such as a fenced ad or another site's frame. Only actual
links are explained; local transient messages share the capsule. Text truncates
in the middle; explained text expands immediately. Ordinary hover uses a
0.5-second debounce and 1.5-second expansion delay, token-guarded alpha fade and
immediate side changes.

The capsule reads the Space's colours when it appears and on appearance change.
While it shows, it also repaints when its window posts the palette notification
it sends AirPlay (`PCNativeAirPlayThemeDidChangeNotification`), so a Space-theme
edit recolours it in place. Only colours change; timing, visibility, text and
layout stay put.

<a id="banners-and-blocked-pop-ups-arcs-disposition"></a>
### Banners and blocked pop-ups

Confirm infobars remain in their genuine `ContentInfoBarManager`, unanswered and
expiring by their own rules, without an app shelf. Hiding presentation does not
call Accept or change the underlying security decision.

The one exception is Chromium's warning that an extension “started debugging
this browser”: every page carrying that bar shows a 40-point strip under its
toolbar, in each split pane, Peek and private window alike, and the page moves
down to make room. It uses the toast palette from the Space theme, the bar's own
wording, and a Cancel button that runs the bar's real button and detaches the
debugger everywhere. The × does what Chrome's close does, which also detaches,
so the warning can never be put away while the extension keeps debugging.
Cancel and × join the window's Tab order as soon as a row appears, and
Chromium's request to focus the infobar area moves focus to the first row's
Cancel on that page. VoiceOver announces each warning once, when its page is
first visible in the key window, so one that arrived in a background tab or
window is announced on arrival there. Page full screen hides it.

Tab sharing exposes **Share this tab instead** on the eligible hovered sidebar
row through its actual `TabSharingInfoBarDelegate`. It appears before Close,
not on split children, and keeps the real sharing callback. There is no in-page
bar or fabricated stop/source-switch action; the capturing site owns stopping.

Chromium's pop-up blocker still makes every decision; Parc shows its results.
`Engine/ParcNative/native_popup_blocking.cc` stores each blocked `window.open`
with Parc's own delegate (the browser client swaps the blocker's delegate
factory) and records blocked link pop-ups with the same blocker before Parc's
routing runs. Blocked redirects, where a cross-site frame without a user gesture
tries to send the whole page elsewhere, come from Chromium's framebust helper.
Both lists belong to the page's current document, and a new main document clears
them, as the blocker itself does.

**The sign.** A page that blocked something shows Parc's pop-up glyph, or a
redirect glyph when only a redirect was blocked, just left of the site button:
in the sidebar address pill, where it stays visible while the pill's other
buttons wait for hover; in the page toolbar, each split pane's bar and Peek's
bar; in the Developer Mode toolbar, just left of its Extensions button, which
opens the same card; and inside a pop-up window's address field. A narrow pane
gives it the site button's place, and hides it only when even that would crowd
out the title. There is no count, badge or toast; the tooltip and VoiceOver
label say what happened ("3 pop-ups blocked").
It fades in over 0.2 seconds. In the pill it rests at 60% of the theme's ink and
reaches full strength over 0.18 seconds on hover; toolbar and pop-up buttons use
their own hover and pressed fills. Reduce Motion removes the fades. VoiceOver
announces the summary once per document while that page is current in the key
window; later blocks on the same document stay silent. Clicking the sign opens
the Site Control Center anchored to it.

**The card.** A **Blocked** section sits between Extensions and Settings. Its
hover link opens pop-up and redirect settings, like the other sections' links.
Each item is a setting-style row with the destination host, truncated from the
front, "Pop-up" or "Redirect", and an **Open** or **Go** capsule. Redirects list
first, three rows show and "N more" expands the rest. **Open All** appears for
two or more pop-ups. **Always Allow Pop-ups** writes the same per-site rule as
Chromium's own "Always allow pop-ups and redirects", in the page's Profile, and
is offered only while the user controls that setting. The card's Settings
section then shows the revocable "Pop-ups and redirects" row. A hint steers
sign-in and payment windows to allowing and trying again; afterwards an allowed
row replaces the tile and the listed items stay openable.

**Opening.** Open, Open All and Go close the card, then revalidate the page and
its document. Chromium's stock replay would open a fresh window without
`window.opener`, in a window chosen by Profile alone. Parc instead rebuilds the
window as content's own `window.open` path does: it keeps the opener while the
frame that asked still shows the same document and the request wasn't
`noopener`, reapplies a sandboxed frame's propagating sandbox flags, and hands
the page to the source window's delegate. Parc's pop-up windows, Peek, Space
routing and tab provenance then apply exactly as for an allowed pop-up, and a
private window's pop-up stays in its private Profile. The page's original
`window.open` call already returned nothing, so a script polling that handle
still fails; flows that wait for the pop-up to message `window.opener` can
finish. Allowing the site and repeating the action gives a fully connected
pop-up. Go navigates the page to the blocked redirect, as Chromium's list does.

In a private window Always Allow writes to the private Profile, so the rule ends
with the private session and never reaches the regular Profile; regular-Profile
rules still apply in private windows, as in Chromium.

## Failure and recovery surfaces — WEB17

`PageFailureView.swift` and `SadTabContent.swift` present actual page failure
snapshots, separately from ordinary navigation error pages. The native page's
process termination/error code owns the crash state. Recovery actions retain
that page identity and cannot reload another tab after selection or transfer.
The crash shows the wilting flower; Parc's own "This page couldn’t open" view
(a load that fails after it started, an unsupported app address, an Easel
failure) shows the paper plane from `Resources/PageFailure`, with the raw
message in the corner.

### Network error pages and security warnings

A failed navigation still commits Chromium's error page at the failed address,
so the address field, Copy URL and history keep the site's own address (an
internal one shows as `parc://`). Parc changes only the page's template, through
the resource-bundle delegates Parc already installs in every process
([how Parc changes Chromium](chromium-seams.md#extension-points-come-first)):

- Network errors use Parc's template from
  [`Engine/ParcChromium/error_pages`](../Engine/ParcChromium/error_pages/README.md)
  in place of Chromium's. Chromium still fills it with its localized data, so
  automatic reload when the network returns, Reload, Details, DNS-check
  updates and the diagnostics links behave as before. Each common error has
  Parc's drawing and words; any other code shows Chromium's own localized
  heading and summary in Parc's layout. Details shows Chromium's exact
  sentence, suggestions and links. Return presses the primary button.
  Go back appears only when there is history behind the page: when the page
  finishes parsing, Parc's renderer client tells it, so one with only forward
  history offers Try again.
- Offline pages replace the dinosaur with a toy: Space tosses a spark from the
  plug to the bobbing socket, three misses end a round, and the best score is
  kept in the Profile, where Chromium kept the dinosaur's. The
  `--disable-dinosaur-easter-egg` switch turns it off. `parc://dino` opens it.
- Security warnings keep Chromium's interstitial page and script, so every
  command, the proceed click delay, the typed bypass, reporting, the
  certificate details and the strict script policy stay as they were. Parc
  adds its stylesheet, drawings and a small script that gives every warning
  Parc's headline and lede and labels the details button Details. Chromium's
  own paragraph keeps its links and specifics: it moves into Details (the date
  on a clock warning, the app on a security-software warning) or stays as a
  quieter note when a warning has no Details (the network on a captive portal,
  the reason on HTTPS-Only, an organization's own message). Safe Browsing says
  "this site" because Chromium doesn't give it the address. Chromium 157 wires
  no command to the monitoring warning's Back to safety button, so Parc hides
  it and Details takes over, as on the security-software warning. Parc hides
  the enhanced protection promo, which Settings offers only to people on it.
- Chromium's two rarer error templates get Parc's look the same way: a web
  app's offline page (its icon, Parc's plug and Chromium's message) and an
  organization proxy's sign-in page (the warning skin over Chromium's page and
  script).
- Titles and visible text say `parc://` where Chromium's say `chrome://`;
  links still go to the real internal page.

`tests/ErrorPages/check.py` renders every variant windowlessly with
Chromium-shaped data and checks those behaviours; see its
[README](../tests/ErrorPages/README.md).

The failure view is contained in the page's actual pane/Peek bounds and replaces
content immediately. The reload link uses native pointer, keyboard and
accessibility actions; hover changes the cursor. The hung-renderer sheet says
"This page is stuck" in Parc's words and uses the unresponsive widget's actual
renderer process. Wait
restarts its hang timer; Exit terminates that process. A replacement request or
page detach invalidates the old decision. The sheet is Parc's dialog: it lists
titles without favicons under Parc's mark, Wait answers Return and Escape, and
Exit is an unbadged neutral button. Renderer and ordinary navigation failures
must not be conflated merely because both show an error surface.

## Webpage actions, keyboard, focus and accessibility — WEB18

Share, Save Page As, Print, Find, navigation, reload/stop, zoom, developer tools,
copy formats and captures use the real existing command owners. The target is
the active Peek, then focused split pane, then selected tab in the command's
physical window. Popup browsers own themselves. Easel-embedded pages use their
selected-object route for navigation; they are not silently treated as the
window's page-tools target.

Share passes the committed URL to `NSSharingServicePicker` anchored at the page.
Paste and Match Style forwards through the original native responder chain;
focused Easel pages receive it instead of a new canvas text object. Standard
Delete, spelling, substitution, transformation and speech selectors remain
nil-targeted native commands; unsupported page operations stay disabled.

Appearance changes persist the local preference, update `NSApp.appearance` and
register window Undo where supported. Chromium follows effective appearance;
private windows keep their own dark appearance. Easels now inherit the Space's
content appearance through `EaselAppearance`, replacing the old forced-Aqua gap.

The engine owns the genuine `AXWebArea`; the app does not duplicate it with a
synthetic page. Tab traversal, Find return, Peek focus and command-bar dismissal
are described in [keyboard navigation](keyboard-navigation.md#cross-surface-traversal-and-return)
and [sidebar accessibility](sidebar-accessibility.md). Page containers do not
take focus away from the native content.

### Contracts for other families

Window Zoom/Bring All to Front, Manage Spaces, Stay On Top,
Extensions menus and typed Appearance commands are connected. Edit → Format → Font menu
integration is absent. Its implementation must use the working Note/Easel
formatting owners without preempting their native editing behavior.

## Surface motion, hover and haptics — WEB19

Sheets, native context menus, certificate and capture pickers retain their
platform motion. Failure replacement and sidebar sharing-control visibility are
immediate. None of these surfaces adds a sound or haptic.

Toolbar glyphs/fills follow the window's light/dark theme, with distinct enabled,
disabled, hovered and pressed states. Hover fades over 0.18 seconds and press over
0.16 seconds; Reduce Motion skips fades and key-window loss clears hover.

The Site Control Center uses the shared menu's 0.95-scale opening/closing motion.
Tiles use a 0.1-second hover/press response, section hover text 0.12 seconds, and
pin badges a 0.36-second hover dwell followed by 0.12-second fade. Reduce Motion
removes motion but retains hover-intent dwell. Permission buttons keep native
press feedback. Status-capsule style/side changes do not animate.

## Checks

Focused suites are the `SiteControlCenter*Tests` package suites, `tests/NativeSitePermissions`,
`tests/NativeJavaScriptDialogs`, `tests/NativeHTTPAuth`,
`tests/NativeExternalProtocol`, `tests/NativeStatusText`, `ShiftLinkTests.mm` in `tests/ParcNativeTests`,
`RendererCrashPresentationTests`, `BlockedPopupsTests` (blocked-content
wording and parsing), `SitePermissionRowTests` (permission row
wording, including location off in macOS) and relevant extension/page-tool
components.
Native changes need their appropriate compiler checks; app changes need the
Swift checks in [the working contract](../AGENTS.md). Older test helpers may
present windows: inspect them and follow current authorization.

The [backlog](backlog.md) indexes the remaining cross-family menu work
described above.
