# Product status

Parc is a native macOS browser with its own Swift/AppKit application and an
independently built Chromium engine. This page describes the product that exists
and the remaining work; its historical filename is kept for existing links.
Matching another browser is no longer the organizing principle for the docs.

Use the [backlog](backlog.md) for unfinished work, the linked subsystem guides
for behavior and architecture, and [release notes](../CHANGELOG.md) for history.
The older ledger is available in Git; do not copy it into an archive document.

## What the old percentages meant

The November 10 audit reconciled the retired checklist with existing behavior.
These figures preserve that comparison, not a new ongoing scoreboard. An item
received no credit while partly unfinished, and every item had equal weight.
Some items were questions or broad review obligations rather than missing
features. These numbers do not measure the percentage of Parc that works,
remaining effort, speed, or additions outside that old checklist.

| Area | Old headline | Reconciled old checklist |
|---|---:|---|
| Link destinations | 92.3% | 12/13, still 92.3%; overlapping private-window openings/closings remain. |
| Windows | 71.4% | 10/14, still 71.4%; each remaining broad item contains a specific limitation. |
| Data and credentials | 75.0% | 15/16, 93.8%; additional browser-import formats remain. |
| Folders | 65.2% | 19/23, 82.6%; copying, selection, document moves and later folder restoration remain. |
| Archive and history | 70.6% | 15/17, 88.2%; broader previews and deleted-folder reconstruction remain. |
| Command bar | 82.8% | 26/29, 89.7%; missing commands and covered controls reacting to hover remain. |
| Recent-tab switcher | 69.2% | 13/13, 100% of that inventory; the old open claims were already implemented. |
| Peek | 66.7% | At least 16/21, 76.2%; two old open items are complete, while other items overlap remaining cases. |
| First-run setup | 75.0% | Its own old rows already said 35/36, 97.2%; the headline had not caught up. |
| Automation | 69.2% | 9/13, unchanged; additional commands remain explicitly deferred. |
| Performance | 40.0% | Retired: broad comparison obligations did not describe a measured speed deficit. |
| Whole-product polish | 0% | Retired: universal review criteria did not mean no polishing had been done. |

