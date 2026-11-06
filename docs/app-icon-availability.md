# App icon availability and discovery

Every approved Parc variant is discoverable in **Settings → Icon** and can be
selected immediately, offline. Original remains the default for all builds.
Account age, referrals and release channels do not change Parc availability.

## Reference evidence

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
`components.py find` found no retained component contract for
`AppIconPreferencesContentView`, `AppIconOptionView` or `AppIconClientImpl`.
The existing native-identity contract in [Settings](settings.md#app-icon) was
retained. `arctypes.py`, `arcidx.py` and `arcfn.py` resolve the remaining question;
no new heavy decompilation or second-version investigation was needed.

original, candy, hologram, neon, flutedGlass, schoolbook, colorful. The presence of
additional bundled artwork is not evidence of additional cases or unlock rules.
current icon, `customAppIconsAllAccessEnabled`, optional `redeemedInviteCount`,
optional `accountCreationDate` and the resulting icon/UI states.

three availability inputs plus the candidate icon. Its result type is
`availableByDefault`, `notAvailable`, `availabilityIsLoading` or `unlocked`.
The following conditions are recovered from that decision, not inferred from
asset names:

| Reference candidate | Historical condition |
|---|---|
| Original | Available by default without an account date. With a date, the all-access flag can classify it as unlocked. |
| Candy | Available by default when the account date exists; the all-access flag can classify it as unlocked. |
| Neon | With an account date and without all-access, requires 1 redeemed invitation. |
| Fluted Glass | Same path, threshold 5. |
| Schoolbook | Same path, threshold 15. |
| Colorful | Same path, threshold 50. |

With no account date, every non-Original candidate is unavailable. For the four
referral candidates, a missing invitation count produces loading, a count below
the threshold produces the required total, and a sufficient count produces
unlocked. All-access bypasses the invitation count after account-date and
Hologram eligibility handling. There is no browsing activity, elapsed local
usage, hidden click sequence or local achievement input in this decision.

availability decision for other candidates. It formats the unavailable referral
total as “Refer %d friend(s) to unlock.” This is distinct from the active-state
marker and the native selection application described in Settings.

the account date and all-access value with an invitation-count publication into
emits `AppAction.presentSidebarBannerNewArcIconUnlocked(availableAppIcons:)`
The banner is tied to this account/reward flow; it is not evidence of an
independent offline discovery requirement.

Raw helper receipts are retained outside Git in
`work/app-icons-checks/icon11/arc-1.122-availability.txt` and
`arc-1.122-types.txt`, under `/Users/josh/Documents/Codex/2026-10-23/re` as documented in
[Collaboration](collaboration.md#local-layout-and-evidence).

## Parc availability contract

exclusions take precedence over reproducing those historical gates.

| Parc choices | Included behavior |
|---|---|
| Original, Candy, Neon, Fluted Glass, Schoolbook, Colorful | Always selectable in the established reference pane order. |
| Hologram, Early Birds, Canary, Dev | Always selectable after those six as explicitly approved Parc choices. No eligibility or build-channel implication is derived from their names. |
| Every choice | Preview, current-icon state, atomic local selection, restoration and native identity application through the existing controller. |

Parc does not create a referral count, account creation date, server all-access
flag, locked/loading reward rows, sharing call to action or unlock banner.
Those are excluded service behavior rather than missing local unlock state.
All choices already being available also means there is no false “newly
unlocked” transition to announce. The permanent Settings Icon pane provides
discovery without manufacturing an achievement or storing a seen/unseen list.
The shared choice remains app-wide; Profiles and Spaces do not own it.

This is an explicit Parc availability adaptation, not a claim that all ten
service operations and environment-branding rules are outside the included
contract. The seven candidate decision above is fully resolved for ICON11;
there is no outstanding included unlock dependency.

## Native artwork integration and checks

By agreement with ICON09, `AppIconController.Variant.image` loads a bundled
`AppIcons/<id>.icns` when present. Both the picker and the live app/Dock/Finder
consumer receive that same native image with its size representations; the
non-running Dock plugin already reads the same ICNS. Source-only/inert previews
may use PNG when ICNS is absent. An existing unreadable ICNS reports artwork
failure and cannot silently fall back. This preserves the controller interface,
selection file and native identity owner. ICON09 owns exported size/optical
treatment; ICON10 owns picker interaction and motion.

`bash scripts/test-app-icon-controller.sh` builds only the production icon
controller and an inert AppKit harness. Its temporary catalog/export fixtures
check every approved choice and order, Original default, selection/restoration,
unknown-ID rejection, all native pixel sizes, the image delivered to the live
consumer, PNG fallback only when ICNS is absent, and corrupt-ICNS refusal. The
applier is injected, so no system icon, installed bundle, real preference,
browser process or user Dock state is changed. Whole-module Swift compilation
is recorded with this delivery; it does not establish browser runtime parity.
