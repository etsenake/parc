# Software updates

Released Parc builds use Sparkle with Parc's own update window and sidebar
banners. Development/disposable builds do not update themselves. Release creation
and publication are covered by [the release guide](master-release.md); bundled
notes generation is covered by [What's New](../Sources/WhatsNew/README.md).

## Parc

`SoftwareUpdater` owns `SPUUpdater`, `SPUUserDriver` and `SPUUpdaterDelegate`.
`SoftwareUpdateSession` is the AppKit/Sparkle-independent state model. Distribution
packages carry the pinned Sparkle framework, feed and verification key. Without
`SUFeedURL`, Sparkle never starts and Check for Updates remains disabled with
“Updates are only available in released builds.” `--parc-profile` and
`--disable-software-updater` also block updater startup.

## Menus

Check for Updates appears in the Parc menu and command bar. Its title becomes
Update Available when an update is available/ready, and Updating while downloading,
preparing or installing. Help → Release Notes and the corresponding command open
the bundled What's New page at `parc://whats-new` in a new tab through
`openExactAddress`, without search-engine initialization or an intermediate
blank-page route.

## Updater windows

Manual checks show checking, up-to-date, update-found or error presentation.
Scheduled checks every four hours download silently; ready updates show a sidebar
banner. Closing a status window cancels checking/downloading. Prepared updates
remain ready and can install on quit. Remind me Later dismisses the prompt without
throwing away a downloaded update.

| State | Presentation and action |
|---|---|
| Checking | “Checking for updates...” and Cancel. |
| Up to date | Parc title/version, “Your browser is up to date”, Close. |
| Available | Installed/new versions, embedded notes, Download or Install and Relaunch, Remind me Later. |
| Downloading | Byte counter, progress and Cancel. |
| Preparing | “Preparing…” with actions disabled. |
| Ready | “Ready to Install”, full bar, Install and Relaunch. |
| Installing | Installing status, actions disabled. |
| Failure | Update error alert with acknowledgement and manual-download action. |

The up-to-date window is 270 × 341; status is 270 × 334. Update-found adds a
398 × 394 notes pane with 12-point gaps/insets. The icon occupies an 82-point
view, primary button is 170 × 48 with radius 10, and labels use native light/dark
colors. Windows use transparent titlebar/full-size content with native close
behavior.

`SoftwareUpdateDownloadProgress` accumulates bytes and publishes counter/bar
snapshots at most every 100 ms. It reserves equal-width digits, fractional zeroes
and completed-count width so decimal/total alignment stays stable. Unknown totals
remain indeterminate; zero does not erase a known total, while corrected positive
totals are honored. Native animation mode changes only at state transitions.
Closing, extraction, failure or a new transfer cancels pending refreshes.

## Automatic restart

Parc periodically checks whether a background-downloaded update can install.
`AutomaticUpdate` tracks Mac/display sleep, screensaver and screen-lock events;
the away period begins with the first and ends when the last stops. Lock/saver
notifications deliver immediately even while Parc is inactive.

Checks run every 300 seconds of awake uptime. An away-event period qualifies
after 300 seconds, so installation is considered approximately five to ten
minutes after it begins. Sleeping time does not count. An additional idle rule
qualifies a Mac with no keyboard/pointer input for 30 minutes, provided no process
holds a display-sleep-prevention assertion. Failure to read that assertion is
conservatively treated as active use.

Automatic installation requires all of the following, rechecked after a successful
HEAD request to the feed (60-second timeout):

- Automatic Updates enabled and a background install-now handler available.
- No protected live page: audio (including muted), capture/mirroring, PiP, VR,
  active forms/edits, or active/ducking/suspended media sessions. Paused video
  therefore also prevents automatic restart.
- No pending/running/paused download, sheet, modal alert or private window.
- At least three seconds without input and the Mac still qualifying as away.

Manual-check downloads never install automatically merely because their window
was dismissed. The normal quit path retains real beforeunload consent; a refusal
can retry later. Explicit Quit's warning is not synthesized for update restart.
Automatic Updates controls Parc's `ParcAutomaticallyInstallsUpdates` preference,
on by default. Turning it off preserves silent downloads and explicit/quit-time
installation. A previous disabled-download preference is migrated into disabled
automatic installation. The banner is the current control; there is no duplicate
Settings checkbox.

Input idle uses IOHIDSystem `HIDIdleTime`. Real or synthetic keyboard/pointer
activity in the HID stream resets it; a running agent or a power assertion alone
is not keyboard/pointer activity. Missing/zero idle information is treated as use.

## Sidebar banners

One `SidebarBannerHost` slot sits eight points in above the bottom bar. Update
ready takes priority over Update Complete and auto-archive education. Education
remains armed while another banner occupies the slot.

### Update ready

The collapsed New Parc Version Available header expands after 300 ms hover, or
click/Space/accessibility press. Expansion persists until a newly shown banner.
It exposes Automatic Updates and Restart and Update. It remains through installing
so a cancelled quit can retry. Keyboard focus moves from the header to Automatic
Updates when expanded by keyboard/accessibility. Buttons use the current Space
palette; labels keep readable black/white contrast.

### Update Complete

The banner appears on the first eligible launch after a newer bundle version,
including Homebrew upgrades. `release-notes-launch.json` is data-directory scoped;
disposable profiles do not share it. Fresh installs show nothing. Setup/hidden
sidebar can defer display until a later launch. Recorded shown versions prevent
repeat banners after downgrade/re-upgrade. Missing bundled notes suppress it.

See What's New opens `parc://whats-new/#from=<replaced>&to=<installed>` and
retires the banner only after admission to open succeeds. The page marks skipped
releases only when `to` matches its own version. Share Parc copies the public
release URL and leaves the banner open; Close retires it. There is no referral
service or vendor-video row.

The card has radius 12, shared spring/fade motion, a close control and separate
native key/accessibility stops for Close, See What's New and Share Parc. Notes
text stays black/white, including hover, so pale Space themes remain readable.
Decorative sparkles are bounded to 15 seconds.

## What's New page ownership

`scripts/build.py` creates self-contained `WhatsNew.html` from
`release-notes.json`, including release history, and bundles it in the app's
resources. The page has its own internal address, `parc://whats-new`, so the
bundle path never reaches the address field, Chromium History, Copy URL, share,
bookmarks, exports or capture attribution. It behaves like Parc's other internal
pages: the toolbar shows the address, Copy URL copies it, and History skips it
because Chromium never records `chrome://` visits.

The engine owns the address. `RegisterWhatsNewWebUI` in
[parc_branding.cc](../Engine/ParcChromium/parc_branding.cc) runs from the
browser-main `PreBrowserStart` callback, after Chromium registers its own
`chrome://whats-new` controller and before any window opens, and replaces that
controller with one that reads the outer app bundle's `WhatsNew.html` off the
main thread. A request whose path is anything but `/` returns nothing. The
update range after `#` is not part of that path, so See What's New's
`#from=…&to=…` and a restored tab carrying it open the page. Chromium's WebUI
request path includes the fragment, which is why the source checks the URL's own
path instead. The data source keeps Chromium's WebUI header policy (no frames,
plugins or framing, Trusted Types) except its script rule, so the page's own
policy, which allows only its inline script by hash and no network, governs
scripts.

