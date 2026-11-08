import Foundation

@main struct BrowserImportTests {
    @MainActor static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(condition(), message)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Session dates use second-resolution ISO 8601; fix the production
        // clock to that representation for exact reload comparisons.
        let importedAt = Date(timeIntervalSince1970: 1_793_000_000)
        let store = try BrowserStore(directory: directory, now: { importedAt })
        let original = store.activeSpace
        let target = BrowserImportDestination(spaceID: original.id, profileID: original.profileID)
        let one = BrowserImportBookmark(id: "one", title: "Same title", url: "https://example.test/one", children: [])
        let two = BrowserImportBookmark(id: "two", title: "Same title", url: "https://example.test/one", children: [])
        let nested = BrowserImportBookmark(id: "nested", title: "Nested", url: nil, children: [two])
        let folder = BrowserImportBookmark(id: "folder", title: "Work", url: nil, children: [one, nested])
        let loose = BrowserImportBookmark(id: "loose", title: "Loose", url: "https://example.test/loose", children: [])
        var selection = try BrowserImportSelection(roots: [folder, loose])
        expect(selection.selectedPageCount == 3, "Same-title and same-URL originals remain independently selectable")
        selection.toggle("folder")
        expect(selection.selected == ["loose"], "Toggling the original folder deselects every descendant")
        selection.toggle("two")
        expect(selection.includedRoots.first?.children.first?.children.first?.id == "two", "Selecting a descendant preserves only its original ancestor chain")
        selection.toggleExpanded("folder")
        expect(selection.expanded.contains("folder"), "Expansion is independent of selection")
        selection.toggleExpanded("loose")
        expect(!selection.expanded.contains("loose"), "A URL is never treated as a folder")
        selection.toggle("missing")
        expect(selection.selected == ["two", "loose"], "A stale identifier cannot select a replacement")
        expect(!selection.allSelected, "A partially selected subtree cannot claim Select All")
        selection.toggleAll()
        expect(selection.allSelected && selection.selectedPageCount == 3,
               "Select All restores collapsed descendants without merging equal titles or URLs")
        expect(selection.expanded == ["folder"], "Select All leaves folder expansion unchanged")
        selection.toggleAll()
        expect(selection.selected.isEmpty && selection.includedRoots.isEmpty,
               "Clearing Select All removes every selected folder and page")
        expect(selection.expanded == ["folder"], "Clearing selection does not collapse the tree")
        selection.toggle("two"); selection.toggle("loose")
        var emptySelection = try BrowserImportSelection(roots: [])
        emptySelection.toggleAll()
        expect(!emptySelection.allSelected && emptySelection.selected.isEmpty,
               "An empty source does not become a selected phantom root")
        let rankedPages = (0..<8).map { index in
            BrowserImportBookmark(id: "rank-\(index)", title: "Page \(index)",
                url: "https://example.test/page-\(index)", children: [])
        }
        let rankedFolder = BrowserImportBookmark(id: "ranked-folder", title: "Bookmarks", url: nil, children: rankedPages)
        let setupSelection = try BrowserImportSelection(roots: [rankedFolder], expandsTopFolders: true)
        expect(setupSelection.allSelected && setupSelection.selectedPageCount == 8,
               "Setup starts with every bookmark ticked")
        expect(setupSelection.expanded == ["ranked-folder"], "Setup opens the top-level folder so its pages show")
        do {
            _ = try BrowserImportSelection(roots: [one, one])
            preconditionFailure("Duplicate native identifiers must fail")
        } catch { checks += 1 }
        do {
            _ = try BrowserImportSelection(roots: [.init(id: "bad", title: "Bad", url: one.url, children: [two])])
            preconditionFailure("Mixed URL/container nodes must fail")
        } catch { checks += 1 }

