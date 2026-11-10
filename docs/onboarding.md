# First launch and Replay onboarding

Parc owns a welcome and setup window before creating its first browser window.
The engine can initialize, but browser creation, Dock reopen, incoming URLs,
singleton relaunch, popup requests and download-parent creation wait for setup.
This guide describes current behavior; [product status](parity.md) and the
[backlog](backlog.md) track product work.

## Ownership and persistence

`OnboardingWindow` owns the presentation, desktop backdrop, animation deadlines,
video and welcome music. One host survives welcome phase changes. The backdrop
is an owned child window, not a browser or a macOS fullscreen Space. Closing or
terminating setup cancels timers, tears down owned presentation and stops music.
Leaving welcome allows an already-running backdrop dim to finish.

`OnboardingDraft` stores an atomic, private-permission `onboarding.json` draft in
the application profile directory. Persisted stage tags remain stable; explicit
stage ordering maps the former introduction card to import. A resumed setup
continues its saved stage; an interrupted welcome starts from the beginning.
A corrupt draft offers an explicit restart without erasing the browser session.
Closing setup never marks it complete; Dock reopen presents it again.

`BrowserStore.completeOnboarding` commits the chosen setup and completion marker
in one atomic session write. Failure restores the previous model and leaves a
retry. A repeated completion does not duplicate Favorites or bookmarks. Browser
creation must succeed before the welcome owner disappears and its draft is
removed. Deferred navigation is delivered after the browser reveal.

Completed native imports are separate transactions: accepting an import can
save data before final setup completion. Closing setup does not undo such an
accepted import or a system change already confirmed by the user.

## Included setup order and ad-blocker branch

The account-free sequence is:

1. Browser or HTML bookmark import, including conditional access/password pages.
2. Favorites.
3. Theme and Space name.
4. Ad blockers when applicable.
5. Default browser.
6. The finished card and **Get Started**.

Account, cloud and AI steps are excluded. No starter folder is seeded. Import
is skipped if no browser is found; HTML selection remains available through its
own action. Favorites follow the complete import. That position remains the
existing default pending the product ordering decision (OB17).

Back follows the actual conditional order. Import pages use **Do this later**
or **Skip for now** as appropriate. Theme Skip clears the first-launch color;
replay instead restores its starting theme. Favorites Skip selects no new
Favorites, preserving existing ones in replay. Back is hidden on the finished
card. The counter reflects the included setup steps rather than enum values.

The ad-blocker step is omitted only when the imported set is exactly uBlock
Origin; it also appears after an empty or skipped import. With no imported
blockers, **YES, block away!** is selected by default, with a No option. With
imported blockers, the first is selected, a Don't block ads option removes the
imported blockers, and **Use all imported ad blockers** preserves them all.
There is no unsupported native blocker option.

The accepted choice applies once after setup completes. Keeping one removes
other imported blockers from their recorded destination Profiles; keeping all
changes none. Yes requests uBlock Origin and falls back to uBlock Origin Lite
when Manifest V2 is refused. Native removal is restricted to known blocker IDs,
refuses external installs and can wait for an outstanding download. Installation
failure uses the browser's existing failure notice. Removal failures are currently
logged without a visible failure or retry notice.
These are actual engine operations, not consequences of simply selecting a row.

## Welcome presentation

The welcome uses the bundled Parc mark, typography, artwork and video; it has
no installed-browser resource dependency. Logo, headline and forward control
appear during the second welcome phase. The forward control leaves welcome in
one press. Welcome crossfades into setup over 0.2 seconds.

Video display waits for a usable frame and keeps the poster while preparing.
Late readiness from a canceled or replaced owner cannot change the new owner.
Closing, replaying or Reduce Motion cancels owned deadlines and layer motion.
Animations do not create additional browser windows or steal a new responder at
every welcome phase.

## Persistent setup presentation

The outer blue background stays independent of the inner card. The inner card
uses `ThemeRendererView` for the selected gradient, intensity and texture.
Headings, body copy, Space name, Back/Skip and step counter use the same `title`
color as sidebar page titles. Next uses `maxContrastColor` fill and
`backgroundExtra` ink. The picker follows the application's light/dark appearance.

