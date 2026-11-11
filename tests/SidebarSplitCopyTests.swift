import Foundation

@main @MainActor
struct SidebarSplitCopyTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func main() throws {
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
        let target = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: initial)!
        let urls = [left.id: "https://live.invalid/left", right.id: "https://live.invalid/right"]
        try check(SidebarHierarchy.children(in: pinned, state: initial) == [.tab(keep.id), .split(split.id), .folder(folder.id)], "Fixture projects the split as one root")
        try check(SidebarSplitCopy(items: [.tab(keep.id)], spaceID: here.id, profileID: profile.id, state: initial) == nil
                  && SidebarSplitCopy(items: [.folder(folder.id)], spaceID: here.id, profileID: profile.id, state: initial) == nil
                  && SidebarSplitCopy(items: [.split(split.id), .tab(keep.id)], spaceID: here.id, profileID: profile.id, state: initial) == nil,
                  "Only whole splits are copied here; loose tabs and folders stay FOLD17's")

        try check(store.canCopySidebarSplits(target, to: pinned, before: .tab(keep.id), destinations: urls) && store.state == initial, "Proposal admits the copy without publishing")
        let foreign = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .favorite, profileID: UUID())
        try check(!store.canCopySidebarSplits(target, to: foreign, before: nil, destinations: urls), "A foreign Profile's Favorites refuse the copy")
        try check(!store.canCopySidebarSplits(target, to: pinned, before: .tab(away.id), destinations: urls), "A before item outside the destination refuses")
        try check(!store.canCopySidebarSplits(target, to: pinned, before: nil, destinations: [left.id: urls[left.id]!]), "Every child needs its resolved destination")
        try check(try store.copySidebarSplits(target, to: pinned, before: .tab(away.id), destinations: urls) == nil && store.state == initial, "A refused copy publishes nothing")

        let first = try store.copySidebarSplits(target, to: pinned, before: .tab(keep.id), destinations: urls)!
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

        let base = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let foldered = try store.copySidebarSplits(base, to: inFolder, before: nil, destinations: urls)!
        after = store.state
        guard case .split(let folderedID)? = foldered.roots.first, let folderedGroup = after.splitLayouts.first(where: { $0.id == folderedID }) else { throw NSError(domain: "folder copy", code: 1) }
        try check(SidebarHierarchy.children(in: inFolder, state: after) == [.tab(inside.id), .split(folderedID)], "Folder drop appends the copy inside it")
        try check(folderedGroup.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.folderID == folder.id }, "Folder copy children carry the folder")

        let todayTarget = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let unpinned = try store.copySidebarSplits(todayTarget, to: todayLocation, before: .tab(today.id), destinations: urls)!
        after = store.state
        guard case .split(let todayID)? = unpinned.roots.first, let todayGroup = after.splitLayouts.first(where: { $0.id == todayID }) else { throw NSError(domain: "today copy", code: 1) }
        try check(SidebarHierarchy.children(in: todayLocation, state: after).first == .split(todayID), "Today drop places the copy before its target")
        try check(todayGroup.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.kind == .today }, "Today copy children become Today items")

        let awayTarget = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let moved = try store.copySidebarSplits(awayTarget, to: therePinned, before: .tab(away.id), destinations: urls)!
        after = store.state
        guard case .split(let awayID)? = moved.roots.first, let awayGroup = after.splitLayouts.first(where: { $0.id == awayID }) else { throw NSError(domain: "space copy", code: 1) }
        try check(SidebarHierarchy.children(in: therePinned, state: after) == [.split(awayID), .tab(away.id)], "Another Space's window places the copy in its own Space")
        try check(awayGroup.spaceID == there.id && awayGroup.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.spaceID == there.id }, "Cross-Space copy belongs to the destination Space")
        try check(SidebarHierarchy.children(in: pinned, state: after).contains(.split(split.id)) && after.splitLayouts.first(where: { $0.id == split.id })?.spaceID == here.id, "The source Space keeps the original")

        let trayTarget = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let tray = try store.copySidebarSplits(trayTarget, to: favorites, before: nil, destinations: urls)!
        after = store.state
        guard case .split(let trayID)? = tray.roots.first, let trayGroup = after.splitLayouts.first(where: { $0.id == trayID }) else { throw NSError(domain: "tray copy", code: 1) }
        try check(SidebarHierarchy.children(in: favorites, state: after).contains(.split(trayID)), "App Tray drop makes the copy a Favorite root")
        try check(trayGroup.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.kind == .favorite }, "Favorite copy children are Favorites")
        try check(after.splitLayouts.first(where: { $0.id == split.id }) == split, "Original still unchanged after every copy")

        let favoriteCopy = SidebarSplitCopy(items: [.split(favorite.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let favURLs = [favA.id: "https://live.invalid/a", favB.id: "https://live.invalid/b"]
        let outOfTray = try store.copySidebarSplits(favoriteCopy, to: pinned, before: nil, destinations: favURLs)!
        after = store.state
        guard case .split(let outID)? = outOfTray.roots.first, let outGroup = after.splitLayouts.first(where: { $0.id == outID }) else { throw NSError(domain: "favorite copy", code: 1) }
        try check(SidebarHierarchy.children(in: pinned, state: after).last == .split(outID), "A Favorite split's copy lands at the drop location")
        try check(outGroup.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }.map { $0.kind == .pinned && $0.spaceID == here.id } == true }, "Its children become pinned items in the Space")
        try check(SidebarHierarchy.children(in: favorites, state: after).contains(.split(favorite.id)) && after.splitLayouts.contains(favorite), "The Favorite original stays in the tray")
        try check(outOfTray.openTabIDs == outGroup.tabIDs, "Favorite copy children request background pages")
        let favoriteAgain = SidebarSplitCopy(items: [.split(favorite.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let inTray = try store.copySidebarSplits(favoriteAgain, to: favorites, before: .split(favorite.id), destinations: favURLs)!
        after = store.state
        guard case .split(let inTrayID)? = inTray.roots.first else { throw NSError(domain: "tray reorder copy", code: 1) }
        let trayOrder = SidebarHierarchy.children(in: favorites, state: after)
        try check(trayOrder.firstIndex(of: .split(inTrayID)).map { $0 + 1 == trayOrder.firstIndex(of: .split(favorite.id)) } == true, "A copy within the tray lands before its target")

        let crossTarget = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
        let crossed = try store.copySidebarSplits(crossTarget, to: elsewherePinned, before: .tab(foreignTab.id), destinations: urls)!
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
        let reloadTarget = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: after)!
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
        var typedNote = note; let noteID = UUID(); typedNote.url = InternalPage.note(noteID).urlString; typedNote.savedURL = typedNote.url
        withNote.tabs += [typedNote, web]; withNote.splitLayouts.append(noteSplit)
        let noteRoot = root.appendingPathComponent("Notes-" + UUID().uuidString)
        try encoder.encode(withNote).write(to: noteRoot.appendingPathComponent("session.json", isDirectory: false), options: [], createDirectory: noteRoot)
        let noteStore = try BrowserStore(directory: noteRoot, now: { Date(timeIntervalSince1970: 1000) })
        let noteCopy = SidebarSplitCopy(items: [.split(noteSplit.id)], spaceID: here.id, profileID: profile.id, state: noteStore.state)!
        let noteDocs = [typedNote.id: SidebarDocumentReference(page: .note(noteID), profileID: profile.id) {}]
        let noteURLs = [typedNote.id: typedNote.savedURL, web.id: "https://live.invalid/web"]
        try check(!noteStore.canCopySidebarSplits(noteCopy, to: elsewherePinned, before: nil, destinations: noteURLs, documents: noteDocs), "A split with a Note child cannot copy into another Profile")
        try check(noteStore.canCopySidebarSplits(noteCopy, to: pinned, before: nil, destinations: noteURLs, documents: noteDocs), "The same split copies within its Profile as a document alias")

        let stale = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: store.state)!
        store.updateTab(left.id, title: "Renamed while deciding", url: "https://live.invalid/moved-on")
        _ = store.open("https://unrelated.invalid/", kind: .today)
        let staleResult = try store.copySidebarSplits(stale, to: pinned, before: nil, destinations: urls)
        guard case .split(let staleID)? = staleResult?.roots.first else { throw NSError(domain: "stale copy", code: 1) }
        try check(store.state.tabs.first { $0.id == store.state.splitLayouts.first { $0.id == staleID }!.tabIDs[0] }?.savedTitle
                  == store.state.tabs.first { $0.id == left.id }?.savedTitle, "A stale gesture copies the current records")
        var refoldered = store.state
        if let index = refoldered.tabs.firstIndex(where: { $0.id == right.id }) { refoldered.tabs[index].folderID = folder.id }
        try check(SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: refoldered)?.matchesPlacement(of: stale) != true,
                  "A child that changed folder no longer matches the gesture")

        let sessionURL = root.appendingPathComponent("session.json")
        let beforeFailure = store.state, savedBytes = try Data(contentsOf: sessionURL)
        try FileManager.default.removeItem(at: sessionURL)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: false)
        let failing = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: store.state)!
        var threw = false
        do { _ = try store.copySidebarSplits(failing, to: pinned, before: nil, destinations: urls) } catch { threw = true }
        try FileManager.default.removeItem(at: sessionURL); try savedBytes.write(to: sessionURL)
        try check(threw && store.state == beforeFailure && (try Data(contentsOf: sessionURL)) == savedBytes, "A failed save throws and changes neither state nor disk")

        var pendingDone: ((Bool) -> Void)?
        store.requestPageRetirement = { _, _, done in pendingDone = done }
        store.closeTabs([right.id]) { _ in }
        let retiringCopy = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: store.state)!
        try check(!store.canCopySidebarSplits(retiringCopy, to: pinned, before: nil, destinations: urls), "A retiring child refuses the copy")
        pendingDone?(false); store.requestPageRetirement = nil
        let ephemeral = BrowserStore(privateParentProfileID: profile.id, engineProfilePath: "/nonexistent", directory: root, settings: BrowserSettings())
        try check(!ephemeral.canCopySidebarSplits(retiringCopy, to: pinned, before: nil, destinations: urls), "A private (ephemeral) store never copies")
        var archived = store.state
        if let index = archived.tabs.firstIndex(where: { $0.id == right.id }) { archived.tabs[index].archivedAt = Date(timeIntervalSince1970: 5) }
        try check(SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: archived) == nil, "An archived child is not copied (InterProfileMove.admits)")
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
        let intoFull = SidebarSplitCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: fullStore.state)!
        let withinFull = SidebarSplitCopy(items: [.split(favorite.id)], spaceID: here.id, profileID: profile.id, state: fullStore.state)!
        try check(!fullStore.canCopySidebarSplits(intoFull, to: favorites, before: nil, destinations: urls)
                  && (try fullStore.copySidebarSplits(intoFull, to: favorites, before: nil, destinations: urls)) == nil
                  && fullStore.state.tabs.count == full.tabs.count, "A full tray refuses a split copied in")
        try check(!fullStore.canCopySidebarSplits(withinFull, to: favorites, before: nil, destinations: favURLs), "A full tray refuses a Favorite split copied within it")
        try check(fullStore.canCopySidebarSplits(withinFull, to: pinned, before: nil, destinations: favURLs), "The same Favorite split still copies out of a full tray")

        var multi = store.state
        let m1 = tab("M1"), m2 = tab("M2")
        let second = BrowserSplitLayout(sidebarAnchorID: m1.id, spaceID: here.id, tabIDs: [m1.id, m2.id], widthFactors: [0.5, 0.5])
        multi.tabs += [m1, m2]; multi.splitLayouts.append(second)
        multi.sidebarItemOrder[pinned.key] = (multi.sidebarItemOrder[pinned.key] ?? []) + [.tab(m1.id)]
        let multiRoot = root.appendingPathComponent("Multi-" + UUID().uuidString)
        try encoder.encode(multi).write(to: multiRoot.appendingPathComponent("session.json", isDirectory: false), options: [], createDirectory: multiRoot)
        let multiStore = try BrowserStore(directory: multiRoot)
        let both = SidebarSplitCopy(items: [.split(split.id), .split(second.id)], spaceID: here.id, profileID: profile.id, state: multiStore.state)!
        var bothURLs = urls; bothURLs[m1.id] = "https://live.invalid/m1"; bothURLs[m2.id] = "https://live.invalid/m2"
        let pair = try multiStore.copySidebarSplits(both, to: todayLocation, before: nil, destinations: bothURLs)!
        try check(pair.roots.count == 2 && Array(SidebarHierarchy.children(in: todayLocation, state: multiStore.state).suffix(2)) == pair.roots,
                  "Several splits land together in their original order")
        try check(pair.openTabIDs.count == 4, "Every copied split's children request pages, not only the last")

        let reload = try BrowserStore(directory: root)
        try check([firstID, folderedID, todayID, awayID, trayID, outID, inTrayID, crossID, reloadedID, staleID].allSatisfy { id in reload.state.splitLayouts.contains { $0.id == id } }, "Every placed copy reloads durably")
        print("\(count) whole-split copy assertions passed")
    }
}

private extension Data {
    func write(to url: URL, options: Data.WritingOptions, createDirectory directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(to: url, options: options)
    }
}