Tabs saved with a Parc bundle's page file, from this install or an earlier one
whose bundle still carries Parc's identifier, restore at `parc://whats-new` and
keep a saved update range. Their earlier back/forward list is not restored,
because it was saved under the file address, and other tabs' restored
back/forward lists drop this install's page file. Earlier visits Chromium History
recorded under the file address stay out of command-bar suggestions until History
expires them.

### Page presentation

What's New uses the shared native page host. It settles changed page dimensions
before showing content and retains the display connection across reuse and
suspension, so a rendered static page does not depend on later input to appear.
See [page compositing](page-compositing.md) for the handoff and presentation rules.

### Updater API

The main-actor interface includes `phase`, `phaseDidChangeNotification`,
`checkForUpdates()`, `installAndRelaunch()`, `automaticallyInstallsUpdates`,
`installsWithoutWindow` and the `activity` snapshot supplied by `AppDelegate`.
Phases are idle, checking, available, downloading, preparing, readyToInstall and
installing. Listeners read current phase after notification. Install executes the
retained background handler or ready-window reply and supports retry after a
cancelled quit.

### Appcast contract

The public latest-release feed accompanies verified ZIP/DMG assets.
`scripts/appcast.py` signs the notarized ZIP only when its public key matches the
app's `SUPublicEDKey`, verifies that signature and emits an item containing:

- `sparkle:version` from `CFBundleVersion`, display version and minimum macOS.
- Exact public ZIP URL, length and EdDSA signature.
- Title and HTML notes in `<description>`; the app does not fetch an external
  `sparkle:releaseNotesLink`.

The Homebrew cask marks `auto_updates true`; Sparkle and Homebrew share the same
published versioned artifacts.

## Validation

`bash scripts/test-software-update.sh --inert` covers the session, restart policy,
byte counting and actual status controls without windows/web views. The full
script's notes-layout check creates a WKWebView and is outside the current inert
check scope. Page-generation and native-host regressions cover bundled resources
and layout ownership.
