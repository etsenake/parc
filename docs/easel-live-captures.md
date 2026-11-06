# Live captured regions

A captured WebCard keeps its original PNG, URL, acquisition time and optional
renderer geometry. **Make Live**, on the selected card and its context menu,
opens a real auxiliary Chromium page in that Easel editor's window and Profile.
The first use presents the recovered Make it Live/Cancel education, explaining that sites can change and the original screenshot remains available through Snapshot. Its callback is bound to the same window, selection and document. The page is framed to the captured region. Its own renderer continues to update;
there is no screenshot timer or image relabeling. **Snapshot** returns to the
same original image after the live page actually agrees to close.

## Recovered contract

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The local component, type, cross-reference and annotated-function helpers resolve
this contract without new decompilation:

- `EaselClient.WebCard` owns image, text, URL, favicon, acquisition date,
  capture type and optional `CaptureLayoutInfo`. Layout stores web-content size,
  content offset and the rectangle relative to the viewport.
  actual canvas window, loads the original captured URL, retains the content and
  live toggle and first-use education; the preference uses the object identity.
  view and back. The live view retains its provider, content, positioning
  cancellation and an interaction overlay.
  scale from the displayed width divided by captured-region width, converts the
  stored rectangle's bottom-origin Y, and positions the real content.
  wait for the actual body to be ready, transform it using scale and translation,
  scroll to the scaled original offset, and accept an offset within three CSS
  pixels. `EaselLiveCaptureOverlay` separately owns forwarded input.

Exact helper outputs are retained in local `work/easel-coordination/easel23`.
These are static recovered facts, not a claim of observed browser behavior.

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
annotated or Portrait-framed outputs remain image cards: their changed output
cannot truthfully describe the original renderer region. Undo and persistence
retain exact original asset identity, date, source URL and capture geometry.

## Real page ownership

A live card is a member of the existing `EaselBrowserObjects` pool. Its pending
request and eventual actual page use the same creation, selection, visibility,
beforeunload, window-transfer and retirement boundaries as an ordinary embedded
browser object. The original capture page stays untouched. Reopening live mode
explicitly creates a new auxiliary page from the saved source, as the recovered
provider does; hiding the Easel preserves its existing live page.

The native positioning API only accepts an already-owned embedded page and
finite bounded geometry. Each attempt validates the same renderer document,
page, native window and embedded owner. Navigation, destruction, retirement or
transfer invalidates pending work. A five-second deadline bounds a nonresponsive
renderer; the twenty-attempt limit is recovered, while the 100-ms retry spacing
and deadline are Parc adaptations. Stale callbacks cannot replace a newer
position or report it as successful.

The page retains normal renderer updates and original permission, dialog,
security, capture-stop and crash owners. Selected-object input uses the existing
single-selection canvas policy. The original screenshot remains immutable even
when the live page navigates: navigation never rewrites capture provenance.
Switching to Snapshot, deletion and Undo ask all original shared-document child
owners to retire before committing. A refused close preserves live mode. Pending positioning is suspended during retirement or physical-window transfer and resumes only after settlement; an already positioned page keeps its current interaction state.
Cross-Profile moves retire these same children before the document moves; the
destination owns fresh content in its destination Profile, never a rebound
source renderer.

## Explicit adaptations and checks

Parc stores the live preference with the local object so it follows document
Undo and relocation. The compact security/reload/Snapshot control strip and
single-selection input reuse the existing browser-object surface. The region
fits beneath that strip without changing its aspect ratio or showing neighboring
page pixels. Oversized canvas objects letterbox at the original renderer's
maximum viewport extent. Browser zoom is accounted for without changing the
Profile's zoom preference. The fixed positioning script preserves unrelated
inline style rather than replacing the body's entire CSS text.

Compilation and injected page-pool checks validate source, geometry ownership,
retirement and immutable image persistence. They create no browser and make no
claim about installed appearance, animation, renderer interaction or runtime
acceptance. Functional browser tests remain prohibited.

The final integrated whole-module SIL pass has zero diagnostics. The real
Swift pool with injected engine replies passes 57 assertions, including delayed
source-window positioning, destination retry, stale-callback status suppression,
completed-page rollback and beforeunload refusal. The native capture translation
unit passes its pinned production compiler flags. Exact source `18b4012f` is
independently CLEAR and published. EASEL29's separately reviewed `e9221af7`
integration expands the pool to 76 assertions, including fresh destination
Profile pages for live cards and no live request for paused cards, while
preserving original pixels and capture geometry.

The dedicated engine owner completed v239/overlay247 apply, real engine build,
seal and dependent release app package, all with exit 0. The package at
`/Users/josh/Parc/build/independent-v239/development-app-a60c015` contains app
source `a60c0157` and both required new native capture exports. All 369 reviewed
inputs and 755 package inputs stayed unchanged; strict app and sibling-component
signature verification passed. Actual stage, artifact-verification and completion
receipts are in `work/integrated-engine239`; engine publication `11019b6f`
confirms delivery. EASEL23 is DONE under the source/component completion rule.
The package was not executed, and these checks do not claim browser runtime or
final appearance/motion acceptance.
