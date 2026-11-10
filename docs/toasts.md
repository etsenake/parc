# Toasts

card in its own passive `ToastWindow` child, implemented once in
[settings](settings.md#press-again-presentation-and-original-window-lifetime))
keeps its native-router-owned lifetime but draws the same card.

`4e452201…9547`). Everything below came from the helpers (`arctypes.py`,
`arcidx.py`, `arcfn.py`) and direct reads of the binary's data; no new REA
decompilation was needed. Pixel values come from Josh's November 1 screenshot of

## Types

- `Toasts.ToastType` (73 cases) names every toast; `ToastController.ViewState`
  holds `[WindowToast]`, each with an id, type and `WindowToast.Location`
  (`windowContent(WindowContentID)`, `window`, `library`).
  position, location, duration, palettes and tap closures.
- `ToastContentOptions`: `.default(icon, label, subLabel, buttons)`,
  `.shortcut(leadingLabel, shortcut, trailingLabel)`, plus undoable,
  downloadRenamed, tracing and empty.
- `ToastContent.Button`: `shareButton(items: [URL])`, `confirmButton`,
  `actionButton`. Parc presents `shareButton`.

## Placement

- The factory stores position 3, `floatingTopRight`, for every toast
  frame for `.window` and `.library`. For `.windowContent(id)` it returns a
  frame only while `ViewState.layoutPresentation == .spaces` (key path pattern
  less the height of an attached `contentPanelViewSubject` view (field offset
  coordinates — the content's upper half.
  `(maxX−20−600, maxY−600)`, fromTopCenter `(midX−300, maxY−600)`,
  fromLeadingEdgeAtBottom `(minX, minY+20)`, floatingTopRight
  `(maxX−600, maxY−600)`.
- The card is laid out `frame(width:height:alignment:)` in that window, top
  top and trailing padding. `ToastWindow.ViewModel.maxWidth` is the window width.
- So a content toast sits 8 points in from its own pane's top-right corner,
  over that pane's header, in a single pane or either split pane. Josh's
  screenshot measures the card top 17 px below the pane ring and its right edge
  16–18 px inside it.
  presented `ModalV2WindowContentContainerViewController`'s own content
  content, scrim, card, controls and a snapshot ([peek](peek.md)); it has no
  title band, so its content starts at the card's top.
  observer registration; its selectors are child-window, colour, timer and menu
  calls. The child then moves with its parent window, as AppKit child windows
  do; resizing the window, toggling the sidebar or closing the pane leaves it
  where it was for the rest of its life.

Parc: `.content` toasts anchor to the given pane, else a presented Peek's card
below Parc's own title band (`PeekHostView.toastContentRect`), else the focused pane (`BrowserPane`, which includes its header). A hidden or
detached anchor uses the window placement, as the delegate's nil frame does.
`.window` toasts use the 600-point window placement. Both, and the Press Again

## Card

The dropdown body, palette and motion were recovered with the Press Again cue
(see [settings](settings.md#press-again-presentation-and-original-window-lifetime)):
horizontal/vertical padding 12/10, minimum height 42, continuous corner 12,
black 0.2 shadow radius 16 y 6, native material raw value 1 under the adjusted
Space colour at 0.8, the black/white 0.2/0.4 gradient and black 0.3 hairline,
spring response 0.4 / damping 0.7 / blend 0.1, scale and opacity from
`(0.5, 0.1)`.

leading column of label and sub-label with spacing 2, then the buttons. The
column gains 4 points of vertical padding only when there is a sub-label and at
The label-to-button gap measures 8.5 points; Parc uses 8.

  foreground colour. The screenshot's cap height (10 pt) and text width (131 pt)
  match SF 14 medium exactly.
  ([tooltips](tooltips.md)).
  semibold, the foreground at 0.33: system 11 semibold. That is about 2:1 on a
  light card, so Parc draws it at 0.7 (about 5.5:1).
  (semibold) 13. Its body sets only the font; neither it, the default content
  view nor the dropdown applies a colour, so the icon keeps the inherited
  primary colour of the app appearance, not the toast's ink. With a dark app
  and a light Space that is white on a light card (1.7:1), so Parc draws the
  whole card's content, icon included, in the toast's ink.
  palette: foreground and accessory foreground from `title` (class offset
  0x150), background from `backgroundExtra` (0xb0), accessory background from
  The label, sub-label, keycap (`ToastBigKeyView`) and share button read the
  hotkey pill nor the tracing view, so no Parc toast uses the semantic palette.
- Light or dark: the toast views only read the colour scheme. Nothing in the
  the card follows the app's appearance, not a Space's forced one. The tint and
  the light/dark button and label treatment come from the window's theme
  incognito window the static incognito theme's basic colour, which tints
  the card P3 (0.159, 0.277, 0.570) with white text
  ([private window theme](window-appearance.md#private-window-theme)).
  Parc gives the child its parent window's appearance, which is the app's (a
  private window is dark).

## Share button

  `Image(systemName: "square.and.arrow.up").offset(x: 0, y: -1)`
  helper `ToastBigKeyView` uses, system 13 — semibold; the background-based
  toast, 0.2 on a dark one; a 3-point inner stroke of white 0.2 (light) / 0.12
  (dark) fading to clear across the top quarter; a 0.5-point stroke of the
  foreground at 0.36 / 0.2; and a black 0.05 overlay while pressed, 0.025 while
- Measured: the button is 31.5 × 27.5 points, and its fill (221,222,231) equals
  white 0.6 over the card's (171,176,197).
  `popUpMenuPositioningItem:nil atLocation:NSEvent.mouseLocation inView:nil`.
  Parc uses the URL menu's own builder (`PaneShareMenu.menu(for:)`): the
  `sharingServicesForItems:` services for those URLs, each titled and imaged by
  the service, performing it with the same URLs.

## Lifetime

  copy; long values for three sync errors).
- A repeating timer at that interval dismisses on its first tick with no hover
  the default run-loop mode, so it waits while the share menu is open.
- Scrolling in the window or the toast dismisses (`ToastAnimator`'s
  `ScrollWheelObserver`); so does a 10-point vertical drag on the card. Parc
  ignores scroll events that move nothing, such as a finger resting on the
  trackpad.
  loop), so a new toast replaces the visible one. The Press Again cue is one of
  those toasts: presenting it closes an open toast, and a new toast consumes the
  cue's queued command, which retires it. A retiring toast stops taking input at
  copy types (cases 0, 1, 2, 13–16, 20, 21, 39), maxNumberPanes or the background
  clickToReveal, newSpaceCreated, unarchive, downloadRenamed and several others.
- Parc adaptations: closing, miniaturizing, a sheet and full-screen transitions
  close the toast at once; Reduce Motion drops the scale and the exit delay; the
  toast's label (and sub-label) is announced to VoiceOver at medium priority; a
  tappable toast is a VoiceOver button whose action is the tap; changing a
  observe nothing, so the move toast stays for its full time whatever the
  window or sidebar does; once its item is gone a click does nothing.

## Parc's toasts

|---|---|---|---|
| Copy URL (menu, keyboard, popup, command-bar result) | copyTabURL (1) | “Copied Current URL” + share | focused pane or Peek |
| Copy URL as Markdown | copyTabURL (1) | “Copied Current URL” + share | focused pane or Peek |
| Copy URL as Quote, shared-quote copy | copyTabURLQuote (2) | quote.bubble.fill, “Copied Link”, “With Quote” + share of the copied link | focused pane or Peek |
| Split pane menu Copy Link | copyTabURL (1) | “Copied Current URL” + share | that pane |
| Sidebar multi-item / folder link copy | copyItemURLs (0) | “Copied item links” + share of every link | focused pane |
| Press Again cue | webContentConsumedHotkey (17) | keycap + “again to …”, Edit accessory | window |
| Library: copy a capture's source address | copyTabURL (1) | “Copied Current URL” + share | window |

Copy toasts share the link just written to the pasteboard when it has the
page's scheme (the page URL, or a quote's text-fragment link), otherwise the
page's URL. A Peek's toasts sit on the Peek's content, below Parc's title band.

### How the new producers were found

every caller of the `ToastType` accessor were dumped; each case's location is
the tuple element at `+0x30`: two zero words for `.window`, the modal-or-focused
content's own reducer go through its `presentToast` delegate action. The Library
unbound Exit does not leave full screen, so Parc names the live Toggle Full
Screen binding instead. Its exact trigger branch in the core reducer
unless a page is full screen, and a page entering full screen closes it at once,
in either order. The Library's
`HomeScreenshotPageDelegateAction` maps `copyURL` to the URL copy toast and
`copyImage(path:)` to `copyFile`; `HomeDownloadsDelegateAction` has only
`didCopyDownload(at:)` (`copyFile`) and `onOpenSourceURL`. Every URL copy toast is
from the command bar, the window reducer, Home, web content and window content;
“[text]! Use [⌘Z] to undo.”: `UndoableToastContentView`'s body witness
`ToastBigKeyView` with the localized string “⌘Z” at −2 horizontal padding
Only Clear passes the `clearedTabs` completion toast to the shared begin-close
on the window's Undo without a toast. See [Close Undo](reopen-closed-tabs.md#close-undo).

## Checks

`bash scripts/test-toasts.sh` runs inert placement, content, framing (once, not
on resize), card geometry and scale-in place, hit-testing, replacement, timer
and hover hold, scroll, tap order, binding-change and parent-notification
checks on offscreen windows, plus each new toast's wording, the quote icon's
weight, the quote icon's and sub-label's measured contrast (a dark app over a
light Space and a light app over a dark Space) and the Peek's content region (measured on a stand-in anchor view with
a title band, not a live `PeekHostView`). The Press Again cue keeps
`scripts/test-shortcut-hint-presentation.sh` and `scripts/test-shortcut-cue.sh`;
the share builder is covered by `tests/BrowserToolbar`.

## Recorded gaps

- The card's tint is the Space theme's adjusted average. The offscreen renders
  use guessed themes and cannot draw the native material behind the card, so
  verified. Geometry, type, button and colour formulas are.
  Parc has no such panel and subtracts nothing; Josh's screenshot shows no
  subtraction for the split pane header.
- Pin and unpin toasts (“Pinned Tab to “[Space]””, “Un-Pinned Tab from …”) and
  “Auto archived %d tabs” have no producer the helpers could find; Parc does not
  show them.
  links. Parc's Notes and Easels are local and have no shareable link, so those
  toasts have nothing to copy.
  button, because Parc's capture catalog stores images without a file URL.
  `copyItemURLs` (“Copied item links”) and the plural `copyTabURL` (“Copied URLs”)
  describe selection copies, and the window reducer's selection copy calls the
  links”. The split pane Copy Link and Markdown routes into the builder were not
  isolated; both can only produce `copyTabURL`.
  the core reducer was not isolated. With Exit unbound Parc names Toggle Full
- “New Document Created” cannot appear yet: separating from a pinned tab needs a
  live page, and an internal document page has none.
- The background-tab affordance's tap and unarchive's “Click to view.” tap are
  inferred to select the tab; the window actions they send were not named.
  checkmark.shield.fill) never appears because Parc does not strip trackers.
- Hover feedback on the share button and clicks in the non-key child window are
  not runtime-verified; the timer's hover hold uses pointer geometry.
  Edit accessory's label) and the exciting-level particles are not recovered;
  Parc's are its own.
