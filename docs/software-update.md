# Software update

and the menu entries. The ledger rows are UPD04–UPD06 in
[parity](parity.md#software-updates-and-release-notes).

`4e452201…9547`). Facts come from the helpers (`arcidx.py`, `arctypes.py`,
halved to points). No new REA decompilation was used. Raw helper output stays
outside Git in `work/updates-research/` of the research worktree. That folder
also has a wrapper, `arcfnw.py`: `arcfn.py` crashes on a selector reference
that resolves to a bind.

Each item is marked **[R]** (recovered from the binary or its assets),
**[M]** (measured on the 1.172.1 screenshot) or **[I]** (inference).


`SoftwareUpdaterClient.CustomUserDriver`. It has three window controllers:
`checkingStatusController` and `downloadingStatusController` (both
`UpdaterStatusController`), and `newVersionController`
(`UpdaterWindowController`) [R].

### Windows

There are two window kinds. Both are borderless-looking, with a transparent
titlebar and a full-size content view.

| | Updater window (`UpdaterWindowView`) | Status window (`UpdaterStatusView`) |
|---|---|---|
| Style mask | `0x8003`: titled, closable, full-size content. `0x8001` (no close button) in minimum-version mode (`isMinimumVersionRequirement`) [R] | Same choice between `0x8003` and `0x8001` [R] |
| Backing / defer | Buffered, not deferred [R] | Same [R] |

The traffic lights are the system's. Minimise and zoom are present but
disabled, because the mask has no miniaturizable or resizable bit [R]/[M].

### Updater window layout


- **Left column.** A plain `NSView`, 270 wide, pinned to the view's top,
  leading and bottom edges. When there is no update, its trailing edge is the
  view's. When there is an update, it ends 12 before the release notes.
- **Release notes** (update found only). 398 × 394, inset 12 from the top,
  trailing and bottom edges.
  centred horizontally. It holds `NSWorkspace iconForFile:` for the app bundle,
  sized to 64 × 64 [R]. The visible icon art measures 51 pt [M], which is a
  64 pt icon's art.
  `convertFont:toHaveTrait:` [R]. Top = icon bottom + 12; leading and trailing
  match the column. Colour: default label colour [R]; #DDDDDF in dark [M].
  "1.172.1 (90370)" [M]. Centred, `FontSet.subLabel` (system 11), colour
  `ForegroundSecondary` [R]. That is black at 0.5 in light, white at 0.5 in
  background [M]. Top = title bottom; the version is leading/trailing to the
  title.
  centred, line spacing 4, wrapping, not single-line. Font `FontSet.label`
  (system 13), colour `ForegroundSecondary` [R]. Width 270 − 2 × 32 = 206,
  centred, top = version bottom + 20 [R].
  [R].
  - Borderless, button type 5. Font `FontSet.label` with the bold trait
    in light, white at 0.8 in dark, which measures #CCCCCC on black [R][M].
  - Background `UpdaterButtonBackgroundColor` (`ARC_SoftwareUpdaterClient`
    asset): white in light, black in Dark Aqua [R].
  outside the primary button on every side [R]. The image is from
  `NSButton`, type 5, bold 13, `ForegroundPrimary` tint, continuous corner
  radius 10, hidden by default [R]. Top = primary bottom + 20, centred [R].
    button's bottom 38 above the column bottom [R]. The screenshot measures
    37–38 [M].
- **Actions.** The primary button calls `didClickPrimaryButton` and the
  - A title field: `AppUpdate.title`, else "A new version is available"
    uses 32 and 20 [R].
  - The web view renders `AppUpdate.description` with this stylesheet
    12/8/16/0; `li` line-height 20px; links #458AFF; white background; in dark
    mode a black background with white text. With no notes it starts
    "<p>Thanks for using …" [R].

### Status window layout


- **Icon.** The same 82 pt view with its 64 pt icon, top + 54, centred.
  width. Top = icon bottom + 30.
  each side. Top = status bottom + 12. It starts indeterminate, with threaded
  animation, already animating.
  style, action `didClickCancel`. Top = progress bottom + 44, centred, with the
  same 0.15 shadow image 10 outside it.

### Copy and buttons per state

The left column is the `SPUUserDriver` callback (strings at

| State | Callback | Window | Copy | Buttons |
|---|---|---|---|---|
| Check ended | `dismissUserInitiatedUpdateCheck()` | Closes the checking window | — | — |
| Permission request | `show(_:reply:)` | Assertion: "should never be called, because we set SUEnableAutomaticChecks" | — | — |

**Remind me later** is Sparkle's dismiss choice. Its click sends an
`SPUUserUpdateChoice` through `completionBlock` [R]; that the value is
`.dismiss` is [I].

`--disable-software-updater` turns the updater off [R], via
`SoftwareUpdaterClient.isDisabled`. "Application is not allowed to update."
is its error [R].

### Automatic checks

and an 8-hour `SUScheduledCheckInterval` [R].

- **Silent download.** Scheduled checks call `checkForUpdatesInBackground`
  asserting `show(_:reply:)` is unreachable].
  as `installAndQuitHandler` [R].
  - It emits `SoftwareUpdaterClient.DelegateAction.willInstallUpdateOnQuit(AppUpdate)`.
    `SharedAppFeature.SoftwareUpdate` stores it as `availableUpdate`, which
    shows the sidebar banner [R for the types, I for the exact path].
