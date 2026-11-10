# Web interactions presentation

Evidence and delivery notes for the LEFT Web interactions rows (WEB14–WEB19)
in the [parity ledger](parity.md#web-interactions). The page services these
surfaces present (WEB01–WEB13) are already connected; each section below

## Site Control Center — WEB14

Status: DONE. Source: `Sources/ParcApp/SiteControlCenter.swift` (SwiftUI, as
`Resources/SiteControlCenter` and the PageInfo session in
`Engine/ParcNative/native_page_info.mm` (engine overlay, pending apply).

types from the type table, values from annotated disassembly, two raw Ghidra
names. Retained scratch: `work/claude-web14-rea`.

**Structure [D].** `SiteControlCenterView.Body` is
`VStack(center, 10) { HStack(8) { ForEach(buttons) ActionButton }; ExtensionsView;
BoostsView?; SettingsView?; IfLetStore(footer) { Divider; FooterView } }
`0x6e8` (8), `0x6f0` (48 × 32), `0x720` (16), `0x728` (14), `0x758` (32),
fonts `0x730` 14 semibold, `0x738` 12 semibold, `0x748` 14 semibold, `0x750`
13 regular, `0x780` 14 medium.

  capture?, Option ? capturePortraitMode : captureFullPage]`, the capture pair
  offset −1, asset `copy-url` height 17, `camera` 16, `capture-full-page` 19,
  Share, Copy URL, Capture a portion of this page, Capture the full page,
  Capture in Portrait Mode, plus the button's keyboard shortcut.
  0.8 (0.3 disabled); face white (light) or Gray1 0.085 (dark), pressed white
  0.88 / Gray1 at 0.88; white → black 0.22 vertical gradient at 0.13 / 0.08;
  1-point white top highlight (inset −0.5, offset y 1) at 0.08 / 0.22;
  continuous radius 6 clip; enabled-only 0.25-point black hairline (inset
  −0.25) at 0.5 / 0.87. Secondary: black/white 0.05, pressed 0.15, radius 6.
  Interaction (`SiteControlCenterButtonInteraction`): hover +1 pt, press −1 pt
  on the shorter side, centred; primary shadow black 0.15 radius = y = 2,
  3 hovered, 1 pressed; easeOut(0.1).
  semibold 0.8; Spacer; hover text 12 semibold 0.46 while hovered }.onTap;
  content }.padding(.bottom, 5)`. Extensions: "Extensions" / "Manage", header →
  Manage Extensions. Settings: "Settings" / "More", header → site settings.
  Add Extension (`plus` 13 semibold 0.8), rows of four 48 × 32 Secondary items,
  spacing (236 − 20 − 192) / 3 = 8. An item is the 16-point action icon over
  `AlternateClickView` (secondary click → its context menu, described below);
  the picker's
  focus is a 2-point maxContrast stroke, radius 6; the pin badge
  `pin.fill` 8 black, rotated 0.576 rad, knocked out (destinationOut) of a
  14-point maxContrast circle at 1 pinned / 0.33 not; tooltip Pin / Unpin.
  VStack(leading) { title 14 semibold 0.8; subtitle 13 regular 0.46 }; Spacer }`;
  icon = symbol (13 medium; Preview 14 bold) knocked out of a 32-point
  maxContrast circle at 1 on / 0.33 off, black 0.3 behind it while pressed,
  Developer Mode only; secure → Preview (for a recent-pages host,
  Automatic Picture-in-Picture, then ADK's content settings (type `0x1d`
  Developer Mode `hammer.fill`, Content Blockers `shield.fill`, content
  Enabled/Disabled, On/Off, On/Off, Allowed (allow or session-only)/Blocked;
  row of its own.
  `HStack { security button; Spacer; ellipsis 32 × 32 }.font(14 medium)`, both
  Secondary. Security: `lock.fill` "Secure" (black/white 0.8) or `lock.slash.fill`
  "Insecure" in BaseAssets BrandRed (P3 0.843, 0.282, 0.027) at 0.9, padding
  pointer: Clear Cache, Clear Cookies, [Boost items], —, Manage Extensions…, Add
  Extension…, —, All Site Settings….
  content size = hosted intrinsic size, controller as delegate, preferred edge
  maxY of the entry button, detachable (`popoverShouldDetach:` YES,
  address pill's (`CommandBarPlaceholderButtonState…SiteControlCenterButtonState`,
  Extensions button (`TopBarButtonType`).
- **Extension picker**: hidden "Open Extensions" ⌘E (`toggleOpenExtensions:`,
  with →/↓/E, selects on Return or on releasing ⌘, cancels on Escape.

implemented as recovered; the look follows Josh's November 1 restyle below.
Every entry opens the one Site Control Center: the Toolbar's button and the
developer toolbar's Extensions button and ⌘E (a hidden shortcut; the picker
starts only while ⌘ is held, since releasing ⌘ selects). It replaces Parc's
former Extensions popover and the Toolbar's Extensions Menu button
(unification); pinned actions stay in the Toolbar/pill strips. A new page or
document (navigation start, the PageInfo session ending) closes it as
Chromium's page bubbles close. Backends:
Share → the Share command's page (WEB18) in `NSSharingServicePicker` at the
button; Copy URL → the existing copy owner;
captures → the page capture owner (portion, full page, portrait); extensions →
the genuine toolbar-action leases (run, context menu, pin); Developer Mode and
Preview → their existing preferences; content-setting rows → a headless
genuine PageInfo session (`PCNativePage openSiteControls…`), toggled by its
allow/block change, closed by its `OnUIClosing` (reload infobar); Clear
Cache / Clear Cookies → the real page tools; Manage / Add Extension →
`settings/content/siteDetails?site=<origin>`; Secure/Insecure → Chromium's
certificate viewer for the visible entry's server certificate
(`PCNativePage showCertificate`, the native viewer sheet), nothing without
one.

**Adaptations and limits.**
- Boosts are excluded: no Boost section, New Boost button or Boost menu items;
  the entry glyph stays the inactive outline (its filled state is Boost colour).
- CAP17 follows the user's unified-capture direction: Visible Area occupies the
  ordinary second button slot previously used for Boosts/Copy URL while capture
  is available, beside Portion and Full Page. All three enter the shared preview
  with optional Portrait framing; the separate Option/Portrait action is removed.
  The original four-button width and native popover ownership remain. Without
  capture the Share/Copy URL pair remains. Capture actions revalidate their
  original page/document/window/Profile/Space after native dismissal completes.
- Content Blockers: Parc has no built-in content blocker, so the row is not
  shown (contract below). Automatic Picture-in-Picture is always listed first
  from the profile's genuine content setting (ASK counts as on, as PageInfo's
  toggle does) and changed through the same presenter. Other permissions
  appear when PageInfo lists them. Titles are Chromium's localized type names
  compound and managed settings are shown but not toggled. Rows keep a stable
  identity per type and origin.
  row; a site's pop-ups setting appears only as PageInfo lists it (a site
- Preview uses Parc's single recent-pages preference for Notion, Figma, Linear
  extension, file and about: pages show it. Secure follows Chromium's SECURE
  level, which those pages never reach (no certificate), so they read
  Clear Cookies stay listed and are disabled off http/https by the page tools.
  (November 1) shows exactly this: Settings with Developer Mode / Off, then
  the Insecure footer and the ellipsis.
- Developer Mode on an insecure page: the builder's insecure branch
  Parc keys Developer Mode by `PCNativePage.developerModeSiteHost`: the
  committed web host, or the committed `chrome-extension://` page's extension
  ID (`developerModeExtensionHost`, overlay 284; earlier engines have none), so
  its row, toggle, menu item, reload and Developer Mode toolbar agree there.
  for a hostless URL was not traced.
  and its Settings builder tests only the host and the secure flag
  (run, pin) on a `chrome-extension://` page. Chromium's desktop PageInfo
  refuses WebUI, DevTools, view-source and extension pages (`ComputeUIInputs`
  DCHECKs; the location bar shows `InternalPageInfoBubbleView`). Parc opens the
  popover there without a PageInfo session or settings rows, and Site Settings
  and Security is unavailable. The app (`PCBrowserView.hasPageInfo`) offers
  PageInfo only to a visible and committed http/https page, so earlier engines
  are safe; the engine (`HasPageInfo` in `native_page_info.mm`, overlay 281)
  applies Chromium's own test (`PageInfo::IsFileOrInternalPage`, extension and
  distiller schemes, as `permission_dashboard_controller.cc`) plus about: other
  than about:blank, on the virtual and committed URLs. The app gate also
  has no PageInfo popover, and its settings rows need a secure host
  59, offset `0x3b0` of the 0x7a0-byte client) with the page's frame; no URL
  the certificate viewer for the visible security state's certificate and only
  logs "Attempted to open certificate dialog for page without SSL." otherwise.
  Parc does the same through Chromium's `ShowCertificateViewer`; with a
  certificate it closes the popover first, like its other after-close actions.
  Engines before overlay 284 keep the PageInfo popover on http/https pages
  and do nothing elsewhere.
