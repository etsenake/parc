# Downloads in Library

Downloads is a profile-owned catalog in the shared Library. It presents the
engine's download records and capabilities; it does not construct its list by
scanning the Downloads folder. Product status and remaining work belong in
[the product status](parity.md) and [backlog](backlog.md).

## Source owners

| Responsibility | Source |
| --- | --- |
| Download records, persistence and private projection | `Sources/ParcCore/BrowserStore.swift` |
| Library presentation and filtering | `Sources/ParcApp/DownloadLibraryView.swift`, `LibraryView.swift` |
| Table selection and original-item commands | `DownloadLibraryTable.swift`, `DownloadLibrarySelection.swift` |
| Approved thumbnails, preview and drag | `DownloadThumbnailProvider.swift`, `DownloadLibraryPreview.swift`, `DownloadFileDrag.swift` |
| Entry, flyout, progress and arrival | `SidebarLibraryEntry.swift`, `LibraryFlyout.swift`, `DownloadActivityBadge.swift`, `DownloadArrival.swift` |
| Location preferences and review | `DownloadLocationPicker.swift`, `DownloadReviewController.swift` |
| Engine manager and creation notification | `Engine/ParcNative/downloads.cc`, `native_download_arrival.mm` |

App filenames without a directory are under `Sources/ParcApp`.

## Catalog and identity

A live record carries its original Profile, manager GUID and unguessable item
incarnation. Incarnations and capabilities are never serialized. Restored
metadata remains browsable, but file and transfer actions wait for a live manager
snapshot. Unknown-profile updates are rejected.

Opening Downloads initializes owned regular profiles through the engine registry
without creating a page. Stale persisted records are removed only after that
exact manager reports history ready and its authoritative GUID set. Loading,
failure and Retry are visible; profile retirement is not reported as empty
history. Filtering never changes the browser's Space or retargets a command.

Unchanged profile/record inputs skip catalog filter and sort work. Metadata
updates reload changed rows; a new Library context renews callbacks even when
its filtered list looks identical.

## Private-window Downloads

Regular and private Library windows show the merged regular/live-private
collection. Private records occupy a separate memory-only projection; encoding
an individual private record is refused. The same GUID in different managers
never identifies the same item.

`PCNativePrivateDownloadContext` holds a random context ID and weak profile
lifetime. It cannot create or retain a private Profile. Every refresh, action,
review, preview and drag revalidates the original context, registered owner,
GUID and incarnation. Context destruction revokes its token before removing
records from every view; other managers and in-flight transfers remain separate.
Closing one presentation does not cancel another window's transfer.

Source and help URLs use a live window of that same private context. Downloads
alone does not initialize persistent capture/document catalogs. The private
Library's Media category opens its normal-parent catalog only when selected and
when both parent and private context remain valid. The sidebar flyout uses its
own window-kind filter; it is not the merged Downloads page.

<a id="original-filter-header-chips-and-ordering"></a>
<a id="original-library-search-composition"></a>
## Search, filter and layout

Search matches names and source URLs. Profile chips select one original Profile;
selecting it again clears the filter. Search selection, marked text and caret
belong to the native field. Closing Filter retires a hidden chip's focus without
rewriting the query. Date ordering is newest first, stable for equal dates.
Records with no start date appear last under **Earlier**.

