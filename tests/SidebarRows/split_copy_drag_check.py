#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source
root = Path(__file__).resolve().parents[2]
controller = browser_window_controller_source(root / "Sources/ParcApp")
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
split = (root / "Sources/ParcApp/SplitDragView.swift").read_text()
drag = (root / "Sources/ParcApp/SidebarItemDrag.swift").read_text()
store = (root / "Sources/ParcCore/BrowserStore.swift").read_text()
tile = (root / "Sources/ParcApp/FavoriteTile.swift").read_text()
checks = 0

def body(source, signature):
    start = source.index(signature)
    depth, i = 0, source.index("{", start)
    for j in range(i, len(source)):
        depth += {"{": 1, "}": -1}.get(source[j], 0)
        if depth == 0:
            return source[start:j + 1]
    raise AssertionError(f"unterminated {signature}")

def expect(condition, message):
    global checks
    assert condition, message
    checks += 1

surface = body(split, "final class SidebarSplitMoveSurface: SidebarMoveHandle")
mask = body(surface, "override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)")
expect("guard context == .withinApplication else { return .copy }" in mask, "outside the app the split offers copy only")
expect("sidebarDrag?.allowsCopy == true ? [.move, .copy] : .move" in mask, "inside the app copy joins move only for copyable sessions")
handle = body(drag, "class SidebarMoveHandle: NSView, NSDraggingSource, SidebarItemDragSource")
expect("guard context == .withinApplication else { return [] }" in handle
       and "sidebarDrag?.allowsCopy == true ? [.move, .copy] : .move" in handle,
       "folder handles offer copy beside move inside Parc for copyable sessions, nothing outside")
row = body(sidebar, "final class SidebarTabRow: NSView, NSDraggingSource")
row_mask = body(row, "func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)")
expect("guard context == .withinApplication else { return [] }" in row_mask
       and "sidebarDrag?.allowsCopy == true ? [.move, .copy] : .move" in row_mask,
       "tab rows offer copy beside move inside Parc for copyable sessions, nothing outside")
expect("forType: SidebarMoveSession.pasteboardType" in handle and handle.count("setString") == 1,
       "the pasteboard item carries only the private session type")
expect("if let rendered = makeDragImage?() { image = rendered }" in handle, "a supplied renderer replaces the live capture")

group = body(split, "final class SidebarSplitGroupView: NSView")
image = body(group, "func dragImage() -> NSImage")
expect(image.index("setHover(false)") < image.index("cacheDisplay") < image.index("setHover(wasHovered)"),
       "the drag image is captured without hover, then hover is restored")
expect("moveSurface.makeDragImage = { [weak self] in self?.dragImage() }" in group, "the split cell renders its own drag image")

moves = body(controller, "func prepareSidebarMoves(_ items: [SidebarItemReference]) -> SidebarMoveSession?")
expect("allowsCopy: wholeSplits || folderDuplicateContextAvailable" in moves
       and "if case .split = $0 { return true } else { return false }" in moves,
       "every session can offer copy where copies are allowed, and whole splits as before")
wrapper = body(controller, "func prepareSidebarCopyDrop(")
expect("cached.key == key, cached.revision == store.stateRevision { return cached.action }" in wrapper
       and "copyDropCache = (key, store.stateRevision, action)" in wrapper,
       "dragging updates reuse one proposal per target and state revision")
copy = body(controller, "private func makeSidebarCopyDrop(")
for guard in ("session.allowsCopy", "session.isValidForWindowTransfer", "source.store === store",
              "folderDuplicateContextAvailable", "source.folderDuplicateContextAvailable",
              "sidebarWindowMoveEnvironment", "source.sidebarWindowMoveEnvironment",
              "InterProfileMove.profilesAvailable(source.activeProfileID, destinationProfile, in: store.state)",
              "SidebarItemsCopy(items: items, spaceID: source.activeSpaceID",
              "copy.wholeSplits || (source === self && destinationProfile == source.activeProfileID)"):
    expect(guard in copy, f"copy preparation condition missing: {guard}")
expect("store.canCopySidebarItems(" in copy and "guard !consumed" in copy and "consumed = true" in copy,
       "the copy is proposed without saving and runs once")
expect(copy.count("session.isValidForWindowTransfer") == 1 and copy.index("session.isValidForWindowTransfer") < copy.index("let current"),
       "the ended session is consulted only while preparing; copy(_:) validates it before running the action")
arrive = copy[copy.index("let arrive:"):copy.index("let perform:")]
perform = copy[copy.index("let perform:"):]
expect(arrive.index("self.registerSidebarCopyUndo(SidebarCopyUndo.dragCopyName") < arrive.index("self.openDuplicatedChildren(")
       < arrive.index("self.selectTab(") and perform.index("self.store.copySidebarItems(") < perform.index("arrive(result, urls)"),
       "copy saves, registers Undo Copy, then opens pages in the background and selects a whole-split copy")
