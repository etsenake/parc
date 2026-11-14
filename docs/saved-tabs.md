# Saved tabs, Favorites and row actions

Saved items keep stable identity, Profile/Space membership and saved destinations
independent of their live page. Every pointer, menu or accessibility action
captures its original item and revalidates ownership before dispatch.

## Production actions

Today Close archives regular tabs; private Today Close remains memory-only.
Saved Close unloads live content without deleting its saved anchor. Reset
navigates the original live page to that anchor through native beforeunload.
Unclaimed dormant records use the existing metadata-reset path. A page held by
a different window, a Peek, retirement or a security sheet cannot be reset by
an old row action. Accepted dispatch is not completed native close consent.

## Saved-home URL comparison

Reset eligibility first compares actual Foundation URLs, then normalized full
URLs. Normalization lowercases the absolute string, supplies HTTPS for missing/
HTTP scheme, removes one `www.` prefix, ordinary fragments and a final path
slash. A hashbang fragment is retained, with its final slash removed instead.
Empty-valued and `utm_` query items are removed; remaining order, duplicates,
ports and user information matter. Unchanged query arrays retain their encoding.
Conversion failure preserves the original URL.

This equivalence only decides Reset eligibility. Navigation always uses the
original saved URL, and security/request/transfer validation compares original
values. Exact Command-click Favorite reset is a separate forced action.

## Reset all tabs in this Space

`SavedTabResetTargets` visits visible Favorites, then the current Space's mixed
Pinned hierarchy. Only expanded folders contribute children; visible splits keep
their child order. Today, archives, other Profiles, local documents and equivalent
home URLs are excluded. Original identities are deduplicated without changing
selection, disclosure or stored order.

Availability and dispatch use that same projection. One-use page actions run in
order without selecting/transferring targets or creating batch consent. Each
native navigation may accept or refuse independently; a competing native sheet
is refused conservatively. A refused page keeps its current URL/saved anchor.

## Favorite App Tray interaction owner

Favorites are profile-wide saved items. Tiles retain original IDs across redraws,
prepare fresh context/accessibility actions and request one-use activation/close
leases from their window. Those leases bind record, Space/Profile, page wrapper,
transfer/retirement, sheet and shutdown state. Titles and exact-URL help remain
available to accessibility; tiles have no ordinary hover tooltip.

### Favorite tile presentation

The grid has 8-point insets/gaps, at most four columns, 47-point rows and 55-point
pitch. Columns are balanced and at least 47 points. Selected tiles use their own
shadow/wash and ring. Split Favorites lay out original child icons; a custom
container icon replaces them. Favicon replies validate original item/row state;
missing icons use a themed monogram. Hover crossfades fill over 0.12 seconds;
selection changes immediately.

Original-page overlays include actual recording state, a retained Peek's icon,
Developer Mode ring and eligible music particles. They do not take input or add
duplicate accessible elements. Repeated updates do not restart motion. Inactive
windows dim selected tiles; Reduce Motion disables particles. Capture Stop stays
in the tile's **Camera, Microphone and Sharing…** menu. No notification/unread
service badge or hold-Command number overlay is fabricated.

### Favorite pointer phase and saved-home reset

Plain/Shift presses in a key window activate on down, once. Exact Command-down
resets the saved home and selects it; double-click uses reset eligibility rather
than Rename. Control-click opens the original context menu. Favorites do not
join the outline's Command/Shift multi-selection. They reject first mouse in an
inactive window, so activation alone does not press/select/start a drag.

Press feedback uses scale 0.99, response 0.2/damping 0.5, reversing from current
presentation. Removal, hiding, disabling, dragging and deactivation cancel held
input. Reduce Motion settles it. No extra hover Close/Reset glyph or haptic exists.

### Favorite Option split and focused duplication

Exact Option-release inserts the original Favorite after the focused pane. An
already visible Favorite receives focus there. If it is already focused and the
split has capacity, a new Today item copies its actual current URL, falling back
to saved URL only when dormant. Away from home it uses the live title; at home
it retains saved presentation. The original page/history/anchor is not cloned or
reset. The model saves before creating only the new copy.

With no presentation/focused pane, Option selects normally. A fifth pane shows
**Cannot Add New Pane**; a focused Favorite at capacity stays unchanged. Other
Option combinations select normally except exact Option–Command, which remains
consumed because the separate mini browser window is excluded. Release classification ignores flags
outside the four primary modifiers. Stale window/selection/layout/URL leases
cannot commit a delayed split.

### App Tray selection and modifier corner cases

