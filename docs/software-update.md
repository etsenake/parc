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
  - **See What’s New** → `didClickViewReleaseNotes`. Its icon follows the
    `heart.circle.fill` for text notes, `play.circle.fill` once the view's
    `didClickViewReferralCode`.
  - the optional video-series row, SF Symbol `play.rectangle`

that is the release-notes row's icon.)

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
  and Extensions. `scripts/build.py` renders the page from
  `release-notes.json` (`Sources/WhatsNew/README.md`); a bundle without it
  disables the item. The command bar lists it
- **The page has no address.** It stays an ordinary file page, so reload,
  back, forward and session restore work, but its address is a path into the
  `WhatsNewPage` (`BrowserStore.swift`) recognises only the running app's
  page; another app's `WhatsNew.html` keeps its address. The sidebar and
  toolbar address show its title, and Copy URL (plain, Markdown, Quote),
  Share, the command bar's address edit and rows, row and Favorite help, link
  copies, bookmark export, the Archive, folder previews and the back/forward
  list omit it. At session load, a saved address of another install's page
  opens this build's page when that bundle's `Info.plist` still says
  `org.parc.Browser`. Chromium's own History page and captures of the page
  still carry the file address.
- **Feed.** Every release publishes the feed the embedded Sparkle reads,
  `SUFeedURL` = `parc-releases/releases/latest/download/appcast.xml`
  (`scripts/sparkle.py`). The release's appcast stage (`scripts/appcast.py`)
  signs the notarized ZIP with `sign_update --account parc` once that key's
  public half matches the app's `SUPublicEDKey`, verifies it with
  `sign_update --verify`, and writes one item. The item carries
  `sparkle:version` = `CFBundleVersion`, `shortVersionString`, the app's
  `LSMinimumSystemVersion`, the ZIP enclosure, and this version's notes as
  HTML grouped like the What's New page. The homebrew stage uploads it with the
  ZIP and DMG to the same public release and makes that release latest. The cask
  says `auto_updates true`, so `brew upgrade` leaves Sparkle-updated installs
  alone; installs from before Sparkle need one `brew upgrade parc` (or
  `--greedy`) to reach the first Sparkle build. Pipeline and recovery:
  [master-release](master-release.md).

- **Check for Updates…** sits in the Parc menu after Import from Another
  follows the phase: "Update Available…" while an update is available or
  ready, "Updating…" while downloading, preparing or installing, otherwise
  ("Download; Update; Check for Updates") and a Parc icon,
  item's tooltip.
