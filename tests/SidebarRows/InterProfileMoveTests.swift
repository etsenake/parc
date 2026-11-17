import Foundation

@main @MainActor struct InterProfileMoveTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ reason: String) throws {
        count += 1; if try !value() { throw NSError(domain: reason, code: count) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        try gateAndPrompt()
        try splitDrop()
        try stackedSplitDrops()
        try collectionMoves()
        try storeTransaction()
        try sameProfileDrop()
        try documentRelocation()
        try mixedDocumentCollection()
        try sharedAssetRollback()
        try documentBlocks()
        try dataChangeBlocks()
        print("InterProfileMoveTests: \(count) assertions passed")
    }

    static func gateAndPrompt() throws {
        let p = UUID(), q = UUID()
        try check(InterProfileMoveGate.resolve(sourceProfiles: [], destination: q, decision: nil, bypass: false) == .proceed(remembersChoice: false), "empty move proceeds")
        try check(InterProfileMoveGate.resolve(sourceProfiles: [q], destination: q, decision: nil, bypass: false) == .proceed(remembersChoice: false), "same Profile proceeds without prompt")
        try check(InterProfileMoveGate.resolve(sourceProfiles: [p, q], destination: q, decision: .proceed, bypass: true) == nil, "multiple source Profiles refuse")
        try check(InterProfileMoveGate.resolve(sourceProfiles: [p], destination: q, decision: nil, bypass: false) == .confirm, "the unregistered default asks")
        try check(InterProfileMoveGate.resolve(sourceProfiles: [p], destination: q, decision: nil, bypass: true) == .proceed(remembersChoice: false), "remembered bypass skips the dialog")
        try check(InterProfileMoveGate.resolve(sourceProfiles: [p], destination: q, decision: .abort, bypass: true) == .abort, "abort cancels")
        try check(InterProfileMoveGate.resolve(sourceProfiles: [p], destination: q, decision: .proceed, bypass: false) == .proceed(remembersChoice: false), "proceed once")
        try check(InterProfileMoveGate.resolve(sourceProfiles: [p], destination: q, decision: .alwaysProceed, bypass: false) == .proceed(remembersChoice: true), "always stores preference")
        let one = InterProfileMovePrompt(tabCount: 1, spaceName: "Work")
        try check(one.title == "Move tab to Work?", "singular title")
        try check(one.message == "Work uses different data, so you might get logged out or lose your progress in this tab.\n\nThis can't be undone!", "singular message")
        let many = InterProfileMovePrompt(tabCount: 3, spaceName: "Work")
        try check(many.title == "Move tabs to Work?" && many.message.contains("progress in these tabs."), "plural copy")
        try check(InterProfileMovePrompt.displayName("123456789012345678901234") == "123456789012345678901234", "24 characters fit")
        try check(InterProfileMovePrompt.displayName("12345678901234567890123 5") == "12345678901234567890123…", "truncation trims then appends ellipsis")
        try check(InterProfileMovePrompt.confirmTitle == "Move it" && InterProfileMovePrompt.cancelTitle == "Cancel"
            && InterProfileMovePrompt.suppressionTitle == "Don’t ask again" && InterProfileMovePrompt.dialogWidth == 455, "recovered controls")
        try check(InterProfileMovePrompt.decision(confirmed: true, suppressed: false) == .proceed
            && InterProfileMovePrompt.decision(confirmed: true, suppressed: true) == .alwaysProceed
            && InterProfileMovePrompt.decision(confirmed: false, suppressed: true) == .abort, "dialog decision mapping")
        var state = BrowserState.initial()
        state.spaces.append(BrowserSpace(id: UUID(), name: "", symbol: "circle", color: "B9B5D4", profileID: state.profiles[0].id))
        try check(InterProfileMovePrompt(tabCount: 1, destinationSpaceID: state.spaces[1].id, state: state)?.destinationName == "Space 2", "untitled Space uses Space N")
    }

    struct Fixture {
        var state: BrowserState
        let p: BrowserProfile, q: BrowserProfile
        let s: BrowserSpace, d: BrowserSpace
        let today: BrowserTab, pinned: BrowserTab, g1: BrowserTab, g2: BrowserTab, sibling: BrowserTab
        let d1: BrowserTab, d2: BrowserTab
        let group: BrowserSplitLayout
        let root: SidebarContainerLocation
    }