        let otherSpace = store.createSpace(name: "Other")
        try store.save()
        try store.commitImportedBookmarks(selection.includedRoots, destination: target)
        expect(store.activeSpaceID == otherSpace, "Import does not change the active Space")
        expect(store.state.tabs.filter { $0.spaceID == original.id && $0.kind == .pinned }.count == 2,
               "Only selected original URL nodes are inserted into the captured Space")
        expect(!store.state.tabs.contains { $0.spaceID == otherSpace && $0.kind == .pinned }, "No front-Space fallback")
        let folders = store.state.folders.filter { $0.spaceID == original.id }
        expect(folders.count == 2, "Original ancestor hierarchy is retained")
        let outer = folders.first { $0.name == "Work" }!, inner = folders.first { $0.name == "Nested" }!
        expect(inner.parentID == outer.id, "Nested folder identity survives insertion")
        let pages = store.state.tabs.filter { $0.spaceID == original.id && $0.kind == .pinned }
        expect(pages.first { $0.title == "Same title" }?.folderID == inner.id, "Original bookmark is attached to its actual parent")
        let rootOrder = SidebarHierarchy.children(in: .init(spaceID: original.id, folderID: nil, section: .pinned), state: store.state)
        expect(rootOrder.first == .folder(outer.id), "Mixed original root order begins with folder")
        expect(rootOrder.last == .tab(pages.first { $0.title == "Loose" }!.id), "Mixed root order ends with loose page")
        let reloaded = try BrowserStore(directory: directory)
        expect(reloaded.state.folders == store.state.folders, "Genuine session reload preserves imported hierarchy")
        expect(reloaded.state.tabs == store.state.tabs, "Genuine session reload preserves imported pages")
        let internalBookmark = BrowserImportBookmark(id: "settings", title: "Settings", url: "chrome://settings", children: [])
        try store.commitImportedBookmarks([internalBookmark], destination: target)
        expect(store.state.tabs.last?.url == "parc://settings" && store.state.tabs.last?.savedURL == "parc://settings",
               "Imported browser pages use Parc's public namespace immediately")
        do {
            try store.commitImportedBookmarks([.init(id: "excluded", title: "Arc", url: "arc://settings", children: [])], destination: target)
            preconditionFailure("An Arc-only scheme must not become a Parc shortcut")
        } catch { checks += 1 }

        let before = store.state
        let session = directory.appendingPathComponent("session.json")
        let backup = directory.appendingPathComponent("prior-session.json")
        try FileManager.default.moveItem(at: session, to: backup)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
        do {
            try store.commitImportedBookmarks([one], destination: target)
            preconditionFailure("Real disk refusal must propagate")
        } catch { checks += 1 }
        expect(store.state.tabs == before.tabs && store.state.folders == before.folders,
               "Failed persistence leaves no half-inserted bookmarks")
        try FileManager.default.removeItem(at: session)
        try FileManager.default.moveItem(at: backup, to: session)
        try store.commitImportedBookmarks([one], destination: target)
        expect(store.state.tabs.count == before.tabs.count + 1, "Retry commits one new original after prior failure")

        let count = store.state.profiles.count
        let separate = try store.createImportDestination(name: "Imported Work", basedOn: target)
        expect(separate.profileID != target.profileID && separate.spaceID != target.spaceID, "Additional source profile has isolated identity")
        expect(store.state.profiles.count == count + 1 && separate.isCurrent(in: store.state), "Destination creation commits its Profile and Space together")
        expect(store.activeSpaceID == otherSpace, "Preparing native destination never switches the current Space")
        expect(store.state.spaces.first { $0.id == separate.spaceID }?.theme == original.theme,
               "New destination inherits the captured Space, not the current window's Space")
        let saved = try BrowserStore(directory: directory)
        expect(separate.isCurrent(in: saved.state), "Native destination is durable before context acquisition")
        let stale = BrowserImportDestination(spaceID: original.id, profileID: separate.profileID)
        do {
            try store.commitImportedBookmarks([loose], destination: stale)
            preconditionFailure("Wrong original Profile must refuse")
        } catch { checks += 1 }
        let originalTarget = BrowserImportProfileTarget(profileID: target.profileID, spaceID: target.spaceID)
        let unchanged = store.state
        let existing = try store.prepareImportDestination(originalTarget, basedOn: target)
        expect(existing == target, "Existing original Profile keeps the captured original Space")
        expect(store.state.spaces == unchanged.spaces && store.state.profiles == unchanged.profiles,
               "Existing destination does not create or rename records")
        expect(store.activeSpaceID == otherSpace, "Another active Space does not retarget destination")
        let choices = BrowserImportProfileTarget.choices(in: store.state, original: target)
        expect(choices.first { $0.profileID == target.profileID } == originalTarget,
               "Original Profile's target retains invocation Space despite other matching Spaces")
        let separateTarget = BrowserImportProfileTarget(profileID: separate.profileID, spaceID: separate.spaceID)
        expect(choices.contains(separateTarget), "Another actual Profile is reachable through its own captured Space")
        let resolvedSeparate = try store.prepareImportDestination(separateTarget, basedOn: target)
        expect(resolvedSeparate == separate, "Another existing Profile keeps that exact Profile and Space")

