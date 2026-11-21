# First launch and Replay onboarding

Parc owns a welcome and setup window before creating its first browser window.
The engine can initialize, but browser creation, Dock reopen, incoming URLs,
singleton relaunch, popup requests and download-parent creation wait for setup.
This guide describes current behavior; the [product guide](product.md) keeps its
product decisions and the [backlog](backlog.md) holds unfinished work.

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
Setup left on Favorites while the import still has pages, or on those pages,
resumes at the import so none of them is skipped.
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

1. Browser import: choosing a browser or skipping, plus Full Disk Access
   guidance when the browser's files are protected.
2. Favorites, shown the moment the chosen import starts.
3. The rest of that import, when anything is left: its progress page while it
   still reads, then bookmarks, Safari's password choice and the Safari,
   Firefox or Zen password file.
4. Theme and Space name.
5. **Find your frame**: window frame thickness.
6. Ad blockers when applicable.
7. Default browser.
8. The finished card and **Get Started**.

Account, cloud and AI steps are excluded. No starter folder is seeded. Import
is skipped if no browser is found. Choosing Safari's card also offers **Use
Safari’s export file instead…**, which imports the file Safari's own export
saves; see [browser import](browser-import.md#safaris-export-file).

Favorites sits right after the browser choice so people pick sites while the
import reads. Access guidance comes first because the import cannot start
without it; pages that need imported results follow Favorites in their usual
order. If the import is still reading when Favorites is done, its progress page
with **Stop Import** stays until the next page or the end. When it finished with
nothing left, or failed, Favorites goes straight to theme; failures still show
the import notice in the browser. A skipped import, or no browser found, goes
straight to Favorites and then theme.

The counter counts included setup steps, not enum values, and each of the
import's later pages is a step of its own. Until an import starts, the total
holds only the steps everyone sees. From Favorites on, it adds the pages the
import still expects: its bookmarks while it reads or once some are found, and
for Safari, Firefox and Zen the password choice or file, following the selected
choice. The progress page counts once it shows. The counter settles when a page
appears and holds still while it stays up, so the total changes only on moving
to another page, by the pages that turned up or dropped away. Pages already
passed keep their numbers, so Back and Next step over a finished progress page,
and theme keeps its number after a trip Back to Favorites. A page backed out of
drops away unless it is still coming, and another import starts the count
afresh, counting its own pages even while it waits for the last one to finish.
A setup resumed after the import keeps those pages in its count.

Back follows the actual order. From Favorites it returns to the browser choice
with the import kept: a running import keeps running there with **Stop Import**
and Next returns to Favorites; finished results wait behind the browser cards,
and choosing another browser starts over. Safari's passwords-only path returns
to its access page instead. The import's later pages go Back to Favorites unless
the import's own Back leads to another of them, such as password choice to
bookmarks; theme goes Back to Favorites. Import pages use **Do this later** or
**Skip for now** as appropriate. Theme Skip clears the first-launch color;
replay instead restores its starting theme. Frame Skip keeps the saved thickness.
Favorites Skip selects no new
Favorites, preserving existing ones in replay. Back is hidden on the finished
card.

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
leaves blockers that an administrator's policy or another app installed, and
can wait up to ten minutes for an outstanding download; a blocker still
downloading then counts as not removed. Each blocker is removed separately, so a
failure is attributed to the right one. The browser window shows **Couldn’t add
uBlock Origin Lite** or **Couldn’t remove** with the blocker's name; when that
blocker was being removed from more than one Profile, the notice says which, as
in “from Work and School” (beyond three, “and 2 more”). Failures that arrive
together share one notice: a single failure is named and several are counted,
and a failed add sits above a failed removal. Its **Retry** runs every listed
install or removal again; one that fails again brings the notice back. The
import's own extension failures work the same way (see
[browser import](browser-import.md#sequencing-and-cancellation)), and their
retries stay with the import's installs, never setup's. They also follow the
ad-blocker choice: after keeping just one, adding uBlock Origin or choosing not
to block ads, the setup import's other known blockers get no notice and Retry
never re-adds them, so a retry that works still leaves only the chosen one; Use
all imported ad blockers keeps every Retry. Imports from the File menu keep
theirs. Each setup and Replay keeps its own choice, so a download from an
earlier setup that fails after a Replay begins still follows that setup's
choice.

When the engine knows a change can never work, the notice says why instead of
offering Retry: “Kept installed by your administrator” or “by another app” for a
removal, “Blocked by your administrator”, “Needs a parent’s approval” or
“Flagged as unsafe” for an add. Those, and failures Parc can't retry at all,
such as iCloud Passwords refused by Apple's helper, get earlier notices without
Retry, one per reason, and an import-data failure notice goes before them all.
Each waiting notice appears once the one before it finishes on its own (time, a
click, Retry, Escape or a scroll) while the window stays in front, otherwise when
the window next comes forward. These are actual engine operations, not
consequences of simply selecting a row.

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
usable result. Start fresh, switching source or choosing Safari's export file
cancels the previous lease and advances its generation. Stale callbacks cannot restore a
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

Bookmark selection precedes the optional Safari, Firefox or Zen password file.
Empty bookmark results omit that page. Accepting bookmarks saves them once;
skipping passwords does not reopen or duplicate the accepted results. Stop
suppresses a later password offer even when native completion wins the
cancellation race; any returned bookmarks remain selectable.

Setup's outer control uses **Next**. The menu importer retains its separate
password/bookmark order and final results. Export-file panel callbacks require
the same importer instance and original window.

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

Safari, Firefox and Zen password files use the actual CSV importer. Firefox
and Zen have no iCloud Passwords choice, so they go straight to the file page,
whose steps and help panel follow Firefox's own export: the ☰ menu's Passwords
page (Zen: type `about:logins`), then ⋯ → Export Passwords…, saving
`passwords.csv`. File selection and drop target the same owner, with
source/destination and generation checks.
Next stays disabled until the required file import succeeds. Native upload-state
changes are immediate; the containing setup stage owns its transition.

The password export help panel belongs to this importer. Its Tab loop remains
inside the help UI and dismissal restores the original responder. Command-W
closes this panel before closing setup. Closing or changing stage invalidates
late panel and file callbacks; no password material is placed in the setup draft.

### Safari password choice and finish-owned installation

When Apple's helper admits Parc (below), Safari setup offers **Add iCloud
Passwords Extension** (recommended, initially selected) or **Import Passwords
from Safari** (manual).
Selecting a row changes pending state only. Next accepts it; the manual route
opens CSV import, while the extension route stores the exact destination Profile
and skips CSV.

An accepted extension request runs only after successful setup completion and
browser preparation; replay uses Finish. Skip, cancellation, stale ownership and
failed completion cannot install it. The request outlives the setup window. A
failed install shows **Couldn’t add iCloud Passwords** in the browser window,
sharing the ad-blocker notice above. Chromium retains metadata, policy, signature
and CRX validation. Child Profiles are refused because this path cannot provide
parental reauthentication.

The extension talks to Apple's iCloud Passwords helper, which ships with
Safari rather than macOS, so an updated Safari on macOS 14 or early 15 can
already refuse Parc. Parc reads the helper's code signature, never launching
it: the helper Chromium's native-messaging manifest names, else the one in
Safari's system folder. Its parent launch constraint carries
[Apple's list](https://github.com/apple/password-manager-resources), admitting
only listed browsers, by signing identifier and team, or browsers signed with
Apple's passkey-browser entitlement. Parc checks its own signature against that
constraint. A helper without one admits any browser; with no helper, or a
constraint Parc can't evaluate, macOS 14 through 15.4 decide as before. Parc is
neither listed nor entitled, so setup offers the choice only with an older
helper and otherwise goes straight to manual import; macOS 13 never offers it.
Parc deliberately does not ask Apple to add it to that list. If Parc is listed
or gains the entitlement, the choice returns on its own. A setup saved with the
extension choice before the helper changed installs nothing at Finish and shows
the Couldn’t add notice, without Retry.

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

## Find your frame step

Setup runs before any browser window exists, so this step shows a true-size
copy of a browser window drawn at one pixel per point: 560 by 380 points,
rounded like a real window, in the Space colors and light or dark from the Theme
step, with no sidebar and a plain page card inset by the frame on all four
sides. The window crank sits at its real place and size, 125 points in from the
copy's left and bottom edges, clipped by the copy's corners. No panel, border or
number field surrounds the copy. On compact displays the whole setup card,
copy included, scales down with it.

Turning the crank re-insets the page card live; at 3 and 13 the card gives the
real window's short sideways shudder, except under Reduce Motion. The crank
stays out for the whole step and takes keyboard focus when the step appears.
Return or a click elsewhere keeps the value in the draft and brings a fresh crank
straight back with focus on Next, so a second Return continues; Escape returns
to the value the step last kept. Next and Back keep a value that differs from
where the step started; untouched, and with Skip, the saved thickness, 10 on
first launch, stays. The step never previews live
browser windows.

Successful completion saves the chosen thickness as the app-wide
[window frame](window-frame.md) preference before the browser opens. A save
failure is logged and setup continues. Replay starts from the saved thickness
and applies a choice only at Finish.

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

Entering theme focuses Space name. On the frame step the crank takes focus
when it appears, so arrow keys turn it and VoiceOver reads it as a slider; other
setup steps focus their progression control. Phase-only welcome updates do not steal focus. Each step's choices,
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

- `tests/ParcCoreTests/Presentation/Onboarding` (Swift Testing): draft migration,
  defaults, ordering, commits, replay and the import step counter.
- `tests/ParcTests/Presentation/OnboardingPresentationTests.swift`: setup cards,
  frame and theme layout, confetti samples and replay consent.
- `test-onboarding-keyboard.sh` and `OnboardingVideoHandoffTests`: component behavior.
- Browser-import coordinator/access/password checks and replay lifecycle checks.
- The whole-module Swift check for material application changes.

Read check entry points and follow [AGENTS.md](../AGENTS.md); this guide grants
no permission to open apps or run browser fixtures. Remaining work is in the
[backlog](backlog.md). Reduce Motion, the Lite blocker fallback and
no seeded starter folder retain the behavior above.