The shared shell has a 112-point category rail and a page card. Downloads uses
the standard 417-point page width, with containment supplied by the shell;
[Spaces](space-management.md#library-width-on-the-spaces-page) has its own width.
Search uses the shared 36-point rounded header control and 14-point native
editor. Filter/Done uses its fitting width. There is no item-count footer.

Rows are 56 points high with 12-point outer insets, a 24-point file image,
8-point horizontal spacing and 2 points between the 14-point title and 12-point
subtitle. Progress and missing-file artwork use a separate 32-point accessory
slot. Names truncate without covering controls. Full name, status and original
Profile/source remain available through accessibility and tooltips.

## Keyboard selection and original-item commands

There is one optional selected item. Up/Down skip headings and stop at either
end; with no selection they choose the first item. Shift does not extend a
range, Command-click does not add another item, and table Select All is disabled.
Text-field Select All and composition remain native editing operations.

Return and keypad Enter confirm the cursor, or select the first row when none
is selected; they do not open files. Submitting Search returns focus to the
current row. Space previews, Command-C copies through the original resolver,
Command-F focuses Search, and Delete removes the selected record. Modifier
variants do not accidentally invoke the unmodified action.

Selection survives metadata updates only for the same Profile, GUID and live
incarnation. Filtering out an item, replacing its manager lease, removing its
Profile or changing category invalidates captured menus and output actions.
A stale or plural command is refused before dispatch. Another attached sheet
prevents an action from escaping its original window.

<a id="original-single-item-selection-and-direct-removal"></a>
## File and transfer actions

The original manager determines availability of Pause, Resume, Cancel, Retry,
Review, Open, Show in Finder, Copy File, Copy Download Link, Open Source URL,
Open When Finished, Hide from Parc and Move to Trash.

- Open, Reveal and Open When Finished execute Chromium `DownloadCommands`.
- Copy File writes an approved completed file URL. A missing file never becomes
  a metadata string presented as a copied file.
- Hide from Parc calls `DownloadItem::Remove` on the captured item. Completed
  files stay on disk; Chromium may discard incomplete partial files. Parc waits
  for the manager's update instead of removing a row optimistically.
- Move to Trash uses the real asynchronous `NSWorkspace.recycle` outcome.
  Only success for the same current item and path removes its record. Failure
  retains it and reports the error; duplicate or conflicting operations refuse.
- Review retains the original item, policy DTO, callback and browser window.
  Regular-profile source/help navigation requires an existing Space of that
  Profile; it cannot silently use the currently selected different Profile.

Hide and Trash have no extra confirmation. Security review and failure feedback
remain authoritative. One completed safe file can be dragged as a copy, lazily
resolving its approved URL again at delivery. Ending a drag never deletes the
original. Busy, incomplete, unsafe, missing and stale items cannot produce it.

## Populated list presentation

The trailing More button appears for a hovered or selected row, but hides during
live scrolling. It has a 32-point target; hiding it returns space to the title
and returns its keyboard focus to the same table. Key-window loss and detachment
clear pointer state. The menu retains all capabilities; no duplicate inline
transfer controls are manufactured.

Titles use the file URL's lowercased last component for display only. Original
filenames, paths and actions remain unchanged. Failed, canceled and missing
items use secondary title ink. Transfer subtitles come from actual status, MIME,
byte counts and time remaining. Security review keeps its warning state.

Thumbnail and native-file-icon requests share the exact file/item lease. The
icon may display provisionally; a successful Quick Look thumbnail wins. Requests
and cache insertion revalidate policy, path, byte count and owner even if the
incarnation is unchanged. Detachment or context replacement cancels both
producers. The per-Library cache is bounded to 64 entries, and native icon
lookup runs off the main queue.

<a id="original-artwork-to-preview-transition"></a>
## Parent-owned media preview

The approved file appears in a transparent borderless child covering its original
browser window. Quick Look does not autostart media. Previous/Next, Close, More,
Open, position text and accessibility use the same original-item resolver.
Up/Down traverse eligible files without wrapping, Return opens when allowed,
Command-C copies, and Space/Escape close.

The backdrop is black at 70%; content is centered at
`max(round(parent dimension × 0.8) − 50, 100)`, contained by the actual parent.
Opening uses the invoking row's already-owned artwork and frame, crossfading
into live content. Closing reverses from the current presentation state. Opening
uses damping ratio 0.9/response 0.25; closing uses 0.95/0.15. Reduce Motion or an
unavailable source uses immediate presentation.

Changing selection/context, missing files, replacing a manager item, a competing
sheet and window retirement close or replace the preview. Resize settles all
layers together. Cleanup consumes callbacks once and removes animations, bitmap,
Quick Look content and child ownership. Focus returns only if this child owned
focus and its original Library/window still qualifies.

<a id="original-entry-animation-owner"></a>
## Original Library entry

`SidebarLibraryEntry` occupies the sidebar dock's 32-point Library slot. It
uses bundled artwork, a **View Library** tooltip with the live shortcut and one
accessibility button labeled **Home**. Its hover artwork respects Reduce Motion.

A click opens Downloads when an unread download badge appeared within 300
seconds and Library has not opened since; otherwise it opens the last Library
category. Opening Library through any route clears unread state. Private windows
open Downloads without recording a category. Clicking the displayed category
closes it.

The entry menu selects media sources: Downloads, Saved Captures, Documents,
Desktop and Screenshots. Folder sources contribute immediate children to the
flyout. Parc leaves those folders alone until someone first settles on the
Library button, so macOS asks for Desktop and Documents access then, worded
around Library's recent files, instead of right after onboarding. Once those
prompts have been answered, every window reads and watches the folders from
launch. The download catalog itself remains manager-backed. Badging state is
per window. Source removal, detachment and window close retire timers and the
visible item once.

The progress ring represents the newest in-progress item, never aggregate
throughput; paused and restored metadata do not count. Unknown totals use a
static partial ring. The sidebar badge confirms completion from status. The
Library rail follows the newest active item's actual progress, removes its
badge when no transfer is active and does not hold it for a completion effect.
Its completed animation has a bounded 1.45-second lifetime.

## Original Library flyout

Hovering the entry expands up to four newest unique files. Entry dwell is
0.15 seconds; entering the flyout keeps it expanded, and leaving through the
dock region uses a 0.5-second delay. Hover within 100 ms of Library closing does
not reopen it. Removing a hovered region clears its hover registration.

Rows show title, status/date, file or capture artwork, live progress and a Cancel
control for active transfers. Expansion preserves the visible badge's renderer
while it moves into the row. Reduce Motion fades in place. Menus resolve the
same original items; completed downloads drag as files and captures as PNGs.
Capture deletion has its own confirmation and store owner.

A completed media/PDF download opens the parent-owned preview. A capture opens
Library's Media category. The preview list contains downloads only. The flyout
is unavailable while Library, the tab switcher or command bar is presented;
private windows list private downloads only.

## Original DownloadToLibrary arrival

Arrival is driven once by genuine `OnDownloadCreated` for a live initiating
page; restored/imported records and manager enumeration never replay it. The
original page must be visible in its key window, without a security reservation.
The receipt retains page, primary document, Profile, private context, item and
window identity. Popup windows are excluded.

The source point comes from the original hovered-link rectangle, adjusted for
visual viewport and zoom, or the pointer when unavailable. A newer creation
supersedes a pending source query; navigation or retirement invalidates it.
`DownloadArrivalOwner` keeps one temporary child per window and captures the
sidebar-hidden/bin choice and palette at creation. It never becomes key or main.
Drawn arrival pixels swallow clicks; transparent regions pass them through.

Flights use `DownloadArrivalMotion`; concurrent arrivals share the bin. A drained
group ends once and drops later arrivals. Window/security retirement forces
cleanup; completion updates do not replay the flight. This arrival path currently
has no sound, haptic or Reduce Motion gate; the separate entry, flyout and progress
surfaces apply their own accessibility motion behavior.

## Original download prompt default and Download Location

Downloads default to saving without asking. Settings → Downloads presents the
original Profile's folder, **Other…** and **Ask every time**. Choosing a folder
sets it and then disables prompting; cancel preserves effective preferences.
Managed values disable the picker. Loading/failure shows Unavailable and Retry;
changing pane/Profile or removing it retires an open folder sheet.

A one-time migration clears the old Parc-seeded true prompt preference only
after Chromium commits the change, preserving managed values and stored false.
An intentional ask preference from that old format is indistinguishable from
the seed and is cleared once. The marker prevents subsequent user choices from
being reset again.

## Checks and remaining work

Focused components are under `tests/DownloadLibrary`, with separate view,
selection, pointer, preview/entry, arrival and download-location checks. Native
manager tests cover history initialization, private lifetimes, capability
validation and creation-only arrival. Consult [the working contract](../AGENTS.md)
before running a suite; older helpers may create windows.

The large-folder/history investigation remains explicitly deferred until after
the product polish pass as **DL-PERF-01** in [the backlog](backlog.md). Its original
report concerned another browser; it is not a reproduced Parc stall. Start by
identifying a repeatable delay and separating filesystem size, manager history
size, transfer throughput and main-thread presentation work.

Documents, Desktop and Screenshots are filesystem sources in the entry flyout;
they have no dedicated Library pages. Library's Easels & Notes category opens
Parc documents. Download arrival still needs a Reduce Motion presentation path.