- An extension tile's menu (secondary click, Control-click or VoiceOver's
  Show Menu) keeps the card open and is Parc's own, both at Josh's request.
  palette, 8-point row plate, 13-point medium titles, separators and motion,
  It hangs 4 points off the card's edge with its first row level with the
  tile, like a submenu. It looks for room as the card does: inside the
  window's part on screen, then on the screen (as beside a small popup
  window). There it takes the side where it and its submenus, every level
  deep, all fit, so a pane at the window's right edge, or a narrow one, opens
  the whole chain to the left rather than a submenu doubling back over the
  card. Failing that, it takes the side the menu alone fits, then the roomier
  one, and moves in from any edge. The tile stays lit while it is
  open, and the site-access submenu hangs from the menu the same way. Like
  NSMenu it runs its own event-tracking loop: arrows, Return, Escape, a release
  over a row (including a drag from the tile), a press outside and an open
  submenu waiting while the pointer heads into it behave as NSMenu's do; the
  keys stay with the lit row until Right. The item runs after the menu has closed, inside the engine's
  synchronous show, so its model lease and guarded targets hold through the
  command. Closing the card cancels the menu, as does the engine's own
  cancellation. Engines before overlay 650 have no presenter hook and show
  their menu at the pointer, with the card kept open. A disabled row shows
  the engine's reason it is unavailable as Parc's tooltip once the pointer
  rests on the row, as the grey menu did (VoiceOver reads it as help). A pinned
  extension button's menu is the same themed menu, in the card's colours,
  hanging beside the button with its first row level with it and
  any open card left open.
- A secondary click, Control-click or VoiceOver's Show Menu on an entry button
  argument was not decoded (rounded rectangle assumed); default SwiftUI
  resolves picker wrap, physical E (keyCode 14), Return selection and unrelated
  key cancellation, replacing the old character/keypad-Enter adaptation.
  Copy URL, captures, Secure/Insecure, site settings and the menu's actions run
  after the popover has closed and the window holds key again.
- PageInfo and Automatic Picture-in-Picture rows need the pending engine apply
  (overlay 236); until then the Settings section lists Preview and Developer
  Mode only (Swift checks `responds(to:)`). The engine half has a syntax-only
  compile; it has not been built or run.

motion contract §1). The restyle below opens and closes with the plus HUD's
easeOut(0.12) and the pin badge on easeInOut(0.12) after a 0.36 s hover-in

