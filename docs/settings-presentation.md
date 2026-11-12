# Settings pane presentation

Settings follows the current macOS settings layout: a full-height sidebar,
back and forward buttons with the page title in the toolbar, and grouped rows
on the page. It is an adaptation for Parc, not a copy of another app; every
existing control, preference and command owner is unchanged.

## Window and sidebar

The window is 792 points wide with a 196-point sidebar from the standard split
view controller, so macOS supplies the sidebar glass, the wallpaper tinting and
the inactive-window flattening. The sidebar is a plain source-list outline with
a clear background; it adds no visual effect view of its own. Icons use the
monochrome tint, rows are 28 points with 14-point text, and the system draws
the rounded selection: accent with white text while the window is in front,
grey behind it. Cell text colors follow the row's background style rather than
the bound-text-field recolor, so an unfocused selection never turns blue.

The first row is your card: a monogram over the card's own palette and your
display name, which is also that page's title. Then come General, Profiles,
Links, Shortcuts, Icon and Advanced. Keyboard focus starts in the sidebar;
arrowing through it switches pages without leaving it. Tab moves from the
sidebar into the page and back.

## Toolbar and navigation

Back and Forward are two plain navigational toolbar buttons, which macOS places
on one glass capsule without a divider. The title is a non-bordered 15-point
bold toolbar label so it stays off the glass. Command-[ and Command-] reach the
same history through the menu, which validates them against it. History
records each page and Edit Profile visit; a removed profile drops out of it and
a shown removed profile returns to the list. Panes sit below the toolbar, so
the header stays solid with no scroll-edge line or hover separator.

## Pages

Groups are 556 points wide on 20-point margins, with 12-point continuous
corners, a faint label-tinted fill and no outline. Rows are 42 points, or 56
with a note; separators inset 12 points. Section headings are 13-point
semibold, outside the group. Command rows (Privacy and Security, Passwords,
Credit Cards, Notifications) show a 20-point badge, the title and a diagonal
arrow because they open a page in the browser. Pill buttons use a quiet fill;
Delete Profile uses red text.

Profiles lists every profile with its Space count and a chevron, then New
Profile. Choosing one opens Edit Profile: the name with Rename, Search, Tabs and
Downloads, Your Data and Settings, and Clear Browsing Data and Delete Profile at
the bottom right. Rename keeps Parc's rename dialog. General's Profile Settings
opens the selected profile's Edit Profile page.

General groups Warn before quitting, Previews and Profile Settings, and Replay
onboarding, which must stay available. Advanced groups Sound and Feedback,
Windows and Tabs, and Websites, followed by More Settings and Export Data.
Links groups the two Peek switches with their note, then Air Traffic Control.
The icon list sits on the page with row separators and no box. Shortcuts keeps
its list and detail columns on the new margins.

## Checks and evidence

`tests/SettingsPresentation/check.py` covers production component layout,
input ownership, decorative-descendant isolation, truncation, disabled colors
and light/dark renders. The history model has its own test in
`tests/SettingsNavigation`. Shared Download Location checks cover that
component's integration; typechecking and SIL complement these inert checks.

Focus and motion have separate [Settings](settings.md) and
[motion](settings-motion.md) contracts.
