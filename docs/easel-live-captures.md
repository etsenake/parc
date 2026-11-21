# Live captured regions

A captured WebCard keeps its original PNG, URL, acquisition time and optional
renderer geometry. **Make Live**, on the selected card and its context menu,
opens a real auxiliary Chromium page in that Easel editor's window and Profile.
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
but offers no live-region capability. Full-page captures have no region layout.

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

The page retains normal renderer updates and original permission, dialog,
security, capture-stop and crash owners. Selected-object input uses the existing
single-selection canvas policy. The original screenshot remains immutable even
when the live page navigates: navigation never rewrites capture provenance.
Going back to the snapshot, deletion and Undo ask all original shared-document child
owners to retire before committing. A refused close preserves live mode. Pending positioning is suspended during retirement or physical-window transfer and resumes only after settlement; an already positioned page keeps its current interaction state.
Cross-Profile moves retire these same children before the document moves; the
destination owns fresh content in its destination Profile, never a rebound
source renderer.

## Presentation and checks

Parc stores the live preference with the local object so it follows document
Undo and relocation. Make live depends only on the saved card (image, web
address and valid region geometry), so it stays available after deselecting,
switching tabs, reopening the Easel or relaunching. The live page uses the
shared embed header described in [Easel editing](easels.md#embedded-webpages-and-captured-cards);
single-selection input reuses the browser-object surface. The region fits
beneath that header without changing its aspect ratio or showing neighboring
page pixels. Oversized canvas objects letterbox at the original renderer's
maximum viewport extent. Browser zoom is accounted for without changing the
Profile's zoom preference. The fixed positioning script preserves unrelated
inline style rather than replacing the body's entire CSS text.

Injected page-pool checks cover geometry ownership, retirement and immutable
image persistence.
