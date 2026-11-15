# Membership-card artwork

These images are Parc's own drawings for the local membership card. See
[membership card](../../docs/settings-membership-card.md) for behavior.

`Shape1`–`Shape4` are 416 × 384 alpha masks at 2× for the 208 × 192-point
artwork: a ticket with four round bites along its top, a drop with one square
corner, a panel split by an S-shaped gap, and a pointed arch.
`AnimatingCardBlob` (1268 × 1338 at 2×) is a smooth seven-lobed blob that the
card tints and blurs. `Lines` (116 × 134 at 2×) is a block of diagonal stripes
for the date ticket. All of these were drawn as vectors and rendered with 8×
supersampling.

`fallback-gradient-1`…`8` (956 × 772 at 2×) are soft gradients mixed from each
card palette's three colors, numbered through
`MembershipCardState.fallbackNumbers`. Parc supplies the card's text and
identity; no branded stamp, other app's mark, asset catalog or executable is
bundled.

The live card also uses `Resources/Onboarding/grain-1.png`, described in the
[welcome resources](../Onboarding/README.md). All files resolve within Parc's
bundle, and `scripts/build.py` copies the Resources tree. The inert card
component check covers all four masks and all gradients.
