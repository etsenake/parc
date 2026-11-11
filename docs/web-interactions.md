# Web interactions

Native page surfaces use the original Chromium page, document, Profile and
request lifetime. The app owns presentation and local product choices; native
security decisions and callbacks remain authoritative. This guide describes
current source behavior. [Product status](parity.md) and [the backlog](backlog.md)
carry progress and unfinished work.

## Site Control Center — WEB14

`Sources/ParcApp/SiteControlCenter.swift` and its browser-window presenter own one
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
leave an open card open. A disabled row's engine-supplied reason appears in the
tooltip and accessibility help.

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
| Server certificate | Chromium's certificate viewer sheet for the visible certificate |
| Client certificate | Genuine Chromium `SSLClientCertificateSelector` |
| Screen/window/tab sharing | Genuine Chromium/system picker under its original request lease |

Page dialogs use the engine's shared Parc dialog (`dialog_style.mm`): Parc's
mark, the bold title, the page's text (scrolling when very long), key-badged
**Cancel** (Escape) and **OK** (Return or keypad Enter). A prompt's field is
the app dialog's tinted rounded card ([dialogs](dialogs.md)): 16 points below
the text, 36 points tall with 12-point padding and no focus ring. OK stays inert for
half a second after the sheet appears, and a held Return or one pressed before
then never accepts, so a page cannot time a dialog under a keystroke. An input
method composing in the field keeps Return and Escape. A plain alert still has
only OK and ignores Escape.

JavaScript prompts offer **Don't show this again** from the sixth page dialog.
Suppression returns the native cancellation result; primary-page change resets
count and block. Programmatic handling does not pretend the checkbox was shown.
Inherited frame origins remain part of the dialog title. Beforeunload retains
whole-window/tab consent rather than using ordinary alert suppression.

HTTP authentication uses the actual authority, including proxy text, and the
native trust explanation. Return submits and Escape cancels. Native secure text
fields, original callbacks and sheet lifetime remain authoritative.

External-protocol remembering uses Chromium's per-origin policy. Its input
protection gates both buttons and Return. Missing origin/application information
keeps the native fallback text; it does not fabricate a trusted site/app name.

Permission requests anchor to the visible page's toolbar, sidebar or popup
control, otherwise its top-leading page corner. The sidebar control remains
revealed until the prompt and any successor popover close. Escape/outside click
means Not Now. A second prompt in the same window refuses rather than stacks;
a competing sheet ends it neutrally.

Ordinary permissions use the two-action card; permission-element stages retain
their native titles and choices. During a handoff to macOS, the card stays open
with progress. Location retains the engine's initial accuracy. Request type
supplies the title and symbol, including protocol-handler and combined
camera/microphone wording. Chromium's certificate error interstitial remains
the page error surface.

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
popup owners do not offer this context-menu route. Option and Option–Command
link clicks already use the native split-link lease; their status-text gap is
separate from actual split functionality.

### Hovered-link status

`Engine/ParcNative/status_text.mm` draws a 24-point capsule ten points from the
page's bottom/leading edges, using window material/theme and a subtle border and
shadow. Text is 12-point medium, with 9-point side padding and a 6-point icon gap.
Compact width caps at 400 points; expansion stays inside the page.

Plain display removes the scheme prefix/trailing slash for readability, with
insecure/mail icons where appropriate. Modifier descriptions explain background
or foreground tabs, Peek and new-window destinations without changing the link.
Only actual links are explained; local transient messages share the capsule.
Text truncates in the middle; explained text expands immediately. Ordinary
hover uses a 0.5-second debounce and 1.5-second expansion delay, token-guarded
alpha fade and immediate side changes. Theme is refreshed on presentation and
appearance change, not continuously during a Space-theme edit.

The current `native_appkit_page.mm` outcome callback still omits Option and
Option–Command split descriptions. The split destination works; only **Open …
in Split View** hover feedback is missing. That concrete engine follow-up is in
[the backlog](backlog.md).

<a id="banners-and-blocked-pop-ups-arcs-disposition"></a>
### Banners and blocked pop-ups

Confirm infobars remain in their genuine `ContentInfoBarManager`, unanswered and
expiring by their own rules, without an app shelf. Hiding presentation does not
call Accept or change the underlying security decision.

Tab sharing exposes **Share this tab instead** on the eligible hovered sidebar
row through its actual `TabSharingInfoBarDelegate`. It appears before Close,
not on split children, and keeps the real sharing callback. There is no in-page
bar or fabricated stop/source-switch action; the capturing site owns stopping.

Chromium's popup blocker remains active. Parc currently has no blocked-popup
indicator, chooser or release command. This is existing product behavior, not
permission to remove other working controls.

## Failure and recovery surfaces — WEB17

`PageFailureView.swift` and `SadTabContent.swift` present actual page failure
snapshots, separately from ordinary navigation error pages. The native page's
process termination/error code owns the crash state. Recovery actions retain
that page identity and cannot reload another tab after selection or transfer.

The failure view is contained in the page's actual pane/Peek bounds and replaces
content immediately. The reload link uses native pointer, keyboard and
accessibility actions; hover changes the cursor. The hung-renderer sheet uses
Chromium's text and the unresponsive widget's actual renderer process. Wait
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

Window Zoom/Bring All to Front, Manage Spaces, Change Profile, Stay On Top,
Extensions menus and typed Appearance commands are connected. Edit → Format → Font menu
integration is absent. Its implementation must use the working Note/Easel
formatting owners without preempting their native editing behavior.
Task Manager without a native page, Restore Data and collapsible Pinned-section
work remain in [the backlog](backlog.md).

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

Focused suites are `tests/SiteControlCenter`, `tests/NativeSitePermissions`,
`tests/NativeJavaScriptDialogs`, `tests/NativeHTTPAuth`,
`tests/NativeExternalProtocol`, `tests/NativeStatusText`,
`tests/RendererCrashPresentation` and relevant extension/page-tool components.
Native changes need their appropriate compiler checks; app changes need the
Swift checks in [the working contract](../AGENTS.md). Older test helpers may
present windows: inspect them and follow current authorization.

The [backlog](backlog.md) indexes the remaining split-link hover descriptions,
live status-capsule theme updates, blocked-popup controls and cross-family
menu work described above.