Content crossfades in place. Titles and descriptions move 400 points in the
chosen direction, using their separate springs; there is no setup slide from
welcome. Reduce Motion retains fades and skips slides. The control-enabled
transition is 0.12 seconds. A stage change updates the existing owners rather
than rebuilding active text fields or native import controllers.

## Inline browser import owner and source rows

`BrowserImportViewController` is embedded in the setup card and shares its
window. `BrowserImportCoordinator` owns source discovery, exact source/Profile
identity, native admission, access/password continuation and bookmark acceptance.
The File → Import window wraps the same presenter for its originating browser.
See [browser import](browser-import.md) for native data and consent boundaries.

Selecting a browser begins cancellable discovery, not import. Next waits for a
usable result. Start fresh, switching source or accepting an HTML file cancels
the previous lease and advances its generation. Stale callbacks cannot restore a
discarded choice. The original setup Space/Profile remains the primary destination.
Supported data and extensions follow the selected browser's import; cookie
protection and engine policy remain native.

### Inline source profiles

There is no Profile-selection step: every readable source Profile comes along.
The browser's default Profile, or first readable one, goes into the originating
Parc Profile/Space. Other source Profiles reuse an eligible same-named destination
or create their own as they import. Every source extension follows its Profile.
Discovery alone imports nothing, and unavailable data is described truthfully.
Actions retain their original source and destination identities; later window
selection cannot redirect them. The File menu uses the same destination policy.

### Inline bookmark selection

The current picker begins with **every bookmark selected** and no description.
The previous five-bookmark history recommendation is no longer the setup policy.
Results retain source-profile sections, original bookmark identities, Select All,
folder selection circles and independent folder-label expansion. A folder circle
selects its entire subtree; its label expands it without changing selection.

Duplicate names and URLs retain their separate result IDs. Acceptance validates
the current result page and destination, then atomically saves selected leaves
and their ancestors. Top folders begin expanded. The list retains its light
appearance inside dark setup. Native folder controls and explicit action labels
provide the selection/expansion routes.

### Import progression inside setup

Bookmark selection precedes optional Safari password import. Empty bookmark
results omit that page. Accepting bookmarks saves them once; skipping passwords
does not reopen or duplicate the accepted results. Stop suppresses a later
password offer even when native completion wins the cancellation race; any
returned bookmarks remain selectable.

Setup's outer control uses **Next**. The menu importer retains its separate
password/bookmark order and final results. HTML-panel callbacks require
the same setup stage, importer instance and original window.

### Safari access inside setup

Safari and protected Chromium source directories use the existing Full Disk
Access owner. Setup displays genuine access status and system guidance in its
card, with the helper actions owned by the original import. Denial retains the
readable-only continuation; a successful button press is not evidence that
macOS granted access. A requested restart stores an explicit import intent.

Restart intents, source identity and replay restoration are covered in
[browser import](browser-import.md). They do not authorize silently importing
another source or changing a real system preference during a check.

### Password import inside setup

Manual Safari password import uses the actual CSV importer. File selection and
drop target the same owner, with source/destination and generation checks.
Next stays disabled until the required file import succeeds. Native upload-state
changes are immediate; the containing setup stage owns its transition.

The password export help panel belongs to this importer. Its Tab loop remains
inside the help UI and dismissal restores the original responder. Command-W
closes this panel before closing setup. Closing or changing stage invalidates
late panel and file callbacks; no password material is placed in the setup draft.

### Safari password choice and finish-owned installation

On macOS 14 and later, Safari setup offers **Add iCloud Passwords Extension**
(recommended, initially selected) or **Import Passwords from Safari** (manual).
Selecting a row changes pending state only. Next accepts it; the manual route
opens CSV import, while the extension route stores the exact destination Profile
and skips CSV.