expect("originatingSpaceID: location.spaceID, window: window)" in arrive and "spaceID: location.spaceID," in arrive,
       "Undo Copy belongs to the window and Space the copy landed in")
expect("if copy.wholeSplits, case .split(let id)? = result.roots.last" in arrive,
       "tab, folder and mixed copies leave selection alone, as Duplicate does")
expect(perform.count("arrive(result, urls)") == 2, "both the same-data and separate-data split copies register Undo")
expect("guard self.activeSpaceID == location.spaceID, self.activeProfileID == destinationProfile else" in arrive,
       "a copy is opened and selected only in the Space it landed in")
expect("guard destinationProfile != sourceProfile else { return perform() }" in copy
       and "self.confirmInterProfileMove(tabCount: copy.tabs.count, sourceProfiles: [sourceProfile]" in copy,
       "a cross-Profile copy first passes the inter-Profile decision")
expect("sidebar.prepareCopyDrop = { [weak self] session, items, location, before in" in controller, "the destination window prepares copies")

drag_tile = body(tile, "override func mouseDragged(with event: NSEvent)")
expect("!event.modifierFlags.contains(.option) || session.allowsCopy" in drag_tile, "a Favorite tile starts an Option drag whenever its session can copy")
tile_mask = body(tile, "func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)")
expect("sidebarDrag?.allowsCopy == true ? [.move, .copy] : .move" in tile_mask and "return []" in tile_mask,
       "a copyable tile offers copy and move inside Parc, nothing outside")

hd = body(sidebar, "private func headerOrDockDrop(")
header = hd[:hd.index("guard !spacesHost.isHiddenOrHasHiddenAncestor")]
expect("guard !copying" not in header and "admitDrop(session, to: pinned, before: before, copying: copying)" in header
       and "return copying ? .copy : .move" in header, "the Space header moves, or copies with Option")
expect('SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .pinned)' in header
       and "let before = copying ? children.first : children.first { !session.items.contains($0) }" in header,
       "after the pinnedTabsHeader accessory: the top of Pinned, above even the originals for a copy")
dock = hd[hd.index("guard !spacesHost.isHiddenOrHasHiddenAncestor"):]
expect("let items = session.items.filter { space(of: $0) != target }" in dock and "$0.kind != .favorite" in dock,
       "items already in the dock's Space are skipped; Favorites are in no Space")
expect("items.allSatisfy { [.pinned, .favorite].contains(kind($0)) } ? .pinned : .today" in dock,
       "the dock picks Pinned when every item is pinned or a Favorite, else Today")
expect("let top = SidebarHierarchy.children(in: destination, state: state).first { !items.contains($0) }" in dock,
       "dock drops land at index 0 of the list (drop type on → SidebarLocation index 0)")
expect("guard session.allowsCopy, let action = prepareCopyDrop?(session, items, destination, top)" in dock
       and dock.index("let items = session.items.filter") < dock.index("if copying {"),
       "a dock Option drop copies the items not already there to the top of the list")
expect("prepareDockDrop?(session, items, destination, top)" in dock, "a dock move runs the window's dock transaction")
perform_dock = body(sidebar, "override func performDragOperation(_ sender: NSDraggingInfo) -> Bool")
expect("else if let dock { dropped = session.transferThenEnd(dock) }" in perform_dock,
       "a dock drop finishes its transfer under the live session, then ends the drag")

dockc = body(controller, "func prepareSidebarDockDrop(")
expect("SidebarWindowMove(items: items, sourceSpaceID: source.activeSpaceID" in dockc and "destinationProfileID: space.profileID" in dockc,
       "the dock move is the ordinary placement into that Space, any Profile")
cross = dockc[dockc.index("if source !== self {"):dockc.index("guard sidebarWindowMoveAvailable, let validateOwners")]
expect(cross.index("self.selectSpaceFromUser(location.spaceID") < cross.index("self.prepareSidebarWindowDrop(session, to: location, before: top)"),
       "another window's items: this window shows the dock's Space, then receives them by window transfer")
expect("self.confirmInterProfileMove(" in dockc and "self.store.moveAcrossProfiles(moved, proposal: { current($0)?.applying(to: $0) })" in dockc,
       "a same-window dock move into another Profile passes the inter-Profile decision")
expect("_ = self.selectSpaceFromUser(location.spaceID, profileID: space.profileID)" in dockc,
       "the window then focuses the dock's Space")
expect("sidebar.prepareDockDrop = { [weak self] session, items, location, before in" in controller, "the window wires its dock drop")
expect(copy.index("self.store.copySidebarSplitsReloadingOriginals(") > copy.index("guard destinationProfile != sourceProfile else {"),
       "a cross-Profile copy reloads the originals through page consent (deleteAndReloadWindowContentsFor)")
expect("source.activeSpaceID == sourceSpace, let shown = sourceFocus" in copy and "_ = source.selectTab(shown)" in copy,
       "originals the source window showed are shown (reloaded) again")