- **Sparkle.** Parc embeds the pinned Sparkle 2.10.1 (`scripts/sparkle.py`,
  [packaging](../tests/Packaging/README.md#sparkle)). Only distribution
  and local test builds never replace themselves. Without `SUFeedURL` Parc
  never starts Sparkle: Check for Updates… stays in the menu and the command
  bar but is disabled, with the tooltip "Updates are only available in
  released builds".
- **Updater.** `SoftwareUpdater` (`Sources/ParcApp/SoftwareUpdater.swift`) is
  `SPUUpdaterDelegate`. Its state is `SoftwareUpdateSession`
  (`Sources/ParcCore/SoftwareUpdateSession.swift`), free of Sparkle and AppKit;
  `scripts/test-software-update.sh` tests it and the up-to-date window's
  label to its 11-point font's 13-point line height: AppKit pads the label to
  - A manual check shows the status window ("Checking for updates..."), then
    the up-to-date window, the update-found window, or the "Update error!"
    alert, following the table above.
  - A scheduled check (every 8 hours) downloads silently. Sparkle's
    `willInstallUpdateOnQuit` handler is kept, the phase becomes
    `readyToInstall`, and only the sidebar banner shows it. Restart and Update
    runs the handler; otherwise Sparkle installs on quit.
  - A scheduled find that isn't downloaded (automatic downloads turned off)
    also shows no window; the menu reads Update Available… and opens it.
  - Closing a status window cancels a check or download. A prepared update
    stays ready and still installs on quit. A downloaded update whose window
    is dismissed with Remind me Later also stays ready: Sparkle keeps it, and
    installs it on quit once it has begun installing.
    `--disable-software-updater` never start Sparkle: a disposable session
    shares the installed Parc's bundle identifier, defaults and Sparkle
    to update." error.

- **Update Complete** is the V2 summary banner in the shared slot: the same
  `SidebarBannerHost` as the auto-archive card (8 points in, directly above
  the bottom bar), with its spring/fade motion. One banner shows at a time:
  while Update Complete holds the slot the auto-archive producer leaves its
  - **When.** On the first launch whose Info.plist version
    (`CFBundleShortVersionString`, then `CFBundleVersion`) is newer than the
    one that last launched on this data, so Sparkle and Homebrew updates both
    count. The record (`release-notes-launch.json` in the data directory, so
    a disposable `--parc-profile` never shares it) stands in for
    `firstLaunchAfterUpdatedFromVersion` / `pendingReleaseNotesVersionToShow`
    / `lastReleaseNotesVersionShown`. A fresh install shows nothing. Data with
    no record but a previous run's `launch.json` (written by every release
    since 1.0.0) was last run by an older Parc, so it counts as an update;
    seeded test profiles without one stay fresh. Following the inferred rule
    above, a browser window whose sidebar isn't hidden records the version
    once it shows the banner, so it appears on that one launch; a launch that
    never shows it (setup, a hidden sidebar) carries it to the next. The
    shown version is kept, so a downgrade shows nothing and a later upgrade
    to that version, or an older one, doesn't show it again. A build without `WhatsNew.html` shows no banner.
    See What’s New retires the banner only when the window can open the page.
  - **Content.** "Update Complete!", then **See What’s New** (opens the
    bundled page in a new tab of that window and retires the banner) and
    **Share Parc** (Parc has no referral service: it copies
    `https://github.com/etsenake/parc-releases` and shows "Copied Link" with
    a share button; the banner stays). The close button retires it. The
    are text, so See What’s New keeps `heart.circle.fill`.
    8. Card: continuous radius 12, black/white at 0.9 (dark/light), shadow
    black at 0.15/0.05 radius 2 y 2, a white 0.1 stroke in dark inset −0.5.
    Header: title system 12, padding 4 vertical / 8 horizontal, centred, and
    leading once its width + 40 exceeds the header; a 1-point divider (white
    0.15 / black 0.07). Close button: 24 × 24, `xmark` bold 9 at 0.4 (1 on
    hover), hover plate 20 × 20 at 0.15/0.1 with corners 2/11/2/2. Rows:
    `HStack(spacing: 4)` of the icon and system-12 text, white 1 / black
    0.8, 16 high, leading, inset 8; 0.75 opacity until hovered, ease-out
    0.1 s. While the banner is hovered the release-notes row paints its text
    with `ButtonBackground`: two blurred (12, 6) capsules hue-turned ±40°
    over a base colour, brightness 0.6/−0.2 and saturation 1/2. The sparkles
    run for `update-complete-sparkle-timeout-in-seconds` (default 15,
  - **Not recovered** (Parc's values, open): the header height (24, the close
    button's), the gradient's base palette colour (Parc uses the theme's max-
    or min-contrast colour, else the accent colour when that is grey by HSL
    saturation) and its turn speed (4 s), and the sparkles' glyph, count,
    colour and timing (six `sparkle` glyphs in the base colour with the
    not modelled. Like the auto-archive card's native controls, each button
    is its own stop in the sidebar's key loop: an empty AppKit button laid
    over the SwiftUI one (`UpdateBannerKeyStop`) that draws its focus ring,
    presses with Space, is its VoiceOver element, and lets the pointer
    through. Tab runs close, See What's New, Share Parc; as for every
    sidebar button, AppKit stops on them only with Full Keyboard Access.

  is `readyToInstall`, and through `installing` so a page that cancels the
  quit leaves Restart and Update to retry; it takes the slot from Update Complete and the
  auto-archive card. The shared header reads "New Parc Version Available"
  `automaticallyDownloadsUpdates`, and **Restart and Update**, which calls
  `installAndRelaunch()`. The primary button is the theme base colour in a
  continuous radius-6 shape, with `ButtonBackground`'s gradient (blur 12,
  opacity 0.5) while the banner is hovered, a white 0.2 edge in dark, and a
  0.97 scale with 0.8 label opacity on a 0.2/0.6 spring when pressed [R].
  Parc's values (open): the label is 12-point medium in black or white by the
  the header's own fill (white/black at 0.1/0.03, doubled on hover, a 0.08
  edge) and the container's dark white-0.2 edge. Once the pointer rests on it
  passes) it expands for good on a 0.35/0.7 spring: the card background,
  divider and controls appear, and the slot grows. Parc's additions: the
  collapsed title is a button, so a click, Space with Full Keyboard Access
  or VoiceOver's press also expands it. Collapsed, the title is the only
  key stop; open, Automatic Updates and Restart and Update are. Opening it
  from the title's focus (Space or VoiceOver) moves focus to Automatic
  Updates. It collapses only when shown anew, after the host has taken
  focus back, so the title is the stop again. Unverified without a run: how the slot's growth and the
  spring line up (the slot resizes at once; the content springs inside it).

### Updater API

For the sidebar's update banners (UPD05). Everything is on the main actor.

```swift
SoftwareUpdater.shared.phase                       // SoftwareUpdater.Phase
SoftwareUpdater.phaseDidChangeNotification         // posted on the main thread, object: SoftwareUpdater.shared
SoftwareUpdater.shared.installAndRelaunch()        // Restart and Update
SoftwareUpdater.shared.automaticallyDownloadsUpdates  // get/set; the Automatic Updates checkbox
SoftwareUpdater.shared.checkForUpdates()           // the menu's action
```

A build without a feed never leaves `idle`, and `checkForUpdates()` does
nothing there.

`Phase` is `idle`, `checking`, `available(version:)`, `downloading`,
`preparing`, `readyToInstall(version:)` or `installing`. The version is
Sparkle's display version, e.g. "1.9.0".

- Show **update ready** while the phase is `readyToInstall` (Parc keeps it
  through `installing`, so a cancelled quit can retry); the notification
  fires on every phase change, so read `phase` when it arrives.
- `installAndRelaunch()` acts in `readyToInstall`, and retries in
  `installing` if a page cancelled the quit. It runs Sparkle's install-now
  handler for a background download or answers the ready window's reply. For
  a downloaded update whose window was dismissed, it starts a check that
  resumes the update and installs it without another window. Parc quits and
  Sparkle relaunches it.
- `automaticallyDownloadsUpdates` is Sparkle's own persisted setting
  (`SUAutomaticallyUpdate`, on by default). Turning it off makes later
  scheduled checks report `available(version:)` without downloading.
- Dismissing the banner needs nothing from the updater: the update stays
  ready and installs on quit.

### Appcast contract

For the release appcast's owner. The update-found window shows the item's
embedded notes only; Parc doesn't fetch `sparkle:releaseNotesLink`.

  appcast does. Without it the window says "Thanks for using Parc!".
- `sparkle:version` is `CFBundleVersion` (Sparkle compares it) and
  `sparkle:shortVersionString` the plain version, e.g. "1.9.0". The prompt
  reads "v1.9.0 (23)" from these two.
- The enclosure must carry `sparkle:edSignature` from the Keychain key
  (account `parc`) and its `length`; Parc's ZIP may keep its `development/`
  folder, since Sparkle finds `Parc.app` anywhere in the archive.

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
