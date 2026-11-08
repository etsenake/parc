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
        let counts = Dictionary(uniqueKeysWithValues: (0..<8).map { (rankedPages[$0].url!, $0 * 10) })
        var recommended = try BrowserImportSelection(roots: [rankedFolder], historyVisitCounts: counts)
        expect(recommended.selected == Set((3..<8).map { "rank-\($0)" }),
               "Setup recommends the five most visited source bookmarks, not the first five tree rows")
        expect(!recommended.allSelected && recommended.selectedPageCount == 5,
               "The recommendation is a five-page selection, not implicit folder selection")
        expect(recommended.expanded == ["ranked-folder"], "The initial top-level folder exposes its choices")
        expect(recommended.includedRoots.first?.children.count == 5,
               "Recommended leaves keep their actual source parent")
        recommended.toggle("rank-0")
        expect(recommended.selectedPageCount == 6, "Five is a recommendation, never a limit on explicit choices")
        recommended.toggleAll()
        expect(recommended.allSelected && recommended.selectedPageCount == 8,
               "Select All overrides the recommendation normally")
        let unavailableHistory = try BrowserImportSelection(roots: [rankedFolder], historyVisitCounts: [:])
        expect(unavailableHistory.selected.isEmpty, "Unavailable history cannot fabricate a top-five recommendation")
        let unvisited = try BrowserImportSelection(roots: [rankedFolder], historyVisitCounts: ["https://other.test": 999])
        expect(unvisited.selected.isEmpty, "History from unrelated URLs cannot select arbitrary source bookmarks")
        let duplicates = try BrowserImportSelection(roots: [folder, loose], historyVisitCounts: [one.url!: 30, loose.url!: 2])
        expect(duplicates.selected == ["one", "loose"], "Automatic choice picks one original per matching URL; duplicates remain manually available")
        let tied = try BrowserImportSelection(roots: rankedPages, historyVisitCounts: counts.mapValues { _ in 1 })
        expect(tied.selected == Set((0..<5).map { "rank-\($0)" }), "Ties use deterministic original tree order")
        let normalized = try BrowserImportSelection(roots: [one], historyVisitCounts: ["http://www.EXAMPLE.test/ONE/?utm_source=test#section": 8])
        expect(normalized.selected == ["one"], "Recommendation identity handles the reference's case, www, scheme, fragment and campaign normalization")
        expect(normalized.includedRoots.first?.children.isEmpty == true && normalized.includedRoots.first?.url == one.url,
               "Recommendation matching never rewrites the URL that will actually be imported")
        expect(BrowserImportSelection.recommendationURL("https://example.test/a?keep=one&empty=&utm_medium=x") == URL(string: "https://example.test/a?keep=one"),
               "Real query values are retained; empty and campaign arguments are excluded only from matching")
        expect(BrowserImportSelection.recommendationURL("https://example.test/#!/route/") != BrowserImportSelection.recommendationURL("https://example.test/#!/other/"),
               "Distinct hashbang application routes do not collapse to the same recommendation")
        expect(BrowserImportSelection.recommendationURL("www.example.test/path/") == URL(string: "https://example.test/path"),
               "A source identity without a scheme receives the reference's secure URL prefix")
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
        var choice = BrowserImportDestinationChoice()
        let originalTarget = BrowserImportProfileTarget(profileID: target.profileID, spaceID: target.spaceID)
        expect(choice.option == nil && !choice.canSubmit(in: store.state), "Destination starts unselected, not inferred from the front Profile")
        expect(!choice.replaceExistingCookies, "Initial existing-cookie replacement is off")
        let unchanged = store.state
        choice.select(.new)
        expect(choice.replaceExistingCookies && !choice.canSubmit(in: store.state), "New destination requires a name and takes the imported cookies")
        choice.newProfileName = "   "; expect(!choice.canSubmit(in: store.state), "Whitespace is not a new Profile name")
        choice.newProfileName = "  Personal 名  "
        expect(choice.canSubmit(in: store.state) && choice.profileName == "Personal 名", "Actual entered Unicode name is retained and trimmed")
        expect(store.state.profiles == unchanged.profiles && store.state.spaces == unchanged.spaces,
               "Editing destination choice never persists a Profile or Space")
        choice.select(.existing(originalTarget))
        expect(!choice.replaceExistingCookies, "Changing New to an existing Profile keeps that Profile's cookies")
        choice.appeared()
        expect(!choice.replaceExistingCookies, "Returning to destination keeps an existing Profile's cookies")
        choice.select(.new); choice.appeared()
        expect(choice.replaceExistingCookies && choice.newProfileName == "  Personal 名  ", "Returning preserves new name and forces replacement")
        choice.select(.existing(originalTarget))
        let existing = try store.prepareImportDestination(choice, basedOn: target)
        expect(existing == target, "Existing original Profile keeps the captured original Space")
        expect(store.state.spaces == unchanged.spaces && store.state.profiles == unchanged.profiles,
               "Existing destination does not create or rename records")
        expect(store.activeSpaceID == otherSpace, "Another active Space does not retarget destination")
        let choices = BrowserImportProfileTarget.choices(in: store.state, original: target)
        expect(choices.first { $0.profileID == target.profileID } == originalTarget,
               "Original Profile's choice retains invocation Space despite other matching Spaces")
        expect(choices.contains(.init(profileID: separate.profileID, spaceID: separate.spaceID)),
               "Another actual Profile is selectable through its own captured Space")
        choice.select(.existing(.init(profileID: separate.profileID, spaceID: separate.spaceID)))
        let resolvedSeparate = try store.prepareImportDestination(choice, basedOn: target)
        expect(resolvedSeparate == separate,
               "Choosing another existing Profile preserves that exact Profile and Space")

        let unusedID = store.createProfile(name: "Unused")
        let unused = BrowserImportProfileTarget(profileID: unusedID, spaceID: nil)
        expect(BrowserImportProfileTarget.choices(in: store.state, original: target).contains(unused),
               "A real unused Profile is offered without creating a Space early")
        choice.select(.existing(unused))
        let profileCount = store.state.profiles.count, spacesBefore = store.state.spaces.count
        let unusedDestination = try store.prepareImportDestination(choice, basedOn: target)
        expect(unusedDestination.profileID == unusedID, "An unused Profile keeps its native identity")
        expect(store.state.profiles.count == profileCount && store.state.spaces.count == spacesBefore + 1,
               "Unused destination adds only its needed bookmark Space")
        expect(store.activeSpaceID == otherSpace, "Unused destination preparation does not focus its Space")
        expect(!choice.canSubmit(in: store.state), "Issued no-Space choice expires after its Space is created")
        do {
            _ = try store.prepareImportDestination(choice, basedOn: target)
            preconditionFailure("Stale unused target must not create duplicate Spaces")
        } catch { checks += 1 }
        let reloadedUnused = try BrowserStore(directory: directory)
        expect(unusedDestination.isCurrent(in: reloadedUnused.state),
               "Unused Profile destination persists before native admission")
        choice.select(.new)
        let made = try store.prepareImportDestination(choice, basedOn: target)
        expect(made.profileID != unusedID && made.profileID != target.profileID, "New destination has its own Profile identity")
        expect(store.state.profiles.first { $0.id == made.profileID }?.name == "Personal 名", "Only actual entered name is saved")
        let reloadedMade = try BrowserStore(directory: directory)
        expect(made.isCurrent(in: reloadedMade.state), "New Profile and Space are durable together")
        expect(store.activeSpaceID == otherSpace, "New destination preserves active browsing selection")

        var retired = store.state
        retired.profileRemovals.append(.init(id: UUID(), profileID: separate.profileID, profileName: "Imported Work"))
        let separateTarget = BrowserImportProfileTarget(profileID: separate.profileID, spaceID: separate.spaceID)
        choice.select(.existing(separateTarget))
        expect(!choice.canSubmit(in: retired), "Profile retirement invalidates an issued choice")
        expect(!BrowserImportProfileTarget.choices(in: retired, original: target).contains(separateTarget),
               "Retiring Profiles are not offered")
        var reassigned = store.state
        let movedIndex = reassigned.spaces.firstIndex { $0.id == separate.spaceID }!
        reassigned.spaces[movedIndex].profileID = target.profileID
        expect(!choice.canSubmit(in: reassigned), "Reassigned Space never silently retargets native data")
        choice.invalidate(); expect(!choice.canSubmit(in: store.state), "Invalidation requires a new explicit destination")
        do {
            _ = try store.prepareImportDestination(choice, basedOn: target)
            preconditionFailure("Missing selection must refuse")
        } catch { checks += 1 }

        let failureProfile = store.createProfile(name: "Unused failure")
        try store.save()
        let beforeFailure = store.state
        try FileManager.default.moveItem(at: session, to: backup)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
        choice.select(.existing(.init(profileID: failureProfile, spaceID: nil)))
        do {
            _ = try store.prepareImportDestination(choice, basedOn: target)
            preconditionFailure("Existing unused destination write refusal must propagate")
        } catch { checks += 1 }
        expect(store.state.spaces == beforeFailure.spaces && store.state.profiles == beforeFailure.profiles,
               "Failed unused-destination save preserves both original collections")
        choice.select(.new)
        do {
            _ = try store.prepareImportDestination(choice, basedOn: target)
            preconditionFailure("New destination write refusal must propagate")
        } catch { checks += 1 }
        expect(store.state.spaces == beforeFailure.spaces && store.state.profiles == beforeFailure.profiles,
               "Failed new-destination save leaves no half-created Profile or Space")
        try FileManager.default.removeItem(at: session)
        try FileManager.default.moveItem(at: backup, to: session)
        print("\(checks) actual browser-import selection/store assertions passed; no browser or personal source reads.")
    }
}
