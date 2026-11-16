import Foundation

@main @MainActor struct SidebarNewSpaceTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        var state = BrowserState.initial()
        let source = state.spaces[0], profile = source.profileID
        let other = BrowserProfile(id: UUID(), name: "Other")
        state.profiles.append(other)
        let following = BrowserSpace(id: UUID(), name: "Following", symbol: "star", color: "112233", profileID: other.id)
        state.spaces.append(following)
        let folder = BrowserFolder(id: UUID(), spaceID: source.id, name: "Original", parentID: nil, isExpanded: false)
        let nested = BrowserFolder(id: UUID(), spaceID: source.id, name: "Nested", parentID: folder.id, isExpanded: true)
        func tab(_ kind: TabKind, _ folder: UUID? = nil) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: source.id, profileID: profile, url: "https://example.test/live",
                title: "Original", kind: kind, folderID: folder,
                createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 2),
                savedURL: "https://example.test/saved", savedTitle: "Saved", isMuted: true, isUnread: true)
        }
        let a = tab(.pinned, nested.id), b = tab(.pinned, nested.id), c = tab(.pinned, folder.id)
        let today = tab(.today), retained = tab(.pinned), favorite = tab(.favorite)
        state.tabs = [a,b,c,today,retained,favorite]; state.folders = [folder,nested]
        let group = BrowserSplitLayout(id: UUID(), sidebarAnchorID: b.id, customTitle: "Split", customIcon: .emoji("📚"),
            spaceID: source.id, tabIDs: [a.id,b.id], orientation: .vertical, widthFactors: [0.3,0.7])
        state.splitLayouts = [group]; state.selectedTabIDs = group.tabIDs
        state.selectionBySpace = [source.id.uuidString: group.tabIDs]
        func container(_ space: UUID, _ parent: UUID? = nil, _ kind: TabKind = .pinned) -> SidebarContainerLocation {
            .init(spaceID: space, folderID: parent, section: kind)
        }
        state.sidebarItemOrder[container(source.id).key] = [.folder(folder.id),.tab(retained.id)]
        state.sidebarItemOrder[container(source.id,folder.id).key] = [.tab(c.id),.folder(nested.id)]
        state.sidebarItemOrder[container(source.id,nested.id).key] = [.tab(b.id)]
        let snapshot = SidebarHierarchySnapshot(state: state, spaceID: source.id, profileID: profile)!
        var draft = SidebarNewSpaceDraft(items: [.folder(folder.id),.split(group.id),.tab(today.id)], from: snapshot, state: state)!
        check(draft.name.isEmpty && draft.profileID == profile && draft.theme == source.theme, "Draft starts in original Profile and theme")
        check(draft.roots == [.folder(folder.id),.tab(today.id)], "Selected ancestor owns descendants")
        check(draft.tabIDs == [c.id,a.id,b.id,today.id] && draft.folderIDs == [folder.id,nested.id] && draft.groupIDs == [group.id], "Exposes exact ordered identities for native owner claims")
        check(draft.applying(to: state) == nil, "Blank editing draft does not create Space")
        draft.name = "  Research  "; draft.customIcon = .emoji("📚")
        draft.theme = SpaceTheme(primaryColor: ThemeColor(hex: "123456"), colorCount: 2, wheel: .analogous, appearance: .dark, noise: 0.2, intensity: 0.7)
        let move = draft.move(in: state)!, next = draft.applying(to: state)!
        check(next.spaces.map(\.id) == [source.id,draft.spaceID,following.id], "Creation resolves after original Space rather than appending")
        let created = next.spaces[1]
        check(created.name == draft.name && created.profileID == profile && created.customIcon == draft.customIcon && created.theme == draft.theme, "Authored name/style/Profile commit together")
        check(next.tabs.count == state.tabs.count && next.folders.count == state.folders.count, "Move never copies or recreates original items")
        for original in state.tabs {
            var expected = original
            if draft.tabIDs.contains(original.id) { expected.spaceID = draft.spaceID }
            check(next.tabs.first { $0.id == original.id } == expected, "Original saved/live navigation and identity survives")
        }
        var expectedGroup = group; expectedGroup.spaceID = draft.spaceID
        check(next.splitLayouts == [expectedGroup], "Whole split identity, name, icon and geometry survives")
        check(next.folders.first { $0.id == nested.id }?.parentID == folder.id, "Nested hierarchy retained")
        check(next.folders.first { $0.id == folder.id }?.isExpanded == false, "Collapsed parent retained")
        check(SidebarHierarchy.children(in: container(draft.spaceID,folder.id), state: next) == [.tab(c.id),.folder(nested.id)], "Mixed child order preserved")
        check(SidebarHierarchy.children(in: container(draft.spaceID,nested.id), state: next) == [.split(group.id)], "Whole split remains typed in original mixed order")
        check(next.sidebarItemOrder[container(source.id,nested.id).key] == nil, "Original nested order key is removed atomically")
        check(next.activeSpaceID == source.id && next.selectedTabIDs.isEmpty, "Core does not impersonate originating physical-window focus")
        check(draft.applying(to: next) == nil, "Fixed creation identity prevents replay")
        let window = UUID(), foreignWindow = UUID()
        check(move.permitsSplitOwners([a.id:window,b.id:window], in: window), "Original split owner may retain original pages")
        check(!move.permitsSplitOwners([a.id:window,b.id:foreignWindow], in: window), "Mixed physical ownership refuses whole move")
        var changed = state; changed.tabs[0].url = "https://example.test/latest"; changed.tabs[0].title = "Changed live title"
        check(draft.applying(to: changed)?.tabs[0].url == changed.tabs[0].url, "Live navigation metadata is not overwritten by draft")
        changed = state; changed.folders[0].name = "Changed hierarchy"
        check(draft.applying(to: changed) == nil, "Changed original hierarchy refuses stale draft")
        changed = state; changed.spaces[0].profileID = other.id
        check(draft.applying(to: changed) == nil, "Reassigned source Space refuses original ownership")
        changed = state; changed.spaces.removeFirst()
        check(draft.applying(to: changed) == nil, "Missing original anchor/source cannot choose a substitute Space")
        changed = state; changed.profileRemovals = [.init(id: UUID(), profileID: profile, profileName: source.name)]
        check(draft.applying(to: changed) == nil, "Retiring source Profile refuses move")
        check(!draft.canUseProfile(other.id, in: state), "Nonempty cross-Profile relocation is truthfully unavailable")
        var invalid = draft; invalid.profileID = other.id
        check(invalid.applying(to: state) == nil, "Programmatic Profile change cannot transplant live pages")
        invalid = draft; invalid.name = " \n\t"
        check(invalid.applying(to: state) == nil, "Whitespace-only title cannot submit")
        invalid = draft; invalid.customIcon = .symbol("invalid")
        check(invalid.applying(to: state) == nil, "Unsupported icon cannot enter durable state")
        invalid = draft; invalid.theme.noise = .nan
        check(invalid.applying(to: state) == nil, "Invalid theme cannot enter durable state")
        check(SidebarNewSpaceDraft(items: [.tab(a.id)], from: snapshot, state: state) == nil, "Partial split move is refused")
        check(SidebarNewSpaceDraft(items: [.tab(favorite.id)], from: snapshot, state: state) == nil, "Profile Favorite is not silently made a Space item")
        check(SidebarNewSpaceDraft(items: [.tab(today.id),.tab(today.id)], from: snapshot, state: state) == nil, "Duplicate selected root cannot commit twice")
        check(SidebarNewSpaceDraft(from: snapshot, state: state, spaceID: following.id) == nil, "Existing Space ID cannot be reused")
        var empty = SidebarNewSpaceDraft(from: snapshot, state: state)!
        empty.name = "Empty"; empty.profileID = other.id
        check(empty.roots.isEmpty && empty.tabIDs.isEmpty && empty.folderIDs.isEmpty && empty.groupIDs.isEmpty, "Ordinary creation has no fabricated move identities")
        check(empty.canUseProfile(other.id, in: state) && empty.move(in: state) == nil, "Ordinary creation can choose another existing Profile without a move")
        let emptyNext = empty.applying(to: state)!
        check(emptyNext.spaces[1].profileID == other.id && emptyNext.tabs == state.tabs && emptyNext.folders == state.folders, "Empty creation preserves all source contents")
        check(emptyNext.selectedTabIDs == state.selectedTabIDs && emptyNext.selectionBySpace == state.selectionBySpace, "Empty creation does not clear original selection")
        changed = state; changed.folders[0].name = "Unrelated edit"
        check(empty.applying(to: changed) != nil, "No-root draft does not bind unrelated hierarchy edits")
        changed = state; changed.profiles.removeAll { $0.id == other.id }
        check(empty.applying(to: changed) == nil, "Removed destination Profile cannot fall back to Default")
        changed = state; changed.profileRemovals = [.init(id: UUID(), profileID: other.id, profileName: other.name)]
        check(empty.applying(to: changed) == nil, "Retiring destination Profile refuses even empty creation")
        var first = SidebarNewSpaceDraft(from: snapshot, state: state, insertion: .absolute(0))!; first.name = "First"
        check(first.applying(to: state)?.spaces.first?.id == first.spaceID, "Explicit absolute insertion is honored")
        check(SidebarNewSpaceDraft(from: snapshot, state: state, insertion: .absolute(-1)) == nil, "Negative absolute index refused")
        check(SidebarNewSpaceDraft(from: snapshot, state: state, insertion: .absolute(3)) == nil, "Out-of-range absolute index refused")
        check(SidebarNewSpaceDraft(from: snapshot, state: state, insertion: .after(UUID())) == nil, "Missing explicit anchor refused")
        var reordered = state; reordered.spaces.swapAt(0,1)
        check(draft.applying(to: reordered)?.spaces.map(\.id) == [following.id,source.id,draft.spaceID], "Relative insertion follows original anchor after a reorder")

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let roundTrip = try decoder.decode(BrowserSpace.self, from: encoder.encode(created))
        check(roundTrip == created, "Typed custom icon/theme round-trip")
        var legacy = try JSONSerialization.jsonObject(with: encoder.encode(source)) as! [String:Any]
        legacy.removeValue(forKey: "customIcon"); legacy.removeValue(forKey: "theme"); legacy["color"] = "123456"
        let migrated = try decoder.decode(BrowserSpace.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(migrated.customIcon == nil && migrated.symbol == source.symbol && migrated.theme == .singleColor(ThemeColor(hex:"123456")!), "Legacy Space symbol/color migration remains compatible")
        var invalidIcon = created; invalidIcon.customIcon = .emoji("not an emoji")
        let recoveredIcon = try decoder.decode(BrowserSpace.self, from: encoder.encode(invalidIcon))
        check(recoveredIcon.customIcon == nil, "Invalid optional icon recovers ordinary symbol fallback")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ParcNewSpace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("session.json")
        try encoder.encode(state).write(to: file)
        let store = try BrowserStore(directory: dir)
        let diskBefore = try Data(contentsOf: file), before = store.state
        var abandoned = draft; abandoned.name = "Cancelled"; abandoned.profileID = other.id
        _ = abandoned.canUseProfile(other.id, in: store.state)
        let unchangedDisk = try Data(contentsOf: file)
        check(store.state == before && unchangedDisk == diskBefore, "Editing and discarding draft has no durable or model effect")
        let committed = try store.createSpaceAndMoveSidebarItems(draft)
        check(committed == draft.spaceID, "Actual atomic store operation returns original fixed identity")
        let reopened = try BrowserStore(directory: dir)
        check(reopened.state.spaces.contains(created) && reopened.state.splitLayouts == [expectedGroup], "Space and original split placements persist together")
        let result0 = try store.createSpaceAndMoveSidebarItems(draft)
        check(result0 == nil, "Already committed draft cannot replay")
        try encoder.encode(state).write(to: file)
        let failing = try BrowserStore(directory: dir), original = failing.state
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { _ = try failing.createSpaceAndMoveSidebarItems(draft); preconditionFailure("Expected durable rename failure") } catch {}
        check(failing.state == original && failing.persistenceError != nil, "Write failure publishes neither empty Space nor partial move")
        try FileManager.default.removeItem(at: file)
        let result1 = try failing.createSpaceAndMoveSidebarItems(draft)
        check(result1 == draft.spaceID, "Same draft retries original ID after persistence failure")
        try encoder.encode(state).write(to: file)
        let retiring = try BrowserStore(directory: dir)
        var release: ((Bool)->Void)?
        retiring.requestPageRetirement = { _,_,completion in release = completion }
        retiring.closeTabs([today.id])
        check(retiring.retiringTabIDs.contains(today.id), "Fixture holds genuine original retirement reservation")
        let result2 = try retiring.createSpaceAndMoveSidebarItems(draft)
        check(result2 == nil, "Pending beforeunload/retirement cannot be stolen by creation")
        release?(false)
        let result3 = try retiring.createSpaceAndMoveSidebarItems(draft)
        check(result3 == draft.spaceID, "Refused close releases exact original move for explicit retry")
        let ephemeral = BrowserStore(privateParentProfileID: profile, engineProfilePath: "unused", directory: dir, settings: state.settings)
        let privateSnapshot = SidebarHierarchySnapshot(state: ephemeral.state, spaceID: ephemeral.activeSpaceID, profileID: ephemeral.activeSpace.profileID)!
        var privateDraft = SidebarNewSpaceDraft(from: privateSnapshot, state: ephemeral.state)!; privateDraft.name = "Private"
        let result4 = try ephemeral.createSpaceAndMoveSidebarItems(privateDraft)
        check(result4 == nil, "Ephemeral browser cannot publish a normal Space")
        print("SidebarNewSpaceTests: \(checks) assertions passed")
    }
}