kept and the capture buttons unchanged (ledger: Completion requirements).
- Panel: the dock plus HUD's (`SidebarPlusMenu.swift`): `SidebarPlusMenuWindow`
  separators, 12-point continuous corners, no shadow, its 0.95-scale
  open/close motion and its dismissals (parent close, miniaturize, sheet,
  resize, app deactivation, losing key; a press on the button that closed it
  does not reopen it). Escape closes, and the sidebar hiding closes a card
  hanging from the pill. The card centres under its button with the tail on
  the button's midpoint. From every anchor (the sidebar URL bar, the top
  toolbar, each split pane's bar, a popup's bar) it hangs from the button
  inside the part of the window on the button's display, opening above when
  there's no room below. Failing both, it hangs from the button past the
  window, on screen. Only with no room on either side anywhere does it take
  the roomier side and move onto the screen over the button. It follows the
  button and re-flips as it grows. It takes
  takes its positioning view's, announces itself as a popover, and gives the
  hosted buttons keyboard focus (Tab, Full Keyboard Access).
  (its methods are `popoverDidClose:` and `popoverShouldDetach:`), so
  AppKit's default applies. A drag that starts on the card's background
  tears it off: it loses its tail and its parent link, gains a window shadow,
  moves on its own and stays open on outside clicks, resizes and
  deactivation. Escape, its browser window closing, minimizing or beginning
  a sheet, the owner's navigation and document dismissals, another Space or
  Profile (even one showing the same Favorite's page) and the entry button
  still close it, as they close an attached card; it no longer
  defers the window's other surfaces or holds the pill's buttons revealed.
  detached card has no close button [I].
  PageSidebarItem style), shared through its static fill, radius and press
  values: tiles (actions, extensions, Add, footer) rest at its hover fill
  (Josh, 12:28). Rows take its selected fill (0.1) while hovered or
  picker-focused. Tiles lift then (Josh, 15:48): the plus HUD's
  light) and its hovered / pressed shadow (black 0.15, radius and offset 3 /
  spring(0.18, 0.8) press. Glyphs, the
  lock and the ellipsis are the plus HUD's title colour at full strength,
  like the text (Josh: brighter, not washed-out grey); extension icons keep
  their own artwork. Titles and state lines use the plus HUD's 13-point
  medium / regular fonts in its title and subtitle colours; section headers
  its subtitle colour. Settings rows are 40-point rows (icon centre 20, title
  at 42), 8 points apart. Setting circles (32) and the pin badge (14) draw a
  real title-colour glyph, no knockout: on / pinned on the theme's `focus`
  (white 6.3:1 green, 6.6:1 purple), off on the rail's selected fill. Top-row
  glyphs are offset so their ink centroids sit on the tile centre (share −2,
  `window-screenshot-icon` draws its frame at 40% alpha. Extension images are
  the engine's 32-point canvas shown at its own size: Chromium centres the
  16-point action icon in it (`IconWithBadgeImageSource`), and squeezing the
  icons, a 10.5-point plus, 14-point badge and the same action glyph sizes.
  Badges are the pinned strips' (Josh, November 1): with overlay 290's
  unbadged canvas the tile draws `ExtensionActionBadgeView` in the
  extension's own colours over the icon's top-right corner, framed by
  `ExtensionActionBadgeMetrics` in the 48 × 32 tile and clear of the
  bottom-right pin badge; older engines show the baked canvas and its
  Chromium badge alone. VoiceOver reads the badge text as the tile's value.
- Colours are the theme's light/dark pairs resolved by the card's appearance,
  are the dark half's colour (Josh's screenshot, raw P3 193, 255, 219).
- Tooltips: main's SwiftUI `.parcTooltip` anchors with each control's
  live keycaps, the extension's own tooltip, Pin / Unpin, Add Extension;
  Parc's labels elsewhere (Manage Extensions and All Site Settings for the
  section headers, from the ellipsis menu; each setting's title; Secure /
  Insecure; More). The card's window controller takes the window theme's

**Checks.** `tests/SiteControlCenter/check.py` (width, artwork, button order,
tooltips and hints, picker wrap, layout collapse and rows, placement, chrome,
after-close actions, click pass-through, and the real card over an off-screen
parent: child window, focus, appearance, Escape, losing key, deactivation,
parent close, detach, the closing press, delayed shows; optional light/dark
renders), updated
`tests/BrowserToolbar` (135, three Toolbar action buttons) and `tests/NativeExtensionControls`, whole-module
typecheck with zero diagnostics, and a pinned-flag syntax-only compile of
`native_page_info.mm`. An independent review's findings (navigation, key
window, picker gating, detach and close timing, page-menu keyboard access,
Parc were not inspected on screen. The extension/internal-page refusal
(November 1) passed the whole-module typecheck, the facade's packaging-flag
compile, a `libcef_static`-flag syntax-only compile of `native_page_info.mm`
and the Site Control Center check (68 assertions); it has not been built or run.
The footer and certificate route passed the same checks, with source
assertions for the facade gate and Site Controls' PageInfo guard, and an
offscreen 2x light/dark render of an extension page's popover.
The restyle passes the Site Control Center check (70: placement, chrome, card
Escape, tooltips, hit-target routing, dismissal barrier, delayed show), the
plus menu (161 + 37), Library rail (31), Browser Toolbar (332), header-glyph
(91) and Space manager (169) checks and the whole-module typecheck; renders
are offscreen only. It has not been built, run or reviewed.

**Contracts.** Content Blockers (receiving: Settings, whichever owner adds
(On / Off) after Developer Mode for pages with a host.

## Dialogs, authentication, certificates and permissions — WEB15

notes are in `work/claude-web15-rea` (`decomp1` holds REA/Ghidra pseudocode
for the login window and before-unload paths). Every surface below is a
native page-bound presentation; none plays a sound or haptic.

message text and the page message as informative text, default style and icon,
"OK" (tag 1) and, except for an alert, "Cancel" (tag 0); a prompt's
`NSTextField` (initial first responder) and an optional "Don't show this
again" switch go into a vertical `NSStackView` 280 wide and 24 points per view
computes it with `AppModalDialogManager::GetTitleImpl` (1.170 `0x6c744d8`,
resources 36242–36245: "<origin> says", "An embedded page at <origin> says",
"This page says", …). The checkbox appears once the page's
that per-page count before each dialog and skips dialogs while
`isBlockingJavascriptPopups` is set (1.170 `0x438fb94`/`0x438fc68`); checking it
same sheet; the runner passes Chromium's `GetSiteFrameTitle` (the alerting
origin is that of the frame committed at CEF's alerting URL, so about:blank and
srcdoc frames keep their inherited origin), counts alert/confirm/prompt per
page, offers the checkbox from the sixth and, once checked, answers later ones
with Chromium's cancel result. Programmatic handling (DevTools) never reports
both when the primary page changes, as Chromium's own suppression does.

its delegate first refusal (tab close/quit consent), then shows the same helper
in confirm form with "OK" and "Cancel"; the primary-button label ADK forwards
is not shown. The title and message are Chromium's ("Leave site?"/"Reload
site?", "Changes you made may not be saved.", 1.170 `0xa041714`). Parc shows
those strings (`IDS_BEFOREUNLOAD_*`/`IDS_BEFORERELOAD_*`) with OK = leave and
no-window auto-accept is behavior and stays with WEB03's existing refusal.

