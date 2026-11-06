# Capture destinations and source attribution

The capture palette keeps Library, Copy, Save and Messages first, then the
editing actions and Retake, then New Easel and existing local Easels. The
user-requested reversible Portrait actions remain beside Crop. Existing Easels
rank by their most recent original Sidebar activity, descending; editing a
document does not promote it. Only two destinations show initially. Show More
reveals the rest without performing an output action. Search lowercases the
query and each current displayed title, searches all destinations including the
collapsed ones, and preserves the original action and activity order. A saved
Library toggle matches its current Saved to Library label. Search is a literal
substring match, including spaces; filtered results omit section dividers.

Selection retains an action ID or exact Easel UUID across title changes and
availability refreshes. New search text selects the first available result;
arrows skip unavailable actions, Return activates the selected result, and
Escape uses the existing capture cancellation owner. Expanding selects the first
newly exposed Easel. No result means no output selection. The expansion and
keyboard presentation use the same real action list as pointer clicks.

`CaptureEaselDestination.catalog` joins the profile's actual local document
catalog with the original non-archived Sidebar records. It resolves current and
saved internal Easel URLs to exact document UUIDs, takes the maximum matching
activity date in the original profile, and gives documents without a matching
Sidebar record no activity date. Local profile partitioning substitutes for the
excluded account/cloud permission model. A UUID tie-break for equal or absent
dates and including local documents without Sidebar references are deterministic
Parc adaptations. The existing Easel importer still reopens the selected UUID,
commits actual PNG bytes and metadata, and retains its undo session. Missing or
deleted destinations fail without creating substitutes. New Easel still uses
the original page title and opens the committed document, as the established
local document ownership adaptation.

Messages prepares the currently previewed PNG together with the original
capture lease's absolute URL, in URL-then-image order. It adds no title or brand
text. Crop and Portrait changes replace the image while keeping that original
source. An absent or relative source address produces an image-only payload;
this preserves Parc's existing available output and is an explicit adaptation
of the reference caller's missing-URL early return. No replacement URL is
looked up and no attribution is derived from the later selected tab. The same
prepared item types are checked for service availability and passed to the
native Compose Message service. The existing delegate continues to distinguish
completion, cancellation and failure; completion is not proof of recipient
delivery. Original lease invalidation detaches the callback. AppKit owns an
already-open composer and exposes no public retraction API.


Reference: retained arm64 main executable, SHA256
`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The retained component index, Swift type table, cross-reference index and
annotated original functions resolved this row; no heavy decompilation or
second-version tracing was needed. These are recovered contracts, not source.

- `CaptureImageMenuView` stores `elements`, `onSelected`, `selectedID` and
  `onExpanded`. Its Element cases distinguish divider, item and expandable
  `(numItemsToShow, items)`; `CapturedImageActionView.SelectedID` distinguishes
  item and expand.
  Edit and Retake, another divider, New Easel, then existing Easel items in an
  Easel ID, title, optional lastActive, shareStatus and creatorID.
  creator identity; the local profile-owned store replaces those excluded
  service identities rather than fabricating them.
- `CapturedImageActionsView` owns text, isExpanded and elements. Its update
  the selected toggle label/current item label and calls Foundation `contains`;
  expandable contents recurse through the same search, while dividers drop out.
  `SharingServiceClient.IMessagePayload`, stores the image, and explicitly zeros
  appends optional URL, image and text in that order. Its text support is not
  evidence that the capture caller supplies a page title or branded caption.

## Ownership and checks

CAP20 owns ranking, menu action/search/selection and message payloads. CAP18 owns
the private overlay's layout and row colors/drawing; CAP19 owns the Portrait
compositor and controls, and continues supplying current `CapturedImage` pixels.
CAP17 owns entry/admission. CAP21 replaces the current Crop `.edit` adaptation
with the recovered shared-canvas editor, introduces a separate `.crop` action in
`CaptureDestinationAction`/`CaptureDestinationMenu`, and owns context variants.
CAP23 owns external
media discovery, and CAP24 the remaining motion/focus/accessibility presentation.
The exact UUID output and original page/document/Profile/Space/window lease
remain shared acceptance boundaries, not duplicated state owners.

`CaptureDestinationTests` uses the actual destination model, native payload
preparation, importer, persistent Easel store and undo session with generated
PNG pixels and a disposable directory. It covers activity versus modification
order, profile isolation, collapsed and searched destinations, renamed UUID
selection, disabled/empty results, exact PNG/source payloads, missing attribution,
failed output and existing-document preservation. It never invokes a sharing
service, sends a message, opens a browser or touches the system pasteboard.
The component passes 43 assertions. Final whole-module SIL after CAP17/CAP18
integration passes in 29 seconds with zero diagnostics. Compiler and component
results do not claim browser-runtime, composer appearance
or accessibility acceptance.