        let unusedID = store.createProfile(name: "Unused")
        let unused = BrowserImportProfileTarget(profileID: unusedID, spaceID: nil)
        expect(BrowserImportProfileTarget.choices(in: store.state, original: target).contains(unused),
               "A real unused Profile is a target without creating a Space early")
        let profileCount = store.state.profiles.count, spacesBefore = store.state.spaces.count
        let unusedDestination = try store.prepareImportDestination(unused, basedOn: target)
        expect(unusedDestination.profileID == unusedID, "An unused Profile keeps its native identity")
        expect(store.state.profiles.count == profileCount && store.state.spaces.count == spacesBefore + 1,
               "Unused destination adds only its needed bookmark Space")
        expect(store.activeSpaceID == otherSpace, "Unused destination preparation does not focus its Space")
        expect(!unused.isCurrent(in: store.state), "An issued no-Space target expires after its Space is created")
        do {
            _ = try store.prepareImportDestination(unused, basedOn: target)
            preconditionFailure("Stale unused target must not create duplicate Spaces")
        } catch { checks += 1 }
        let reloadedUnused = try BrowserStore(directory: directory)
        expect(unusedDestination.isCurrent(in: reloadedUnused.state),
               "Unused Profile destination persists before native admission")

        var retired = store.state
        retired.profileRemovals.append(.init(id: UUID(), profileID: separate.profileID, profileName: "Imported Work"))
        expect(!separateTarget.isCurrent(in: retired), "Profile retirement invalidates an issued target")
        expect(!BrowserImportProfileTarget.choices(in: retired, original: target).contains(separateTarget),
               "Retiring Profiles are not targets")
        var reassigned = store.state
        let movedIndex = reassigned.spaces.firstIndex { $0.id == separate.spaceID }!
        reassigned.spaces[movedIndex].profileID = target.profileID
        expect(!separateTarget.isCurrent(in: reassigned), "Reassigned Space never silently retargets native data")

        let failureProfile = store.createProfile(name: "Unused failure")
        try store.save()
        let beforeFailure = store.state
        try FileManager.default.moveItem(at: session, to: backup)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
        do {
            _ = try store.prepareImportDestination(.init(profileID: failureProfile, spaceID: nil), basedOn: target)
            preconditionFailure("Existing unused destination write refusal must propagate")
        } catch { checks += 1 }
        expect(store.state.spaces == beforeFailure.spaces && store.state.profiles == beforeFailure.profiles,
               "Failed unused-destination save preserves both original collections")
        do {
            _ = try store.createImportDestination(name: "Personal", basedOn: target)
            preconditionFailure("New destination write refusal must propagate")
        } catch { checks += 1 }
        expect(store.state.spaces == beforeFailure.spaces && store.state.profiles == beforeFailure.profiles,
               "Failed new-destination save leaves no half-created Profile or Space")
        try FileManager.default.removeItem(at: session)
        try FileManager.default.moveItem(at: backup, to: session)
        print("\(checks) actual browser-import selection/store assertions passed; no browser or personal source reads.")
    }
}
