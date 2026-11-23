# Live captured regions

A captured WebCard keeps its original PNG, URL, acquisition time and optional
renderer geometry. **Make Live**, on the card's header and its context menu,
opens a real auxiliary Chromium page in that Easel editor's window and Profile.
The snapshot header with Make live and Open shows while the card is selected or
hovered, fading in and out and staying while the pointer travels onto it; its
buttons act on that card without selecting it first.
The first use presents the Make it Live/Cancel education, explaining that sites can change and the original screenshot remains available through Back to snapshot. Its callback is bound to the same window, selection and document. The page is framed to the captured region. Its own renderer continues to update;
there is no screenshot timer or image relabeling. **Back to snapshot** returns to the
same original image after the live page actually agrees to close.

## Source and geometry

`PCNativePageCaptureResult.layout` is produced from the original leased renderer.
The native capture reads its visual viewport immediately before compositor copy
and after the reply; matching values and page zoom admit CSS-pixel viewport,
scroll and outward-rounded capture-region geometry. The lease still validates
its original document, native page, Profile, window, screenshot policy and
security ownership. Changed geometry leaves the ordinary genuine PNG intact
but offers no live-region capability. A full-page capture records the page's
CSS viewport at capture time, a zero scroll and a region covering that whole
viewport, so Make live can open the page from its top.

The same geometry read records the scroll context under the region's centre:
every scrolled or scrollable ancestor of the element there (up to eight,
outermost first, crossing open shadow roots), with its scroll offset and its
document-space frame. Each panel is found again by a locator: the nearest
ancestor with a readable, unique id (generated-looking ids with digit runs are
skipped) followed by tag-and-index steps, or a path from the root element.
App shells and single-page apps whose content scrolls inside a panel rather
than the window are framed this way. A scrolled panel that can't be located,
such as one inside a closed shadow root, leaves the capture without a region
layout rather than framing the wrong content. Window-only captures, and every
card saved before panels were recorded, store no panel list and keep
window-only framing. Notes save the same list in the capture's `scrollers`
attribute.

Element captures from capture mode's element selector take the same path: the
element's viewport rectangle, outset by two points and clipped to the viewport,
is captured as a region and gets the same geometry (`EaselCaptureGeometry`).
The app carries that optional geometry through the existing exact-destination
import transaction. Old cards never acquire guessed coordinates. Cropped,
annotated or Portrait-framed captures retain their saved image without Make Live:
their changed output no longer describes the original renderer region. Undo and
persistence retain exact original asset identity, date, source URL and capture
geometry.

## Real page ownership

A live card is a member of the existing `EaselBrowserObjects` pool. Its pending
request and eventual actual page use the same creation, selection, visibility,
beforeunload, window-transfer and retirement boundaries as an ordinary embedded
browser object. The original capture page stays untouched. Reopening live mode
explicitly creates a new auxiliary page from the saved source, from its saved capture metadata; hiding the Easel preserves its existing live page.

The native positioning API only accepts an already-owned embedded page and
finite bounded geometry. Each attempt validates the same renderer document,
page, native window and embedded owner. Navigation, destruction, retirement or
transfer invalidates pending work. A five-second deadline bounds a nonresponsive
renderer; there are at most twenty attempts, spaced 100 ms apart. Stale callbacks cannot replace a newer
position or report it as successful.

When the capture recorded scroll panels, each attempt first clears Parc's
framing transform, restores every panel's scroll offset outermost first and
then the window's original offset, and checks that each panel reached its
offset and sits at its recorded frame within a few CSS pixels. Only then does
the attempt count as aligned; it reapplies the framing transform either way,
so a retry never shows an unframed page. Fonts and images that shift layout
late are absorbed by the same bounded retries.

The live page stays covered by the status card (“Lining up the region you
captured…”) from admission until positioning succeeds, so an unframed page is
never shown, even while a slow page keeps loading. Positioning starts as soon as
the document is ready; an attempt that fails while the page is still loading
waits for the load to finish and tries again. If a loaded page still can't be
framed, the card returns to its snapshot and the header says “Snapshot · couldn't
go live”, with Make live available to try again. The framed region takes
clicks and typing, but wheel scrolling over it scrolls the Easel rather than the
page, and deselecting the card re-frames it, so the page never drifts into an
unframed document (`EaselLiveFraming`).

The page retains normal renderer updates and original permission, dialog,
security, capture-stop and crash owners. Selected-object input uses the existing
single-selection canvas policy. The original screenshot remains immutable even
when the live page navigates: navigation never rewrites capture provenance.
Going back to the snapshot, deletion and Undo ask all original shared-document child
owners to retire before committing. A refused close preserves live mode. In a
multi-page Easel the check reads the whole document, so deleting or undoing on
one page never closes a live page that stays on another.

A board with any live page draws each object in its own layer around the native
pages; a board without one paints everything itself. When the last live page
leaves (deletion, Cut, Back to snapshot, Undo or Redo, on any page) or a first
one arrives, the canvas repaints the whole board in that same step, so nothing
waits for a zoom to come back. Pending positioning is suspended during retirement or physical-window transfer and resumes only after settlement; an already positioned page keeps its current interaction state.
Cross-Profile moves retire these same children before the document moves; the
destination owns fresh content in its destination Profile, never a rebound
source renderer.

## Presentation and checks

Parc stores the live preference with the local object so it follows document
Undo and relocation. Make live depends only on the saved card (image, web
address and valid region geometry), so it stays available after deselecting,
switching tabs, reopening the Easel or relaunching. The live page uses the
shared embed header described in [Easel editing](easels.md#embedded-webpages-and-captured-cards);
single-selection input reuses the shared embed surface (`NoteEmbedSurface`). The region fits
beneath that header without changing its aspect ratio or showing neighboring
page pixels. Oversized canvas objects letterbox at the original renderer's
maximum viewport extent. Browser zoom is accounted for without changing the
Profile's zoom preference. The fixed positioning script preserves unrelated
inline style rather than replacing the body's entire CSS text.

Injected page-pool checks cover geometry ownership, retirement and immutable
image persistence.

## Live captures in notes

A capture sent to a note becomes an image block carrying the same PNG, source
URL, acquisition time and optional geometry
([file format](notes-format.md#media-bookmarks-and-page-links)). Its labels and
can-go-live rule come from `EaselWebItemChrome` by mapping the block onto a web
card (`NoteCaptureLive`), and its header is the shared `EmbeddedPageHeader`.
Make live presents the same first-use education and stores `live` in the block,
so it follows Undo. The live page is a member of the note's `NoteEmbeddedPages`
pool, keyed by URL plus geometry, and takes the note's first-click, scroll
chaining and Escape rules. `EmbeddedLiveCapturePositioner` owns positioning with
the native API's validation and deadlines. Back to snapshot asks the page to
close before committing; a refused close keeps live mode. Navigation never
rewrites the saved source. `NoteCaptureTests` covers the format, exports,
labels, destination catalog and delivery into note files.