    static func fixture() -> Fixture {
        let p = BrowserProfile(id: UUID(), name: "Personal"), q = BrowserProfile(id: UUID(), name: "Work")
        let s = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "AABBCC", profileID: p.id)
        let d = BrowserSpace(id: UUID(), name: "Office", symbol: "circle", color: "AABBCC", profileID: q.id)
        func tab(_ space: BrowserSpace, _ kind: TabKind, _ name: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://live.invalid/" + name,
                title: "Live " + name, kind: kind, folderID: nil, createdAt: Date(timeIntervalSince1970: 1),
                lastAccessed: Date(timeIntervalSince1970: 2), savedURL: "https://saved.invalid/" + name, savedTitle: "Saved " + name)
        }
        var today = tab(s, .today, "today"); today.referrerID = UUID()
        let pinned = tab(s, .pinned, "pinned"), sibling = tab(s, .pinned, "sibling")
        let g1 = tab(s, .today, "g1"), g2 = tab(s, .today, "g2")
        let d1 = tab(d, .today, "d1"), d2 = tab(d, .today, "d2")
        let group = BrowserSplitLayout(sidebarAnchorID: g1.id, customTitle: "Pair", spaceID: s.id, tabIDs: [g1.id, g2.id],
                                       orientation: .vertical, widthFactors: [0.4, 0.6])
        var state = BrowserState(profiles: [p, q], spaces: [s, d], activeSpaceID: d.id)
        state.tabs = [today, pinned, sibling, g1, g2, d1, d2]; state.splitLayouts = [group]
        let root = SidebarContainerLocation(spaceID: s.id, folderID: nil, section: .pinned)
        state.sidebarItemOrder[root.key] = [.tab(sibling.id), .tab(pinned.id)]
        state.selectedTabIDs = [d1.id]; state.selectionBySpace = [s.id.uuidString: [pinned.id], d.id.uuidString: [d1.id]]
        return Fixture(state: state, p: p, q: q, s: s, d: d, today: today, pinned: pinned, g1: g1, g2: g2,
                       sibling: sibling, d1: d1, d2: d2, group: group, root: root)
    }

    static func request(_ f: Fixture, _ source: BrowserTab, target: SplitDropTarget = .insert(1),
                        selection: [UUID]? = nil, layout: BrowserSplitLayout? = nil, home: UUID = UUID(),
                        homes: [UUID: UUID] = [:]) -> ForeignSplitDrop.Request {
        ForeignSplitDrop.Request(source: source, sourceHomeID: home, spaceID: f.d.id, profileID: f.q.id,
            selection: selection ?? [f.d1.id], layout: layout, target: target, orientation: .horizontal, destinationHomeIDs: homes)
    }

    static func splitDrop() throws {
        let f = fixture(), now = Date(timeIntervalSince1970: 99)
        func propose(_ r: ForeignSplitDrop.Request, _ state: BrowserState? = nil) -> BrowserState? {
            ForeignSplitDrop.proposal(r, state: state ?? f.state, now: now, creation: nil)
        }
        let moved = try unwrap(propose(request(f, f.today)), "Today original crosses Profiles")
        let live = moved.tabs.first { $0.id == f.today.id }!
        try check(live.profileID == f.q.id && live.spaceID == f.d.id && live.kind == .today && live.folderID == nil, "original record carries destination Profile/Space")
        try check(live.url == f.today.url && live.title == f.today.title && live.referrerID == f.today.referrerID, "original identity, URL and provenance retained")
        try check(moved.selectedTabIDs == [f.d1.id, f.today.id] && moved.splitLayouts.contains { $0.tabIDs == [f.d1.id, f.today.id] && $0.spaceID == f.d.id }, "destination group publishes with original")
        try check(moved.tabs.count == f.state.tabs.count, "Today move creates no copy")
        let home = UUID()
        let saved = try unwrap(propose(request(f, f.pinned, home: home)), "pinned original crosses Profiles")
        let copy = saved.tabs.first { $0.id == home }!
        try check(copy.profileID == f.p.id && copy.spaceID == f.s.id && copy.kind == .pinned && copy.url == f.pinned.savedURL && copy.title == f.pinned.savedTitle, "fresh home stays in source Profile with saved destination")
        try check(SidebarHierarchy.children(in: f.root, state: saved) == [.tab(f.sibling.id), .tab(home)], "home replaces exact source parent slot")
        try check(saved.selectionBySpace[f.s.id.uuidString] == [home], "source Space remembers the home, not the moved original")
        try check(saved.tabs.first { $0.id == f.pinned.id }?.kind == .today && saved.tabs.first { $0.id == f.pinned.id }?.profileID == f.q.id, "live original becomes destination Today")
        try check(propose(request(f, f.pinned, home: f.sibling.id)) == nil, "colliding home identity refuses")
        let child = try unwrap(propose(request(f, f.g2)), "split child crosses Profiles")
        try check(!child.splitLayouts.contains { $0.id == f.group.id } && child.tabs.first { $0.id == f.g1.id } == f.g1, "two-member source split dissolves, survivor intact")
        var three = f.state
        let g3 = BrowserTab(id: UUID(), spaceID: f.s.id, profileID: f.p.id, url: "https://live.invalid/g3", title: "g3", kind: .today,
                            folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "https://live.invalid/g3", savedTitle: "g3")
        three.tabs.append(g3); three.splitLayouts[0].tabIDs = [f.g1.id, f.g2.id, g3.id]; three.splitLayouts[0].widthFactors = [0.2, 0.3, 0.5]
        let anchorMoved = try unwrap(propose(request(f, f.g1), three), "anchor child crosses Profiles")
        let kept = anchorMoved.splitLayouts.first { $0.id == f.group.id }!
        try check(kept.tabIDs == [f.g2.id, g3.id] && kept.sidebarAnchorID == f.g2.id && kept.customTitle == "Pair" && kept.orientation == .vertical, "surviving source group keeps identity/appearance and reanchors")
        try check(abs(kept.widthFactors.reduce(0, +) - 1) < 0.0001, "surviving proportions renormalize")
        var grouped = f.state
        let layout = BrowserSplitLayout(spaceID: f.d.id, tabIDs: [f.d1.id, f.d2.id], orientation: .horizontal, widthFactors: [0.5, 0.5])
        grouped.splitLayouts.append(layout); grouped.selectedTabIDs = layout.tabIDs; grouped.selectionBySpace[f.d.id.uuidString] = layout.tabIDs
        let joined = try unwrap(propose(request(f, f.today, target: .insert(2), selection: layout.tabIDs, layout: layout), grouped), "join existing group")
        try check(joined.splitLayouts.first { $0.id == layout.id }?.tabIDs == [f.d1.id, f.d2.id, f.today.id], "existing destination group identity retained")
        let replaced = try unwrap(propose(request(f, f.today, target: .replace(0))), "center replacement")
        try check(replaced.selectedTabIDs == [f.today.id] && replaced.tabs.contains { $0.id == f.d1.id && $0.archivedAt == nil }, "displaced page survives")
        var note = f.state; let noteID = UUID(); note.tabs[0].url = InternalPage.note(noteID).urlString; note.tabs[0].savedURL = note.tabs[0].url
        let movedNote = try unwrap(propose(request(f, note.tabs[0]), note), "Today Note crosses Profiles")
        try check(InterProfileMove.documents(moving: [f.today.id], after: movedNote) == [.note(noteID)], "its document moves to the destination store")
        var pinnedNote = f.state; pinnedNote.tabs[1].url = InternalPage.note(noteID).urlString; pinnedNote.tabs[1].savedURL = pinnedNote.tabs[1].url
        let split = try unwrap(propose(request(f, pinnedNote.tabs[1]), pinnedNote), "pinned Note proposal")
        try check(InterProfileMove.documents(moving: [f.pinned.id], after: split) == nil, "a home alias left in the source Profile keeps the document there")
        var favorite = f.state; favorite.tabs[0].kind = .favorite
        try check(propose(request(f, favorite.tabs[0]), favorite) == nil, "Profile-wide Favorite refuses")
        var navigated = f.state; navigated.tabs[0].url = "https://live.invalid/next"; navigated.tabs[0].title = "Next"
        navigated.tabs[0].savedURL = navigated.tabs[0].url; navigated.tabs[0].savedTitle = navigated.tabs[0].title
        navigated.tabs[0].lastAccessed = Date(); navigated.tabs[0].isUnread = true
        let reloaded = try unwrap(propose(request(f, f.today), navigated), "live navigation after the gesture")
        try check(reloaded.tabs.first { $0.id == f.today.id }?.url == "https://live.invalid/next", "current live URL is what the destination reloads")
        var changed = f.state; changed.tabs[0].customTitle = "Renamed"
        try check(propose(request(f, f.today), changed) == nil, "changed saved metadata refuses stale gesture")
        changed = f.state; changed.tabs[1].folderID = UUID()
        try check(propose(request(f, f.pinned), changed) == nil, "changed parent refuses stale gesture")
        var removal = f.state; removal.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: f.q.id, profileName: "Work")]
        try check(propose(request(f, f.today), removal) == nil, "pending Profile removal refuses")
        var sameProfile = f.state; sameProfile.tabs[0].profileID = f.q.id; sameProfile.tabs[0].spaceID = f.d.id
        try check(propose(request(f, sameProfile.tabs[0]), sameProfile)?.tabs.first { $0.id == f.today.id }?.profileID == f.q.id, "same-Space same-Profile drop resolves through the ordinary drop")
    }

    static func stackedSplitDrops() throws {
        let f = fixture(), now = Date(timeIntervalSince1970: 99)
        func propose(_ r: ForeignSplitDrop.Request, _ state: BrowserState) -> BrowserState? {
            ForeignSplitDrop.proposal(r, state: state, now: now, creation: nil)
        }
        var grouped = f.state
        let flat = BrowserSplitLayout(spaceID: f.d.id, tabIDs: [f.d1.id, f.d2.id], orientation: .horizontal, widthFactors: [0.5, 0.5])
        grouped.splitLayouts.append(flat); grouped.selectedTabIDs = flat.tabIDs; grouped.selectionBySpace[f.d.id.uuidString] = flat.tabIDs
        let stacked = try unwrap(propose(request(f, f.today, target: .stack(0, after: true), selection: flat.tabIDs, layout: flat), grouped),
                                 "a cross-Profile drop stacks onto a flat split")
        let column = try unwrap(stacked.splitLayouts.first { $0.id == flat.id }, "the destination split keeps its identity")
        try check(column.tabIDs == [f.d1.id, f.today.id, f.d2.id] && column.stacks?.slotSizes == [2, 1] && column.orientation == .horizontal
            && stacked.tabs.first { $0.id == f.today.id }?.profileID == f.q.id, "the moved original stacks below its pane in the destination Profile")
        let joined = try unwrap(propose(request(f, f.g1, target: .stack(1, after: true), selection: column.tabIDs, layout: column), stacked),
                                "a cross-Profile drop joins an existing stack")
        let full = try unwrap(joined.splitLayouts.first { $0.id == flat.id }, "the stacked split keeps its identity")
        try check(full.tabIDs == [f.d1.id, f.today.id, f.g1.id, f.d2.id] && full.stacks?.slotSizes == [3, 1], "it lands below the stacked pane")
        try check(propose(request(f, f.g2, target: .stack(3, after: false), selection: full.tabIDs, layout: full), joined) == nil
            && propose(request(f, f.g2, target: .replace(3), selection: full.tabIDs, layout: full), joined) != nil,
                  "a full split refuses a stack drop but still takes a replacement")
        var same = f.state
        let other = BrowserSpace(id: UUID(), name: "Errands", symbol: "circle", color: "AABBCC", profileID: f.p.id)
        let errands = ["e1", "e2"].map { name in
            BrowserTab(id: UUID(), spaceID: other.id, profileID: f.p.id, url: "https://live.invalid/" + name, title: name, kind: .today,
                       folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "https://live.invalid/" + name, savedTitle: name)
        }
        let pair = BrowserSplitLayout(spaceID: other.id, tabIDs: errands.map(\.id), orientation: .vertical, widthFactors: [0.5, 0.5])
        same.spaces.append(other); same.tabs += errands; same.splitLayouts.append(pair)
        func local(_ source: BrowserTab, _ target: SplitDropTarget, _ layout: BrowserSplitLayout) -> ForeignSplitDrop.Request {
            ForeignSplitDrop.Request(source: source, sourceHomeID: UUID(), spaceID: other.id, profileID: f.p.id,
                selection: layout.tabIDs, layout: layout, target: target, orientation: .vertical, destinationHomeIDs: [:])
        }
        let row = try unwrap(propose(local(f.today, .stack(1, after: false), pair), same), "a same-Profile drop stacks onto a flat split")
        let rowLayout = try unwrap(row.splitLayouts.first { $0.id == pair.id }, "the same-Profile split keeps its identity")
        try check(rowLayout.tabIDs == [errands[0].id, f.today.id, errands[1].id] && rowLayout.stacks?.slotSizes == [1, 2]
            && rowLayout.orientation == .vertical && row.tabs.first { $0.id == f.today.id }?.profileID == f.p.id,
                  "the original keeps its Profile and sits left of the lower pane")
        let grown = try unwrap(propose(local(f.g1, .stack(2, after: true), rowLayout), row), "a same-Profile drop joins an existing stack")
        try check(grown.splitLayouts.first { $0.id == pair.id }?.tabIDs == [errands[0].id, f.today.id, errands[1].id, f.g1.id]
            && grown.splitLayouts.first { $0.id == pair.id }?.stacks?.slotSizes == [1, 3], "it lands right of the stacked pane")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-foreign-stack-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(grouped).write(to: directory.appendingPathComponent("session.json"))
        let crossStore = try BrowserStore(directory: directory)
        crossStore.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        let crossRequest = request(f, f.today, target: .stack(0, after: true), selection: flat.tabIDs, layout: flat)
        var result: Result<Bool, Error>?
        crossStore.moveAcrossProfiles([f.today.id], proposal: { propose(crossRequest, $0) }) { result = $0 }
        try check((try? result?.get()) == true, "a cross-Profile stack drop commits through the reload transaction")
        let crossSaved = try BrowserStore(directory: directory).state.splitLayouts.first { $0.id == flat.id }
        try check(crossSaved?.tabIDs == [f.d1.id, f.today.id, f.d2.id] && crossSaved?.stacks?.slotSizes == [2, 1], "the cross-Profile stack saves with the move")
        try encoder.encode(same).write(to: directory.appendingPathComponent("session.json"))
        let sameStore = try BrowserStore(directory: directory)
        var retired = false
        sameStore.requestPageRetirement = { _, _, completion in retired = true; completion(false) }
        try check(try sameStore.commitForeignSplitDrop([f.today.id]) { propose(local(f.today, .stack(1, after: false), pair), $0) } && !retired,
                  "a same-Profile stack drop commits without a reload")
        let sameSaved = try BrowserStore(directory: directory).state.splitLayouts.first { $0.id == pair.id }
        try check(sameSaved?.tabIDs == [errands[0].id, f.today.id, errands[1].id] && sameSaved?.stacks?.slotSizes == [1, 2],
                  "the same-Profile stack saves with the placement")
    }

    static func collectionMoves() throws {
        let f = fixture()
        let from = SidebarHierarchySnapshot(state: f.state, spaceID: f.s.id, profileID: f.p.id)!
        let to = SidebarHierarchySnapshot(state: f.state, spaceID: f.d.id, profileID: f.q.id)!
        let move = try unwrap(SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: f.state), "whole split Move to another Profile")
        try check(move.crossesProfiles && move.tabIDs == f.group.tabIDs, "whole group crosses as one container")
        let applied = try unwrap(move.applying(to: f.state), "apply whole-group move")
        try check(applied.tabs.filter { f.group.tabIDs.contains($0.id) }.allSatisfy { $0.profileID == f.q.id && $0.spaceID == f.d.id }, "every child carries the destination Profile")
        var expected = f.group; expected.spaceID = f.d.id
        try check(applied.splitLayouts == [expected], "group ID, anchor, appearance and proportions survive")
        try check(applied.tabs.first { $0.id == f.g1.id }?.url == f.g1.url, "live URL retained for destination reload")
        try check(SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: from, state: f.state) == nil, "same Space refuses")
        var note = f.state; let easelID = UUID(); note.tabs[3].url = InternalPage.easel(easelID).urlString
        let noteFrom = SidebarHierarchySnapshot(state: note, spaceID: f.s.id, profileID: f.p.id)!
        let withEasel = try unwrap(SidebarSpaceMove(items: [.split(f.group.id)], from: noteFrom, to: to, state: note)?.applying(to: note), "group with an Easel crosses Profiles")
        try check(InterProfileMove.documents(moving: Set(f.group.tabIDs), after: withEasel) == [.easel(easelID)], "the Easel document moves with its group")
        var removing = f.state; removing.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: f.q.id, profileName: "Work")]
        try check(SidebarHierarchySnapshot(state: removing, spaceID: f.d.id, profileID: f.q.id) == nil, "removed destination Profile has no snapshot")
        let location = SidebarContainerLocation(spaceID: f.d.id, folderID: nil, section: .today)
        let window = try unwrap(SidebarWindowMove(items: [.split(f.group.id)], sourceSpaceID: f.s.id, profileID: f.p.id,
            destinationProfileID: f.q.id, to: location, before: .tab(f.d1.id), state: f.state), "window drop crosses Profiles")
        try check(window.crossesProfiles, "window move records Profile crossing")
        let dropped = try unwrap(window.applying(to: f.state), "window move applies")
        try check(dropped.tabs.filter { f.group.tabIDs.contains($0.id) }.allSatisfy { $0.profileID == f.q.id && $0.spaceID == f.d.id && $0.kind == .today }, "dropped children take destination section and Profile")
        try check(SidebarHierarchy.children(in: location, state: dropped).first == .split(f.group.id), "drop lands before the requested destination item")
        let tray = SidebarContainerLocation(spaceID: f.d.id, folderID: nil, section: .favorite, profileID: f.q.id)
        let toTray = try unwrap(SidebarWindowMove(items: [.split(f.group.id)], sourceSpaceID: f.s.id, profileID: f.p.id,
            destinationProfileID: f.q.id, to: tray, before: nil, state: f.state)?.applying(to: f.state), "whole split enters another Profile's tray")
        try check(toTray.tabs.filter { f.group.tabIDs.contains($0.id) }.allSatisfy { $0.kind == .favorite && $0.profileID == f.q.id && $0.folderID == nil }, "tray drop makes destination-Profile Favorites")
        try check(SidebarHierarchy.children(in: tray, state: toTray) == [.split(f.group.id)], "whole group occupies one tray slot")
        var favoriteSource = f.state
        let favorite = BrowserTab(id: UUID(), spaceID: f.s.id, profileID: f.p.id, url: "https://live.invalid/fav", title: "Fav",
            kind: .favorite, folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "https://saved.invalid/fav", savedTitle: "Fav")
        let sourceTray = SidebarContainerLocation(spaceID: f.s.id, folderID: nil, section: .favorite, profileID: f.p.id)
        favoriteSource.tabs.append(favorite); favoriteSource.sidebarItemOrder[sourceTray.key] = [.tab(favorite.id)]
        let favoriteMoved = try unwrap(SidebarWindowMove(items: [.tab(favorite.id)], sourceSpaceID: f.s.id, profileID: f.p.id,
            destinationProfileID: f.q.id, to: location, before: nil, state: favoriteSource)?.applying(to: favoriteSource), "Favorite leaves its Profile's tray")
        let arrived = favoriteMoved.tabs.first { $0.id == favorite.id }!
        try check(arrived.kind == .today && arrived.profileID == f.q.id && arrived.spaceID == f.d.id && arrived.savedURL == favorite.url, "Favorite becomes a destination Today item under the existing section conversion")
        try check(SidebarHierarchy.children(in: sourceTray, state: favoriteMoved).isEmpty, "source tray slot is vacated")
        try check(SidebarWindowMove(items: [.split(f.group.id)], sourceSpaceID: f.s.id, profileID: f.p.id,
            to: location, before: nil, state: f.state) == nil, "implicit same-Profile drop still refuses another Profile")
    }

    static func storeTransaction() throws {
        let f = fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-inter-profile-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let file = directory.appendingPathComponent("session.json")
        try encoder.encode(f.state).write(to: file)
        let store = try BrowserStore(directory: directory)
        try check(!store.bypassesInterProfileMoveConfirmation, "dialog preference defaults off")
        let r = request(f, f.today)
        let proposal: (BrowserState) -> BrowserState? = { ForeignSplitDrop.proposal(r, state: $0, now: Date(), creation: nil) }
        var asked: Set<UUID> = []
        store.requestPageRetirement = { ids, _, completion in asked = ids; completion(false) }
        var result: Result<Bool, Error>?
        store.moveAcrossProfiles([f.today.id], proposal: proposal) { result = $0 }
        try check(asked == [f.today.id] && (try? result?.get()) == false && store.state == f.state, "refused page consent publishes nothing")
        var pending: (() -> Bool, (Bool) -> Void)?
        store.requestPageRetirement = { _, shouldCommit, completion in pending = (shouldCommit, completion) }
        result = nil
        store.moveAcrossProfiles([f.today.id], proposal: proposal) { result = $0 }
        try check(store.retiringTabIDs == [f.today.id] && result == nil, "moved tab is reserved while pages retire")
        try check(pending?.0() == true && store.state == f.state, "approval does not publish before every page closes")
        pending?.1(true)
        try check((try? result?.get()) == true, "move commits after retirement")
        try check(store.state.tabs.first { $0.id == f.today.id }?.profileID == f.q.id && store.retiringTabIDs.isEmpty, "record published in destination Profile")
        let reopened = try BrowserStore(directory: directory)
        try check(reopened.state.tabs.first { $0.id == f.today.id }?.profileID == f.q.id, "move persisted atomically")
        var edited = f.state; edited.tabs[0].customTitle = "Renamed"
        try encoder.encode(edited).write(to: file)
        let staleStore = try BrowserStore(directory: directory)
        staleStore.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        result = nil
        staleStore.moveAcrossProfiles([f.today.id], proposal: proposal) { result = $0 }
        try check((try? result?.get()) == false && staleStore.state == edited, "changed original after the gesture refuses")
        try encoder.encode(f.state).write(to: file)
        let failing = try BrowserStore(directory: directory)
        failing.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        result = nil
        failing.moveAcrossProfiles([f.today.id], proposal: proposal) { result = $0 }
        var failed = false
        if case .failure? = result { failed = true }
        try check(failed && failing.state == f.state, "failed save publishes nothing")
        try FileManager.default.removeItem(at: file)
        var emptyFolder = f.state
        let folder = BrowserFolder(id: UUID(), spaceID: f.s.id, name: "Empty")
        emptyFolder.folders.append(folder); emptyFolder.sidebarItemOrder[f.root.key]?.append(.folder(folder.id))
        try encoder.encode(emptyFolder).write(to: file)
        let folders = try BrowserStore(directory: directory)
        var retiredEmpty = false
        folders.requestPageRetirement = { _, _, completion in retiredEmpty = true; completion(false) }
        let folderMove = SidebarSpaceMove(items: [.folder(folder.id)],
            from: SidebarHierarchySnapshot(state: emptyFolder, spaceID: f.s.id, profileID: f.p.id)!,
            to: SidebarHierarchySnapshot(state: emptyFolder, spaceID: f.d.id, profileID: f.q.id)!, state: emptyFolder)!
        try check(folderMove.tabIDs.isEmpty && InterProfileMoveGate.resolve(sourceProfiles: [], destination: f.q.id,
            decision: nil, bypass: false) == .proceed(remembersChoice: false), "an empty folder needs no decision")
        result = nil
        folders.moveAcrossProfiles([], proposal: { folderMove.applying(to: $0) }) { result = $0 }
        try check((try? result?.get()) == true && !retiredEmpty
            && folders.state.folders.first { $0.id == folder.id }?.spaceID == f.d.id, "an empty folder moves at once")
        try encoder.encode(f.state).write(to: file)
        let plain = try BrowserStore(directory: directory)
        let from = SidebarHierarchySnapshot(state: f.state, spaceID: f.s.id, profileID: f.p.id)!
        let to = SidebarHierarchySnapshot(state: f.state, spaceID: f.d.id, profileID: f.q.id)!
        let move = SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: f.state)!
        try check(try plain.moveSidebarItemsAcrossSpaces(move) == false && plain.state == f.state, "ordinary relocation cannot skip page reload")
        plain.rememberInterProfileMoveChoice()
        try check(plain.bypassesInterProfileMoveConfirmation, "Don’t ask again stores the preference")
        try encoder.encode(f.state).write(to: file)
        var withNote = f.state; let noteID = UUID(); withNote.tabs[0].url = InternalPage.note(noteID).urlString
        try encoder.encode(withNote).write(to: file)
        let documents = try BrowserStore(directory: directory)
        let noteProposal: (BrowserState) -> BrowserState? = { InterProfileSplitDropShim.proposal(r, $0) }
        result = nil
        documents.moveAcrossProfiles([f.today.id], proposal: noteProposal) { result = $0 }
        try check((try? result?.get()) == false && documents.state == withNote, "document move without its relocation owner refuses")
        var relocated: [InternalPage] = [], fromProfile: UUID?, toProfile: UUID?, reversed = 0
        documents.relocateLocalDocuments = { _, pages, a, b in relocated = pages; fromProfile = a; toProfile = b; return { reversed += 1 } }
        var editorValid = false, retirementCalls = 0
        documents.prepareLocalDocumentRelocation = { ids in
            precondition(ids == [f.today.id]); return { editorValid }
        }
        documents.requestPageRetirement = { _, shouldCommit, completion in retirementCalls += 1; pending = (shouldCommit, completion) }
        result = nil
        documents.moveAcrossProfiles([f.today.id], proposal: noteProposal) { result = $0 }
        try check((try? result?.get()) == false && retirementCalls == 0 && relocated.isEmpty,
                  "unfinished original editor refuses before native page retirement")
        editorValid = true; result = nil
        documents.moveAcrossProfiles([f.today.id], proposal: noteProposal) { result = $0 }
        editorValid = false
        try check(pending?.0() == false, "changed editor or new composition during consent refuses before unload")
        pending?.1(false)
        try check((try? result?.get()) == false && relocated.isEmpty && documents.state == withNote,
                  "editor refusal leaves original document and Profile untouched")
        editorValid = true; result = nil
        documents.moveAcrossProfiles([f.today.id], proposal: noteProposal) { result = $0 }
        try check(pending?.0() == true, "unchanged original editors admit the actual unload")
        editorValid = false; pending?.1(true)
        try check((try? result?.get()) == false && relocated.isEmpty && documents.state == withNote,
                  "late editor change after unload still prevents document relocation")
        editorValid = true
        documents.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        result = nil
        documents.moveAcrossProfiles([f.today.id], proposal: noteProposal) { result = $0 }
        try check((try? result?.get()) == true && relocated == [.note(noteID)] && fromProfile == f.p.id && toProfile == f.q.id && reversed == 0, "documents relocate source → destination before publication")
        try encoder.encode(withNote).write(to: file)
        let failingDocs = try BrowserStore(directory: directory)
        failingDocs.relocateLocalDocuments = { _, _, _, _ in { reversed += 1 } }
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        result = nil
        failingDocs.moveAcrossProfiles([f.today.id], proposal: noteProposal) { result = $0 }
        try check(reversed == 1 && failingDocs.state == withNote, "failed save reverses the document move")
        try FileManager.default.removeItem(at: file)
        _ = asked
    }

    enum InterProfileSplitDropShim {
        static func proposal(_ r: ForeignSplitDrop.Request, _ state: BrowserState) -> BrowserState? {
            ForeignSplitDrop.proposal(r, state: state, now: Date(), creation: nil)
        }
    }

    static func sameProfileDrop() throws {
        var f = fixture()
        let other = BrowserSpace(id: UUID(), name: "Errands", symbol: "circle", color: "AABBCC", profileID: f.p.id)
        let e1 = BrowserTab(id: UUID(), spaceID: other.id, profileID: f.p.id, url: "https://live.invalid/e1", title: "e1", kind: .today,
                            folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "https://live.invalid/e1", savedTitle: "e1")
        f.state.spaces.append(other); f.state.tabs.append(e1)
        let r = ForeignSplitDrop.Request(source: f.today, sourceHomeID: UUID(), spaceID: other.id, profileID: f.p.id,
            selection: [e1.id], layout: nil, target: .insert(1), orientation: .vertical, destinationHomeIDs: [:])
        let moved = try unwrap(ForeignSplitDrop.proposal(r, state: f.state, now: Date(), creation: nil), "same-Profile other-window drop")
        let live = moved.tabs.first { $0.id == f.today.id }!
        try check(live.profileID == f.p.id && live.spaceID == other.id && live.url == f.today.url, "original keeps its Profile and joins the other Space")
        try check(moved.splitLayouts.contains { $0.tabIDs == [e1.id, f.today.id] && $0.orientation == .vertical }, "group forms in the destination window's Space")
        var same = f.state
        let home = UUID()
        let sameSpace = ForeignSplitDrop.Request(source: f.pinned, sourceHomeID: home, spaceID: f.s.id, profileID: f.p.id,
            selection: [f.sibling.id], layout: nil, target: .insert(0), orientation: .horizontal, destinationHomeIDs: [f.sibling.id: UUID()])
        same.activeSpaceID = f.s.id
        let placed = try unwrap(ForeignSplitDrop.proposal(sameSpace, state: same, now: Date(), creation: nil), "same-Space other-window drop")
        try check(placed.tabs.contains { $0.id == home && $0.kind == .pinned && $0.url == f.pinned.savedURL }
            && placed.selectedTabIDs == [f.pinned.id, f.sibling.id], "same-Space drop leaves the source's saved home")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-foreign-drop-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(f.state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        var retired = false
        store.requestPageRetirement = { _, _, completion in retired = true; completion(false) }
        try check(try store.commitForeignSplitDrop([f.today.id]) { ForeignSplitDrop.proposal(r, state: $0, now: Date(), creation: nil) } && !retired, "same-Profile placement commits without reload")
        try check(try BrowserStore(directory: directory).state.tabs.first { $0.id == f.today.id }?.spaceID == other.id, "placement persisted")
        let cross = ForeignSplitDrop.Request(source: f.g1, sourceHomeID: UUID(), spaceID: f.d.id, profileID: f.q.id,
            selection: [f.d1.id], layout: nil, target: .insert(1), orientation: .horizontal, destinationHomeIDs: [:])
        try check(try store.commitForeignSplitDrop([f.g1.id]) { ForeignSplitDrop.proposal(cross, state: $0, now: Date(), creation: nil) } == false, "a Profile change cannot skip the reload transaction")
    }

    static func mixedDocumentCollection() throws {
        let f = fixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-mixed-profile-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = try NoteStore(directory: root.appendingPathComponent("source/Notes"), diskSaveDelay: 0)
        let easels = try EaselStore(directory: root.appendingPathComponent("source/Easels"))
        let targetNotes = try NoteStore(directory: root.appendingPathComponent("target/Notes"), diskSaveDelay: 0)
        let targetEasels = try EaselStore(directory: root.appendingPathComponent("target/Easels"))
        let note = try notes.create(), easel = try easels.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 0, y: 0, width: 320, height: 200), url: "https://example.com/embedded")
        try note.updateTitle("Original Note", replacing: note.document.title)
        try easel.perform("Browser") { $0.items = [browser] }
        var initial = f.state
        for (tabID, page) in [(f.g1.id, InternalPage.note(note.document.id)), (f.g2.id, InternalPage.easel(easel.document.id))] {
            let index = initial.tabs.firstIndex { $0.id == tabID }!
            initial.tabs[index].url = page.urlString; initial.tabs[index].savedURL = page.urlString
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(initial).write(to: root.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: root)
        let from = SidebarHierarchySnapshot(state: initial, spaceID: f.s.id, profileID: f.p.id)!
        let to = SidebarHierarchySnapshot(state: initial, spaceID: f.d.id, profileID: f.q.id)!
        let move = SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: initial)!
        var editorValid = true
        store.prepareLocalDocumentRelocation = { _ in { editorValid } }
        store.requestPageRetirement = { _, validate, complete in complete(validate()) }
        store.relocateLocalDocuments = { _, pages, source, destination in
            precondition(source == f.p.id && destination == f.q.id)
            precondition(Set(pages.map(\.urlString)) == Set([InternalPage.note(note.document.id).urlString, InternalPage.easel(easel.document.id).urlString]))
            try notes.retireSessionForRelocation(note.document.id)
            try easels.retireSessionForRelocation(easel.document.id)
            try notes.relocate(note.document.id, to: targetNotes)
            let copied = try easels.relocate(easel.document.id, to: targetEasels)
            return {
                _ = try? targetEasels.relocate(easel.document.id, to: easels); targetEasels.removeAssets(copied)
                try? targetNotes.relocate(note.document.id, to: notes)
            }
        }
        var result: Result<Bool, Error>?
        editorValid = false
        store.moveAcrossProfiles(Set(move.tabIDs), proposal: { move.applying(to: $0) }) { result = $0 }
        try check((try? result?.get()) == false && (try notes.load(note.document.id)) === note && (try easels.load(easel.document.id)) === easel,
                  "mixed collection draft refusal preserves both original stores and sessions")
        editorValid = true
        store.moveAcrossProfiles(Set(move.tabIDs), proposal: { move.applying(to: $0) }) { result = $0 }
        try check((try? result?.get()) == true && move.tabIDs.allSatisfy { id in store.state.tabs.first { $0.id == id }?.profileID == f.q.id },
                  "mixed Note/Easel split commits its exact original records to the destination Profile")
        try check((try? notes.load(note.document.id)) == nil && (try? easels.load(easel.document.id)) == nil,
                  "mixed collection leaves neither document in the source Profile")
        try check((try targetNotes.load(note.document.id)).document == note.document && (try targetEasels.load(easel.document.id)).document == easel.document,
                  "mixed destination documents retain original saved contents with old owners still retained")
    }

    static func sharedAssetRollback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-shared-rollback-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try EaselStore(directory: root.appendingPathComponent("source"))
        let destination = try EaselStore(directory: root.appendingPathComponent("destination"))
        let a = try source.create(), b = try source.create()
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try a.importPNG(png)
        for session in [a, b] {
            try session.perform("Shared image") { $0.items = [EaselItem(kind: .image, frame: .init(x: 0, y: 0, width: 10, height: 10), assetID: asset)] }
            try source.retireSessionForRelocation(session.document.id)
        }
        let rollback = LocalDocumentRelocationRollback()
        var attempted = 0
        for session in [a, b] {
            let id = session.document.id, copied = try source.relocate(session.document.id, to: destination)
            rollback.append(reverse: {
                attempted += 1
                do { _ = try destination.relocate(id, to: source); return true }
                catch { return false }
            }, cleanup: { destination.removeAssets(copied) })
        }
        let blocked = root.appendingPathComponent("source/documents/" + b.document.id.uuidString.lowercased() + ".json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
        rollback.run()
        try check(attempted == 2, "collection rollback attempts every reversal after one fails")
        try check((try source.load(a.document.id)).document == a.document && (try destination.load(b.document.id)).document == b.document,
                  "partial rollback keeps the successfully restored and still-destination documents intact")
        try check(try destination.load(b.document.id).assetData(asset) == png,
                  "partial rollback preserves a shared asset copied by the successfully reversed document")
        rollback.run()
        try check(attempted == 2, "rollback capability is consumed once")
        try FileManager.default.removeItem(at: blocked)
        try destination.retireSessionForRelocation(b.document.id)
        _ = try destination.relocate(b.document.id, to: source)
        try source.retireSessionForRelocation(a.document.id)
        destination.removeAssets([asset])
        let copied = try source.relocate(a.document.id, to: destination)
        let complete = LocalDocumentRelocationRollback()
        var cleaned = false
        complete.append(reverse: {
            do { _ = try destination.relocate(a.document.id, to: source); return true }
            catch { return false }
        }, cleanup: { destination.removeAssets(copied); cleaned = true })
        complete.run()
        try check(cleaned && (try source.load(a.document.id)).document == a.document
            && !FileManager.default.fileExists(atPath: destination.directory.appendingPathComponent("assets/" + asset).path),
                  "a fully reversed collection removes its copied assets after document restoration")
    }

    static func documentRelocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-doc-relocate-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let x = try NoteStore(directory: root.appendingPathComponent("X/Notes"), diskSaveDelay: 0), y = try NoteStore(directory: root.appendingPathComponent("Y/Notes"), diskSaveDelay: 0)
        var session: NoteSession? = try x.create()
        let id = session!.document.id
        try session!.updateTitle("Plan", replacing: session!.document.title)
        do { try x.relocate(id, to: y); try check(false, "a live note session refuses relocation") } catch { try check(true, "live note session refuses") }
        let retained = session!; session = nil
        try x.retireSessionForRelocation(id)
        try x.relocate(id, to: y)
        do { try retained.updateTitle("Late callback", replacing: "Plan"); try check(false, "retired Note must not recreate the source file") }
        catch { try check(true, "retained original Note callback is revoked before relocation") }
        try check((try? x.load(id)) == nil && (try y.load(id)).document.title == "Plan", "exact note document moves to the destination store")
        try y.relocate(id, to: x)
        try check((try x.load(id)).document.title == "Plan", "reverse move restores the source")
        let ex = try EaselStore(directory: root.appendingPathComponent("X/Easels")), ey = try EaselStore(directory: root.appendingPathComponent("Y/Easels"))
        var easel: EaselSession? = try ex.create(title: "Board")
        let easelID = easel!.document.id
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13] + Array("IHDR".utf8) + Array(repeating: 0, count: 13))
        let asset = try easel!.importPNG(png)
        try easel!.perform("Add image") { $0.items.append(EaselItem(kind: .image, frame: EaselRect(x: 0, y: 0, width: 10, height: 10), assetID: asset)) }
        easel = nil
        let copied = try ex.relocate(easelID, to: ey)
        try check(copied == [asset] && (try? ex.load(easelID)) == nil, "Easel document moves with its copied assets")
        let fm = FileManager.default
        func assetExists(_ side: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(side + "/Easels/assets/" + asset).path) }
        try check(try ey.load(easelID).document.items.first?.assetID == asset && assetExists("X") && assetExists("Y"), "destination resolves the asset; source assets stay")
        _ = try ey.relocate(easelID, to: ex); ey.removeAssets(copied)
        try check(!assetExists("Y") && assetExists("X") && (try ex.load(easelID)).document.title == "Board", "rollback removes only copied assets")
    }

    static func documentBlocks() throws {
        let f = fixture()
        let note = InternalPage.note(UUID()).urlString, easel = InternalPage.easel(UUID()).urlString
        let research = BrowserFolder(id: UUID(), spaceID: f.s.id, name: "Research")
        func set(_ id: UUID, _ url: String, title: String? = nil, in state: inout BrowserState) {
            let index = state.tabs.firstIndex { $0.id == id }!
            state.tabs[index].url = url; state.tabs[index].savedURL = url
            if let title { state.tabs[index].title = title; state.tabs[index].savedTitle = title }
        }
        func alias(_ url: String, _ space: BrowserSpace, _ kind: TabKind, folder: UUID? = nil, archived: Bool = false) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: "Alias", kind: kind,
                       folderID: folder, createdAt: Date(timeIntervalSince1970: 3), lastAccessed: Date(timeIntervalSince1970: 4),
                       archivedAt: archived ? Date(timeIntervalSince1970: 5) : nil, savedURL: url, savedTitle: "Alias")
        }
        func block(_ items: [SidebarItemReference], _ state: BrowserState) throws -> (InterProfileDocumentBlock?, Bool) {
            let source = SidebarHierarchySnapshot(state: state, spaceID: f.s.id, profileID: f.p.id)!
            let target = SidebarHierarchySnapshot(state: state, spaceID: f.d.id, profileID: f.q.id)!
            let move = try unwrap(SidebarSpaceMove(items: items, from: source, to: target, state: state), "cross-data move proposal")
            let after = move.applying(to: state)
            let refused = after.map { InterProfileMove.documents(moving: Set(move.tabIDs), after: $0) == nil } ?? false
            return (InterProfileDocumentBlock(moving: Set(move.tabIDs), before: state, after: after), refused)
        }

        try check(InterProfileMoveGate.resolve(sourceProfiles: [f.p.id], destination: f.q.id, decision: nil, bypass: false, blocked: true) == .blocked,
                  "a blocked document move explains instead of asking for the data warning")
        try check(InterProfileMoveGate.resolve(sourceProfiles: [f.p.id], destination: f.q.id, decision: nil, bypass: true, blocked: true) == .blocked,
                  "don’t ask again still explains a blocked move instead of moving")
        try check(InterProfileMoveGate.resolve(sourceProfiles: [f.q.id], destination: f.q.id, decision: nil, bypass: false, blocked: true) == .proceed(remembersChoice: false),
                  "a same-data move is never gated by the document check")
        try check(InterProfileMoveGate.resolve(sourceProfiles: [f.p.id], destination: f.q.id, decision: nil, bypass: false, blocked: false) == .confirm,
                  "an unblocked move still asks first")

        var clean = f.state; set(f.today.id, note, in: &clean)
        let (none, cleanRefused) = try block([.tab(f.today.id)], clean)
        try check(none == nil && !cleanRefused, "a Note with no other entries has nothing to explain and still moves")
        let (web, webRefused) = try block([.split(f.group.id)], f.state)
        try check(web == nil && !webRefused, "web pages never produce a document explanation")
        try check(InterProfileDocumentBlock(moving: [f.today.id], before: f.state, after: nil) == nil, "a move that no longer applies explains nothing")

        var duplicated = clean; duplicated.folders = [research]
        duplicated.tabs.append(alias(note, f.s, .pinned, folder: research.id))
        let (copy, copyRefused) = try block([.tab(f.today.id)], duplicated)
        let folder = try unwrap(copy, "a duplicate in a folder blocks the move")
        try check(copyRefused, "the explanation matches a move the store refuses")
        try check(folder.places == [.sidebar(.folder("Research"), split: false, otherSpace: nil)], "the duplicate is placed in its folder")
        try check(folder.title == "Can’t move to Office", "the title names the destination Space")
        try check(folder.message == "This Note is still used elsewhere in Home: in the folder “Research”.", "folder duplicate wording")

        var archived = f.state; set(f.today.id, easel, in: &archived)
        archived.tabs.append(alias(easel, f.s, .today, archived: true))
        let (old, oldRefused) = try block([.tab(f.today.id)], archived)
        let archive = try unwrap(old, "an archived entry blocks the move")
        try check(oldRefused && archive.places == [.archive], "an archived entry is reported as the Archive")
        try check(archive.message == "This Easel is still used elsewhere in Home: in the Archive.", "archived entry wording")

        var joined = f.state
        var pinnedNote = joined.tabs.first { $0.id == f.pinned.id }!
        pinnedNote.url = note; pinnedNote.savedURL = note
        let home = SplitMembership.makeHome(of: pinnedNote, id: UUID(), now: Date(timeIntervalSince1970: 6), activeTabBeforeCreationID: nil)
        joined.tabs.append(home)
        set(f.g1.id, note, title: "Plans", in: &joined)
        var away = clean
        let awayIndex = away.tabs.firstIndex { $0.id == f.pinned.id }!
        away.tabs[awayIndex].savedURL = note; away.tabs[awayIndex].savedTitle = "Plans"; away.tabs[awayIndex].title = "Docs page"
        let (navigated, navigatedRefused) = try block([.tab(f.pinned.id)], away)
        try check(navigatedRefused && navigated?.message == "The Note “Plans” is still used elsewhere in Home: in Today.",
                  "a pinned tab showing a web page names the Note saved in it")
        let (spot, spotRefused) = try block([.split(f.group.id)], joined)
        let saved = try unwrap(spot, "the saved spot a pinned Note left when it joined a split blocks the move")
        try check(spotRefused && saved.places == [.sidebar(.pinned, split: false, otherSpace: nil)], "the saved spot is reported where it is pinned")
        try check(saved.message == "The Note “Plans” is still used elsewhere in Home: in Pinned.", "a multi-tab move names the Note that blocks it")

        var pinnedSplit = clean
        for id in f.group.tabIDs { pinnedSplit.tabs[pinnedSplit.tabs.firstIndex { $0.id == id }!].kind = .pinned }
        set(f.g2.id, note, in: &pinnedSplit)
        let (split, splitRefused) = try block([.tab(f.today.id)], pinnedSplit)
        let paired = try unwrap(split, "a copy inside a pinned split blocks the move")
        try check(splitRefused && paired.places == [.sidebar(.pinned, split: true, otherSpace: nil)], "a pinned split member is reported as a split")
        try check(paired.message == "This Note is still used elsewhere in Home: in a pinned split.", "pinned split wording")

        var dragged = f.state; set(f.pinned.id, note, in: &dragged)
        let dragRequest = ForeignSplitDrop.Request(source: dragged.tab(f.pinned.id)!, sourceHomeID: UUID(), spaceID: f.d.id, profileID: f.q.id,
            selection: [f.d1.id], layout: nil, target: .insert(1), orientation: .horizontal, destinationHomeIDs: [:])
        let dropped = ForeignSplitDrop.proposal(dragRequest, state: dragged, now: Date(timeIntervalSince1970: 7), creation: nil)
        let behind = try unwrap(InterProfileDocumentBlock(moving: [f.pinned.id], before: dragged, after: dropped),
                                "dragging a pinned Note into another data’s split leaves its pinned spot behind")
        try check(behind.places == [.leftBehind(.pinned, split: false)], "the spot this move would leave is reported as left behind")
        try check(behind.message == "This Note is still used elsewhere in Home: in the pinned spot it leaves behind.", "left-behind spot wording")

        let work = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "AABBCC", profileID: f.p.id)
        var shared = duplicated; shared.spaces.append(work)
        let favorite = alias(note, f.s, .favorite)
        shared.tabs.insert(contentsOf: [alias(note, work, .today), favorite], at: shared.tabs.count - 1)
        let (spread, spreadRefused) = try block([.tab(f.today.id)], shared)
        let many = try unwrap(spread, "entries in a Space sharing the same data block the move")
        try check(spreadRefused && many.places == [.sidebar(.today, split: false, otherSpace: "Work"), .sidebar(.favorites, split: false, otherSpace: nil),
                                                   .sidebar(.folder("Research"), split: false, otherSpace: nil)], "every distinct place is kept once, in a stable order")
        try check(many.message == "This Note is still used elsewhere: in Today in Work, in Favorites and in the folder “Research” in Home.",
                  "entries outside the source Space name their Space")
        shared.tabs.append(alias(note, f.s, .today, archived: true))
        try check(try block([.tab(f.today.id)], shared).0?.message == "This Note is still used elsewhere: in Today in Work, in Favorites and 2 more places.",
                  "a long list stays short")

        var pair = duplicated
        set(f.g1.id, note, title: "Plans", in: &pair); set(f.g2.id, easel, title: "Board", in: &pair)
        pair.tabs.removeAll { $0.id == f.today.id }
        pair.tabs.append(alias(easel, f.s, .today, archived: true))
        let (both, bothRefused) = try block([.split(f.group.id)], pair)
        let first = try unwrap(both, "a split with two blocked documents refuses")
        try check(bothRefused && first.document == InternalPage(urlString: note) && first.others == [InternalPage(urlString: easel)!],
                  "the first blocked document is explained and the other is counted")
        try check(first.message == "The Note “Plans” is still used elsewhere in Home: in the folder “Research”. 1 more Easel is too.",
                  "a multi-item move explains once and counts the rest")
        var onlyEasel = pair; onlyEasel.tabs.removeAll { $0.folderID == research.id }
        let (one, oneRefused) = try block([.split(f.group.id)], onlyEasel)
        try check(oneRefused && one?.message == "The Easel “Board” is still used elsewhere in Home: in the Archive.",
                  "a multi-item move names the one item that blocks it")

        var draft = try unwrap(SidebarNewSpaceDraft(items: [.tab(f.today.id)], from: SidebarHierarchySnapshot(state: duplicated, spaceID: f.s.id, profileID: f.p.id)!,
                                                    state: duplicated), "New Space draft with the Note")
        draft.name = "Fresh"; draft.keepSeparate()
        let fresh = try unwrap(InterProfileDocumentBlock(moving: Set(draft.tabIDs), before: duplicated, after: draft.applying(to: duplicated)),
                               "a New Space that keeps separate data is blocked the same way")
        try check(fresh.message == "This Note is still used elsewhere in Home: in the folder “Research”.", "the New Space form shows the same explanation")
    }

    static func dataChangeBlocks() throws {
        let f = fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-data-change-block-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = InternalPage.note(UUID()).urlString, easel = InternalPage.easel(UUID()).urlString
        let work = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "AABBCC", profileID: f.p.id)
        func set(_ id: UUID, _ url: String, title: String, in state: inout BrowserState) {
            let index = state.tabs.firstIndex { $0.id == id }!
            state.tabs[index].url = url; state.tabs[index].savedURL = url
            state.tabs[index].title = title; state.tabs[index].savedTitle = title
        }
        func alias(_ url: String, _ space: BrowserSpace, _ kind: TabKind, archived: Bool = false) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: "Alias", kind: kind,
                       createdAt: Date(timeIntervalSince1970: 3), lastAccessed: Date(timeIntervalSince1970: 4),
                       archivedAt: archived ? Date(timeIntervalSince1970: 5) : nil, savedURL: url, savedTitle: "Alias")
        }
        func stored(_ state: BrowserState) throws -> BrowserStore {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
            return try BrowserStore(directory: directory)
        }
        func refused(_ store: BrowserStore) -> Bool {
            guard let assignment = store.profileAssignment(f.q.id, toSpace: f.s.id), let after = assignment.proposal(store.state) else { return false }
            return InterProfileMove.documents(moving: assignment.tabIDs, after: after) == nil
        }

        var state = f.state; state.spaces.append(work)
        set(f.today.id, note, title: "Plans", in: &state)
        let quiet = try stored(state)
        try check(quiet.sharingDocumentBlock(forSpace: f.s.id, to: .separate) == nil
                  && quiet.sharingDocumentBlock(forSpace: f.s.id, to: .share(withSpace: f.d.id)) == nil && !refused(quiet),
                  "a Note used only in the Space changing its data has nothing to explain and is not refused")

        var spread = state; spread.tabs.append(alias(note, work, .today))
        let separate = try unwrap(try stored(spread).sharingDocumentBlock(forSpace: f.s.id, to: .separate),
                                  "a Note open in another Space on the old data blocks Keep separate")
        try check(separate.change == .keepSeparate && separate.title == "Can’t keep Home separate", "Keep separate names the Space it can’t separate")
        try check(separate.message == "The Note “Plans” is still used elsewhere on Home’s current data: in Today in Work.",
                  "an entry in a Space sharing the old data is named with its Space")

        var kept = state; kept.tabs += [alias(note, f.s, .favorite), alias(note, f.s, .today, archived: true)]
        let keptStore = try stored(kept)
        let share = try unwrap(keptStore.sharingDocumentBlock(forSpace: f.s.id, to: .share(withSpace: f.d.id)),
                               "a Favorite and an archived entry block sharing other data")
        try check(refused(keptStore), "the explanation matches a data change the store refuses")
        try check(share.change == .share(target: "Office") && share.title == "Can’t share Office’s data with Home", "sharing names both Spaces")
        try check(share.message == "The Note “Plans” is still used elsewhere on Home’s current data: in Favorites and in the Archive.",
                  "Favorites and the Archive stay with the old data")

        var pair = spread; set(f.g1.id, easel, title: "Board", in: &pair)
        pair.tabs.append(alias(easel, f.s, .today, archived: true))
        try check(try stored(pair).sharingDocumentBlock(forSpace: f.s.id, to: .separate)?.message
                  == "The Note “Plans” is still used elsewhere on Home’s current data: in Today in Work. 1 more Easel is too.",
                  "a data change explains the first document and counts the rest")

        var after = kept; after.tabs[after.tabs.firstIndex { $0.id == f.today.id }!].profileID = UUID()
        let lone = try unwrap(InterProfileDocumentBlock(moving: [f.today.id], before: kept, after: after, sharing: .separate),
                              "a lone Note still blocks a data change")
        try check(lone.subject == "The Note “Plans”", "a data change names the Note even when it is the Space’s only item")
        let moved = try unwrap(InterProfileDocumentBlock(moving: [f.today.id], before: kept, after: after), "the same entries block a move")
        try check(moved.change == .move && moved.subject == "This Note" && moved.title == "Can’t move to Home"
                  && moved.message == "This Note is still used elsewhere in Home: in Favorites and in the Archive.",
                  "move wording is unchanged when no data change is given")
    }

    static func unwrap<T>(_ value: T?, _ reason: String) throws -> T {
        count += 1
        guard let value else { throw NSError(domain: reason, code: count) }
        return value
    }
}
