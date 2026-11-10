# Membership-card artwork

constructors reference the same resource keys. See
[membership card](../../docs/settings-membership-card.md) for behavior.

The bundled PNGs contain Shape1–Shape4 (416 × 384 at 2×), AnimatingCardBlob
(1268 × 1338 at 2×), Lines (116 × 134 at 2×), and fallback-gradient-1…8
(956 × 772 at 2×). The source vectors were rendered natively to PNG. Parc
complete asset catalog or executable is bundled.

The live card also uses `Resources/Onboarding/grain-1.png`, described in the
[welcome resources](../Onboarding/README.md). All files resolve within Parc's
bundle, and `scripts/build.py` copies the Resources tree. The inert card
component check covers all four masks and all gradients.
