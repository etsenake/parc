# Toasts

`Sources/ParcApp/ParcToast.swift` provides one shared transient card through
`ParcToastPresenter`, `ParcToastPresentation` and `ParcToastCard`. Its passive child
window never becomes a second browser owner. The Press Again shortcut cue retains
native-router lifetime while drawing the same card.

## Placement

Content toasts use the given pane, otherwise the presented Peek's content below
its title band, otherwise the focused pane including its header. Hidden/detached
anchors fall back to window placement. The card is inset eight points from the
anchor's top-right corner. Window toasts use the parent frame's 600-point top-right
placement region. Geometry is captured once; resizing or sidebar changes do not
re-anchor a toast during its lifetime. The child moves with its parent.

## Card

The card has 12/10-point horizontal/vertical padding, minimum height 42, continuous
corner radius 12, black 0.2 shadow radius 16 at y 6, native material and a theme tint.
Its entry combines scale/opacity from 0.5/0.1 with response 0.4, damping 0.7 and
blend 0.1. Parent appearance determines light/dark treatment, including private
windows' dark appearance.

The label uses system 14 medium; secondary text uses system 11 semibold at 0.7
foreground opacity. The icon uses system 13 semibold. All card content takes the
card's foreground ink, including icons, so a light Space in a dark app does not
produce an unreadable inherited icon. Optional label/subtitle spacing is two
points, with extra vertical padding when a subtitle and action coexist.

## Share button

The square-and-arrow control has system 13 semibold ink, eight-point horizontal
padding, minimum height 27 and six-point corners. Light/dark fills, inner highlight,
foreground outline and hover/press overlays remain distinct. `PaneShareMenu`
queries actual AppKit services for the immutable URLs and dispatches those same
URLs; unavailable services do not get fabricated commands.

**Retry** uses that same button style with a text label. Like a tap, it removes
the toast before running its captured action, once.

## Lifetime

One toast is visible per window. Presenting another retires it; Press Again and
ordinary toasts share replacement semantics. Retired cards stop accepting input
immediately, with up to one second retained for exit. Reduce Motion removes the
scale and exit delay.

A five-second repeating timer dismisses on the first tick without hover or
keyboard focus. Default
run-loop scheduling waits while the share menu is open. Real scroll movement or
a ten-point vertical card drag dismisses; zero-motion trackpad events do not.
Tap removes the toast before invoking its captured action. Close, miniaturization,
sheets and fullscreen transitions dismiss immediately. A toast that finishes on
its own (timer, tap, Retry, Escape, scroll or drag) leaves the window idle, and the
browser window then shows any waiting import notice; replacement, those window
changes and outside dismissal do not count. The window's `ParcToastQueue` shows
import notices only in an ordinary, ready browser window, holds each back while
the previous one is showing, brings the next on that idle hand-off only while the
window is in front, and puts back one no window could show. Binding changes dismiss
only cards showing a shortcut. VoiceOver announces label/subtitle; a clickable
card, Share and Retry are separate named buttons that carry the actual captured
action.

## Keyboard

A toast never takes focus when it appears, so typing stays in the page or field.
While a toast with an action is showing, Command–Option–Shift–A (Chromium's
shortcut for focusing a popup that didn't take focus) or Control–F6 (macOS's
Move focus to the floating window, when that system shortcut leaves the key to
Parc) in its browser window moves focus into it, unless that shortcut belongs to
a Parc command, as when the person assigns it in Settings: the command wins,
even from inside the toast. A local key monitor catches the shortcut before the
page can, and only while such a toast is visible. Its stops are the whole card
when it is clickable, then Share and Retry; Tab, Shift-Tab and the arrow keys
move between them under the system focus ring, Space or Return presses the
focused one and Escape dismisses the toast. Share opens its menu under the
button and keeps focus in the toast. Retry, a clickable card, Escape, Control–F6
again and any Command shortcut hand focus back to the window, which keeps its
own focused page or field; a Command shortcut then goes on to the page and
Parc's menus as if pressed there. Each stop is an AppKit button element in place
of SwiftUI's own, so moving between them is an ordinary first-responder change
that VoiceOver announces once, by role and name. Clicking elsewhere just ends
the keyboard session, and if Parc goes to the background meanwhile, the window
gets focus back. The child window can become key only during that keyboard
session, so clicks never take focus.

## Parc's toasts

| Action | Content and destination |
|---|---|
| Copy URL/Markdown | Copied Current URL; share the copied link |
| Quote/shared quote copy | Copied Link / With Quote; share the text-fragment URL |
| Sidebar row/selection copy, split Copy Links | Copied Link or Copied Links; share every copied link |
| Copy shortcut education | Copy links faster by pressing, with live keycap |
| Press Again | Again-to-action cue and Edit accessory |
| Fifth split pane | Cannot Add New Pane |
| Move/copy to Space or folder | Move message; click reveals original item |
| Note/Easel move blocked by its other entries | Can’t move to the destination, then where the document is still used |
| Pin to folder | Pinned to the named folder |
| Separate pinned tab | New Tab Created, optionally naming its Space; click selects |
| Capture Copy | Copied Image |
| Zoom | Current zoom percentage |
| Enter browser fullscreen | Exit binding, falling back to Toggle Full Screen binding |
| Library file/image copy | Copied File; file-backed items can be shared |
| Copy Download Link/capture source | Copied Current URL; share link |
| Clear Archive | Archive Cleared |
| Put Back | Tab restored to the named Space; click to view |
| Clear Today | Cleared Tabs! Use Command-Z to undo |
| Import or setup failure | Import-data result, then extension changes Parc can't retry (saying why when it's known), then Couldn’t add/remove with Retry |
| Copy/drop failures | Actual Parc error wording |

Copy feedback uses the actual copied URL when it retains the page's scheme,
otherwise the page URL. Ordinary close/archive adds no Clear Today toast.
Share actions hand the selected URLs to the chosen system service.

## Checks

`scripts/test-toasts.sh` covers placement, one-time framing, geometry, hit testing,
replacement, timer/hover, scroll, tap and Retry ordering, keyboard focus and
keys, the focus elements VoiceOver hears, focus-shortcut routing and its yielding
to an assigned command, idle hand-off, the import-notice queue, extension notice
wording, binding/parent changes and theme contrast. The live-chord index check
covers which shortcuts Settings has assigned. Shortcut cue checks
retain their own lifecycle tests; BrowserToolbar checks cover share-menu
construction.

## Scope

Library-capture Copy has no Share button because the catalog supplies no file
URL. Local Notes/Easels have no cloud share link. Clean-link feedback is absent
because Parc does not strip trackers. New Document Created is unreachable from
pinned-tab separation, which requires a live browser page.