400, style titled | full-size content, not opaque, transparent title bar,
≤ −20); subtitle 20 below; username and password rows (65-point right-aligned
label + 300-point field, row height 40) 15 apart; a Cancel / Sign in row (75
each, height 40) 15 below, trailing-aligned, 15 above the bottom. Title "Sign
passes Chromium's authority unchanged (1.170 `0x43b12cc`, which also derives
`is_url_potentially_trustworthy` from the absence of Chromium's not-private
explanation): an origin such as "https://login.example:8443", whose host drops
the port, or for a proxy Chromium's sentence "The proxy <url> requires a
username and password.", which has no host, so a proxy reads "Sign in to The
proxy … requires a username and password." Fonts come from
`FontsManager.FontManager`'s current `FontSet`: the views read `label` (key
that family at NSFontManager weight 7, traits 0, then 18 points
private." or "…is not private." by `isURLPotentiallyTrustworthy`. Labels use
ForegroundSecondary. Fields (`WebDialogTextField`): borderless text in a
radius-5 box inset 7, border 2 in VibrantText while editing (clear otherwise,
placeholders "Username"/"Password". Buttons (`LoginButton`): borderless title
inset 7, radius 5 continuous; Cancel on SidebarItemBackground with
ForegroundPrimary text, Sign in on VibrantText with white text. In a field,
`http_auth_presenter.mm` on its existing page sheet, with the same fonts (the
title through the same NSFontManager call) and the same proxy title. Parc has
chalkboard, inconsolata), so the default set applies; corners are drawn
continuous through the layer.
Color values (light / dark): ForegroundPrimary P3 0.055/0.059/0.063 at 0.9 /
white 0.8; ForegroundSecondary black 0.5 / white 0.5; SidebarItemBackground P3
0.055/0.059/0.063 at 0.05 / P3 0.98/0.984/1 at 0.1; VibrantText sRGB
0.047/0.314/1 / 0.165/0.714/0.965.

"“<source>” wants to open “<destination>”." with an empty informative text and
the destination's icon, then `NSWindow.showDialogSheetDeprecated`
buttons in order "Open “<app>”" (tag 1, default), "Always open “<app>”" (tag
99999) and "Cancel" (tag 0, Escape). Parc's presenter is now that alert; the
controller supplies the security-display origin, Chromium's application name
and the application icon from Launch Services. "Always open" accepts and
remembers through Chromium's own per-origin preference and appears only where
own dialog defaults to Cancel); Chromium's input-protection check still gates
Open, Always open and Return. Without an initiating origin or application name
the request keeps Chromium's text, with a plain "Always open" button.