An accepted extension request runs only after successful setup completion and
browser preparation; replay uses Finish. Skip, cancellation, stale ownership and
failed completion cannot install it. The request outlives the setup window. An
installation failure is currently logged without a visible failure or retry
notice. Chromium retains metadata, policy, signature and CRX validation. Child Profiles are refused because this path cannot provide parental
reauthentication. Older macOS versions keep the manual path.

### Import content and initial bookmark recommendations

Current source selection, access guidance, bookmarks, password choice and manual
export retain their own titles and context. Import cards use their source
backdrops. Bookmark selection is all-selected, with no history-ranked shortlist.
The Space name, counter, Favorite name tooltips, Stop Import and access helper
buttons are intentional Parc additions and must remain available.

## Favorites setup content and selection

The nine choices are X, Gmail, Google Calendar, Spotify, YouTube, Notion, Slack,
Figma and Outlook. New drafts select YouTube and Google Calendar. Selecting a
new choice inserts it at the front of the ordered selection; removing and
reselecting changes that order. Empty selection is allowed. Commit uses that
order rather than catalog order.

Draft migration preserves old selections and known URL aliases without turning
unknown URLs into new catalog choices. Replay selects existing Profile Favorites
and cannot remove them; clicking an existing Favorite beeps. Newly selected
Favorites are added only once at Finish.

One host retains the three-by-three grid and bundled light/dark artwork while
selection changes. Buttons expose their names and selected state, use the
pointing hand, and suppress inappropriate motion under Reduce Motion. A stale
hover exit cannot clear a newer tile's hover.

## Theme step editor composition

Setup embeds the shared `SpaceThemeEditorView` with its setup presentation:
**Click to pick a color**, a 340-point color pad, a 356×508 editor composed at
0.83 scale, a 16-point outer corner, and a parent-owned shadow. The surrounding
hit region prevents padding clicks from falling through the card. The sidebar
editor keeps its own size, copy and popover chrome.

The left-column Space-name field is a Parc addition. Theme and appearance update
live without replacing the editor. First launch saves the final choices with
setup; replay uses the reversible preview transaction below.

## Optional default-browser step and setup order

The initial choice is **YES, make Parc default.** The No option advances without
a system request. Yes starts the shared application-owned default-browser
controller and advances immediately; setup never waits for macOS or substitutes
a saved Boolean for actual system status. Settings reports the resulting status.
Replay follows the same rule.

