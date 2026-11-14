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

## Lifetime

One toast is visible per window. Presenting another retires it; Press Again and
ordinary toasts share replacement semantics. Retired cards stop accepting input
immediately, with up to one second retained for exit. Reduce Motion removes the
scale and exit delay.

A five-second repeating timer dismisses on the first non-hover tick. Default
run-loop scheduling waits while the share menu is open. Real scroll movement or
a ten-point vertical card drag dismisses; zero-motion trackpad events do not.
Tap removes the toast before invoking its captured action. Close, miniaturization,
sheets and fullscreen transitions dismiss immediately. Binding changes dismiss
only cards showing a shortcut. VoiceOver announces label/subtitle; actionable
cards expose a button role and the actual captured action.

## Parc's toasts

| Action | Content and destination |
|---|---|
| Copy URL/Markdown, pane Copy Link | Copied Current URL; share the copied link |
| Quote/shared quote copy | Copied Link / With Quote; share the text-fragment URL |
| Multi-item/folder copy | Copied item links; share every exported link |
| Copy shortcut education | Copy links faster by pressing, with live keycap |
| Press Again | Again-to-action cue and Edit accessory |
| Fifth split pane | Cannot Add New Pane |
| Move/copy to Space or folder | Move message; click reveals original item |
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
| Copy/drop failures | Actual Parc error wording |

Copy feedback uses the actual copied URL when it retains the page's scheme,
otherwise the page URL. Ordinary close/archive adds no Clear Today toast.
Share actions hand the selected URLs to the chosen system service.

## Checks

`scripts/test-toasts.sh` covers placement, one-time framing, geometry, hit testing,
replacement, timer/hover, scroll, tap ordering, binding/parent changes and theme
contrast. Shortcut cue checks retain their own lifecycle tests; BrowserToolbar
checks cover share-menu construction.

## Scope

Library-capture Copy has no Share button because the catalog supplies no file
URL. Local Notes/Easels have no cloud share link. Clean-link feedback is absent
because Parc does not strip trackers. New Document Created is unreachable from
pinned-tab separation, which requires a live browser page.
