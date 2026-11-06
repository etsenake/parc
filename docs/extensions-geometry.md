# Extension geometry and artwork (EXT12)

EXT12 compares the native pinned actions, Site Control Center, genuine context
menu, popup window and extension side-panel container. Extension/profile/page
identity, action permission, pin order and the native host remain their existing
owners. EXT13 owns input/focus/hover/accessibility; EXT14 owns presentation and
teardown. Functional browser tests remain prohibited.

## Reference and finite comparison

SHA-256 `4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The retained native action snapshot findings use its corresponding Core image,
SHA-256 `97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`.

The starting evidence is `outputs/parc/arc-extension-action-popup-contract.md`,
`arc-extension-popup-presentation-contract.md` and
`arc-extension-side-panel-contract.md` under the retained research checkout,
plus [Site Control Center](web-interactions.md#site-control-center--web14).
`components.py`, `arctypes.py`, `arcidx.py` and `arcfn.py` answered the toolbar
and popup questions; no new REA/decompiler session was required. Bounded helper
outputs are retained in `work/extensions-checks/ext12/evidence/`.

| Surface | Recovered contract | Production disposition |
| --- | --- | --- |
| Sidebar pinned actions | `CommandBarPlaceholderButtonsView` constructs a native `SidebarCellButton` around a hosted `ToolbarActionImageView`: 28 × 28 surface, corner radius 9, zero stack spacing, 16-point artwork. | `ExtensionToolbarView(.sidebar)` uses adjoining 28-point surfaces; the icon's frame is independent of the button. Actual pin positions remain authoritative; compression hides only whole buttons. |
| Page toolbar pinned actions | `TopBarPanelView.Body` has `ForEach<ArraySlice<BrowserExtension>>` containing `ExtensionIconView` with a `ControlButton` overlay. Its rounded background is 32 × 24, radius 6, with a centered 16 × 16 icon. | `ExtensionToolbarView(.toolbar)` reserves 32 points per action and centers its 24-point height in the real pane bar. |
| Context menu | The retained original native helper `0xa89cc5c` uses `MenuControllerCocoa` with `isContextMenu:YES`. Native AppKit owns row geometry, marks, separators, submenus and model icons. | Existing `NativeExtensionContextMenu` uses that adapter on the actual Chromium model. No custom row size, tint or synthetic command is imposed. Version-specific model entries remain current Chromium adaptation. |
| Popup | A titled/closable child NSWindow, initial 300 × 300 content fallback, original native page view; frame-based sidebar/focused-view/window formula. It is not an arrow popover. | Existing presenter style and formulas already match. The app anchor now chooses the visible sidebar placeholder, otherwise the actual focused pane/Peek, otherwise the original window. A page toolbar no longer replaces the content anchor. |

## Sidebar and toolbar source evidence

`CommandBarPlaceholderButtonsView` is the live sidebar producer, distinct from
the old `BrowserExtensionsView` nominal type. The latter's type name alone is
not evidence of the pinned control class.

  `TopBarPanelView.Body` associated type binds this view to its extension array
  of nominal metadata.

The AppKit implementation retains existing native action tracking and the
immutable callback lease. `ExtensionActionButtonCell` supplies the centred
32-point canvas rectangle without changing the copied image, so the same image
may be used in the Site Control Center. Style chooses geometry; it does not retarget an
extension or replace a native action model.

## Popup anchor

`WindowViewController.ViewState.isCommandBarPlaceholderVisible`, then returns
`FocusedContentViewState.view`, then fallback. It does not use a toolbar-button
rectangle. Parc's `sidebar.usesContentToolbar` already hides the placeholder
when the selected pane toolbar is present. The anchor provider follows that
same visible-state distinction and includes an active Peek's content card.
`sidebar.isPresented` is the existing layout-owned availability state, including
Library, popup-window and fullscreen suppression plus sidebar transitions.

in the first member of `FocusedContentViewState`. Parc consequently uses the
Peek's actual content card, whose trailing/bottom geometry matches its focused
content, rather than its full-page modal host or toolbar.

`(Pw,Ph)`, sidebar width `S`, or focused view bounds converted to parent content
view `R`:

- Sidebar: `(max(S-W-40,40), Ph-H-10)`.
- Focused view: `(R.maxX-W-40, R.maxY-H-10)`.
- Window fallback: `(Pw-W-40, Ph-H-10)`.

It converts that point through the original parent window to screen coordinates.
The existing native presenter preserves this exact frame/content distinction;
no new screen clamp or toolbar-arrow geometry is added. Current native host
initialization and resize validation remain responsible for actual page size.

## Side-panel compatibility adaptation

[The shared native boundary](extensions-side-panel-adaptation.md) closes the
reference dependency with positive Arc1.122 evidence. Core table `0xc1d9cd0`
identifies key 14 and initializer `0x781790c`, which constructs false then reads
the typed Boolean preference `ExtensionSidePanelEnabled`. Global helper
`0x5fbef80` returns before presentation while the value is false. Native Browser
construction `0x315d588` allocates a zeroed features object; initialization
`0x315f02c` and native post-window setup `0x315e340` leave the panel UI slot
`+0xa8` zero, the exact slot read by the enabled helper at `0x5fbefd0`.
This identifies the dormant native default, not universal absence across every
possible override. The earlier negative Swift type/keypath searches were not
used to claim that no implementation could exist.

Parc explicitly includes genuine current-Chromium side panels (P0-15/EXT08), so
disabling their existing service to copy that dormant default would violate the
product scope. The app owns a deliberate native presentation adaptation:

- A trailing sibling shares the page region's top and bottom, below any capture
  or popup chrome. Preferred width is 30% of the window, bounded to 240–360
  points and clipped to the actual remaining content width. Initial or narrow
  layouts never create a positive off-window panel.
- `ExtensionSidePanelView` gives the real page a separate content container
  below a 32-point header. The generic category label “Extension” does not
  impersonate an extension name. The close control reuses the existing native
  32 × 24, radius-6 `SplitPaneControl` xmark skin, with panel-specific tooltip
  and accessibility label. Its hover, press, focus ring and key activation are
  the shared control implementation.
- The close control and Escape in shell controls call the native
  `closeExtensionSidePanel()` owner. EXT14 connects that API and page Escape to
  the genuine `SidePanelUI`, with original Browser/window/selection validation.
  A separate explicit panel focus scope includes the header and content so
  keyboard dismissal can restore the original responder without treating the
  entire browser window as panel-owned focus.
- The page's identity and rendering remain with its actual extension host.
  Resizing changes the original content container and its autoresizing page;
  it neither navigates another tab to the extension URL nor copies its artwork.
  The shell close button participates in the native key-view loop; only the
  content child is classified as a page owner.

styling. Native menus and extension popups retain their independently recovered
contracts above; this adaptation does not change their layout or lifetime.

## Checks and delivery boundary

Author receipts live in `work/extensions-checks/ext12/`. Native controls and
whole-module Swift checks are inert/compiler checks, not browser acceptance.
The earlier icon/popup increment passed warnings-as-errors whole-module SIL
with zero diagnostics (`claude-split-checks/ext12-geometry-final-anchor.json`)
and pinned native bridge syntax (`native-bridge.json`); all 307 mapped source
and patch hashes matched overlay245. Shared geometry and the image-only cell
correction were folded source-identically into EXT13's reviewed controls with
38 combined native assertions. Light/dark specimens confirmed image-only
rendering. Independent `ext12_geometry/ext12_review` cleared that published
increment and retired its completed review scope.

The final panel adaptation passes 10 inert header/content/close/Escape assertions
(`panel-chrome.log`) and 104 production motion/layout assertions, including
narrow and zero-sized panel fit (`panel-layout.log`). Its finished application
passed whole-module SIL with zero diagnostics
(`claude-split-checks/ext12-panel-header-final.json`). Inert light/dark header
specimens confirm label and close-glyph fit. Fresh independent reviewer
`ext12_geometry/ext12_panel_review` cleared the entire final diff and all new
files. Exact source hashes and clearance are retained in
`panel-review-inputs.json` and `panel-review-clearance.md`. Reconciliation with
native dependency `73068de0` preserves the reviewed panel changes and exact
bridge header; unrelated published theme Undo changes remain intact.

The full EXT12 row is complete under the current implementation/check rule.
Panel width, header and immediate layout remain explicitly documented
compatibility choices. No functional browser, live focus traversal or renderer
runtime acceptance is claimed. The engine owner alone refreshes canonical
inputs and runs apply/build/package, pairing this app consumer with overlay246.