The controller requests HTTP, then HTTPS only after the first succeeds. macOS
owns consent. Original request tokens reject repeated callbacks and prevent
duplicate operations. The choice itself survives draft restart. See
[default browser](settings.md#default-browser).

## Ready step, motion, focus, audio and haptics

The finished step shows the local membership card and **Welcome to Parc, name**,
with Share, Download, Randomize and Get Started. The card actions use the local
[membership-card owner](settings-membership-card.md). Download names the image
`<name>_Parc.png`; sharing includes the setup message. Confetti fires once per
window, after a short arrival delay, and is disabled by Reduce Motion. Successful
completion closes setup and reveals the browser without an extra reveal fade.

Entering theme focuses Space name; other setup steps focus their progression
control. Phase-only welcome updates do not steal focus. Each step's choices,
Back, Skip, card actions and Next participate in the native key-view loop.
Stage changes issue a layout-change announcement. Escape dismisses a presented
modal rather than navigating Back. Command-Q remains available during setup.

Welcome starts one bundled `AVAudioPlayer` cue at volume 0.3 with no loops.
Changing stage or application focus neither restarts nor truncates it. Close,
completion and termination stop it. Resuming a saved setup stage starts no cue;
a fresh replay starts its own. System mute/output volume remain authoritative.
Videos are muted. There are no added welcome, Next or confetti haptics; the shared
theme editor retains its own haptic behavior.

## General → Replay onboarding

**Settings → General → Replay onboarding is the only entry point.** It is a
protected Parc feature, uses the same production `OnboardingWindow`, and starts
from the initial P animation, backdrop and music. Its title, wording, counter,
stages and Get Started action match first launch. Repeated requests reuse the
current owner, without revealing it before an outstanding close transaction ends.

Replay starts with an in-memory draft seeded from the originating Space's name,
saved theme and existing Profile Favorites. It does not read/write/remove
`onboarding.json`, change the completion marker or consume first-launch education.
The original Settings controller and destination remain authoritative.

### Consent and browser restoration

Before welcome, the regular Settings browser flushes Notes and asks its native
pages for normal beforeunload consent. Refusal cancels replay. Only that regular
browser closes; its geometry, selection and history are retained without
archiving saved tabs. Other browser windows are hidden after approval, retaining
the same owners, including private windows and popups.

For a private or popup Settings owner, replay asks the full native page set for
consent, releases the close reservation, and hides that exact owner instead of
closing its context. If it closes itself while setup is open, or there was no
live browser owner, return creates an ordinary browser rather than reconstructing
a private context. Cancel and completion restore the saved regular browser and
reveal the surviving hidden owners.

Notes held for consent stay read-only until the transaction settles; refusal
restores prior editability. Quit waits for that close transaction. Browser-return
failure preserves the saved record and offers retry; it cannot replace the
session with the temporarily closed/hidden state or apply setup twice.

### Reversible previews and final commit

`previewSpaceTheme` changes the live originating Space, but all session writes
retain its saved theme until Finish. Continuous picker drags publish at most
every 50 ms without a session save or split-layout reconciliation. A different
editor's theme save/undo replaces the preview normally. New Spaces derived from
a previewed Space copy its saved theme. Application appearance uses an equivalent
unsaved `AppAppearance.preview`.

Finish calls `applyOnboardingReplay`, sharing first launch's atomic setup commit.
It applies only name/theme choices replay actually changed, preserving edits made
elsewhere to untouched fields. It saves appearance only if replay's choice still
owns the preview. Failure rolls back and permits retry.

New Favorites use saved-tab URL equivalence; new pinned HTML links use exact URL
equality, retaining distinct fragments/queries. Archived items do not suppress
new additions. Existing Favorites remain selected and cannot be removed. Other
tabs, Spaces, preferences and first-launch state remain intact.

Cancel, close or quit restores the saved theme and appearance unless another
editor has already replaced the preview. Actions already committed when performed
remain: explicit browser import, a confirmed macOS default-browser change, and
card Randomize. The replay draft alone is not an authorization to undo them.

### Access-restart continuation

A replay-owned Full Disk Access restart stores `onboarding-replay.json` and an
explicit replay import intent, never a first-launch draft. Relaunch consumes that
intent/draft once for the same Space/Profile, resumes import and reapplies its
unsaved theme and appearance. Without a matching draft, import uses its normal
window. Failed/canceled restart, a different intent, ordinary quit or a fresh
Settings replay removes the obsolete draft. Closing replay's importer cancels
only a restart it owns.

Incoming URLs and relaunch destinations queue behind setup and are delivered
once after completion or cancellation. Returning does not replay the original
launch destination or create duplicate activity/archive timers.

## Source and validation

The main owners are `OnboardingDraft`, `OnboardingExperience`,
`OnboardingStepMotion`, `OnboardingWindow`, `BrowserImportCoordinator`,
`BrowserStore.completeOnboarding` and `BrowserStore.applyOnboardingReplay`.
Relevant existing checks include:

- `scripts/test-onboarding.sh`: draft migration, defaults, ordering and commits.
- `scripts/test-onboarding-presentation.sh`, `test-onboarding-keyboard.sh`,
  `test-onboarding-theme.sh` and `test-onboarding-video.sh`: component behavior.
- Browser-import coordinator/access/password checks and replay lifecycle checks.
- The whole-module Swift check for material application changes.

Read check entry points and follow [AGENTS.md](../AGENTS.md); this guide grants
no permission to open apps or run browser fixtures. Favorites after import is the
remaining ordering decision in the [backlog](backlog.md#onboarding). Reduce Motion,
the Lite blocker fallback and no seeded starter folder retain the behavior above.