(`CommandBarPlaceholderPopoverState.Content.permissionRequest`, shown at
padding 10, a 32-point circle (white 5% dark / black 8% light) with the
permission's SF Symbol in white or black at 66%, an 8-point gap, the 14-point
title in the same colors, 16 points, then "Not Now" and "Allow" side by side, 8
primary white 20% / white with a white-to-black-22% gradient at 5% / 13%, a
1-point top highlight and a 0.25-point outer hairline; 14-point semibold; light
buttons cast a black 11% shadow, radius 2, 1 down). Allow sends response 0 and
their own sentences for notifications, quota storage, multiple downloads and
idle detection, and "Make <site> your default mail app?" for a
protocol-handler request whose ADK type is `mailto` (ADK's
`WebContentPermissionProtocolHandlerType` is `mailto(_)` or `unknown`, built at
scheme reads "access your protocol handler"). Parc reads the scheme from
Chromium's `RegisterProtocolHandlerPermissionRequest` through a one-line
accessor (host patch `native-protocol-handler-request.patch`); camera with microphone reads "camera, microphone", any other
location.fill, bell.fill, clipboard.fill, externaldrive.fill, arrow.down,
textformat.alt, zzz, pianokeys, macwindow.on.rectangle,
bubbles.and.sparkles.fill, keyboard, gearshape.fill; 14 points, 15 for storage
and downloads; bold for fonts, idle and downloads; lifted 1 point for camera and
storage, 0.5 for clipboard and notifications). Parc's presenter is that popover
types, and `BrowserWindowController.parcSitePermissionAnchorForPage:` names the
chrome's) page-controls button, for the current page — the entries the Site
Control Center (WEB14) opens from. Otherwise the popover hangs from the requesting page's top leading
corner, the rule other page controls follow while the sidebar is off-screen.
The sidebar's page-controls button fades in only while the sidebar is hovered.
same while the prompt is up: answering with that button starts
`AddressPopoverRevealHold`, which follows the popover shown next and releases
the reveal when it closes ([navigation](navigation.md#sidebar-url-bar)).
replace Chromium 156's Block, Allow This Time and accuracy choices (location
uses the engine's initial accuracy); a second prompt in the same window
refuses rather than stacking, and another dialog's sheet beginning on the
window ends the prompt neutrally; Chromium's permission-element stages keep their
own titles and labels in the same card (last label primary, more than two
stacked) and, when they hand off to macOS, stay open as an
application-defined popover with the progress line; corners are circular
Bézier paths.

`SFChooseIdentityPanel`, only Chromium's Views `CertificateSelector`; Parc uses
Chromium's `DesktopMediaPickerDialogView` and `SCContentSharingPicker` paths;
Parc forwards source lists to the genuine pinned Chromium picker under its
original request lease, including delegated macOS system selection and the
dedicated current-tab dialog.
MEDIA16 is continuing the remaining keyboard/AX and presentation contract.
Certificate error pages are Chromium's interstitial.

**For WEB19 (motion):** JavaScript dialogs, before unload, HTTP authentication
and external protocol are stock AppKit sheets; the permission prompt is a stock
`NSPopover` show/close (no `setAnimates:` override). Remaining static detail for
WEB19 to animate: PopoverPromptView's ActionButton uses SwiftUI's
`PlainButtonStyle` press feedback, which Parc's buttons do not yet draw.

**Engine:** the presenters, `javascript_dialog_runner.mm`,
`external_protocol.mm`, `site_permissions.mm`, `BUILD.gn` (url_formatter and
custom_handlers deps), three engine unit tests and the new host patch adding
`RegisterProtocolHandlerPermissionRequest::handler()` are overlay inputs
(the first delivery built in v233; this follow-up is overlay version 239,
pending apply), with `javascript_dialog_runner.h` gaining
`PrimaryPageChanged`. Checks: pinned-flag syntax check of all ten units
(`site_permissions.mm` against the patched header), Swift typecheck, and the
four AppKit component suites (98, 37, 42 and 76 assertions). Nothing was linked
or run in a browser.

## Context menus, hovered status and banners — WEB16

Status: **done** (source; the engine overlay below awaits the engine owner's
Parc's engine). Raw REA notes live in `work/claude-web16-rea` (outside Git).

### Webpage context menu

witness for `webContents:willShowContextMenu:withElement:` returns NO in 1.122
model through the stock `MenuControllerCocoa` (`RenderViewContextMenuMacCocoa::Show`
`0x420c124`) with the old icon scheme (`initializeWithNewMenuIconScheme:` NO,
`0x317cf20`): no vector icons, no Option alternates, stock check items. Parc
already has the same presenter and default scheme.

Chromium 156 in these ways, which Parc applies in its menu observer's
`InitMenu`. That hook runs last in the real InitMenu, before the Mac toolkit
adds Look Up (`native_page_context_menu.mm`):

  plain `Open Link in Split View` right after Open Link in New Window
  (`0x426586c–0x42658e0`). It appears only in a normal browser window, and
  only when the link URL is valid and standard (`0x42663f8`). The Open Link
  as/in Profile block and the link-image QR item are gone.
- **Image:** the image search is always `Search ‹engine› for Image` (IDC 50124,
  Image As (`0x426564c`). Parc's existing Add Image to Easel… now takes that
  Image... is off by default (flag 19).
- **Selection outside a link:** the Search item is inserted at index 0
  (`0x81cee38–0x81cef00`). Partial translate (and its selection fallback),
  reading mode and Glic are gone.
- **Page:** Glic, Lens/region search (with the Ask-Google and contextual-tasks
  items), reading mode/Listen and Create QR Code are gone.
- **Video:** the search-for-video-frame items are gone.
- **Everywhere:** QR is disabled (`0x4266488`). Separators that become leading,
  trailing or doubled are removed.


link to the window (`nativePage:openLinkInSplitView:`), which adds it as a
split pane after the page it was chosen in, using the existing split-after
owner (`insertPreviewSplit`), with that tab as referrer. The pane loads the
HTTP(S) URL as a new browser navigation without Chromium's frame referrer. A
ToastType.maxNumberPanes). The item is not offered in Peek, embedded Easel or
popup windows, and is enabled only for an HTTP(S) link while the window can
follows the command bar's recovered `.newPane(.afterFocusedPane)`.

### Hovered-link status


- **Shape:** a 24 pt capsule (corner radius = height × 0.5) at 10 pt from the
  page's bottom and leading edges.
- **Background:** popover material within the window, plus an overlay layer
  (z 3) in the window theme's SemanticColorPalette background. Parc's window
  delegate supplies its `ThemeChromePalette.background` and matching appearance
  (`PCNativeStatusTextThemeSource`).
- **Border and shadow:** a 1 pt FloatingScrimBorder outline (black 0.10 / white
  0.20); a black 0.12 shadow with 5 pt radius and no offset.
- **Contents:** 9 pt side padding and a 6 pt icon gap; the text field at its
  medium BaseSecondary (0.70). The width stays at most 400 pt while compact; expanded
  removes the cap, and the 10 pt insets always win.
  is removed, then one trailing slash. `http:` shows `lock.slash.fill` and
  `mailto:` shows `envelope.fill` (10 pt heavy, BaseSecondary).
  and focus it` (⇧⌘), `… in Peek` (⇧ while Shift-Peek is enabled, the setting
  page's ⇧ table gives a new window) or `… in a new window`.
  The URL range is BaseTertiary, it always truncates in the middle, and it
  expands without the 1.5 s dwell.

Existing timing, avoidance and click-through are unchanged (see
`tests/NativeStatusText/README.md`).

**Adaptations.** The attributed text carries the 12 pt medium font explicitly
or mailto) is explained, because Parc's own transient messages ("Preparing
Reader…") share the pill. Parc's Shift-Option click opens a window, so
Split View`) are not shown because Parc has no Option-click split route; see
the contract below. The theme overlay is read on each presentation and on
appearance change, not live while a bubble stays visible across a Space theme
change.


- **Confirm infobars (no presenter).** `webContents:willShowConfirmInfobar:`
  reaches ADKClient.WebContentFrame. It only forwards to a
  Parc now draws no shelf either. Every confirm delegate stays unanswered in its
  That includes PageInfo's reload prompt, automation/debugging notices and
  every other ConfirmInfoBarDelegate. No callback is answered differently;
  WEB14 owns any Site Control Center reload affordance.
- **Tab sharing (sidebar button only).** There is no in-page bar. The only
  control is the sidebar row's `Share this tab instead`
  Parc keeps the real TabSharingInfoBarDelegate on each page and exposes only
  that action (`PCNativePage (TabSharing)`). The row shows a 24 pt
  SidebarCellButton just before Close, separated by 2 pt. Its glyph is
  `rectangle.inset.filled.and.person.filled` at 14 pt semibold, tinted white
  0.592 / black 0.565. It appears only while the row is hovered without its
  reset subtitle, never on split children, with tooltip `Share this tab
  instead` and AX identifier `shareTabButton`.
  sharing stops from the capturing site, and the sidebar recording indicator
  is the Sidebar family's.
  disable-popup-blocking switch.
  same string is in 1.170).
  Parc likewise removes the sidebar indicator, the page-menu item, the Easel
  object button and the chooser. Pop-ups stay blocked by the real tab helper
  with no list or release; a 1.170 consumer of the published state was not
  found.

WEB10/WEB11 remain DONE; their presentation now follows this disposition.

### For WEB19 (motion)

The status pill keeps the recovered token-guarded alpha fade with AppKit's
theme changes are unanimated (CATransaction actions disabled). The share button
uses SidebarCellButton's existing press spring. Context menus are the stock
NSMenu. Confirm infobars, tab sharing and blocked pop-ups have no surface to
animate.

### Contract and checks

clicks to a split, return `PCNativeStatusLinkOutcomeSplitView` for ⌥ and ⌥⌘ in
`native_appkit_page.mm`'s status `linkOutcome` block. The string `Open %@ in
Split View` is already there.

**Checks run:**

- Native syntax checks (`native-check.py`) passed for every changed unit.
- The facade compiles and the full Swift typecheck passes.
- Component tests passed:
  - `tests/NativeStatusText` (50 assertions, including the explained path)
  - EaselPagePool (32)
  - DownloadLibrary view checks
  - SidebarRows (60 + 157)
  - SidebarChrome

Two existing source-text assertions also fail on unchanged main:
`tests/SidebarAccessibility/check.py` (the `SidebarView` declaration) and
`tests/SiteControlCenter/check.py` (the `.siteInfo` route). This change does
not touch either.

No browser was run. Rendering, live hover/modifier behaviour and live pages are
not verified at runtime.

## Failure and recovery surfaces — WEB17

evidence below. No functional browser test ran and no on-screen comparison was
made (no app was granted for inspection).

1.170 cross-checked where noted. Colours are installed 1.170.0 (89123)

  `sadTabView: SadTab.SadTabHostView?` and scopes its store to
  `ViewState.sadTabState` (`ADKClient.WebContentSadTabState`:
  frame whose lazy `HostingView<SadTabView>` is pinned to all four edges with
  content view inside `WebContentViewControllerSplitView`); nil restores the
  built by `WindowContentViewController.setupWebContentSubscription`
  get their own; Peek's modal content is taken to use the same controller [I].
  (1) an empty `VStack` with `frame(maxWidth: .infinity, maxHeight: .infinity)`
  at offset 8), `ForegroundTertiary`, `frame(maxWidth: .infinity, maxHeight:
  `Image("SadTab", bundle:)` `.resizable().aspectRatio(contentMode: .fit)
  `HStack(alignment: .center, spacing: 0)` of `ForEach` text definitions
  NSLocalizedString in the main bundle; English only in 1.122 and 1.170).
  bracketed word as a link and text, dropping empty parts; without a match
  the whole sentence becomes one link. Each part is `Text(text)
  .foregroundColor(ForegroundTertiary).underline(isLink)` with no font
  `onTapGesture(count: 1)` sending `SadTabAction.delegate(.onReloadClicked)`,
- *One presentation for every kind.* The state holds only the status and the
  code and the view reads only the code, so crash, OOM, kill and repeated
  crashes all show the same sentence and link. The `sad_tab_*` strings are
  analytics (excluded).
  0.3, white at 0.3 in Dark Aqua) for artwork and all text. Behind the clear
  view is the web content's backing: the web content blueprint case of
  white, black in Dark Aqua). Artwork: the `SadTab` template (96 × 103) in
  `ARC_SadTab.bundle`, copied to `Resources/SadTab` with its provenance.
  ships Chromium's own `HungRendererDialogView` with its
  shows Chromium's dialog [I: the fallback was not traced past the declined
  delegate]. Pinned Chromium source: plural title "Page Unresponsive", body
  "You can wait for it to become responsive or exit the page.", the list of
  pages sharing the hung process, OK "Wait" (default, restarts the timer),
  Cancel "Exit Page" (title case on Mac; terminates), no close button.
  renders in the page.

**Parc.**

- `PageFailureView` (with `SadTabContent`) draws the SadTab composition: the
  `FullOpacityBackgroundPrimary` backing, the copied artwork 96 points high at
  its aspect, centred with the sentence 64 points below as one column, the
  link underlined with the pointing-hand cursor over it, and "Error code: N"
  20 points in from the bottom-trailing corner, all in `ForegroundTertiary`,
  13-point system text (SwiftUI's body font). The code is the native
  `crashedErrorCode`. The link calls the existing native SadTab action;
  Chromium's `SadTab::PerformAction(kButton)` reloads, offering feedback only
  identity, acknowledgment and ownership checks are unchanged from WEB13.
- Chromium's "Aw, Snap!" title, info text and repeat-crash suggestions are no
- Contexts: every browser pane (ordinary tab, each split pane) and Peek use
  the view; a narrow pane wraps the HStack's texts; light and dark follow the
  window's effective appearance, so a private window (Dark Aqua) shows the
- A navigation failure (Parc only) keeps its own Retry and message in the
  same composition: "This page couldn’t open. Try again" with the message in
  the corner, cut short of the column.
- Hang: the native sheet now uses Chromium's own strings (title, body,
  pages sharing the process, Wait as default, Exit Page) through
  `l10n_util` and `GetHungWebContentsList` / `GetHungWebContentsTitle`
  (`Engine/ParcNative/native_appkit_application.mm`, overlay 235, with the
  `//chrome/browser/ui/hung_renderer` dependency in `native-host.patch`).
- Sidebar ⌘S contract: the sentence and corner text are pinned centred with
  `SidebarMotionController.pinDrawnContent(_:to: .center)` and the view's
  solid backing with `.scaleAxesIndependently`.

**Adaptations and limits.** Parc hides the registered page beneath this
sibling instead of `replaceSubview:with:` (the existing containment
`WebContentViewControllerSplitView`, so a docked DevTools (its separate
`devToolsView`) stays beside the SadTab; Parc's docked DevTools pane is built
by the engine inside the page's registered container (`native_appkit_host.mm`
wraps the page view in `NativeDevToolsPane`, whose layout owns the inspected
view's visibility), so the hidden container takes DevTools with it and the
failure view covers the whole pane. Keeping DevTools visible would need an
engine-owned way to hide just the inspected view and report its frame. The view is AppKit, not SwiftUI: the HStack's narrow-width
wrapping is an equal-share approximation, frames are pixel-aligned, and the
`cursor(nil)` modifier leaves the default arrow. The artwork is hidden from
accessibility (SwiftUI would label it "SadTab"); the link is an AX link,
accepts the engine's explicit crash focus (as WEB13 requires) but takes no
focus from a click and stays out of the key-view loop, activates with Space
or Return, and shows a focus ring only with Full Keyboard Access. The hang dialog stays an AppKit sheet: it
lists titles without favicons, keeps the app icon, and takes the hung
process to be the main frame's. Checks: whole-module typecheck,
`tests/RendererCrashPresentation` (64, including geometry, colours, the
light/dark backing and the link's click, key and AX paths),
`tests/EaselPagePool`, the window key-loop check, `tests/SidebarMotion` (now
asserting the three pins) and `tests/SidebarPacing` (its pane model now
carries them), the native syntax check, and the overlay's patch and hashes
replayed with `apply_context_patch` against the pinned sources.

`replaceSubview:with:` (no animation group or animator), its link's hover
changes only the cursor, and it plays no haptic; the hang dialog's own
presentation is Chromium's.

## Webpage actions, keyboard, focus and accessibility — WEB18

addresses; the shipped MainMenu nib (SHA-256 `c05560f6…1963`, identical in
1.122 and installed 1.170) for titles, keys, `arcKeyBindingID` and
No browser command was executed and no appearance was inspected for this row.

### Inventory of page-level main-menu actions

the registry defaults (`overrideWebView` = Prefer Parc, `promptAfterConsumed…` =
Use Both, absent = Prefer Websites).

- **File.** Share… (602, unbound) — added, see below. Capture…/Capture Full
  Page/Capture in Portrait Mode (263 ⇧⌘2, 1242, 914) — existing capture owner
  ([page-capture.md](page-capture.md)). Save Page As (1207 ⇧⌘S) and Print (901
  ⌘P, Use Both) — existing `PCNativePageTool` owner; titles now drop the
  ellipsis and the group now closes the File menu after Close Window/Archive Tab,
- **Edit.** Undo/Redo/Cut/Copy/Paste/Select All — native responders, with a
  separator after Redo as shipped. Copy URL / as Markdown / as Quote (890/402/1412,
  Prefer Parc) — existing ([keyboard-navigation.md](keyboard-navigation.md#copy-commands)).
  Paste and Match Style (740 ⇧⌘V) and Delete (1885) — added. Find…/Next/Previous/Use
  Selection (799/1254/487/926) — existing; Find and Replace (tag 12) and Jump to
  Selection (⌘J, tag 0) stay the Keyboard family's recorded native-text gap.
  Spelling and Grammar, Substitutions, Transformations, Speech — added.
  Format → Font (Bold ⌘B/Italic ⌘I via NSFontManager, Underline ⌘U) — not added:
  contract below.
- **View.** Appearance (2280) — added. Stop Loading (512 ⌘.), Refresh the Page
  (704 ⌘R), Force Refresh (1039 ⇧⌘R), Clear Cookies and Refresh (1436), Clear Cache
  and Refresh (1083) — existing; the two clearing commands now follow the shipped
  order. Zoom to Actual Size (764 ⌘0, retitled), Zoom In (1051 ⌘+, supplements
  2070/2083 ⌘=), Zoom Out (93 ⌘−, supplement 1881 ⇧⌘−) — existing. Cast (1371) —
  existing. Developer: View Source (655 ⌥⌘U), Developer Tools (1473 ⌥⌘I, 285 F12),
  Inspect Elements (1380 ⌥⌘C), JavaScript Console (1312 ⌥⌘J), Network Inspector
  (521), Allow JavaScript from Apple Events (2038), Toggle Developer Mode (1276 ⌃D) —
  existing ([developer-mode.md](developer-mode.md)). Enter/Exit Full Screen (428)
  and Exit (1324, Escape) — existing. Separators now bracket Reader/Cast as
  shipped; Parc's Enter Reader and Clear Browsing Data… are Page tools additions.
- **Archive.** Go Back (946 ⌘[), Go Forward (61 ⌘], both Prefer Parc) and their
  ⌘←/⌘→ alternates (361/1447) — moved here from View, titled as shipped. The
  alternates stay hidden registered entries (Keyboard family adaptation).
- **Tabs, Window, Help, app menu.** Tab, sidebar, window and app commands are
  Check for Updates and Troubleshooting are excluded scope.

Non-menu page actions are owned elsewhere and already connected: page context
menu (WEB05/WEB16), Site Control Center (WEB14), tab mute (Media). Page
1.122 has no Open in Default Browser string or command.

### Target page

the same owner: the active Peek, else the focused split pane, else the selected
tab, in the physical window that owns the command (popup windows are their own
controllers). Easel-embedded pages are not window contents in either browser, so
page tools stay unavailable for an Easel; Back/Forward/Reload use the Easel's
selected page object through `selectedNativePage`.

### Additions

- **Paste and Match Style.** Nil-targeted `pasteAsPlainText:` with ⇧⌘V (registry
  ID `pasteAsPlainText:`, Prefer Websites) plus the hidden ⌥⇧⌘V equivalent from
  so it is a subordinate `registerEquivalent`). Native text views answer the
  RenderWidgetHostViewCocoa method-list entries `0xd7748a4`/`0xd7748e0` give
  `pasteAsPlainText:` and `pasteAndMatchStyle:` the same IMP `0x416351c`. The
  pinned engine implements only `pasteAndMatchStyle:`, so `WebpageEditCommands`
  walks the key window's responder chain (then the main window's, when the key
  panel has no answering responder, as AppKit does) and forwards to the first
  engine view that lacks `pasteAsPlainText:`, after its own validation (main
  frame only).
  An Easel canvas defers to a focused embedded page instead of inserting a text
  object. The additive `pasteStyleShortcutDefaults` marker disables the new
  default when a saved custom chord owns ⇧⌘V. Adaptation: an app-side forward in
  place of an engine-view alias; no engine overlay.
- **Delete and the text submenus.** Delete, Spelling and Grammar (⌘:, ⌘;),
  Substitutions, Transformations and Speech use the shipped titles, order and
  standard selectors with nil targets; none has a binding ID, so none is a
  answers `delete:`, Show Spelling and Grammar, Check Document Now and Check
  Spelling While Typing (Chrome's view delegate), Show Substitutions, Smart
  Quotes/Dashes, Text Replacement, the three transformations and Start/Stop
  Speaking. Check Grammar With Spelling, Correct Spelling Automatically, Smart
  Copy/Paste, Smart Links and Data Detectors stay disabled on pages, as in any
  view without them; native text answers all of them.
- **Share….** Reducer case 49 builds `[URL]` and calls a WindowProvider
  (MainWindowsManager) presents `NSSharingServicePicker(items:)` relative to a
  one-point strip along the top of the content's flipped view
  content view controller), preferred edge maxY. Parc shares the committed page
  URL of `currentBrowser` from the same strip of that page view, edge chosen for
  (Site Control Center, tab context menu, hover cards) is WEB14/WEB16 scope.
- **Appearance.** "Websites, Easels, and Notes will use:" (disabled header) with
  registers the window undo "Update Appearance", then sets `NSApp.appearance`
  `NSApp.appearance`, registers the same undo in the key browser window's undo
  stack (private and popup windows have none, so they register nothing) and
  persists the choice in user defaults (storage owner is a Parc adaptation).
  Chromium follows `NSApp.effectiveAppearance` (`os_settings_provider_mac.mm`)
  and Notes follow the effective appearance; private windows keep their own dark
  window appearance. Parc's Easel editor still forces Aqua (contract below).

### Focus and keyboard ownership

view or a native control, never on the pane container. Window focus memory is
`PCNativeFocusManager`. Existing owners cover each behavior; none changed here:

- new tab and address entry focus the command bar, Escape restores the original
  page focus ([command-bar.md](command-bar.md));
- an explicit tab/pane/Peek selection moves focus to the displayed content
  (`focusSelectedContent`, [navigation.md](navigation.md#focus-traversal-across-page-controls-and-auxiliary-contexts));
  Peek focus return is [peek.md](peek.md);
- restores after panels, sheets and menus use `SavedFocus.mayReturn`, and Tab
  crosses page and sidebar through `WindowKeyViewLoop`
  ([sidebar-accessibility.md](sidebar-accessibility.md));
- Escape, Find dismissal and the arrow alternates' native-text guard are in
  [keyboard-navigation.md](keyboard-navigation.md); editable contexts never let
  the registry take ⌘C/X/V/A/Z or navigation keys (`eligibleShortcut`);
  unhandled modified keys reach the main menu after the renderer
  (`native_appkit_application.mm` `OnKeyEvent`, `native_appkit_host.mm` `MenuKey`).

### Accessibility

WebContentHostingView and the window ContentView carry no accessibility or
focus-ring overrides (no accessibility, focus or key-view methods in their
method lists, and no `setAccessibilityRole/Label/Element/Children:` or
RenderWidgetHostViewCocoa owns the `AXWebArea`; Parc's `PCBrowserView` is a
plain container, and the genuine `AXWebArea` was established at runtime in the
v57 package (parity.md). No focus ring is drawn around the page in either.

### Contracts for other families

- **Notes (Available):** Edit → Format → Font (Bold ⌘B and Italic ⌘I through
  NSFontManager `addFontTrait:` tags 2/1, Underline ⌘U `underline:`). These
  native-text menu chords would preempt the Notes and Easel emphasis owners, so
  the Notes owner should add them with its own formatting commands. On pages
  Blink's contenteditable bindings take ⌘B/⌘I/⌘U first (`editing_behavior.cc`);
  through the menu the engine view answers only `underline:` (edit-command
  helper), not the font manager's `changeFont:`.
- **Easels (Available):** `EaselEditorViewController` forces an Aqua root, so
  items without a binding ID ("Switch to Light Mode", "Switch to Dark Mode",
  "Switch to Automatic Appearance", Show Spelling and Grammar,
  Redo/Cut/Copy/Paste/Select All). Parc's Actions search lists only registry
- **Windows and lifecycle (Available):** Window → Zoom (1726) and Bring All to
  absent in Parc's menus) and View Downloads (150 ⇧⌘J, Parc Tabs).
  Manage Extensions… 978) is absent.
  Clear Archive (no ellipsis); Parc keeps View Archive, View Saved Captures,
  View History, Clear Archive….
- **Folders / Today / Sidebar owners:** Tabs → Duplicate (566), Reveal Tab in
  Sidebar (752), New Folder… (959, Parc File), Collapse/Expand All Folders
  (134/164, Parc hidden in View) and View → Expand/Collapse Pinned Section
  entries or placement.

Checks: whole-module typecheck (zero diagnostics);
`scripts/test-paste-style-command.sh` (registry default, hidden equivalent,
migration, forwarding and native-text ownership); `scripts/test-easels.sh`
(embedded page keeps Paste and Match Style); the existing shortcut, command and
migration scripts pass unchanged.

## Surface motion, hover and haptics — WEB19

Status: DONE. Every WEB14–WEB17 surface's opening, dismissal, hover and press
in the external work root (`claude-web19-rea/motion-contract.md`). Most of
these surfaces use stock AppKit motion, which Parc keeps:
- JavaScript dialogs (all four kinds) are NSAlert sheets
- The external-protocol prompt is an alert sheet (WEB15's disposition).
  certificate UI of its own (WEB15).
- Site Control Center and permission prompts use transient NSPopovers with
  default animation.
- Pop-ups are blocked silently with no UI (WEB16), so there is nothing to
  animate.

bubble already matches: 0.5 s debounce, 1.5 s expansion delay, a
default-duration alpha fade, an unanimated side flip.

Shipped: the Toolbar's Show sidebar, Copy, Site Control Center and Extensions
- Glyph and fill: the glyph is drawn in FullOpacityForegroundPrimary at
  0.55 light / 0.675 dark while enabled and 0.25 while disabled. A continuous
  six-point rounded fill in the same ink is 0 at rest, 0.05/0.09 when hovered and
  0.09/0.13 when pressed; press wins.
- Motion: hover fades over 0.18 s and press over 0.16 s, both ease-in-out
  since Toolbar geometry stays with its layout owner. The Toolbar takes its
  light/dark appearance from the theme (`palette.isDark`), as the sidebar does,
  so its black/white ink also fits themed Spaces; this also applies to the
  Split and title controls. As in those controls, hover clears on key-window
  loss and Reduce Motion skips the fades.

Shipped on top of WEB14's Site Control Center (`SiteControlCenter.swift`):
- The address pill opens the popover after 10 ms, or 100 ms when its button
  view-state flag and for an array flag inferred to mean active Boosts
  (excluded scope). A token makes an older request stale, and a pending
  show counts as open, so a second click closes it. The Toolbar and
  (2, 3 hovered, 1 pressed); their ±1-point ScaleEffect has
  EmptyAnimatableData. The November 1 restyle (WEB14) keeps the curve and the
  3 / 1 shadow for its tiles and drops the scale.
- Extension buttons show their pin badge with easeInOut(0.12) after a 0.36 s
  of WEB14's panel, so they have nothing to animate. Boost rows are excluded
  scope. As elsewhere in Parc, Reduce Motion drops these curves; the pin
  badge keeps its 0.36 s dwell, which is hover intent rather than motion.

WEB15's surfaces (confirmed on its code):
- Stock motion confirmed: JavaScript dialogs, before unload and the
  external-protocol prompt are NSAlert sheets; the login view sits on a sheet;
  the permission card is a transient NSPopover (application-defined while it
  hands off to macOS) with no `setAnimates:` override.
  No haptics or sounds.
  state and no animation. Its press feedback is the whole button drawn at 75 % while
  pressed: SwiftUI framework behaviour, measured on macOS 27 in light and dark,
  native highlight is on (overlay version 240, pending apply). The light
  buttons' shadow comes from the dimmed content, as SwiftUI's outer shadow does.
  next run-loop turn, which is within a frame of that, so it is unchanged.
  It has no tracking area or hover, so the press is AppKit's own highlight.
  Parc's `PCHTTPAuthButton` builds the same; nothing to add.

WEB16's surfaces (confirmed on its code):
  its motion is the system's.
- The status capsule keeps the token-guarded alpha fade at AppKit's default
  0.5 s debounce, the 1.5 s expansion delay, and unanimated style, side and
  theme changes.
  is no banner motion.
- "Share this tab instead" is the sidebar row's SidebarCellButton. It appears
  `SidebarRowActionButton` hover and press, which the Sidebar family recovered
  for Close (TAB19). Nothing to add.

Dispositions:
  (WEB17) keeps stock motion.
- **Client-certificate and capture pickers:** these are Chromium's stock UI in
- **Site Control Center button's boost-active tint:** Boosts are excluded
  scope.
  The Navigation owner holds the contract in the ledger's Web interactions
  handoff note.
- **Sad tab:** WEB17 shipped the instant swap and the reload link's
  pointing-hand cursor.
