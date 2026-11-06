# Local membership card — SET27

The first Settings toolbar item is the local display name. It precedes General
and opens a dedicated card pane; General's existing controls retain their own
pane. The previous exclusion of the entire Account pane was overbroad. Josh
explicitly included the complete local personalized card on October 28, 2026.
service membership and AI remain excluded.

## Recovered reference contract

SHA256 `4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
`components.py` had no prior card contract. The Swift type table, cross-reference
index and annotated-function helper resolved this work without a decompiler or
an additional REA session. Raw helper receipts remain outside Git at
`work/settings-coordination/set27/`.

  fallback image, display name, creation date, optional saved card state, blobs
  selectors, palette, mask and title. `StorableMembershipCardState`
  `StorableMembershipCard.json`, with a separate `membershipCardDataStore`
  dependency. Persisting a whole chosen design, rather than regenerating on
  every view construction, is an explicit part of the reference's design.
  padding, cream RGB `(1, .99, .92)`, palette-ink foreground, a 54-point shadow
  the **208×192** artwork, 23-point bold name and 11-point monospace title.
  and fallback gradient mapping `[1, 6, 5, 4, 3, 2, 8, 7]`. Shape table
  supplied saved design, otherwise chooses a nonzero palette, creates fifteen
  blob selectors in 1…14, generates a title and derives a mask from the name.
  This is why Josh selects Shape3; it is not a hash of the final character.
  zero remains part of the stored palette table but is not randomly selected.
  vocabulary is retained in `MembershipCard.swift`; it has no network producer.
  rotates by `2° × distance` around `(y, −x, 0)`. Hover uses spring response
  **.3**, damping **.95**, blend **.1**. The pane also wraps card changes in a
  the three 32-point controls in order: **Share**, **Download**, **Randomize**.
  The share picker owns an image, weak anchor and native `NSSharingServicePicker`
  card, with the first palette color under .4 white and a same-color .8-opacity,
  path instead of depending on the hover or a live animation frame.

personal-name toolbar item before General, portrait card and the three controls.
It did not change a name, randomize, share, download or change account settings.
Only the installed asset catalog was used for artwork extraction; behavior was
not re-traced in that version. Resource provenance is in
[`Resources/MembershipCard/README.md`](../Resources/MembershipCard/README.md).

## Parc ownership and local adaptations

`MembershipCardStore` is the sole live owner per normal application directory.
It atomically writes `MembershipCard.json` before publishing a new state. The
name starts from the local macOS display name, and the date is the actual first
explicitly identifies the date; the bottom labels say **PARC**. Service tenure,
anniversary stamps and company marks are omitted because Parc has no truthful
server membership to represent.

The **Display name** row's **Edit…** button replaces the account-management entry
point for this one included local action. The native sheet selects the name,
supports Return/Cancel/Escape, waits for native text composition to finish,
validates a single nonempty line of at most 64 characters, and preserves the draft
and error on failed saving. Name changes retain the palette, generated title,
blob selectors and creation date and recompute the name-derived mask.

Randomize generates a fresh title/blob configuration and a different palette
within 1…7, retaining name, mask and date. Existing malformed
or future-version data is preserved and disables changes. Reload permits retry;
an externally replaced file refuses a stale write. Shared windows observe the
same state, and a stale name sheet cannot silently overwrite a changed design.

The native card renderer uses the original non-brand masks, blob and Lines art,
plus the already bundled grain-1 texture. AppKit and Core Animation replace
SwiftUI. The card chrome and the 208×192 masked artwork are separate layers so
hover and key-window motion cannot stack a second silhouette on the static
bitmap. The chrome layer is not flipped again inside the flipped view: doing so
had drawn the artwork over the name and ticket.

background colour under fifteen tinted `AnimatingCardBlob` images (634×669
of 0…300 points on each axis (`Int.random(in: 0...300)`, rejection threshold
170) and a rotation of −360…360° about the artwork centre, under a 50-point blur;
while the window is key they ease to a second set and back over one 8…15-second
seeds them from the saved design, so the card rests the same way each time,
every Randomize is a new arrangement and colours, and the shared image matches
the screen. Blob textures are blurred once per colour and scaled per blob.
Hover uses the recovered pointer geometry, 1.05 scale and .3/.95 spring; Core
Animation has no separate SwiftUI blendDuration. Design replacement crossfades
the chrome and artwork for .4 seconds. These are renderer adaptations, not
purported original Swift source.

Settings window: the 240×360 card with Share/Download/Randomize 24 points below
(32-point controls, 40 apart, MemberCardActionButtonColor 43.5% grey), a
340-point column of grouped rows 34 points to its right, groups 16 apart, 56-point
rows with 16-point insets and 13-point type, and the whole stack centred in the
pane. Display name and Card created stand in for the excluded Account, Sync and
white/#656068, heart button in `PreferencesLoadableButtonBackgroundColor`) heads
the stack 38 points above the card whenever Parc is not the default browser; its
button runs the existing default-browser request. Row buttons use
`PreferencesButtonBackgroundColor`/`ForegroundColor` with 6-point corners.

Motion is scoped to the visible key Settings window. Pane detachment, sheet
presentation, close, app/key deactivation, hiding/minimizing and Reduce Motion
clear pointer transforms/highlights and remove repeating animations. The card is
one passive accessible image summarizing name, title and local creation date;
decorative layers never enter the focus loop. Buttons have native activation,
labels, tooltips and visible focus rings. No haptic or audio was invented.

Share passes only the current static card matte to the native picker; the user
selects any actual destination. Download captures that same **1236×1593 PNG**
(3×412×531) and writes only after an accepted native save panel. Panel cancellation,
Settings close and stale completions perform no write. Neither action changes
the saved design. No account URL, invite text or tracking token is attached.

## Host integration and checks

SET24's native toolbar/pane geometry stays authoritative. SET27 adds one first
personal-name item and one dedicated 680×560 pane, leaving General and every
existing control intact. SET26's `SettingsFocusState` automatically includes the
persistent native card controls, retains per-pane focus and restores the actual
control after sheets; its lifecycle/close guards remain intact. SET25's
`SettingsHoverButton` retains tracking lifetime while the card action subclass
owns its small hover/pressed treatment. Card animation is independent of shared
pane/modal transitions. These direct interfaces are integrated, not deferred
handoffs.

`bash scripts/test-membership-card.sh <artifact-directory>` uses temporary files
and inert AppKit components. It checks persisted creation/name/design readback,
repeated regeneration, word-derived masks, name validation, write failure,
stale/external replacement, corrupt/future preservation, shared ownership,
native accessible controls/key-chain construction, inactive detached cleanup,
chrome-only versus baked artwork in the 208×192 hole, fifteen live blobs in
a new arrangement and colours after Randomize on both the live layers and the
rendered card, and all four mask renders. It renders card/matte and light/
dark component images for visual inspection. No browser, real user profile,
GUI input walk, share destination or system preference is driven. Whole-module
SIL passed on the finished source (`set27-review-final`, 31 seconds, zero
diagnostics), as did the focused component check and exact-source independent
review. Review's Unicode separator finding is covered for both edited names and
saved names/titles. Receipts and checked source hashes stay under
`work/settings-coordination/set27`; six authentic production-generation previews
and their complete state manifest are under its `generated-previews` folder.
The four `card-1.png`…`card-4.png` files are controlled renderer mask fixtures,
