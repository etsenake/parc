# Space navigation ownership

Space navigation uses the existing physical browser window and its `WindowPresentation`. The Spaces menu carries a stable Space ID and its original profile ID, with a weak reference to the window that presented the menu. Reordering the shared Space list cannot redirect that item to a different Space. Deleted or reassigned destinations and closed or background owners refuse the action.

Next Space and Previous Space follow the current ordered list with wraparound, and are disabled when there is only one Space. Their existing Command-Option-Right/Left shortcuts, shortcut customization and command-bar command rows reach the same selection operation. They operate the active browser or its own command panel; Settings, Downloads, auxiliary windows and the last-active-window fallback are not navigation targets.

The sidebar buttons carry the same original Space/profile identity and expose the selected state and live availability. User selection is refused during page/window retirement, transfer, native tab fullscreen, an active tab switcher, theme editing, an attached sheet or native security reservation. A command-panel row may show prospective availability while its own panel is key; execution dismisses that panel and rechecks the real native window/security gate before changing state. Existing native security notifications refresh sidebar availability. Menu validation always checks current state again.

An accepted switch dismisses the previous history/hover/library presentation and uses the existing per-Space selection and native selection/layout path. It preserves split membership, profile ownership, existing native wrappers and accepted Peek sessions. It does not replay URLs, transfer another window’s page or ask pages to close. Selecting the already-selected Space leaves its focused split pane and Peek intact. Programmatic external-link and native routing entry points continue to use their own existing ownership rules.

## Returning to a Space

Each physical window remembers the actual focused tab alongside its existing per-Space selection. Pointer, native, split and explicit tab-selection changes update this record synchronously. Returning to a Space restores that focused member only while it still belongs to the destination selection, has the same profile and is available to this window. The existing native selection request keeps its exact wrapper/page identity and is consumed before native dispatch; a later user selection replaces it. Shared store publications do not create delayed focus requests.

The window also remembers the selected split’s orientation and relative pane sizes. If a pane closes, moves or becomes owned by another window, the remaining panes keep their order and proportional sizes. Selection and its validated projected split layout enter `BrowserStore` together, so reconciliation does not replace the returning arrangement with the default horizontal/equal split. Explicit changes to the current split continue to refresh its remembered layout.

If the remembered focused pane is unavailable, Parc retains its existing first-surviving-member fallback. It consumes the invalid focus immediately, so that page becoming available later cannot override a newer choice. With no surviving members, the existing empty-selection behavior remains; no additional tab ranking or page creation was added. This focus cache belongs to the live window and is not a new restart-persistence format. Accepted Peek remains attached to its original parent tab; returning to that parent uses the existing Peek presentation and selection path.

## Validation and scope

The window-presentation model checks per-Space focus return, closed-pane filtering,
proportional split restoration, stale-focus refusal and atomic selection/layout
admission. The cache belongs to the live window and does not add restart
persistence. Transition drawing and gesture behavior are maintained in
[sidebar motion](sidebar-motion.md), separately from this selection owner.
No live browser validation is established by these source/model checks.
