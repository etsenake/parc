# Local membership card

The first Settings toolbar item uses the local display name and opens the
personalized card pane. General and all existing controls remain available.
The card is local: account authentication, cloud/sync, referrals, service
membership, telemetry and AI are excluded.

## Parc ownership and local adaptations

`MembershipCardStore` is shared per normal application directory. It atomically
writes `MembershipCard.json` before publishing a change. Initial name comes from
the macOS display name and CARD CREATED is the card's actual local creation date.
The card labels say PARC; they do not imply server membership or tenure.

Display name → Edit opens a native sheet, selects the name and supports
Return/Cancel/Escape. It waits for marked text and accepts one nonempty line of
at most 64 characters. Failed saves preserve draft/error. Renaming retains
palette, title, blob selectors and creation date, recomputing the mask from the
first Unicode scalar of the last word modulo four.

The persisted design includes title, palette, mask and fifteen blob selectors.
Randomize generates a new title/blob configuration, a different mask and a
different palette in 1…7 while retaining name and date. Malformed/future data is
preserved and refuses changes; Reload permits retry. External replacement and stale name
sheets cannot overwrite a newer design. All Settings windows observe one owner.

## Presentation and export

The 240 × 360 card contains 208 × 192 masked artwork, a 23-point bold name,
11-point monospaced decorative title and date ticket. Artwork resources and
provenance are documented in [MembershipCard resources](../Resources/MembershipCard/README.md).
Chrome and artwork are separate layers so hover never stacks a second silhouette.

The fifteen tinted blobs use saved-design-seeded attributes: scale 0.2…0.35,
offset 0…300 on each axis and rotation −360…360°, with a 50-point blur. While
key, they ease to a second set and back over 8…15 seconds. The resting image
therefore remains stable for a saved design; Randomize changes arrangement/colors.
Hover applies radial highlight, 1.05 scale and up to two-degree pointer tilt on a
0.3/0.95 spring. Design replacement crossfades for 0.4 seconds.

Share, Download and Randomize are 32-point controls beneath the card. Display
name and Card created appear in the adjacent grouped-row column. A default-browser
banner appears when appropriate and invokes the existing system request.

Motion stops on pane detachment, sheet presentation, close, deactivation,
hiding/minimizing or Reduce Motion. The card is one passive accessible image
summarizing name, title and local date. Decorative layers never enter the focus
loop; action buttons retain native labels, tooltips and focus rings.

Share sends a static card matte to the native sharing picker. Download uses the
same 1236 × 1593 PNG (3× a 412 × 531 matte), writing only after accepted save
selection. Cancellation, Settings closure and stale completions do not write.
Neither action mutates design, and no account URL or tracking token is attached.

## Host integration and checks

The dedicated pane is 680 × 560. Common Settings focus ownership preserves
per-pane focus and exact-control return after sheets; common hover ownership
handles lifecycle. Card animation is separate from pane/modal transitions.

`MembershipCardStoreTests` uses disposable files to cover persistence, name
validation, failed and stale writes, corrupt and future data, and shared ownership.
`MembershipCardTests` covers card actions, accessibility, arrangement, rendered
artwork and sharing. Renderer fixtures cover all four masks.
