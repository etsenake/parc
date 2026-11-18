# Product guide

Parc is a native macOS browser: a Swift/AppKit application on its own
independently built Chromium engine, with no dependency on another installed
browser. This page is the short orientation every contributor reads first: what
Parc includes, the product decisions to keep, what stays out of scope and where
to read more. Subsystem guides own the details.

## What Parc includes

| Area | Capability | Details |
|---|---|---|
| Engine | Native pages, real Chromium profiles, renderer recovery, permissions, authentication and native input. | [Engine](../Engine/README.md), [Chromium changes](chromium-seams.md), [web interactions](web-interactions.md) |
| Spaces and profiles | Local profiles, named Spaces with rubber-banded trackpad swipes between them, profile assignment, per-window selection and theme editing. | [Space management](space-management.md), [themes](space-theme-editor.md), [swiping](sidebar-motion.md#floating-surface) |
| Sidebar and tabs | Today, a collapsible Pinned section, Favorites, unread/mute state, resizing, hide/reveal, multi-selection, closed-item recovery and tab picture previews. | [Saved tabs](saved-tabs.md), [Pinned section](sidebar-resize.md#pinned-section), [sidebar previews](sidebar-previews.md), [sidebar motion](sidebar-motion.md) |
| Folders and moves | Nested folders and moves across Spaces and windows; Option-drag copies of any sidebar item, duplication and bulk archive/delete come with window Undo and close consent. | [Folder moves](folder-moves.md), [folder commands](folder-commands.md) |
| Navigation and command bar | History navigation with swipe-and-hold, site search, address editing, contextual actions and live typed commands; an empty Space shows a start page with a resident command bar, and closing its last tab fades the page into it. | [Navigation](navigation.md), [swipe navigation](swipe-navigation.md), [command bar](command-bar.md), [start page](start-page.md) |
| Keyboard and switching | Custom shortcuts and website priorities, Essentials, positional/history navigation and the recent-tab switcher. | [Keyboard](keyboard-navigation.md), [tab switcher](tab-switcher.md) |
| Split views | Grouped splits with stacked panes, pane navigation, pointer, keyboard and VoiceOver resizing, tab and link drops, and Copy Links for the whole split. | [Splits](split-groups.md), [split navigation](split-navigation.md), [stacked panes](split-stacks.md) |
| Peek | Temporary pages float above the whole window from links to other sites, Shift-click or a folder preview's Open in Peek, close with a two-finger swipe and expand into normal tabs. | [Peek](peek.md), [swipe dismissal](swipe-navigation.md#peek-dismissal) |
| Archive, history and downloads | Automatic archive protections, a searchable Library, live archive previews over any page, Put Back that rebuilds deleted folders and real download controls with normal/private ownership. | [Archive](archive.md), [archive preview](archive-preview.md), [downloads](download-library.md) |
| Local documents | Editable Notes and Easels with a text formatting menu, embedded pages and captures, local persistence, export and Library cards. | [Notes](notes.md), [Easels](easels.md), [documents Library](documents-library-grid.md) |
| Capture and sharing | Portion, visible-area and full-page screenshots share editing, optional Portrait framing and output destinations; recording and original-page capture controls stay connected. | [Capture](page-capture.md), [framing](portrait-capture-fidelity.md), [destinations](capture-destinations.md) |
| Extensions | Installation and consent, toolbar/sidebar actions, popups, side panels, commands and theme-colored extension menus. | [Extensions](extensions.md), [extension interaction](extensions-interaction.md) |
| Page tools | Find, zoom, Reader, print/save/source, site controls, blocked pop-up controls, data clearing, Task Manager and Developer Mode linked to the real developer tools. | [Web interactions](web-interactions.md), [Developer Mode](developer-mode.md) |
| Media | Native playback controls, mute, a Mini Player whose Cast button also reaches speaker-only homes, picture in picture, platform codecs and protected video that stays in Chromium and follows the page's pitch correction. | [Media](media-interactions.md), [Mini Player](media-mini-player.md), [casting](media-casting.md), [FairPlay identity](fairplay-identity.md) |
| Settings and identity | Local settings, routing rules, profiles, shortcuts, themes, icon variants, a window-frame crank, a personalized membership card and Replay onboarding. | [Settings](settings.md), [window frame](window-frame.md), [membership card](settings-membership-card.md), [icons](app-icon-picker.md) |
| Onboarding and import | Resumable first-launch setup with music, theme, Favorites, default-browser and ad-blocker choices, and real import of Profiles, history, bookmarks, passwords and extensions from other browsers, including Safari's export file. | [Onboarding](onboarding.md), [browser import](browser-import.md) |
| Windows and data | Standard/private/popup windows, live tab transfer, session restoration with a week of sidebar backups and startup rescue, native close consent, local credentials and Parc Safe Storage. | [Windows](windows-lifecycle.md), [sidebar backups](windows-lifecycle.md#saved-sidebar-backups-and-startup-rescue), [private lifecycle](private-route-lifecycle.md), [Keychain](../tests/KeychainNamespace/README.md) |
| Software updates | Sparkle checks, download/status windows, update banners, guarded automatic installation and a bundled What's New page that marks skipped versions. | [Software updates](software-update.md) |
| Distribution | Conventional Commit versioning and notes, frozen release inputs, Developer ID signing, notarization, GitHub artifacts, signed appcast and Homebrew publication. | [Release command](master-release.md), [packaging](../tests/Packaging/README.md) |
| Automation | Local AppleScript access to windows, Spaces and tabs (read, open, select, navigate and close) plus page JavaScript. | [Scripting](scripting.md) |

## Product decisions to preserve

- Keep working features when changing design. Parc's additions are intentional
  product behavior, not discrepancies to remove.
- **Replay onboarding stays in Settings → General only.** It runs the full
  production setup and applies the Finish choices to the originating Space
  without deleting browsing data; Cancel restores the previewed theme and
  appearance, and replay never resets first-launch state.
- The membership card stays local and personalized, with its regenerated designs
  and interactions, and no cloud account.
- Screenshot framing stays unified over the original captured pixels, with every
  existing destination and the Visible Area action.
- Site Control Center and extension menus take the theme's colors; pinned
  extension badges sit top right in the extension's own badge colors.
- Title cleanup uses deterministic, locally authored rules; AI renaming stays out.
- Onboarding keeps its Space-name field, and Favorites comes right after the
  browser choice so it runs alongside the
  [import](onboarding.md#included-setup-order-and-ad-blocker-branch).
- Both Peek triggers, links to other sites and Shift-click, stay on by default
  for new users and switchable in Settings → Links. Peeks never stack or nest: Shift-click
  inside a Peek opens the link in that same Peek. Shift-submitted forms, including ones
  that send data, follow the same rule with their data intact. See
  [Peek](peek.md#presentation-and-remaining-scope) and
  [links inside a Peek](peek.md#links-inside-a-peek).
- Safari Profiles come from Safari's own export file, and Firefox and Zen
  passwords from the browser's own CSV export. Parc never reads Safari's private
  Profile folders or Firefox's encrypted password store. See
  [native import](../Engine/ParcImport/README.md#reader-and-writer-boundary).
- Protected video uses the FairPlay route with automatically learned site
  identity, and pages stay in Chromium. Never substitute a fixed site list.
- Chromium security fixes arrive through deliberate pin upgrades with the
  relevant native integration checks.
- Folders and the Pinned section open and close together in every window showing
  that Space; the state belongs to the folder or the Space, not a window.
- Favorites keep their own clicks and stay out of sidebar range and
  multi-selection. See [sidebar selection](sidebar-selection.md#app-tray-move-boundary).
- Split View offers no pane-handle drag, double-click separation, Option-click
  unsplit or sidebar drop-to-combine gesture; each duplicates an existing route.
  See [split groups](split-groups.md#split-gesture-and-context-inventory--sp33).
- Split stacks run perpendicular to the split, two levels deep at most, with four
  panes in all; a tab dropped on a pane's perpendicular edge stacks it there, and
  an older Parc opens a stacked split as one row. See
  [stacked panes](split-stacks.md).
- Routing rules never move an already-created page into another Profile; the
  page keeps its opener and security context. See
  [routing](settings.md#internal-original-request-routing).
- Private windows have no Notes or Easels: they don't create, open or browse
  them, their Library shows no documents, and their captures copy, share or save
  to the Library labelled Incognito but never go to an Easel. This keeps private
  browsing from writing documents to disk or mixing into an Easel's pages. See
  [capture Library](capture-library.md#private-media-ownership).
- Library → Archive previews single web pages only. Notes, Easels and splits are
  restored rather than previewed, and no close-time page picture is saved. See
  [archive previews](archive-preview.md#product-decisions).
- Every button and clickable control shows the pointing hand; tabs, menu rows,
  the bookmark picker's list and click-to-dismiss backdrops keep the arrow. See
  [the pointing-hand check](../tests/PointingHand/README.md).

## Scope boundaries

Excluded: AI features and preferences; vendor accounts, cloud services and their
update checks; Sentry, Datadog, analytics and telemetry; a separate mini browser
window; Boosts; dedicated live service integrations; and page translation,
because its current service requires Google API keys. Parc's own update system
is included, and Parc never requires Google API keys or paid Google services.

Included: ordinary websites and extensions, general sidebar previews, local
Notes and Easels, password/autofill/security behavior, language detection and
macOS dictation. General Chromium/Google networking is not a removal project.
Safe Browsing stays included without a configured Google API key, which doesn't
disable every browser security warning, and on-device suggestions need no key.
See [engine policy](engine-flags.md#runtime-features).

Broader AppleScript commands and window or sidebar changes through scripting
aren't planned; see [scripting](scripting.md#scope-and-checks).

Chromium's AI exclusions are settled at their current scope. Picture in picture
and the accepted AI cleanup stay done; reopen them only for a new defect or
request.

## Where to read more

- Behavior and architecture: the [documentation index](README.md) and each
  subsystem guide.
- Unfinished work: the [backlog](backlog.md) is the only list of it. Recheck an
  item against current source before starting.
- Releases: the version lives in `app-version.json`, history in the
  [release notes](../CHANGELOG.md), downloads on the
  [published releases](https://github.com/etsenake/parc-releases/releases) page
  and the process in [release operations](master-release.md).
- Engine: most of Parc's Chromium logic lives in Parc-owned code behind
  extension points and one-call hooks, and each kept patch has a recorded
  reason; see [how Parc changes Chromium](chromium-seams.md).
- Working together: the [working contract](../AGENTS.md),
  [collaboration](collaboration.md) and [documentation policy](documentation.md).

Keep this page to about 130 lines, with no version numbers, progress or
history. Change a row only for a meaningful product change, record a new
deliberate decision as one line linking its owning guide, and replace stale
lines rather than appending corrections. Completed fixes stay done unless a new
report or concrete defect reopens them.
