import CoreGraphics
import Foundation

@main struct ArcSidebarImportTests {
    @MainActor static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(condition(), message)
        }
        func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }
        typealias Item = ArcSidebarImport.Item
        typealias Tab = ArcSidebarImport.Tab
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ArcSidebar")
        let data = try Data(contentsOf: fixtures.appendingPathComponent("StorableSidebar.json"))
        let arc = try ArcSidebarImport(data: data)

        let profileOne = ArcSidebarImport.ProfileKey.custom(directory: "Profile 1")
        let profileTwo = ArcSidebarImport.ProfileKey.custom(directory: "Profile 2")
        let profileThree = ArcSidebarImport.ProfileKey.custom(directory: "Profile 3")
        expect(ArcSidebarImport.profileKey(directory: "Default") == .standard, "Chromium's Default directory is Arc's standard Profile")
        expect(ArcSidebarImport.profileKey(directory: "Profile 1") == profileOne, "Other directories are custom Profiles")
        expect(arc.profiles == [.standard, profileOne, profileTwo], "Profiles: standard first, then Spaces, then Favorites")
        expect(arc.spaces.map(\.title) == ["Work", nil, "Side", "Plain", "Odd"],
               "Spaces keep Arc's order; one without a profile is skipped and a null title stays untitled")
        expect(arc.spaces.map(\.profile) == [.standard, .standard, profileOne, .standard, .standard],
               "Both standard encodings and a custom directory are recognised")
        expect(arc.skippedItemCount == 9, "Refused links, an easel, a missing child, a cycle, a broken entry, a Space without a profile and a Favorites folder are counted")

        let work = arc.spaces[0]
        expect(work.icon == .icon(.planet), "Arc icon names are Parc's icon raw values")
        let expected: [Item] = [
            .tab(Tab(title: "Alpha docs", url: "https://docs.example.test/a", customTitle: "Renamed alpha", isMuted: true)),
            .folder(title: "Projects", icon: .icon(.star), children: [
                .tab(Tab(title: "example.test", url: "https://example.test/b")),
                .folder(title: "Imported folder", icon: nil, children: [.tab(Tab(title: "Gamma", url: "https://example.test/c"))])
            ]),
            .split(title: "Compare", icon: .emoji("\u{1F9EA}"), tabs: [Tab(title: "Delta", url: "https://example.test/d"),
                   Tab(title: "Epsilon", url: "https://example.test/e")], orientation: .vertical, widthFactors: [0.3, 0.7]),
            .tab(Tab(title: "Settings", url: "parc://settings"))
        ]
        if case let .split(_, _, _, _, factors) = work.pinned[2] {
            expect(close(factors[0], 0.3) && close(factors[1], 0.7), "Split width factors follow their tab IDs")
        }
        func roundingFactors(_ items: [Item]) -> [Item] {
            items.map { item in
                switch item {
                case let .split(title, icon, tabs, orientation, factors):
                    return .split(title: title, icon: icon, tabs: tabs, orientation: orientation,
                                  widthFactors: factors.map { ($0 * 1e6).rounded() / 1e6 })
                case let .folder(title, icon, children): return .folder(title: title, icon: icon, children: roundingFactors(children))
                case .tab: return item
                }
            }
        }
        expect(roundingFactors(work.pinned) == expected,
               "Pinned tree: renamed and muted tab, nested folders, cycle cut, split, chrome:// as parc://; arc:// and javascript: refused, Today ignored")

        let single = require(work.theme, "Single-color theme parses")
        expect(single.colorCount == 1 && single.wheel == .complimentary && single.texture == .grain, "Single color keeps its texture")
        expect(close(single.noise, 0.8) && close(single.intensity, 1), "Noise and intensity come from Arc's modifiers")
        expect(single.appearance == .automatic, "Content appearance stays contrast-chosen editor derives it")
        let primary = require(single.primaryColor, "Primary color exists")
        expect(primary.colorSpace == .displayP3, "An out-of-sRGB color is carried in Display P3")
        let source = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!, components: [1.0699, -0.143, 0.2, 1])!
        let system = source.converted(to: CGColorSpace(name: CGColorSpace.displayP3)!, intent: .defaultIntent, options: nil)!.components!
        expect(close(primary.red, Double(system[0]), 1e-3) && close(primary.green, Double(system[1]), 1e-3)
               && close(primary.blue, Double(system[2]), 1e-3), "Extended sRGB to Display P3 matches ColorSync")

        let ideas = arc.spaces[1]
        expect(ideas.icon == .emoji("\u{1F680}"), "emoji_v2 is a one-character emoji")
        expect(ideas.theme?.colorCount == 3 && ideas.theme?.wheel == .analogous && ideas.theme?.texture == .sand,
               "Two base colors plus an overlay color is Arc's three-color analogous theme")
        expect(ideas.theme?.primaryColor == ThemeColor(red: 0.2, green: 0.4, blue: 0.8), "An in-range color stays sRGB unchanged")
        expect(ideas.pinned == [.tab(Tab(title: "Golf", url: "https://example.test/g"))], "Reversed container labels still find pinned")
        let side = arc.spaces[2]
        expect(side.icon == .emoji("\u{1F600}"), "Legacy emoji is a Unicode scalar")
        expect(side.theme?.colorCount == 2 && side.theme?.wheel == .complimentary && side.theme?.texture == .tweed
               && side.theme.map { close($0.noise, 0.25) && close($0.intensity, 0.5) } == true, "Two-color complimentary theme")
        expect(side.pinned.count == 1, "newContainerIDs alone locate the pinned container")
        expect(arc.spaces[3].icon == nil && arc.spaces[3].theme == SpaceTheme() && arc.spaces[3].pinned.isEmpty,
               "Unknown icon is dropped; no windowTheme is Arc's unthemed Space; a missing container is empty")
        expect(arc.spaces[4].theme == nil, "An unknown style falls back to Parc's default theme")

        let standardFavorites = require(arc.favorites[.standard], "Standard Favorites")
        expect(standardFavorites.count == 14, "Favorites hold tabs and splits; a folder is skipped")
        expect(standardFavorites[1] == .split(title: nil, icon: nil, tabs: [Tab(title: "Left", url: "https://left.example.test/"),
               Tab(title: "Right", url: "https://right.example.test/")], orientation: .horizontal, widthFactors: [0.5, 0.5]),
               "A Favorites split keeps its pages")
        expect(arc.favorites[profileTwo] == [.tab(Tab(title: "Calendar", url: "https://calendar.example.test/"))],
               "A custom profile's Favorites are read")

        for bad in ["not json", "[]", #"{"sidebar":{"containers":[{"global":{}}]}}"#] {
            do {
                _ = try ArcSidebarImport(data: Data(bad.utf8))
                preconditionFailure("A file without Arc's sidebar shape must fail")
            } catch { checks += 1 }
        }
        func document(items: [Any], pinned: [String]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [["global": [:]], [
                "items": [["P", ["id": "P", "childrenIds": pinned, "data": ["itemContainer": [:]]]]].flatMap { $0 } + items,
                "spaces": ["S", ["id": "S", "title": "Deep", "profile": ["default": true], "containerIDs": ["pinned", "P"]]],
                "topAppsContainerIDs": []]]]])
        }
        var deep: [Any] = []
        for level in 0..<200 {
            let child = level < 199 ? ["F\(level + 1)"] : []
            deep += ["F\(level)", ["id": "F\(level)", "title": "L\(level)", "childrenIds": child, "data": ["list": [:]]]]
        }
        let deepArc = try ArcSidebarImport(data: document(items: deep, pinned: ["F0"]))
        var depth = 0, level = deepArc.spaces[0].pinned
        while case let .folder(_, _, children)? = level.first { depth += 1; level = children }
        expect(depth == ArcSidebarImport.maximumDepth && deepArc.skippedItemCount == 1, "Nesting is bounded at 128")
        var many: [Any] = [], ids: [String] = []
        for index in 0...ArcSidebarImport.maximumItems {
            ids.append("T\(index)")
            many += ["T\(index)", ["id": "T\(index)", "data": ["tab": ["savedURL": "https://example.test/\(index)", "savedTitle": "T"]]]]
        }
        let manyArc = try ArcSidebarImport(data: document(items: many, pinned: ids))
        expect(manyArc.spaces[0].pinned.count == ArcSidebarImport.maximumItems - 1 && manyArc.skippedItemCount == 4,
               "Item count is bounded at 50,000, including the container; the two refused entries and their references are counted")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let importedAt = Date(timeIntervalSince1970: 1_793_000_000)
        let store = try BrowserStore(directory: directory, now: { importedAt })
        let standardID = store.state.profiles[0].id
        let existingID = store.createProfile(name: "WORK PROFILE")
        try store.save()
        let activeBefore = store.activeSpaceID, spacesBefore = store.state.spaces.count, profilesBefore = store.state.profiles.count
        let profiles: [(key: ArcSidebarImport.ProfileKey, name: String)] = [(.standard, "Personal"),
            (profileOne, "Work Profile"), (profileTwo, "Side Projects"), (profileThree, "  Empty  ")]

        let before = store.state
        let session = directory.appendingPathComponent("session.json")
        let backup = directory.appendingPathComponent("prior-session.json")
        try FileManager.default.moveItem(at: session, to: backup)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
        do {
            _ = try store.importArcSidebar(arc, profiles: profiles, standardProfileID: standardID)
            preconditionFailure("A refused session write must propagate")
        } catch { checks += 1 }
        expect(store.state == before, "A failed write leaves no Space, Profile, tab or folder behind")
        try FileManager.default.removeItem(at: session)
        try FileManager.default.moveItem(at: backup, to: session)

        let result = try store.importArcSidebar(arc, profiles: profiles, standardProfileID: standardID)
        let state = store.state
        expect(store.activeSpaceID == activeBefore, "Import does not change the active Space")
        expect(state.profiles.count == profilesBefore + 2, "Two new Profiles: one for Favorites only, one with nothing")
        expect(state.profiles.first { $0.id == standardID }?.name == "Default", "The standard Profile is not renamed")
        let sideProjects = require(state.profiles.first { $0.name == "Side Projects" }, "New Profile for Profile 2")
        let empty = require(state.profiles.first { $0.name == "Empty" }, "New Profile, trimmed name")
        let created = Array(state.spaces.dropFirst(spacesBefore))
        expect(created.map(\.title) == ["Work", nil, "Side", "Plain", "Odd", "Side Projects", "Empty"],
               "Every Arc Space is a new Space in Arc's order; Profiles without Spaces get one named after them")
        expect(created.map(\.profileID) == [standardID, standardID, existingID, standardID, standardID, sideProjects.id, empty.id],
               "A custom Profile reuses the same-named Parc Profile, case-insensitively")
        expect(created[1].name == "Space \(spacesBefore + 2)", "An untitled Space takes its positional name")
        expect(created.allSatisfy { $0.symbol == "circle.fill" }, "Imported Spaces use a new Space's symbol")
        expect(created[0].customIcon == .icon(.planet) && created[0].theme == arc.spaces[0].theme, "Icon and theme are applied")
        expect(created[4].theme == BrowserSpace(id: UUID(), name: "", symbol: "", color: "B9B5D4", profileID: standardID).theme,
               "An unreadable theme becomes a new Space's default")
        expect(result[.standard] == .init(spaceID: created[0].id, profileID: standardID)
               && result[profileOne] == .init(spaceID: created[2].id, profileID: existingID)
               && result[profileTwo] == .init(spaceID: created[5].id, profileID: sideProjects.id)
               && result[profileThree] == .init(spaceID: created[6].id, profileID: empty.id),
               "Each Arc Profile's destination is the first Space created for it")
        expect(result.values.allSatisfy { $0.isCurrent(in: state) }, "Destinations are current")

        let workID = created[0].id
        let root = SidebarHierarchy.children(in: .init(spaceID: workID, folderID: nil, section: .pinned), state: state)
        let workTabs = state.tabs.filter { $0.spaceID == workID && $0.kind == .pinned }
        func tab(_ url: String) -> BrowserTab? { workTabs.first { $0.savedURL == url } }
        let projects = require(state.folders.first { $0.spaceID == workID && $0.parentID == nil }, "Root folder")
        let groups = SidebarSplitItems.groups(in: state, spaceID: workID)
            .filter { !SidebarSplitItems.isFavorite($0, in: state, profileID: standardID) }
        expect(groups.count == 1 && groups[0].orientation == .vertical && groups[0].customTitle == "Compare"
               && groups[0].customIcon == .emoji("\u{1F9EA}"), "The pinned split survives the store's split reconciliation")
        expect(root == [.tab(tab("https://docs.example.test/a")!.id), .folder(projects.id), .split(groups[0].id),
                        .tab(tab("parc://settings")!.id)], "Root order is Arc's order")
        let alpha = tab("https://docs.example.test/a")!
        expect(alpha.title == "Alpha docs" && alpha.customTitle == "Renamed alpha" && alpha.isMuted
               && alpha.profileID == standardID && alpha.createdAt == importedAt, "A tab keeps its title, rename and mute")
        expect(projects.name == "Projects" && projects.customIcon == .icon(.star), "Folder name and icon")
        let inner = require(state.folders.first { $0.parentID == projects.id }, "Nested folder")
        expect(inner.name == "Imported folder" && tab("https://example.test/c")?.folderID == inner.id, "Nesting is kept")
        expect(SidebarHierarchy.children(in: .init(spaceID: workID, folderID: projects.id, section: .pinned), state: state)
               == [.tab(tab("https://example.test/b")!.id), .folder(inner.id)], "Folder order is Arc's order")
        let today = SidebarHierarchy.children(in: .init(spaceID: workID, folderID: nil, section: .today), state: state)
        let newer = require(state.tabs.first { $0.savedURL == "https://example.test/newer-today" }, "Newer Today tab")
        let older = require(state.tabs.first { $0.savedURL == "https://example.test/today" }, "Today tab")
        expect(today == [.tab(newer.id), .tab(older.id)] && newer.kind == .today && older.kind == .today
               && older.spaceID == workID && older.folderID == nil, "Today tabs come into their Space's Today in Arc's order")
        expect(older.lastAccessed == importedAt, "A Today tab's archive clock starts at the import")
        expect(state.arcImportedSpaces["734FF6CE-5A92-54B8-8106-4F9A92236F11"] == workID, "Each imported Space remembers its Arc Space")

        let favoritesLocation = SidebarContainerLocation(spaceID: workID, folderID: nil, section: .favorite, profileID: standardID)
        let favorites = SidebarHierarchy.children(in: favoritesLocation, state: state)
        let favoriteTabs = state.tabs.filter { $0.kind == .favorite && $0.profileID == standardID }
        expect(favorites.count == 12, "Favorites stop at Parc's limit of 12")
        expect(favorites.first == .tab(favoriteTabs.first { $0.savedURL == "https://mail.example.test/" }!.id),
               "Favorites keep Arc's order")
        if case .split(let id) = favorites[1] {
            expect(state.splitLayouts.first { $0.id == id }?.tabIDs.count == 2, "A Favorites split survives")
        } else { expect(false, "The second Favorite is a split") }
        expect(!favoriteTabs.contains { $0.savedURL == "https://www.mail.example.test" }, "A duplicate Favorite is not added twice")
        expect(!favoriteTabs.contains { $0.savedURL == "https://f12.example.test/" }, "The Favorite over the limit is left out")
        expect(state.tabs.filter { $0.kind == .favorite && $0.profileID == sideProjects.id }.map(\.savedURL)
               == ["https://calendar.example.test/"], "A Favorites-only Profile gets its Favorites")

        let reloaded = try BrowserStore(directory: directory)
        expect(reloaded.state.spaces == state.spaces && reloaded.state.profiles == state.profiles
               && reloaded.state.tabs == state.tabs && reloaded.state.folders == state.folders
               && reloaded.state.splitLayouts == state.splitLayouts && reloaded.state.sidebarItemOrder == state.sidebarItemOrder
               && reloaded.state.arcImportedSpaces == state.arcImportedSpaces,
               "The import is durable")

        let again = try store.importArcSidebar(arc, profiles: [(.standard, "Personal")], standardProfileID: standardID)
        let standardSpaces = arc.spaces.filter { $0.profile == .standard }
        expect(standardSpaces.count == 4 && store.state.spaces.count == state.spaces.count && store.state.tabs.count == state.tabs.count,
               "Importing the same Arc Spaces again adds no copies, including Spaces with nothing pinned; a full Favorites row takes nothing new")
        expect(again[.standard] == result[.standard], "A repeated Space stays the destination")
        let spacesBeforeReuse = store.state.spaces.count
        let secondReuse = try store.importArcSidebar(arc, profiles: [(profileOne, "work profile"), (profileTwo, "Side Projects")],
                                                     standardProfileID: standardID)
        expect(secondReuse[profileOne]?.profileID == existingID, "The same Parc Profile is reused on a later import")
        expect(store.state.spaces.count == spacesBeforeReuse && secondReuse[profileTwo]?.spaceID
               == state.spaces.first { $0.title == "Side Projects" }?.id,
               "A Profile without Arc Spaces imports into its existing Space instead of a new empty one")

        let links = try ArcSidebarImport(data: document(items: [
            "N", ["id": "N", "data": ["tab": ["savedURL": "parc://note/0B3E", "savedTitle": "Note"]]],
            "C", ["id": "C", "data": ["tab": ["savedURL": "chrome://settings/", "savedTitle": "Settings"]]],
            "X", ["id": "X", "childrenIds": ["Y"], "data": ["splitView": [:]]],
            "Y", ["id": "Y", "childrenIds": ["Y1", "Y2"], "data": ["list": [:]]],
            "Y1", ["id": "Y1", "data": ["tab": ["savedURL": "https://example.test/y1"]]],
            "Y2", ["id": "Y2", "data": ["tab": ["savedURL": "https://example.test/y2"]]],
        ], pinned: ["N", "C", "X"]))
        expect(links.spaces[0].pinned.map { if case .tab(let tab) = $0 { return tab.url } else { return "" } } == ["parc://settings/"],
               "Only Arc's chrome:// pages become parc:// pages; a stored parc:// link is refused")
        expect(links.skippedItemCount == 4, "A dropped folder in a split counts everything under it")

        let favoritesStore = try BrowserStore(directory: directory.appendingPathComponent("Favorites"))
        let favoritesArc = try ArcSidebarImport(data: JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [[
            "items": ["F", ["id": "F", "childrenIds": ["A", "S"], "data": ["itemContainer": [:]]],
                      "A", ["id": "A", "data": ["tab": ["savedURL": "https://a.example.test/"]]],
                      "S", ["id": "S", "childrenIds": ["A2", "B"], "data": ["splitView": [:]]],
                      "A2", ["id": "A2", "data": ["tab": ["savedURL": "https://a.example.test/"]]],
                      "B", ["id": "B", "data": ["tab": ["savedURL": "https://b.example.test/"]]]],
            "spaces": [], "topAppsContainerIDs": [["default": true], "F"]]]]]))
        let favoritesProfile = favoritesStore.state.profiles[0].id
        _ = try favoritesStore.importArcSidebar(favoritesArc, profiles: [(.standard, "Personal")], standardProfileID: favoritesProfile)
        let favoriteURLs = favoritesStore.state.tabs.filter { $0.kind == .favorite }.map(\.savedURL)
        expect(favoriteURLs == ["https://a.example.test/", "https://b.example.test/"] && favoritesStore.state.splitLayouts.isEmpty,
               "A split page already in Favorites isn't added twice; the rest stays a plain Favorite")
        do {
            _ = try store.importArcSidebar(arc, profiles: profiles, standardProfileID: UUID())
            preconditionFailure("An unknown standard Profile must refuse")
        } catch { checks += 1 }
        let preferences: [String: Any] = [
            "autoArchiveTimeThreshold": "\"sevenDays\"",
            "autoArchiveTimeThresholdsPerProfile": #"{"thresholds":[{"default":{}},"oneHour",{"custom":{"_0":{"directoryBasename":"Profile 1","machineID":"M"}}},{"never":{}}]}"#]
        let hours = ArcSidebarImport.autoArchiveHours(preferences: preferences, profiles: [.standard, profileOne, profileTwo])
        expect(hours == [.standard: 1, profileOne: 0, profileTwo: 168], "Arc's per-Profile archive age wins over its Arc-wide one")
        expect(ArcSidebarImport.autoArchiveHours(preferences: ["autoArchiveTimeThresholdsPerProfile": #"{"thresholds":[]}"#],
                                                 profiles: [.standard]).isEmpty, "Without Arc's setting each Profile keeps Parc's")
        let archiveStore = try BrowserStore(directory: directory.appendingPathComponent("Archive"))
        var timed = arc
        timed.autoArchiveHours = [.standard: 168]
        _ = try archiveStore.importArcSidebar(timed, profiles: [(.standard, "Personal")], standardProfileID: archiveStore.state.profiles[0].id)
        expect(archiveStore.state.profiles[0].autoArchiveHours == 168 && archiveStore.state.autoArchiveDefaultHours == 168
               && !archiveStore.state.autoArchiveEducationEligible,
               "Arc's archive age applies to the mapped Profile and, as a Settings change, to the default and education")
        let legacyStore = try BrowserStore(directory: directory.appendingPathComponent("Legacy"))
        let legacyProfile = legacyStore.state.profiles[0].id
        _ = try legacyStore.importArcSidebar(arc, profiles: [(.standard, "Personal")], standardProfileID: legacyProfile)
        var legacy = legacyStore.state
        legacy.arcImportedSpaces = [:]
        let legacyArc = try ArcSidebarImport(data: data)
        let legacyResult = try legacyArc.inserting(into: legacy, profiles: [(.standard, "Personal")], standardProfileID: legacyProfile, at: importedAt)
        let pinnedSpaces = arc.spaces.filter { $0.profile == .standard && !$0.pinned.isEmpty }.count
        expect(legacyResult.state.spaces.count == legacy.spaces.count + 4 - pinnedSpaces
               && legacyResult.state.arcImportedSpaces.count == 4,
               "An import from before the record matches its Spaces by name and pinned pages and records them")

        let chosenStore = try BrowserStore(directory: directory.appendingPathComponent("Chosen"))
        let original = BrowserImportDestination(spaceID: chosenStore.activeSpace.id, profileID: chosenStore.activeSpace.profileID)
        let chosenID = chosenStore.createProfile(name: "Elsewhere")
        try chosenStore.save()
        let profilesBeforeChoice = chosenStore.state.profiles.count
        let intoExisting = try chosenStore.importArcSidebar(arc, profiles: [(profileOne, "Work Profile")],
            standardProfileID: original.profileID, primary: profileOne, into: chosenID)
        let workSpaces = arc.spaces.filter { $0.profile == profileOne }.count
        expect(intoExisting[profileOne]?.profileID == chosenID && chosenStore.state.profiles.count == profilesBeforeChoice
               && chosenStore.state.spaces.filter { $0.profileID == chosenID }.count == workSpaces,
               "The target Profile takes the Arc Profile's Spaces; no Profile is created by name")
        let refusedBefore = chosenStore.state
        do {
            _ = try chosenStore.importArcSidebar(arc, profiles: [(.standard, "Personal")], standardProfileID: original.profileID,
                                                 primary: .standard, into: UUID())
            preconditionFailure("A target Profile that doesn't exist must refuse")
        } catch { checks += 1 }
        expect(chosenStore.state == refusedBefore, "A refused target writes nothing")
        var retiringState = chosenStore.state
        retiringState.profileRemovals.append(.init(id: UUID(), profileID: chosenID, profileName: "Elsewhere"))
        do {
            _ = try arc.inserting(into: retiringState, profiles: [(.standard, "Personal")], standardProfileID: original.profileID,
                                  target: (.standard, chosenID), at: importedAt)
            preconditionFailure("A target Profile being removed must refuse")
        } catch { checks += 1 }

        let customStore = try BrowserStore(directory: directory.appendingPathComponent("CustomPrimary"))
        let opened = BrowserImportDestination(spaceID: customStore.activeSpace.id, profileID: customStore.activeSpace.profileID)
        let namesake = customStore.createProfile(name: "Work Profile")
        try customStore.save()
        let customBefore = customStore.state
        let custom = try customStore.importArcSidebar(arc, profiles: [(profileOne, "Work Profile"), (profileTwo, "Side Projects")],
            standardProfileID: opened.profileID, primary: profileOne, into: opened.profileID)
        let customState = customStore.state
        let projectsProfile = require(customState.profiles.first { $0.name == "Side Projects" }, "A Parc Profile for the other Arc Profile")
        let customSpaces = Array(customState.spaces.dropFirst(customBefore.spaces.count))
        expect(customSpaces.map(\.title) == ["Side", "Side Projects"]
               && customSpaces.map(\.profileID) == [opened.profileID, projectsProfile.id],
               "The primary's Spaces join the opened Profile; the other gets one Space of its name; standard's stay behind")
        expect(custom[profileOne]?.profileID == opened.profileID && custom[profileTwo]?.profileID == projectsProfile.id
               && custom[.standard] == nil, "Each chosen Arc Profile's destination is its mapped Parc Profile")
        expect(customState.profiles.count == customBefore.profiles.count + 1
               && !customState.spaces.contains { $0.profileID == namesake }
               && customState.profiles.first { $0.id == opened.profileID }?.name
                   == customBefore.profiles.first { $0.id == opened.profileID }?.name,
               "A Parc Profile named like the primary is left alone, and the opened Profile keeps its name")
        expect(customState.tabs.filter { $0.kind == .favorite && $0.profileID == projectsProfile.id }.map(\.savedURL)
               == ["https://calendar.example.test/"]
               && !customState.tabs.contains { $0.kind == .favorite && $0.profileID == opened.profileID },
               "Favorites follow their own Arc Profile; the unchosen standard Profile's don't come")

        print("\(checks) Arc sidebar import parsing/store assertions passed; synthetic fixtures only.")
    }

    static func require<T>(_ value: T?, _ message: String) -> T {
        guard let value else { preconditionFailure(message) }
        return value
    }
}
