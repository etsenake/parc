# Recent-item switcher ownership

Real selections update a window-owned MRU order. A split is one item with its
original page identities, orientation and focused pane. Persisted access dates
seed unvisited items; later archive-protection timestamp refreshes do not reorder
visited items. Preview focus never changes the selected page or MRU order.

The configured Next Tab / Previous Tab actions use the existing native shortcut
priority route. Only an active switcher installs its held-key monitor. Release
commits once; Escape cancels; left/right and hover change preview focus. A late
renderer acknowledgment after modifier release selects without flashing a panel.
The exact held-input table is in [Held, repeated and interrupted input](#held-repeated-and-interrupted-input--kb22).
The ordinary presentation contains five cards and one hidden replacement.
Cycling never reaches that reserve. Closing temporarily hides the panel and
invokes the genuine tab-close transaction; only confirmed closure removes the
card, promotes the reserve and replenishes from available original items. The
focused position is retained or clamped to the final displayed card. Releasing
the held modifier while close is pending ends the session without selecting a
retiring page. A refused close retains the original cards if ownership remains
valid. Actual sheets and app/window deactivation end the session so their normal
event and security handling remains authoritative.
An accepted close that returns from a Favorite to another Space refreshes the
resumed cards with that actual destination Space's theme; it does not retain the
closed presentation's colors.

The nonactivating child panel retains the parent’s first responder. Parent,
page/document, profile, binding, selection, transfer, lifecycle and security
changes invalidate its ownership. Only visible cards and the focused card retain
thumbnail subscriptions. Chromium’s existing `ThumbnailTabHelper` produces web
images; missing images remain title placeholders. The native-profile predicate
enables that same helper on macOS without changing the global hover-card feature
or creating duplicate capture machinery. Delivery is deferred outside the
thumbnail callback so a shell action may safely destroy its subscription.

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
Retained `ModalItemSwitcher` metadata and instructions establish the weak parent,
REA records `ev_a8ca2495c2ed197ce54932c8ce30c08cedc04db780a0f87aa97a36116ec12d61`
and `ev_05d56d1701c7b882170de23d60f827203260461c4bb11330d8406138d4e0d3c2`
are corroborated by full-image assembly; recovered pseudocode is not original
source. The presentation below replaces the provisional card typography, material,
layout and specialized content with the recovered switcher variants.
with the final reserve hidden. The actual reducer witness points to
rebuilds the presentation after confirmed removal, with focused-index policy
`ev_c59a16bf189bafa0e4e9e537e8869d6acd7fe6bbb032923374e22520e6fcfcd5`,
`ev_b2c721cf1d945f7c098a35d684c5ac369fb457476ab7478aefc513df8804fba0` and
`ev_ae71a9c931f5a449450c3a82506d943eb142137a48dd3616ff1f182ba513a97e`
are bound to exact raw ranges and corroborated by full-image instructions and
Swift type metadata. Per-window persisted MRU seeding, native consent suspension,
refusal restoration and terminating on an actual sheet remain explicit Parc
is not established by its synchronous reducer. Card transitions are recovered
below. No browser functional tests were run.

## Original card surface and ownership — KB21

The native child now hosts the recovered SwiftUI row: a 190-point horizontal
scroll view with hidden indicators, 16-point padding and zero inter-card spacing.
Each 158-point card uses a 1.15 width/height ratio, 12-point interior padding and
spacing, 14-point medium captions, 6-point preview corners and the two attributed
preview shadows. The original focused-item CGRect supplies one 8-point rounded
fill: light palette focus at half opacity, or dark palette hover. There is no
extra heading, blue outline or inferred hover Close button. The original tap
gesture commits on release; the separate W-close path retains real page consent.

The background uses the original native popover material, follows-window state,
within-window blending and nonemphasized configuration. Its 24-point continuous
clip and PopoverShadow resource use the original 48-point radius, −24 vertical
offset and 120/144/168/144 shadow padding. The actual content remains centered in
its original parent, with 40-point screen containment; tiny-screen width fitting
is an explicit Parc adaptation. A focus change scrolls with the recovered
0.1-second ease-out and centres the card (`scrollTo(_:anchor: .center)`,
suppression is an explicit accessibility adaptation.

it is not an inferred enum variant. Exact raw-body REA record
`ev_cce3fa190182f18c8001143ae26dcf15b3c18a685ff50ce3d2d107d7bec6cedb`
is corroborated by full-image instructions and named resource records.

Preview subscriptions still belong to the original controller and original page.
The presentation reports actual visible item IDs asynchronously outside SwiftUI's
update, revalidates its same native window/generation, and retains only current
IDs. Hiding, detaching or retiring revokes pending work. Native/AX actions resolve
that same current ID and require the controller's original admission; the host
cannot become first responder. The inert component exercises rendered card
geometry/material, ID reorder/removal, visibility, focus preservation, refusal
and retirement. Its visible synthetic five-card layout exposes one real AX button
The focused component passes 29 assertions; the final combined 189-source app
check passes with zero diagnostics and unchanged inputs.

### Completed variants and transitions — October 28

KB21 is DONE under the source implementation rule. The finished producer reads
real split custom title/icon state, original page favicons, exact-profile cached
favicons for unloaded regular pages, recording state, and a retained Peek tied
to its original parent page. Private windows do not read another profile's icon
cache. An unloaded favicon reply validates its original tab URL/profile; Peek
thumbnail delivery requires the same live Peek identity, parent and native page.
Only displayed items and the focused item subscribe to original page previews;
the hidden sixth replacement never owns an input action or thumbnail lease.

The recovered card variants are:

- Custom split info: its own 16-point icon or a 16-point count badge (10-point
  bold text, 4-point corners), then the 14-point medium title. A split without
  custom info shows one favicon per component. A single item shows its favicon
  and title. Icon tint is the catalog's `ForegroundSecondary`.
- Snapshots: the image path uses high interpolation, antialiasing, zero-cap
  stretch resizing and a width-only frame aligned top-leading. It does not add
  an aspect-fit/fill modifier. A missing snapshot uses `Gray2`; Notes/Easels
  use their native template and a centered two-line 15-point semibold title.
  A private web page without a snapshot uses the incognito template. Templates
  use max-contrast color at 0.05 with a single-pane 2-point outline at 0.1.
- Pane arrangement: a single image has 6-point corners; multiple panes or a
  single template get 4-point corners and 4-point inset over `Gray1`. Each pane
  has `FullOpacityBackgroundPrimary` backing. Split panes keep the original
  orientation, spacing and shadow; the recording marker is 20 points with a
  3-point white ring, red pulse, shadow and −6/−6 offset.
- Peek: the original Peek snapshot appears inset 12 with 4-point corners and
  its own shadow, over the parent image dimmed by black at 0.5. No navigation
  is reconstructed to obtain it.
- Reserve and panel: the sixth replacement stays in the row at zero opacity,
  excluded from the visible panel width, focus, hit testing, accessibility and
  preview subscriptions. Its hidden state and index each use the recovered
  spring (response 0.15, damping 0.95). Confirmed removal promotes that same
  identity. The controller adds its child, closes it and sets its frame directly;
  those paths contain no custom alpha, scale or window animation. Parc explicitly
  disables AppKit window animation and keeps the existing consent suspension.

Retained REA records include
`ev_a5e03873f2db79516bf4ef521c839ceff578ce868f074094e521828b95eef6db`,
`ev_d1d1c364a1fed655fecd282ee875c62a803a54e1eb5d299bb4a970e403764830`,
`ev_49f682f8ee9c3cc5eb4c456589d7dcf5d3c7f271ea02bc8cca22dbd94f8a10d7`,
`ev_0ab344be68a2e9ceff283ead24873968247f429ebc06d87bd8796a386e172293`,
`ev_3f51d68cd15e41d7d41acb82fc2cb9f63c40aed417a9487ecaf4aac9f027584d`
and `ev_2bde10ca5a2a8c2e52c6e7d792ae3575a56b20c69a32a1e96c0df300a385c29e`,
corroborated by the retained full-image annotated instructions in
`work/claude-kbd-rea/kb21`. Pseudocode is not original source.
The three illustrations and palette data come from packaged resources;
[provenance](../Resources/RecentSwitcher/README.md) names the installed 1.170
catalog, used only for the assets. Excluded shared-service items have no producer.

The inert production presentation check passes 37 assertions, including the
sixth reserve's refusal and promotion, real rendered card bounds and all three
native PDF decodes. Light/dark variant captures were inspected at
`work/claude-kbd-checks/kb21-recovery/variants-{light,dark}.png`. They exercise
whole-module SIL receipt is `work/claude-split-checks/kb21-recovery-final.json`,
with input hashes in `work/claude-kbd-checks/kb21-recovery/final-inputs.json`.
No functional browser tests were run. Reduce Motion, tiny-screen containment,
asynchronous consent suspension, local Note/Easel backing and the existing
sidebar fallback favicon are explicit Parc adaptations. Whole-product runtime
and deep polish remain separate ledger requirements.

## Held, repeated and interrupted input — KB22

applies it with the original window/page ownership checks.

- **Start.** The monitor is installed only while some modifier of Next,
  Previous or the Control–backtick alternate is down; otherwise the session
  completes with selection at once (menu use, late renderer acknowledgment).
- **Monitored events.** Key-down and flags-changed only. Clicks are not
  monitored: a card's own tap chooses it, and a click elsewhere neither cancels
  nor commits. Hover focuses a card through the view.
- **Modifier changes.** Every flags-changed event is consumed. The session
  continues only while Shift/Control/Option/Command exactly equal one binding's
  modifiers, so Shift can be pressed or released mid-hold to reverse with the
  configured Previous chord. Releasing the binding, or adding any other
  modifier (Option, Command), commits the focused item. Caps Lock and fn are
  outside the comparison.
- **Keys, including auto-repeat.** In order: Next forward, Previous backward,
  Control–backtick backward, Left backward, Right forward, Escape cancels
  without selection, W closes the focused item. Every other key is consumed and
  the session continues; it no longer cancels and forwards the key to the page
  or menus. There is no repeat filter, so held Tab keeps cycling and held W
  keeps closing once each close is confirmed (W and cycling keys are swallowed
  while a close is pending).
  controller observer). A Space change ends the session without selection, as
  resign-key, sheet, minimize, close, binding revision, selection change and
  page retirement: these follow the native key-window/security reservation
  behind `canPresentTabSwitcher(in:)` and are explicit ownership adaptations.
  after confirmed closure (`updateModalItemSwitcher(confirmedItemIDsToClose:)`
  real consent is pending; refusal restores the same cards when the binding is
  still held and ownership is unchanged, and a modifier change during consent
  ends without selecting a retiring page.
- **Focus.** The panel is nonactivating and never becomes key, so the parent's
  first responder is never moved; nothing needs restoring on any exit path.

cases come from `ModalItemSwitcher.Action`/`DelegateAction` metadata.
Disassembly is in `work/claude-kbd-rea/kb22/`. Checks: 32 switcher model
assertions (`tests/RecentTabSwitcherTests.swift`), the keyboard-navigation
model suite and the whole-module app check. No browser was driven.