The folder count includes answering whether Duplicate has Undo: it does not.
Adding Undo is a separate product decision, not a newly completed feature.
The setup count corrects old arithmetic; the audit also found silent failures
when installing iCloud Passwords or removing an imported blocker. Those failures
remain in the [backlog](backlog.md#onboarding), outside the old count.

The old table already marked keyboard navigation, downloads, sidebar, saved tabs,
auto-archive, general navigation, splits, web interactions, extensions, Spaces
and profiles, icons, settings, capture, Easels, Notes, page tools, media, updates,
accepted AI cleanup and the independent engine at 100%. That meant their listed
requirements were accounted for, not that every later corner case was solved.
The [backlog](backlog.md) remains the authority for actual unfinished behavior;
never treat these historical numbers as a new whole-product completion score.

## Releases and engine

This page carries no version numbers. The current version lives in `app-version.json`,
what each release changed in the [release notes](../CHANGELOG.md), and downloads on the
[published releases](https://github.com/etsenake/parc-releases/releases) page; see
[release operations](master-release.md) for how a release is built and published.
Most of Parc's Chromium logic lives in Parc-owned code behind Chromium's extension points
and one-call hooks, and each remaining direct patch has a recorded reason. See
[how Parc changes Chromium](chromium-seams.md).

## What Parc includes

Existing functionality stays supported while the [remaining work](backlog.md)
is resolved.

| Area | Current capability | Details |
|---|---|---|
| Independent browser engine | Native pages, real Chromium profiles, renderer recovery, permissions, authentication and native input; no dependency on another installed browser. Most of Parc's engine logic sits in its own files behind extension points and hooks. | [Engine](../Engine/README.md), [Chromium changes](chromium-seams.md), [web interactions](web-interactions.md) |
| Spaces and profiles | Local profiles, named Spaces, profile assignment, per-window selection, theme editing and persistence. | [Space management](space-management.md), [themes](space-theme-editor.md) |
| Sidebar and tabs | Today, pinned tabs, Favorites, unread/mute state, resizing, hide/reveal, multi-selection, closed-item recovery and tab picture previews. | [Saved tabs](saved-tabs.md), [sidebar previews](sidebar-previews.md), [sidebar motion](sidebar-motion.md) |
| Folders | Nested folders, original-item moves, duplication and bulk archive/delete with existing Undo and close consent. Some collection and drag cases remain open. | [Folder moves](folder-moves.md), [folder commands](folder-commands.md) |
| Navigation and command bar | History navigation, site search, address editing, contextual actions, typed commands and live command validation inside the browser window; an empty Space shows a start page with a resident command bar. | [Navigation](navigation.md), [command bar](command-bar.md), [start page](start-page.md) |
| Keyboard and switching | Custom shortcuts and website priorities, Essentials, positional/history navigation and the recent-tab switcher. | [Keyboard](keyboard-navigation.md), [tab switcher](tab-switcher.md) |
| Split views and Peek | Grouped splits, pane navigation/resizing, tab and link drops, temporary page previews and promotion into normal tabs. | [Splits](split-groups.md), [Peek](peek.md) |
| Archive, history and downloads | Automatic archive protections, searchable Library, archive preview/restore and real download controls with normal/private ownership. | [Archive](archive.md), [archive preview](archive-preview.md), [downloads](download-library.md) |
| Local documents | Editable Notes and Easels, embedded pages and captures, local persistence, export and Library cards. | [Notes](notes.md), [Easels](easels.md), [documents Library](documents-library-grid.md) |
| Capture and sharing | Portion, visible-area and full-page screenshots share editing, optional Portrait framing and output destinations; recordings and original-page capture controls remain connected. | [Capture](page-capture.md), [framing](portrait-capture-fidelity.md), [destinations](capture-destinations.md) |
| Extensions | Installation and consent, toolbar/sidebar actions, popups, side panels, commands and theme-colored extension menus. | [Extensions](extensions.md), [extension interaction](extensions-interaction.md) |
| Page tools | Find, zoom, Reader, print/save/source, site controls, data clearing and Developer Mode linked to the real developer tools. | [Web interactions](web-interactions.md), [Developer Mode](developer-mode.md) |
| Media | Native playback controls, mute, Mini Player, picture in picture, casting, platform codecs and protected-media integration. FairPlay and learned Safari identity keep pages in Chromium. | [Media](media-interactions.md), [FairPlay identity](fairplay-identity.md), [casting](media-casting.md) |
| Settings and identity | Local settings, routing rules, profiles, shortcuts, themes, icon variants, a window-frame crank for frame thickness, personalized membership card and Replay onboarding. | [Settings](settings.md), [window frame](window-frame.md), [membership card](settings-membership-card.md), [icons](app-icon-picker.md) |
| Onboarding and import | Welcome, music, setup, real browser/bookmark/password import, favorites, theme, default-browser choice, ad-blocker choice and final reveal; resumable first launch and replay. | [Onboarding](onboarding.md), [browser import](browser-import.md) |
| Windows and data | Standard/private/popup windows, live tab transfer, session restoration, native close consent, local credentials and Parc Safe Storage. | [Windows](windows-lifecycle.md), [private lifecycle](private-route-lifecycle.md), [Keychain](../tests/KeychainNamespace/README.md) |
| Software updates | Sparkle checks, download/status windows, update-ready/completed banners, guarded automatic installation and a bundled What's New timeline. | [Software updates](software-update.md) |
| Distribution | Conventional Commit versioning and notes, frozen release inputs, Developer ID signing, notarization, GitHub artifacts, signed appcast and Homebrew publication. | [Release command](master-release.md), [packaging](../tests/Packaging/README.md) |
| Automation | Existing local window/Space/tab scripting and page JavaScript commands remain supported; further expansion is deferred. | [Scripting](scripting.md) |

## Recent product additions and corrections

These summarize capabilities missing or stale in the previous ledger. Subsequent
changes belong in the owning guide and release notes, not an ever-growing log here.

- **Tab picture cards:** hovering another open tab shows its picture, title,
  site and Split View action. General → Previews Settings has a separate
  picture-card switch; the old “no off switch” concern is resolved.
- **Updates and What's New:** four-hour update checks, progress that keeps its
  byte count and bar steady, update banners and a bundled release timeline
  that marks versions skipped since the previous installed release.
- **Unattended updates:** a downloaded background update can install after the
  Mac has been away for five awake minutes, or after thirty minutes without
  keyboard/pointer input when no app keeps the display awake. Media, downloads,
  private windows, dialogs and other interruption guards still prevent restart.
- **Themed extension menus:** menus open beside their actual extension control,
  keep the Site Control Center open, stay inside the available window and
  explain disabled actions with tooltips.
- **One Developer Mode:** site controls and developer shortcuts coordinate the
  toolbar with the page's actual tools instead of separate switches.
- **Native interface corrections:** clickable controls use the pointing hand;
  toast, section-heading and update-banner text retain theme/hover contrast;
  the command bar remains inside its browser window with live commands.
- **Page visibility and sizing:** tabs opened during application activation
  are shown, and new pages settle their content size before appearing.
  These corrections fix fresh tabs appearing with hidden or zero-sized content.
- **Profile-preserving import:** every readable source Profile and its extensions
  are imported; the default Profile uses the captured destination and others
  use suitable existing or new local Profiles. Sidebar data and bookmark
  hierarchies are preserved, existing cookies are kept, and replay uses real
  imports. See [browser import](browser-import.md).
- **Parc identity in the engine:** menus and messages name Parc when they mean
  this browser; references to separate Google products and services remain.

## Product decisions to preserve

- Keep working features when changing design. Parc additions are intentional
  product behavior, not discrepancies to remove.
- **Replay onboarding stays in Settings → General only.** It runs the full
  production welcome/setup experience and applies the choices made on Finish
  to the originating Space without deleting existing browsing data. Cancel
  restores previewed theme/appearance; replay does not reset first-launch state.
- Keep the local personalized membership card, its regenerated designs and
  interactions without adding cloud accounts.
- Keep unified screenshot framing over the original captured pixels, all
  existing destinations and the Visible Area action.
- Keep theme-derived Site Control Center/extension menus and top-right pinned
  extension badges with the extension's own badge colors.
- Keep deterministic, locally authored title-cleanup rules; AI renaming remains
  excluded. Keep the Space-name field in onboarding and the current Favorites
  position until the [remaining decision](backlog.md#onboarding) changes it.
- Both Peek triggers, links to other sites and Shift-click, stay on by default
  for new users and remain switchable in Settings → Links.
  See [Peek](peek.md#presentation-and-remaining-scope).
- Protected video uses the implemented FairPlay route and automatically learned
  site identity; pages remain in Chromium. Do not substitute a fixed site list.
- Preserve upstream security maintenance through deliberate Chromium pin
  upgrades and relevant native integration checks.

## Scope boundaries

Excluded: AI features/preferences; vendor accounts/cloud/services and their
vendor update checks; Sentry, Datadog, analytics and telemetry; a separate mini
browser window; Boosts; dedicated live service integrations; and page translation (excluded
because the current service requires Google API keys). Parc's own update system
is included. Parc must not require Google API keys or paid Google services.

Ordinary websites and extensions, general sidebar previews, local Notes/Easels,
password/autofill/security behavior, language detection and macOS dictation stay
included. General Chromium/Google networking is not a separate removal project.
Safe Browsing remains included without a configured Google API key; that does
not disable every browser security warning. On-device suggestions do not
require a Google API key. See [engine policy](engine-flags.md#runtime-features).

The existing Chromium AI exclusions are the accepted scope. The broader
audit/overhead proposal is closed.
Further scripting remains deferred. The removed cross-Profile created-page
proposal (ROUTE11) and speculative shutdown task (WIN14) stay out of scope.

## Maintenance

The independent engine and picture in picture are implemented. Completed fixes
stay done unless a new report or concrete defect evidence reopens them.

The [backlog](backlog.md) indexes source-checked unfinished behavior, product
decisions and explicit deferrals. Recheck an item against current source before
implementing it. Historical agent names are not
proof of live ownership; coordinate through the [working contract](../AGENTS.md)
and [collaboration guide](collaboration.md).

Keep this page below 200 lines and guides below the repository's hard limit
(changelogs are exempt). Replace stale statements instead of appending corrections, link to the
single owning document, and remove resolved backlog entries in the delivery
that resolves them. Documentation policy lives in [AGENTS.md](../AGENTS.md).
