import Foundation

@main @MainActor
struct SidebarSplitCopyTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-copy-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = BrowserProfile(id: UUID(), name: "Original"), foreignProfile = BrowserProfile(id: UUID(), name: "Other")
        let here = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let there = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "FEDCBA", profileID: profile.id)
        let elsewhere = BrowserSpace(id: UUID(), name: "Elsewhere", symbol: "circle", color: "123456", profileID: foreignProfile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: here.id, name: "Folder")
        func tab(_ title: String, kind: TabKind = .pinned, space: UUID? = nil, folder: UUID? = nil) -> BrowserTab {
            let url = "https://saved.invalid/" + title
            return .init(id: UUID(), spaceID: space ?? here.id, profileID: profile.id, url: url, title: title,
                         kind: kind, folderID: folder, createdAt: Date(timeIntervalSince1970: 10),
                         lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }
        let left = tab("Left"), right = tab("Right"), keep = tab("Keep"), inside = tab("Inside", folder: folder.id)
        let today = tab("Today", kind: .today), away = tab("Away", space: there.id)
        let favA = tab("FavA", kind: .favorite), favB = tab("FavB", kind: .favorite)
        let foreignTab = BrowserTab(id: UUID(), spaceID: elsewhere.id, profileID: foreignProfile.id, url: "https://saved.invalid/F", title: "F",
                                    kind: .pinned, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                                    savedURL: "https://saved.invalid/F", savedTitle: "F")
        let split = BrowserSplitLayout(sidebarAnchorID: left.id, customTitle: "Pair", spaceID: here.id,
            tabIDs: [left.id, right.id], orientation: .vertical, widthFactors: [0.4, 0.6])
        let favorite = BrowserSplitLayout(sidebarAnchorID: favA.id, spaceID: here.id, tabIDs: [favA.id, favB.id], widthFactors: [0.5, 0.5])
        var state = BrowserState(profiles: [profile, foreignProfile], spaces: [here, there, elsewhere], activeSpaceID: here.id)
        state.folders = [folder]; state.tabs = [left, right, keep, inside, today, away, favA, favB, foreignTab]
        state.splitLayouts = [split, favorite]
        let pinned = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .pinned)
        let inFolder = SidebarContainerLocation(spaceID: here.id, folderID: folder.id, section: .pinned)
        let todayLocation = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .today)
        let therePinned = SidebarContainerLocation(spaceID: there.id, folderID: nil, section: .pinned)
        let favorites = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .favorite, profileID: profile.id)
        state.sidebarItemOrder[pinned.key] = [.tab(keep.id), .tab(left.id), .folder(folder.id)]
        state.sidebarItemOrder[inFolder.key] = [.tab(inside.id)]
        state.sidebarItemOrder[therePinned.key] = [.tab(away.id)]
        let elsewherePinned = SidebarContainerLocation(spaceID: elsewhere.id, folderID: nil, section: .pinned)
        state.sidebarItemOrder[elsewherePinned.key] = [.tab(foreignTab.id)]
        state.selectedTabIDs = split.tabIDs; state.selectionBySpace[here.id.uuidString] = split.tabIDs
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: root.appendingPathComponent("session.json", isDirectory: false), options: [], createDirectory: root)
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1000) })
        let initial = store.state
        let target = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: initial)!
        let urls = [left.id: "https://live.invalid/left", right.id: "https://live.invalid/right"]
        try check(SidebarHierarchy.children(in: pinned, state: initial) == [.tab(keep.id), .split(split.id), .folder(folder.id)], "Fixture projects the split as one root")
        try check(target.wholeSplits && SidebarItemsCopy(items: [.tab(keep.id)], spaceID: here.id, profileID: profile.id, state: initial)?.wholeSplits == false
                  && SidebarItemsCopy(items: [.folder(folder.id)], spaceID: here.id, profileID: profile.id, state: initial)?.wholeSplits == false
                  && SidebarItemsCopy(items: [.split(split.id), .tab(keep.id)], spaceID: here.id, profileID: profile.id, state: initial)?.wholeSplits == false,
                  "Loose tabs, folders and mixed selections copy too, but only all-split drags are whole-split copies")

        try check(store.canCopySidebarItems(target, to: pinned, before: .tab(keep.id), destinations: urls) && store.state == initial, "Proposal admits the copy without publishing")
        let foreign = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .favorite, profileID: UUID())
        try check(!store.canCopySidebarItems(target, to: foreign, before: nil, destinations: urls), "A foreign Profile's Favorites refuse the copy")
        try check(!store.canCopySidebarItems(target, to: pinned, before: .tab(away.id), destinations: urls), "A before item outside the destination refuses")
        try check(!store.canCopySidebarItems(target, to: pinned, before: nil, destinations: [left.id: urls[left.id]!]), "Every child needs its resolved destination")
        try check(try store.copySidebarItems(target, to: pinned, before: .tab(away.id), destinations: urls) == nil && store.state == initial, "A refused copy publishes nothing")

        let first = try store.copySidebarItems(target, to: pinned, before: .tab(keep.id), destinations: urls)!
        var after = store.state
        guard case .split(let firstID)? = first.roots.first, let firstGroup = after.splitLayouts.first(where: { $0.id == firstID }) else { throw NSError(domain: "copy root", code: 1) }
        try check(first.roots.count == 1 && firstID != split.id, "One fresh split root")
        try check(Set(firstGroup.tabIDs).isDisjoint(with: split.tabIDs) && firstGroup.tabIDs == first.tabIDs, "Fresh child identities in original order")
        try check(firstGroup.orientation == split.orientation && firstGroup.widthFactors == split.widthFactors && firstGroup.customTitle == split.customTitle, "Orientation, proportions and name copied")
        try check(SidebarHierarchy.children(in: pinned, state: after) == [.split(firstID), .tab(keep.id), .split(split.id), .folder(folder.id)], "Copy placed at the drop location; original keeps its slot")
        try check(after.splitLayouts.first(where: { $0.id == split.id }) == split && split.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id } == initial.tabs.first { $0.id == id } }, "Original split and children unchanged")
        let firstChildren = firstGroup.tabIDs.map { id in after.tabs.first { $0.id == id }! }
        try check(firstChildren.map(\.savedURL) == [urls[left.id]!, urls[right.id]!] && firstChildren.allSatisfy { $0.kind == .pinned && $0.folderID == nil && $0.spaceID == here.id }, "Children take the resolved URLs and the pinned root")
        try check(first.openTabIDs == firstGroup.tabIDs, "Every copied split child requests a background page (options 0x100)")
        try check(after.selectedTabIDs == initial.selectedTabIDs && after.activeSpaceID == initial.activeSpaceID, "Store leaves selection to the window")

        let base = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let foldered = try store.copySidebarItems(base, to: inFolder, before: nil, destinations: urls)!
        after = store.state
        guard case .split(let folderedID)? = foldered.roots.first, let folderedGroup = after.splitLayouts.first(where: { $0.id == folderedID }) else { throw NSError(domain: "folder copy", code: 1) }
        try check(SidebarHierarchy.children(in: inFolder, state: after) == [.tab(inside.id), .split(folderedID)], "Folder drop appends the copy inside it")
        try check(folderedGroup.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.folderID == folder.id }, "Folder copy children carry the folder")

        let todayTarget = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let unpinned = try store.copySidebarItems(todayTarget, to: todayLocation, before: .tab(today.id), destinations: urls)!
        after = store.state
        guard case .split(let todayID)? = unpinned.roots.first, let todayGroup = after.splitLayouts.first(where: { $0.id == todayID }) else { throw NSError(domain: "today copy", code: 1) }
        try check(SidebarHierarchy.children(in: todayLocation, state: after).first == .split(todayID), "Today drop places the copy before its target")
        try check(todayGroup.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.kind == .today }, "Today copy children become Today items")

        let awayTarget = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let moved = try store.copySidebarItems(awayTarget, to: therePinned, before: .tab(away.id), destinations: urls)!
        after = store.state
        guard case .split(let awayID)? = moved.roots.first, let awayGroup = after.splitLayouts.first(where: { $0.id == awayID }) else { throw NSError(domain: "space copy", code: 1) }
        try check(SidebarHierarchy.children(in: therePinned, state: after) == [.split(awayID), .tab(away.id)], "Another Space's window places the copy in its own Space")
        try check(awayGroup.spaceID == there.id && awayGroup.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.spaceID == there.id }, "Cross-Space copy belongs to the destination Space")
        try check(SidebarHierarchy.children(in: pinned, state: after).contains(.split(split.id)) && after.splitLayouts.first(where: { $0.id == split.id })?.spaceID == here.id, "The source Space keeps the original")

        let trayTarget = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let tray = try store.copySidebarItems(trayTarget, to: favorites, before: nil, destinations: urls)!
        after = store.state
        guard case .split(let trayID)? = tray.roots.first, let trayGroup = after.splitLayouts.first(where: { $0.id == trayID }) else { throw NSError(domain: "tray copy", code: 1) }
        try check(SidebarHierarchy.children(in: favorites, state: after).contains(.split(trayID)), "App Tray drop makes the copy a Favorite root")
        try check(trayGroup.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.kind == .favorite }, "Favorite copy children are Favorites")
        try check(after.splitLayouts.first(where: { $0.id == split.id }) == split, "Original still unchanged after every copy")

        let favoriteCopy = SidebarItemsCopy(items: [.split(favorite.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let favURLs = [favA.id: "https://live.invalid/a", favB.id: "https://live.invalid/b"]
        let outOfTray = try store.copySidebarItems(favoriteCopy, to: pinned, before: nil, destinations: favURLs)!
        after = store.state
        guard case .split(let outID)? = outOfTray.roots.first, let outGroup = after.splitLayouts.first(where: { $0.id == outID }) else { throw NSError(domain: "favorite copy", code: 1) }
        try check(SidebarHierarchy.children(in: pinned, state: after).last == .split(outID), "A Favorite split's copy lands at the drop location")
        try check(outGroup.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }.map { $0.kind == .pinned && $0.spaceID == here.id } == true }, "Its children become pinned items in the Space")
        try check(SidebarHierarchy.children(in: favorites, state: after).contains(.split(favorite.id)) && after.splitLayouts.contains(favorite), "The Favorite original stays in the tray")
        try check(outOfTray.openTabIDs == outGroup.tabIDs, "Favorite copy children request background pages")
        let favoriteAgain = SidebarItemsCopy(items: [.split(favorite.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let inTray = try store.copySidebarItems(favoriteAgain, to: favorites, before: .split(favorite.id), destinations: favURLs)!
        after = store.state
        guard case .split(let inTrayID)? = inTray.roots.first else { throw NSError(domain: "tray reorder copy", code: 1) }
        let trayOrder = SidebarHierarchy.children(in: favorites, state: after)
        try check(trayOrder.firstIndex(of: .split(inTrayID)).map { $0 + 1 == trayOrder.firstIndex(of: .split(favorite.id)) } == true, "A copy within the tray lands before its target")

        let crossTarget = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let crossed = try store.copySidebarItems(crossTarget, to: elsewherePinned, before: .tab(foreignTab.id), destinations: urls)!
        after = store.state
        guard case .split(let crossID)? = crossed.roots.first, let crossGroup = after.splitLayouts.first(where: { $0.id == crossID }) else { throw NSError(domain: "profile copy", code: 1) }
        try check(SidebarHierarchy.children(in: elsewherePinned, state: after) == [.split(crossID), .tab(foreignTab.id)], "Cross-Profile copy lands in the other Profile's Space")
        try check(crossGroup.spaceID == elsewhere.id && crossGroup.tabIDs.allSatisfy { id in
            after.tabs.first { $0.id == id }.map { $0.profileID == foreignProfile.id && $0.spaceID == elsewhere.id } == true
        }, "Its children belong to the destination Profile")
        try check(split.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.profileID == profile.id } && after.splitLayouts.contains(split), "The originals keep their Profile")

        var retired: Set<UUID> = []
        var consent = false
        store.requestPageRetirement = { ids, shouldCommit, done in
            retired = ids
            done(consent && shouldCommit())
        }
        let reloadTarget = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        var refused: Result<SidebarDuplicateResult?, Error>?
        store.copySidebarSplitsReloadingOriginals(reloadTarget, to: elsewherePinned, before: nil, destinations: urls) { refused = $0 }
        if case .success(nil)? = refused {} else { throw NSError(domain: "refused reload", code: 1) }
        try check(retired == Set(split.tabIDs) && store.state == after, "A refused leave-page prompt publishes no copy")
        consent = true
        var reloaded: Result<SidebarDuplicateResult?, Error>?
        store.copySidebarSplitsReloadingOriginals(reloadTarget, to: elsewherePinned, before: nil, destinations: urls) { reloaded = $0 }
        guard case .success(let made?)? = reloaded, case .split(let reloadedID)? = made.roots.first else { throw NSError(domain: "reload copy", code: 1) }
        after = store.state
        try check(retired == Set(split.tabIDs) && SidebarHierarchy.children(in: elsewherePinned, state: after).last == .split(reloadedID),
                  "Consent retires exactly the originals' pages, then the copy lands in the other Profile")
        try check(after.splitLayouts.contains(split) && split.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.profileID == profile.id },
                  "The reloaded originals keep their records and Profile")
        store.requestPageRetirement = nil

        let note = tab("Note"), web = tab("Web")
        var withNote = store.state
        let noteSplit = BrowserSplitLayout(sidebarAnchorID: note.id, spaceID: here.id, tabIDs: [note.id, web.id], widthFactors: [0.5, 0.5])
        var typedNote = note; let noteID = URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md"); typedNote.url = InternalPage.note(noteID).urlString; typedNote.savedURL = typedNote.url
        withNote.tabs += [typedNote, web]; withNote.splitLayouts.append(noteSplit)
        let noteRoot = root.appendingPathComponent("Notes-" + UUID().uuidString)
        try encoder.encode(withNote).write(to: noteRoot.appendingPathComponent("session.json", isDirectory: false), options: [], createDirectory: noteRoot)
        let noteStore = try BrowserStore(directory: noteRoot, now: { Date(timeIntervalSince1970: 1000) })
        let noteCopy = SidebarItemsCopy(items: [.split(noteSplit.id)], spaceID: here.id, profileID: profile.id, state: noteStore.state)!
        let noteDocs = [typedNote.id: SidebarDocumentReference(page: .note(noteID), profileID: profile.id) {}]
        let noteURLs = [typedNote.id: typedNote.savedURL, web.id: "https://live.invalid/web"]
        try check(noteStore.canCopySidebarItems(noteCopy, to: elsewherePinned, before: nil, destinations: noteURLs, documents: noteDocs), "A split with a Note child copies into another Profile, since note files belong to none")
        try check(noteStore.canCopySidebarItems(noteCopy, to: pinned, before: nil, destinations: noteURLs, documents: noteDocs), "The same split copies within its Profile as a document alias")

        let stale = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: store.state)!
        store.updateTab(left.id, title: "Renamed while deciding", url: "https://live.invalid/moved-on")
        _ = store.open("https://unrelated.invalid/", kind: .today)
        let staleResult = try store.copySidebarItems(stale, to: pinned, before: nil, destinations: urls)
        guard case .split(let staleID)? = staleResult?.roots.first else { throw NSError(domain: "stale copy", code: 1) }
        try check(store.state.tabs.first { $0.id == store.state.splitLayouts.first { $0.id == staleID }!.tabIDs[0] }?.savedTitle
                  == store.state.tabs.first { $0.id == left.id }?.savedTitle, "A stale gesture copies the current records")
        var refoldered = store.state
        if let index = refoldered.tabs.firstIndex(where: { $0.id == right.id }) { refoldered.tabs[index].folderID = folder.id }
        try check(SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: refoldered)?.matchesPlacement(of: stale) != true,
                  "A child that changed folder no longer matches the gesture")

        let sessionURL = root.appendingPathComponent("session.json")
        let beforeFailure = store.state, savedBytes = try Data(contentsOf: sessionURL)
        try FileManager.default.removeItem(at: sessionURL)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: false)
        let failing = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: store.state)!
        var threw = false
        do { _ = try store.copySidebarItems(failing, to: pinned, before: nil, destinations: urls) } catch { threw = true }
        try FileManager.default.removeItem(at: sessionURL); try savedBytes.write(to: sessionURL)
        try check(threw && store.state == beforeFailure && (try Data(contentsOf: sessionURL)) == savedBytes, "A failed save throws and changes neither state nor disk")

        var pendingDone: ((Bool) -> Void)?
        store.requestPageRetirement = { _, _, done in pendingDone = done }
        store.closeTabs([right.id]) { _ in }
        let retiringCopy = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: store.state)!
        try check(!store.canCopySidebarItems(retiringCopy, to: pinned, before: nil, destinations: urls), "A retiring child refuses the copy")
        pendingDone?(false); store.requestPageRetirement = nil
        let ephemeral = BrowserStore(privateParentProfileID: profile.id, engineProfilePath: "/nonexistent", directory: root, settings: BrowserSettings())
        try check(!ephemeral.canCopySidebarItems(retiringCopy, to: pinned, before: nil, destinations: urls), "A private (ephemeral) store never copies")
        var archived = store.state
        if let index = archived.tabs.firstIndex(where: { $0.id == right.id }) { archived.tabs[index].archivedAt = Date(timeIntervalSince1970: 5) }
        try check(SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: archived) == nil, "An archived child is not copied (InterProfileMove.admits)")
        var removing = store.state
        removing.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: foreignProfile.id, profileName: foreignProfile.name)]
        try check(!InterProfileMove.profilesAvailable(profile.id, foreignProfile.id, in: removing)
                  && SidebarWindowMove(items: [.split(split.id)], sourceSpaceID: here.id, profileID: profile.id,
                      destinationProfileID: foreignProfile.id, to: elsewherePinned, before: nil, state: removing) == nil,
                  "A Profile pending removal takes no copy")

        var full = store.state
        let fillers = (0..<(12 - SidebarHierarchy.children(in: favorites, state: full).count)).map { tab("Filler\($0)", kind: .favorite) }
        full.tabs += fillers
        let fullRoot = root.appendingPathComponent("Full-" + UUID().uuidString)
        try encoder.encode(full).write(to: fullRoot.appendingPathComponent("session.json", isDirectory: false), options: [], createDirectory: fullRoot)
        let fullStore = try BrowserStore(directory: fullRoot)
        try check(SidebarHierarchy.children(in: favorites, state: fullStore.state).count == 12, "Fixture tray is full")
        let intoFull = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: fullStore.state)!
        let withinFull = SidebarItemsCopy(items: [.split(favorite.id)], spaceID: here.id, profileID: profile.id, state: fullStore.state)!
        try check(!fullStore.canCopySidebarItems(intoFull, to: favorites, before: nil, destinations: urls)
                  && (try fullStore.copySidebarItems(intoFull, to: favorites, before: nil, destinations: urls)) == nil
                  && fullStore.state.tabs.count == full.tabs.count, "A full tray refuses a split copied in")
        try check(!fullStore.canCopySidebarItems(withinFull, to: favorites, before: nil, destinations: favURLs), "A full tray refuses a Favorite split copied within it")
        try check(fullStore.canCopySidebarItems(withinFull, to: pinned, before: nil, destinations: favURLs), "The same Favorite split still copies out of a full tray")

        var multi = store.state
        let m1 = tab("M1"), m2 = tab("M2")
        let second = BrowserSplitLayout(sidebarAnchorID: m1.id, spaceID: here.id, tabIDs: [m1.id, m2.id], widthFactors: [0.5, 0.5])
        multi.tabs += [m1, m2]; multi.splitLayouts.append(second)
        multi.sidebarItemOrder[pinned.key] = (multi.sidebarItemOrder[pinned.key] ?? []) + [.tab(m1.id)]
        let multiRoot = root.appendingPathComponent("Multi-" + UUID().uuidString)
        try encoder.encode(multi).write(to: multiRoot.appendingPathComponent("session.json", isDirectory: false), options: [], createDirectory: multiRoot)
        let multiStore = try BrowserStore(directory: multiRoot)
        let both = SidebarItemsCopy(items: [.split(split.id), .split(second.id)], spaceID: here.id, profileID: profile.id, state: multiStore.state)!
        var bothURLs = urls; bothURLs[m1.id] = "https://live.invalid/m1"; bothURLs[m2.id] = "https://live.invalid/m2"
        let pair = try multiStore.copySidebarItems(both, to: todayLocation, before: nil, destinations: bothURLs)!
        try check(pair.roots.count == 2 && Array(SidebarHierarchy.children(in: todayLocation, state: multiStore.state).suffix(2)) == pair.roots,
                  "Several splits land together in their original order")
        try check(pair.openTabIDs.count == 4, "Every copied split's children request pages, not only the last")

        let reload = try BrowserStore(directory: root)
        try check([firstID, folderedID, todayID, awayID, trayID, outID, inTrayID, crossID, reloadedID, staleID].allSatisfy { id in reload.state.splitLayouts.contains { $0.id == id } }, "Every placed copy reloads durably")
        try itemCopies(root)
        print("\(count) sidebar copy assertions passed")
    }

    static func itemCopies(_ root: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let profile = BrowserProfile(id: UUID(), name: "Original"), foreignProfile = BrowserProfile(id: UUID(), name: "Other")
        let here = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let there = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "FEDCBA", profileID: profile.id)
        let elsewhere = BrowserSpace(id: UUID(), name: "Elsewhere", symbol: "circle", color: "123456", profileID: foreignProfile.id)
        let outer = BrowserFolder(id: UUID(), spaceID: here.id, name: "Outer")
        let nested = BrowserFolder(id: UUID(), spaceID: here.id, name: "Nested", parentID: outer.id, isExpanded: false)
        let target = BrowserFolder(id: UUID(), spaceID: here.id, name: "Target")
        func tab(_ title: String, kind: TabKind = .pinned, folder: UUID? = nil, url: String? = nil) -> BrowserTab {
            let url = url ?? "https://saved.invalid/" + title
            return .init(id: UUID(), spaceID: here.id, profileID: profile.id, url: url, title: title, kind: kind, folderID: folder,
                         createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }
        let noteID = URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")
        let loose = tab("Loose"), today = tab("Today", kind: .today), favorite = tab("Favorite", kind: .favorite)
        let inOuter = tab("InOuter", folder: outer.id), inNested = tab("InNested", folder: nested.id)
        let pairA = tab("PairA", folder: nested.id), pairB = tab("PairB", folder: nested.id)
        let rootA = tab("RootA"), rootB = tab("RootB"), note = tab("Note", url: InternalPage.note(noteID).urlString)
        let nestedSplit = BrowserSplitLayout(sidebarAnchorID: pairA.id, spaceID: here.id, tabIDs: [pairA.id, pairB.id], widthFactors: [0.5, 0.5])
        let rootSplit = BrowserSplitLayout(sidebarAnchorID: rootA.id, customTitle: "Root pair", spaceID: here.id,
                                           tabIDs: [rootA.id, rootB.id], widthFactors: [0.3, 0.7])
        var state = BrowserState(profiles: [profile, foreignProfile], spaces: [here, there, elsewhere], activeSpaceID: here.id)
        state.folders = [outer, nested, target]
        state.tabs = [loose, today, favorite, inOuter, inNested, pairA, pairB, rootA, rootB, note]
        state.splitLayouts = [nestedSplit, rootSplit]
        let pinned = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .pinned)
        let todayLocation = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .today)
        let outerLocation = SidebarContainerLocation(spaceID: here.id, folderID: outer.id, section: .pinned)
        let nestedLocation = SidebarContainerLocation(spaceID: here.id, folderID: nested.id, section: .pinned)
        let targetLocation = SidebarContainerLocation(spaceID: here.id, folderID: target.id, section: .pinned)
        let therePinned = SidebarContainerLocation(spaceID: there.id, folderID: nil, section: .pinned)
        let elsewherePinned = SidebarContainerLocation(spaceID: elsewhere.id, folderID: nil, section: .pinned)
        let favorites = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .favorite, profileID: profile.id)
        state.sidebarItemOrder[pinned.key] = [.tab(loose.id), .folder(outer.id), .tab(rootA.id), .tab(note.id), .folder(target.id)]
        state.sidebarItemOrder[outerLocation.key] = [.folder(nested.id), .tab(inOuter.id)]
        state.sidebarItemOrder[nestedLocation.key] = [.tab(inNested.id), .tab(pairA.id)]
        let itemsRoot = root.appendingPathComponent("Items-" + UUID().uuidString)
        try encoder.encode(state).write(to: itemsRoot.appendingPathComponent("session.json", isDirectory: false), options: [], createDirectory: itemsRoot)
        let store = try BrowserStore(directory: itemsRoot, now: { Date(timeIntervalSince1970: 1000) })
        let initial = store.state
        let noteDocs = [note.id: SidebarDocumentReference(page: .note(noteID), profileID: profile.id) {}]
        func copy(_ items: [SidebarItemReference]) -> SidebarItemsCopy? {
            SidebarItemsCopy(items: items, spaceID: here.id, profileID: profile.id, state: store.state)
        }
        func sources(_ copy: SidebarItemsCopy) -> [UUID: String] { Dictionary(uniqueKeysWithValues: copy.tabs.map { ($0.id, $0.savedURL) }) }
        func documents(_ copy: SidebarItemsCopy) -> [UUID: SidebarDocumentReference] { copy.tabs.contains { $0.id == note.id } ? noteDocs : [:] }
        func can(_ items: [SidebarItemReference], _ destination: SidebarContainerLocation, before: SidebarItemReference? = nil) -> Bool {
            guard let made = copy(items) else { return false }
            return store.canCopySidebarItems(made, to: destination, before: before, destinations: sources(made), documents: documents(made))
        }
        func place(_ items: [SidebarItemReference], _ destination: SidebarContainerLocation,
                   before: SidebarItemReference? = nil) throws -> SidebarDuplicateResult {
            guard let made = copy(items), let result = try store.copySidebarItems(made, to: destination, before: before,
                      destinations: sources(made), documents: documents(made)) else { throw NSError(domain: "item copy refused", code: 1) }
            return result
        }
        func children(_ location: SidebarContainerLocation) -> [SidebarItemReference] { SidebarHierarchy.children(in: location, state: store.state) }
        func folderLocation(_ id: UUID, space: UUID = here.id) -> SidebarContainerLocation { .init(spaceID: space, folderID: id, section: .pinned) }

        try check(copy([.tab(loose.id)])?.wholeSplits == false && copy([.folder(outer.id)])?.wholeSplits == false
                  && copy([.tab(loose.id), .folder(outer.id), .split(rootSplit.id)])?.wholeSplits == false
                  && copy([.split(rootSplit.id)])?.wholeSplits == true, "Option-drag copies tabs, folders and mixed selections; only all-split drags count as whole splits")
        try check(copy([.tab(pairA.id)]) == nil, "A single split child is never copied out of its split")

        let looseCopy = try place([.tab(loose.id)], todayLocation, before: .tab(today.id))
        guard case .tab(let todayCopy)? = looseCopy.roots.first else { throw NSError(domain: "tab copy root", code: 1) }
        try check(children(todayLocation) == [.tab(todayCopy), .tab(today.id)], "A tab copied onto Today lands where it was dropped")
        try check(store.state.tab(todayCopy).map { $0.kind == .today && $0.savedURL == loose.savedURL && $0.id != loose.id } == true,
                  "The copy is a fresh Today tab for the same page")
        try check(store.state.tab(loose.id) == initial.tab(loose.id) && SidebarHierarchy.children(in: pinned, state: store.state)
                  == SidebarHierarchy.children(in: pinned, state: initial), "The original tab stays exactly where it was")
        try check(looseCopy.openTabIDs == [todayCopy], "A copied tab opens its page in the background")

        let headerCopy = try place([.tab(loose.id)], pinned, before: .tab(loose.id))
        try check(Array(children(pinned).prefix(2)) == [headerCopy.roots[0], .tab(loose.id)], "The Space header drops the copy at the top of Pinned, above its original")

        let folderCopy = try place([.folder(outer.id)], targetLocation)
        guard case .folder(let outerCopy)? = folderCopy.roots.first, let copiedOuter = store.state.folders.first(where: { $0.id == outerCopy }) else {
            throw NSError(domain: "folder copy root", code: 1)
        }
        try check(children(targetLocation) == [.folder(outerCopy)] && copiedOuter.parentID == target.id && copiedOuter.name == outer.name,
                  "A folder copied onto another folder's middle nests inside it with the same name")
        let outerChildren = children(folderLocation(outerCopy))
        guard outerChildren.count == 2, case .folder(let nestedCopy) = outerChildren[0], case .tab(let inOuterCopy) = outerChildren[1] else {
            throw NSError(domain: "nested copy", code: 1)
        }
        try check(nestedCopy != nested.id && inOuterCopy != inOuter.id && store.state.folders.first { $0.id == nestedCopy }?.isExpanded == false,
                  "Nested folders and tabs are fresh copies that keep their order and disclosure")
        let nestedChildren = children(folderLocation(nestedCopy))
        guard nestedChildren.count == 2, case .split(let nestedSplitCopy) = nestedChildren[1],
              let copiedSplit = store.state.splitLayouts.first(where: { $0.id == nestedSplitCopy }) else { throw NSError(domain: "nested split copy", code: 1) }
        try check(copiedSplit.tabIDs.allSatisfy { id in store.state.tab(id)?.folderID == nestedCopy } && Set(copiedSplit.tabIDs).isDisjoint(with: nestedSplit.tabIDs),
                  "A split inside the folder is copied whole with fresh panes")
        try check(SidebarHierarchy.children(in: outerLocation, state: store.state) == SidebarHierarchy.children(in: outerLocation, state: initial)
                  && store.state.folders.first { $0.id == outer.id } == outer, "The original folder keeps its contents")
        try check(folderCopy.tabIDs.count == 4 && folderCopy.openTabIDs.isEmpty, "A copied folder's pages stay saved until opened")
        try check(!can([.folder(outer.id)], todayLocation) && !can([.folder(outer.id)], favorites), "Folders cannot be copied into Today or the Favorites tray")

        let mixed = try place([.tab(loose.id), .folder(outer.id), .split(rootSplit.id)], targetLocation)
        try check(mixed.roots.count == 3 && Array(children(targetLocation).suffix(3)) == mixed.roots, "A mixed selection lands together in its original order")
        guard case .split(let mixedSplit) = mixed.roots[2], let mixedGroup = store.state.splitLayouts.first(where: { $0.id == mixedSplit }) else {
            throw NSError(domain: "mixed split", code: 1)
        }
        try check(mixedGroup.customTitle == rootSplit.customTitle && mixedGroup.widthFactors == rootSplit.widthFactors, "Its split keeps its name and proportions")
        try check(mixed.openTabIDs.count == 3 && mixed.openTabIDs.allSatisfy(mixed.tabIDs.contains), "Its top-level tab and split open; the folder's pages wait")

        let outOfTray = try place([.tab(favorite.id)], pinned)
        guard case .tab(let favoriteCopy)? = outOfTray.roots.first else { throw NSError(domain: "favorite copy", code: 1) }
        try check(store.state.tab(favoriteCopy).map { $0.kind == .pinned && $0.spaceID == here.id } == true
                  && children(favorites) == [.tab(favorite.id)], "A Favorite tile copies into Pinned and stays in the tray")
        let intoTray = try place([.tab(loose.id)], favorites, before: .tab(favorite.id))
        try check(children(favorites) == [intoTray.roots[0], .tab(favorite.id)]
                  && store.state.tab(intoTray.tabIDs[0])?.kind == .favorite, "A tab copied onto the tray becomes a Favorite before its target")
        let withinTray = try place([.tab(favorite.id)], favorites)
        try check(children(favorites).last == withinTray.roots[0] && children(favorites).count == 3, "A Favorite copied within the tray adds a tile")

        let away = try place([.tab(loose.id), .folder(outer.id)], therePinned)
        guard case .folder(let awayFolder) = away.roots[1] else { throw NSError(domain: "space copy", code: 1) }
        try check(Array(children(therePinned).suffix(2)) == away.roots && away.tabIDs.allSatisfy { store.state.tab($0)?.spaceID == there.id }
                  && store.state.folders.filter { $0.spaceID == there.id }.count == 2 && store.state.folders.first { $0.id == awayFolder }?.spaceID == there.id,
                  "A dock drop copies into another Space that shares data, folders and all")
        try check(children(pinned).contains(.tab(loose.id)) && children(pinned).contains(.folder(outer.id)), "The originals stay in their own Space")

        try check(!can([.tab(loose.id)], elsewherePinned) && !can([.folder(outer.id)], elsewherePinned)
                  && !can([.tab(loose.id), .split(rootSplit.id)], elsewherePinned), "Tabs, folders and mixed selections never copy into a Space that keeps separate data")
        try check(can([.split(rootSplit.id)], elsewherePinned), "Whole web splits keep their separate-data copy")

        let noteCopy = try place([.tab(note.id)], targetLocation)
        try check(store.state.tab(noteCopy.tabIDs[0]).map { $0.savedURL == note.savedURL && $0.id != note.id } == true && noteCopy.openTabIDs.isEmpty,
                  "A copied Note is a new entry for the same document, like Duplicate")
        let noteOnly = copy([.tab(note.id)])!
        try check(!store.canCopySidebarItems(noteOnly, to: targetLocation, before: nil, destinations: sources(noteOnly), documents: [:]),
                  "A Note copy needs its validated document")

        let nestedOnly = copy([.folder(nested.id)])!
        var reparented = store.state
        reparented.folders[reparented.folders.firstIndex { $0.id == nested.id }!].parentID = target.id
        reparented.sidebarItemOrder[outerLocation.key] = [.tab(inOuter.id)]
        try check(SidebarItemsCopy(items: [.folder(nested.id)], spaceID: here.id, profileID: profile.id, state: reparented)?.matchesPlacement(of: nestedOnly) == false,
                  "A folder that moved during the drag no longer matches the gesture")

        var pending: ((Bool) -> Void)?
        store.requestPageRetirement = { _, _, done in pending = done }
        store.closeTabs([inOuter.id]) { _ in }
        try check(!can([.folder(outer.id)], targetLocation), "A folder whose page is closing refuses the copy")
        pending?(false); store.requestPageRetirement = nil

        var bulk = initial
        var bulkRoots: [SidebarItemReference] = []
        for index in 0..<6 {
            let a = tab("SplitA\(index)"), b = tab("SplitB\(index)")
            bulk.tabs += [a, b]
            bulk.splitLayouts.append(BrowserSplitLayout(sidebarAnchorID: a.id, spaceID: here.id, tabIDs: [a.id, b.id], widthFactors: [0.5, 0.5]))
            bulkRoots.append(.split(bulk.splitLayouts.last!.id))
        }
        for index in 0..<3 { let extra = tab("Extra\(index)"); bulk.tabs.append(extra); bulkRoots.append(.tab(extra.id)) }
        let bulkRoot = root.appendingPathComponent("Bulk-" + UUID().uuidString)
        try encoder.encode(bulk).write(to: bulkRoot.appendingPathComponent("session.json", isDirectory: false), options: [], createDirectory: bulkRoot)
        let bulkStore = try BrowserStore(directory: bulkRoot)
        let many = SidebarItemsCopy(items: bulkRoots, spaceID: here.id, profileID: profile.id, state: bulkStore.state)!
        let bulkResult = try bulkStore.copySidebarItems(many, to: todayLocation, before: nil, destinations: sources(many))!
        try check(bulkResult.tabIDs.count == 15 && bulkResult.openTabIDs.count == 10, "Only the first five copied items open pages, so a big copy stays saved")

        let reload = try BrowserStore(directory: itemsRoot)
        try check((looseCopy.tabIDs + folderCopy.tabIDs + mixed.tabIDs + away.tabIDs + noteCopy.tabIDs).allSatisfy { reload.state.tab($0) != nil },
                  "Every Option-drag copy is saved")
    }
}

private extension Data {
    func write(to url: URL, options: Data.WritingOptions, createDirectory directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(to: url, options: options)
    }
}