Selecting a page displayed by another standard window moves that actual page
here through [window transfer](windows-lifecycle.md#moving-selected-content-between-windows).
Option moves it in the background and applies split placement only if release
state still matches, otherwise selects it. Split Favorites move each original
page sequentially. The tile containing the focused pane is the selected tile.
A successful Favorite activation clears outline multi-selection; rows moved into
the tray cannot remain in that outline set.

## Ordinary row action ownership

Today/Pinned activation and Close/Archive/Reset capture original leases before
native tracking. Model, Space, group, page or physical-owner changes reject them.
Control-click uses the same context provider. Hide, detach, drag and key loss
cancel held actions. Row accessibility exposes actions without pointer hover.

### Ordinary row presentation

Rows use 12-point corners, 24-point icon slots, 16-point favicons and a 24-point
Close control inset 6 points. Fill precedence is current/key-dragged, content-
visible, multi-selected, hovered, then clear. A 2-point contrast ring marks
keyboard highlight; non-key/non-main windows dim rows. Close press uses
scale 0.95, response 0.3/damping 0.6. Split children leave fill/ring ownership with
the container and have no separate reset target or subtitle.

A resettable row separates its icon region from the body with a slash. Hovering
the icon shows **Back to Pinned URL**, shifts its title stack 7 points and uses
the saved destination's exact-profile cached favicon. Command-hover shows
**Separate From Pinned Tab** and keeps the live page icon. Region actions consume
one-use leases on release; dragging hands the original mouse-down to the row.
When no eligible action exists, the region passes activation through.

Separate From Pinned Tab atomically creates a Today item at the top with the
live URL/title and resets the pinned record to its saved destination/title.
The original live wrapper/pane/claim moves to the new background item without
reloading. The pinned ID, position, folder and custom title survive. **New Tab
Created** can select the new item; reopening the pinned item later creates its
saved destination. A dormant resettable row is only selected.

## Item keyboard and accessibility

Each tile/row is one named accessible button. Web rows say **Tab**; Note/Easel
rows use the button role. Favorites speak their page title, or a split's name/
joined page titles, with **Favorite item** fallback. Exact URL is help, not a
repeated title. Selected includes current item and explicit row multi-selection.
Press and Show Menu use the same original-item owners as pointer actions.

Control–Space and native menu commands retain their keyboard route. Parc's
existing focusable Favorite tiles and sidebar Up/Down/Delete selection remain;
webpage editing and native IME are not intercepted by row-level key monitors.

## Ordinary row image ownership

Live favicon reads use the exact original page's current NavigationEntry image.
Image-only notifications neither emit navigation metadata nor create visits.
Private pages never consult parent Profile history. Unloaded regular tabs may
use exact-Profile/exact-URL native history icons; stale row/generation/page replies
are rejected. Loading retains the favicon. There is no extra shell icon cache,
URL guessing, network fetch or page creation.

## Sidebar title and inline Rename

Visible names choose manual `customTitle`, nonempty saved title, then saved URL;
live page title remains separate. Empty Rename clears the override. Today metadata
may update its saved source, while pinned/Favorite anchors retain their own
lifetime. Existing deterministic title-cleaning rules use Parc-authored data;
AI renaming remains excluded.

Rename opens one original-row native editor, selecting the displayed label and
hiding trailing controls. Return/focus loss commits; Escape, removal/window loss
cancel. Marked text keeps native Return handling. Completion binds original
Space/Profile/group/page, saves before publishing and preserves private memory-
only behavior. An unchanged edit creates no override. Row rebuilding is deferred
while editing; focus-loss completion waits one guarded main-queue turn so a
removal can cancel first. Failed saves report the real error.

## Global Rename ownership

**Rename Current Tab…** is a hidden native command exposed through command search
and customizable shortcuts, with no default key. It resolves the originating
window's current ordinary item or whole split, never a hovered/highlighted item
or focused split child. After dismissing the command surface, it revalidates,
reveals original ancestors and enters the same editor without creating/selecting
a new page. Favorite command-search Rename uses its separate dialog below.

## Split-container Rename ownership

The optional container title is independent of child titles. Global/context/
accessibility Rename selects the current name in an editor with **Title**
placeholder. Empty text clears it; membership/placement/Profile/page changes
invalidate completion. A named split uses its custom-info row; clearing restores
child rows. Child actions remain in context submenus and capture controls retain
their actual owners. The atomic change affects only the original container name.

## Container-name Undo and Redo

Split-container names use the same original-item chronology described below.

## Ordinary-tab name Undo and Redo

Changed tab/container names register **Rename Item** on the originating window's
same typed chronology as close operations. Undo/Redo changes only the optional
name by original ID/Profile and matching before/after value. Current geometry,
children, saved URLs, live metadata and same-profile moves survive. No-op/cancel
keeps Redo; failed writes remain retryable. Conflicting shared names, archive,
delete or Profile change reject stale inverses. Retirement/security interrupts
availability and window close discards its stack. Native field/document/web
editing retains its own Undo/IME owner.

## Favorite Rename dialog

Favorite context Rename selects the original Favorite then presents **Rename
Tab…**, **Keep it short and sweet!**, Rename and Cancel. Empty input cannot
confirm; nonempty input preserves its literal name. Focus loss does not commit.
The dialog validates item, saved name/membership, window selection, page/local
editor and Profile. It saves only custom title and registers window-owned Rename
Item. Failed writes retain the draft; cancel writes nothing.

### Favorite Rename in command search

The captured current-Favorite command opens the same dialog without repeating
context-menu activation. Later metadata may change, but competing manual names,
saved anchors, selection, membership or owner replacement expire it. The ordinary
menu alias is omitted only from that result set; its registered shortcut survives.

## Unread state and badge ownership

Parc's local background/copy `isUnread` protects unseen items from automatic
archiving and persists until real selection clears it. Drawing a row is not
selection. It does not imply sync, mobile or live-service notification state;
ordinary rows and Favorites show no such unread badge. This local protection is
an intentional supported feature, independent of excluded account integrations.

## Checks and boundaries

Model/native components cover original actions, reset normalization/targets,
copy/split identity, row presentation, rename persistence and typed Undo. Every
source change must preserve the complete action/lease and editing boundaries.