expect(copy.index("if location.spaceID != self.activeSpaceID {") < copy.index("self.openDuplicatedChildren("),
       "a copy into another Space focuses that Space before opening and selecting the copy")

admit = body(sidebar, "private func admitDrop(")
expect(admit.index("if copying {") < admit.index("session.window === window"), "an Option drop never falls back to a move")
expect("session.allowsCopy, let action = prepareCopyDrop?(session, session.items, destination, before)" in admit, "copy needs the session and this window")
drop_update = body(sidebar, "private func updateDrop(_ sender: NSDraggingInfo) -> NSDragOperation")
expect("let operation = proposeDrop(sender)" in drop_update and "return operation" in drop_update,
       "each drag update reports the proposed drop's operation")
update = body(sidebar, "private func proposeDrop(_ sender: NSDraggingInfo) -> NSDragOperation")
expect("let copying = mask.contains(.copy) && option" in update and "option = NSEvent.modifierFlags.contains(.option)" in update,
       "Option held with a copy-capable source selects the copy")
expect("guard !option || copying else { return [] }" in update, "Option never lets a move-only source move")
expect(update.index("headerOrDockDrop(") < update.index("guard scroll.frame.contains(point)"), "the header and dock are targets before the outline")
expect(update.count("admitDrop(session, to: destination, before: before, copying: copying)") == 2, "tray and outline drops share the admission")
expect(update.count("return operation") == 2 and "return .move" not in update
       and "let operation: NSDragOperation = copying ? .copy : .move" in update,
       "the drop reports copy, so AppKit shows the green-plus copy pointer, or move")
expect("override func wantsPeriodicDraggingUpdates() -> Bool { true }" in sidebar,
       "periodic drag updates re-read Option, so the copy pointer follows Option pressed or released mid-drag")
expect("let children = SidebarHierarchy.children(in: folder, state: state)" in update
       and "before = copying ? children.first : children.first { !session.items.contains($0) }" in update,
       "a folder-middle copy lands at the very top of the folder")
pinned_header = body(sidebar, "private func pinnedHeaderDrop(")
expect("moving: copying ? [] : session.items" in pinned_header
       and "admitDrop(session, to: destination, before: first, copying: copying)" in pinned_header,
       "the collapsed Pinned header takes copies at the top of Pinned")
perform = body(sidebar, "override func performDragOperation(_ sender: NSDraggingInfo) -> Bool")
expect(perform.index("if let copy { dropped = session.copy(copy) }") < perform.index("else if let dock")
       < perform.index("else if let external") < perform.index("else { dropped = session.move(to: destination, before: before) }"),
       "a prepared copy runs instead of a dock transfer, window transfer or move")

place = body(store, "private func placedItemsCopy(")
expect(place.index("adjacentCopies(roots: copy.roots") < place.index("SidebarWindowMove(items: copied.result.roots"),
       "duplicate next to the originals with Duplicate's copier, then the ordinary move to the drop location")
expect("opensEverySplit: false" in place, "drag copies open only their first five items' pages")
duplicate = body(store, "func duplicateSidebarItems(")
expect("adjacentCopies(" in duplicate and "opensEverySplit: true" in duplicate, "Duplicate shares the same copier and keeps its page rule")
reload = body(store, "func copySidebarSplitsReloadingOriginals(")
expect(reload.index("withRetiredPages(originals") < reload.index("self.commitProfileSettings(value.state)"),
       "the originals' pages are retired with consent before the copy is saved")
expect("|| (copy.wholeSplits && copy.tabs.allSatisfy({ InternalPage(urlString: $0.savedURL) == nil }))" in place,
       "only whole web splits copy into a Space that keeps separate data; a Note or Easel alias never does")
expect("guard copy.wholeSplits, placed(holding: false) != nil" in reload, "the separate-data reload path is for whole splits only")
expect("now.matchesPlacement(of: copy)" in copy and "self.resolveSidebarCopyDestinations?(now.tabs)" in copy,
       "after the sheet the copy is rebuilt by placement and its current sources resolved")
expect("return immediate ?? began" in copy and "else if !done { NSSound.beep() }" in copy,
       "a remembered decision reports perform's result; a later refusal is heard")
expect("copy.matchesPlacement(of: original)" in place, "the store binds placement, not whole records")
expect("let now = current(self.store.state) else { return false }" in dockc and "proposal: { current($0)?.applying(to: $0) }" in dockc,
       "the dock move rebinds placement at drop and after the decision")
retire = body(controller, "private func retireSidebarItems(")
expect("|| (target.hierarchy.includesFavorites && profile == target.hierarchy.profileID)" in retire
       and retire.count("spaceID: space,") == 2,
       "undoing a tray copy works out the replacement selection in whichever Space of that data the window shows")
expect("$0.spaceID == spaceID || $0.kind == .favorite" in body(controller, "func openDuplicatedChildren("),
       "copied Favorite splits open their children whatever their home Space")
print(f"PASS: {checks} sidebar copy drag source assertions (no browser)")