- **Install on quit.** With no action from the user, Sparkle installs the
- **Restart now.** "Restart and Update" goes through
  which logs "Execute updater immediate installation handler" and runs
  the kept block [R].
- **Window vs banner.** Automatic updates only produce the banner. The window
  appears only for a manual Check for Updates… When the user checks while an
  update is already downloaded, Sparkle reports the found update with a
  non-zero `stage`, so the window offers **Install and Relaunch** [R for the
  stage branch, I for Sparkle's resume path].
  `lastUpdateWasAutoUpdate` and `autoUpdateBannerDismissalCount` [R for the
  names]. That the V2 banner's "Automatic Updates" checkbox toggles it, and
  its conditions (e.g. restarting after sleep), are [I] (open question).


shown at a time.

`State` holds:

- `content`: `updateAvailable`, `updateAvailableV2`, `updateSummary`,
  `multipleAdBlockers`, `downloadRenameItem`, `newArcIconUnlocked`,
  `windowsBuddyDay` or `autoArchiveEducation`.
- `presentationState`: `appeared(Date)`, `initial` or `dismissing`.
- `isHovered`, `newUpdateSummaryBannerEnabled` and
  `newUpdateAvailableBannerEnabled`.

### Placement and motion

- **Placement.** It is the same host and slot as the auto-archive education
  card ([archive](archive.md#recovered-motion-and-lifetime)).
  `AppearanceModifier` bottom-aligns the banner at its measured height [R].
  Parc's existing host (`SidebarView.swift`, `archiveEducationHost`) puts that
  slot 8 in from each side, directly above the bottom bar (Spaces / dock row),
  with media mini players above it. Update banners belong in that same slot
  and replace whatever card is there [I: one `content` at a time].
- **Motion** [R, shared]. Content appears only in `appeared`. It enters with
  `.move(edge: .bottom)` plus opacity on a spring (response 0.6, damping 0.4)
  and leaves with ease-in 0.25 s. The reducer keeps the space for 0.7 s before
  removal. Hover is tracked (`didHover`/`didUnhover`).
- **Colours.** Banners take the window theme's `SemanticColorPalette`
  (`SidebarBannerViewState.colorPalette`) [R]. Exact fills are an open
  question.
- **Dismissal.** Each update banner has a dismiss action, and analytics
  records the source as `auto` or `button`
  (`SoftwareUpdateBannerDismissSource`) [R]. So banners can also dismiss
  themselves; when is an open question.

### Update ready

second argument, which is [I] `newUpdateAvailableBannerEnabled`.

**V1 `UpdateAvailableState`** (title, narrowTitle, message, animation) [R]:

  ready!"; message "Click to restart". Comments: "Software Update banner
  title" / "… description".
  are both "Early Birds update ready!".
- Artwork: the Lottie file `update-heart-animation.json` in
  120 frames (2 s), with layers `heart` and `ring-1`. `Animation` is `loop` or
  `playOnce` (`preferredAnimationChanged`).
- Actions: `didClickBanner` (the whole banner is the restart target) and
  `didClickDismiss`.

**V2 `UpdateAvailableV2State`** (title, primaryButtonTitle,
autoUpdateEnabled, autoUpdateFeatureEnabled) [R]:

- Primary button "Restart and Update" (`didClickUpdate`).
  `SidebarBanner.SecondaryButton` with SF Symbol `checkmark.square` when on,
  `square` when off (`didToggleEnableAutoUpdate`). It is shown only with
  `autoUpdateFeatureEnabled` [I].
- `didClickDismiss`.
- The view keeps a `ParticlesState`
  (`SoftwareUpdateBannerUpdateAvailableView`) [R].

Both lead to `DelegateAction.didClickPerformUpdate`, then
`SoftwareUpdate.performUpdate`, then `installAndQuit` [R for the types].
[R], whose defaults are unknown:

- `software-update-relaunch-animation-enabled`
- `software-update-relaunch-animation-exit-duration`
- `software-update-relaunch-animation-enter-duration`
- `software-update-relaunch-animation-enter-shimmer-duration`

### Update Complete


| Field | First flag set ([I] `newUpdateSummaryBannerEnabled`) | Not set |
|---|---|---|
| narrowTitle | "Updated!" | "Updated!" |
| releaseNotesTitle | "See What’s New" | "What’s New" |
| narrowReleaseTitle | "What’s New" | "What’s New" |
| videoSeriesTitle / URL | Optional | Optional |

- Early Birds: title "Early Birds Updated!", narrowTitle "Early
  Birds\nUpdated!".
- The referral row appears only when the first argument is true. Otherwise
  `referralCodeTitle` is nil.
- Typographic apostrophe (U+2019) throughout.


- a header with a sparkle effect (`BannerHeaderView.SparkleConfiguration`);
- `RowView` rows (title, `systemImageName`, `isNarrow`, own hover):
  - **See What’s New** → `didClickViewReleaseNotes`;
    `didClickViewReferralCode`;
  - the optional video-series row, SF Symbol `play.circle.fill` →
    `didClickVideoSeriesLink(url)`.

recovered.

`SharedWindowFeature.TabCreationOptions` with a URL initialisation, and sends
[R]. That the tab opens in the frontmost window is [I].

### Gating

What is recovered [R]:

- `SoftwareUpdate.State.updateSummaryBannerEligibilityState` is
  `pending(startTime: Date)`, `awaitingAppSetup`, `ineligible` or `eligible`.
- `UpdateSummaryState.sparkleTimeout` is an `Int`.
  `lastReleaseNotesVersionShown`, `pendingReleaseNotesVersionToShow`,
  `firstLaunchAfterUpdatedFromVersion`, `lastUpdateWasAutoUpdate`,
  `currentUpdateAvailableSince`, `currentUpdateDownloadedSince`,
  `mostRecentUpdateDownloadTime` and `autoUpdateBannerDismissalCount`.
- `newUpdateAvailableBannerEnabled`, `newUpdateSummaryBannerEnabled`,
  `updateAvailableV2`, `updateAvailableState` and `appUpdateAvailable` are
  Swift field names (reflection strings), not defaults keys.

The working rule, until the open question below is answered [I]:

- **Update ready** appears when `availableUpdate` becomes non-nil (download
  finished, install on quit pending). It goes on restart or dismissal.
  `currentUpdateAvailableSince` / `currentUpdateDownloadedSince` time-stamp
  it.
- **Update Complete** appears once, on the first launch after an update. Then
  `firstLaunchAfterUpdatedFromVersion` is set and the running version differs
  from `lastReleaseNotesVersionShown`; `pendingReleaseNotesVersionToShow`
  carries a version across a launch that is still in app setup
  (`awaitingAppSetup`). Showing it or clicking See What’s New records the
  version in `lastReleaseNotesVersionShown`.

## Menus

From `Base.lproj/MainMenu.nib` (SHA-256 `c05560f6…1963`, the same in 1.122
and 1.170), decoded as data [R].

  Browser · — · Import from Another Browser… · **Check for Updates…** · — ·
  - Check for Updates… is item 1337. It goes to
    `SoftwareUpdate.State.availableUpdate` is non-nil (or a flag in the state
    is set), otherwise "Check for Updates…", and "Updating…" during an update.
    All three share the comment "Title for menu item to check for updates."
- **Help menu:** Getting Started · Essential Keyboard Shortcuts · **Release
  Notes · — · Troubleshooting ▸.
  - Release Notes is a help resource (selector name
    Opening it in a new tab is [I], following the other resource items.
  is shown is not traced.

Check for Updates and Release Notes were excluded from Parc's earlier menu
and command-bar work ([keyboard navigation](keyboard-navigation.md#excluded-by-the-ledger),
[command bar](command-bar.md)). Josh's request now brings them into scope.

## Parc

  Shortcuts, with no shortcut. It opens the bundled `WhatsNew.html`
  (`Bundle.main.url(forResource: "WhatsNew", withExtension: "html")`) as a
  file URL in a new tab of the key window, through the same path as History
  and Extensions. A build without the page disables the item, so it stays
  disabled until UPD06's build step bundles the page. The command bar lists it

## Open questions

1. **Banner gating.** The exact reads and writes of the release-notes and
   update-time keys, the `pending → awaitingAppSetup → eligible` transitions,
   `sparkleTimeout`, and when a banner dismisses itself (`auto`). Next step:
   [I] rule above.
2. **Banner visuals.** Card size, padding, typography, fills and the
   particle/sparkle header of `SoftwareUpdateBannerUpdateAvailableView`,
   `…UpdateSummaryV2View` and `RowView`. Next step: decompile the view bodies
   heart with "Click to restart", or V2 with "Restart and Update". Next step:
   settles it.
4. **Auto-restart.** The conditions in `AppState+AutoUpdate` (sleep/idle) and
5. **Shadow image.** The image behind the 0.15-alpha button shadow. Next step:
   `xcrun assetutil --info` on the owning bundle.
6. **Download text.** The download status text before the first progress
   callback, and the "Download manually" base URL. Next step: `arcfn.py
   `onSelectResource_releaseNotes:` in
   `feature-discovery/all-objc-methods.json` and annotate it.
8. **Relaunch animation and `--post-update-restart`.** Their defaults, and
