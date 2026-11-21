import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

@MainActor
struct ArcSidebarImportTests {
    typealias Item = ArcSidebarImport.Item
    typealias Tab = ArcSidebarImport.Tab
    typealias Destinations = [ArcSidebarImport.ProfileKey: BrowserImportDestination]

    let profileOne = ArcSidebarImport.ProfileKey.custom(directory: "Profile 1")
    let profileTwo = ArcSidebarImport.ProfileKey.custom(directory: "Profile 2")
    let profileThree = ArcSidebarImport.ProfileKey.custom(directory: "Profile 3")
    let importedAt = Date(timeIntervalSince1970: 1_793_000_000)

    func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    func fixtureData() throws -> Data {
        try Data(contentsOf: DataFixtures.fixture("ArcSidebar/StorableSidebar.json"))
    }

    func loadArc() throws -> ArcSidebarImport {
        try ArcSidebarImport(data: fixtureData())
    }

    func document(items: [Any], pinned: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [["global": [:]], [
            "items": [["P", ["id": "P", "childrenIds": pinned, "data": ["itemContainer": [:]]]]].flatMap { $0 } + items,
            "spaces": ["S", ["id": "S", "title": "Deep", "profile": ["default": true], "containerIDs": ["pinned", "P"]]],
            "topAppsContainerIDs": []]]]])
    }

    func roundingFactors(_ items: [Item]) -> [Item] {
        items.map { item in
            switch item {
            case let .split(title, icon, tabs, orientation, factors):
                return .split(title: title, icon: icon, tabs: tabs, orientation: orientation,
                              widthFactors: factors.map { ($0 * 1e6).rounded() / 1e6 })
            case let .folder(title, icon, children): return .folder(title: title, icon: icon, children: roundingFactors(children))
            case .tab, .stackedSplit: return item
            }
        }
    }

    var allProfiles: [(key: ArcSidebarImport.ProfileKey, name: String)] {
        [(.standard, "Personal"), (profileOne, "Work Profile"), (profileTwo, "Side Projects"), (profileThree, "  Empty  ")]
    }

    struct Imported {
        let store: BrowserStore
        let arc: ArcSidebarImport
        let standardID: UUID
        let existingID: UUID
        let activeBefore: UUID
        let spacesBefore: Int
        let profilesBefore: Int
        let result: Destinations
        let state: BrowserState
        let created: [BrowserSpace]
    }

    func withImport(_ body: (Imported, URL) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try loadArc()
            let importedAt = importedAt
            let store = try BrowserStore(directory: directory, now: { importedAt })
            let standardID = store.state.profiles[0].id
            let existingID = store.createProfile(name: "WORK PROFILE")
            try store.save()
            let activeBefore = store.activeSpaceID
            let spacesBefore = store.state.spaces.count
            let profilesBefore = store.state.profiles.count
            let result = try store.importArcSidebar(arc, profiles: allProfiles, standardProfileID: standardID)
            let state = store.state
            let imported = Imported(store: store, arc: arc, standardID: standardID, existingID: existingID,
                                    activeBefore: activeBefore, spacesBefore: spacesBefore,
                                    profilesBefore: profilesBefore, result: result, state: state,
                                    created: Array(state.spaces.dropFirst(spacesBefore)))
            try body(imported, directory)
        }
    }

    @Test func chromiumDefaultDirectoryIsArcsStandardProfile() {
        #expect(ArcSidebarImport.profileKey(directory: "Default") == .standard)
        #expect(ArcSidebarImport.profileKey(directory: "Profile 1") == profileOne)
    }

    @Test func profilesListStandardFirstThenSpacesThenFavorites() throws {
        let arc = try loadArc()
        #expect(arc.profiles == [.standard, profileOne, profileTwo])
    }

    @Test func spacesKeepArcsOrderAndSkipOnesWithoutAProfile() throws {
        let arc = try loadArc()
        #expect(arc.spaces.map(\.title) == ["Work", nil, "Side", "Plain", "Odd"])
        #expect(arc.spaces.map(\.profile) == [.standard, .standard, profileOne, .standard, .standard])
    }

    @Test func refusedAndBrokenItemsAreCounted() throws {
        let arc = try loadArc()
        #expect(arc.skippedItemCount == 9)
    }

    @Test func pinnedTreeKeepsRenamesFoldersSplitsAndRefusesUnsafeLinks() throws {
        let arc = try loadArc()
        let work = arc.spaces[0]
        #expect(work.icon == .icon(.planet))
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
        #expect(roundingFactors(work.pinned) == expected)
    }

    @Test func splitWidthFactorsFollowTheirTabIDs() throws {
        let arc = try loadArc()
        guard case let .split(_, _, _, _, factors) = arc.spaces[0].pinned[2] else {
            Issue.record("The third pinned item is a split")
            return
        }
        #expect(close(factors[0], 0.3) && close(factors[1], 0.7))
    }

    @Test func singleColorThemeKeepsTextureNoiseAndIntensity() throws {
        let single = try #require(try loadArc().spaces[0].theme)
        #expect(single.colorCount == 1 && single.wheel == .complimentary && single.texture == .grain)
        #expect(close(single.noise, 0.8) && close(single.intensity, 1))
        #expect(single.appearance == .automatic)
    }

    @Test func outOfGamutColorIsCarriedInDisplayP3() throws {
        let single = try #require(try loadArc().spaces[0].theme)
        let primary = try #require(single.primaryColor)
        #expect(primary.colorSpace == .displayP3)
        let extended = try #require(CGColorSpace(name: CGColorSpace.extendedSRGB))
        let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let source = try #require(CGColor(colorSpace: extended, components: [1.0699, -0.143, 0.2, 1]))
        let converted = try #require(source.converted(to: displayP3, intent: .defaultIntent, options: nil))
        let system = try #require(converted.components)
        #expect(close(primary.red, Double(system[0]), 1e-3) && close(primary.green, Double(system[1]), 1e-3)
                && close(primary.blue, Double(system[2]), 1e-3))
    }

    @Test func emojiV2IsAOneCharacterEmojiAndThreeColorsAreAnalogous() throws {
        let ideas = try loadArc().spaces[1]
        #expect(ideas.icon == .emoji("\u{1F680}"))
        #expect(ideas.theme?.colorCount == 3 && ideas.theme?.wheel == .analogous && ideas.theme?.texture == .sand)
        #expect(ideas.theme?.primaryColor == ThemeColor(red: 0.2, green: 0.4, blue: 0.8))
    }

    @Test func reversedContainerLabelsStillFindPinned() throws {
        let ideas = try loadArc().spaces[1]
        #expect(ideas.pinned == [.tab(Tab(title: "Golf", url: "https://example.test/g"))])
    }

    @Test func legacyEmojiIsAUnicodeScalarAndTwoColorsAreComplimentary() throws {
        let side = try loadArc().spaces[2]
        #expect(side.icon == .emoji("\u{1F600}"))
        #expect(side.theme?.colorCount == 2 && side.theme?.wheel == .complimentary && side.theme?.texture == .tweed
                && side.theme.map { close($0.noise, 0.25) && close($0.intensity, 0.5) } == true)
    }

    @Test func newContainerIDsAloneLocateThePinnedContainer() throws {
        let actual = try loadArc().spaces[2].pinned.count
        #expect(actual == 1)
    }

    @Test func unknownIconIsDroppedAndMissingThemeIsArcsUnthemedSpace() throws {
        let plain = try loadArc().spaces[3]
        #expect(plain.icon == nil && plain.theme == SpaceTheme() && plain.pinned.isEmpty)
    }

    @Test func unknownStyleFallsBackToParcsDefaultTheme() throws {
        let actual = try loadArc().spaces[4].theme
        #expect(actual == nil)
    }

    @Test func standardFavoritesHoldTabsAndSplitsButSkipFolders() throws {
        let favorites = try #require(try loadArc().favorites[.standard])
        #expect(favorites.count == 14)
        #expect(favorites[1] == .split(title: nil, icon: nil, tabs: [Tab(title: "Left", url: "https://left.example.test/"),
               Tab(title: "Right", url: "https://right.example.test/")], orientation: .horizontal, widthFactors: [0.5, 0.5]))
    }

    @Test func customProfileFavoritesAreRead() throws {
        let actual = try loadArc().favorites[profileTwo]
        #expect(actual == [.tab(Tab(title: "Calendar", url: "https://calendar.example.test/"))])
    }

    @Test(arguments: ["not json", "[]", #"{"sidebar":{"containers":[{"global":{}}]}}"#])
    func aFileWithoutArcsSidebarShapeFails(bad: String) {
        #expect(throws: (any Error).self) { try ArcSidebarImport(data: Data(bad.utf8)) }
    }

    @Test func nestingIsBoundedAt128() throws {
        var deep: [Any] = []
        for level in 0..<200 {
            let child = level < 199 ? ["F\(level + 1)"] : []
            deep += ["F\(level)", ["id": "F\(level)", "title": "L\(level)", "childrenIds": child, "data": ["list": [:]]]]
        }
        let deepArc = try ArcSidebarImport(data: document(items: deep, pinned: ["F0"]))
        var depth = 0
        var level = deepArc.spaces[0].pinned
        while case let .folder(_, _, children)? = level.first { depth += 1; level = children }
        #expect(depth == ArcSidebarImport.maximumDepth && deepArc.skippedItemCount == 1)
    }

    @Test func itemCountIsBoundedAt50000IncludingTheContainer() throws {
        var many: [Any] = []
        var ids: [String] = []
        for index in 0...ArcSidebarImport.maximumItems {
            ids.append("T\(index)")
            many += ["T\(index)", ["id": "T\(index)", "data": ["tab": ["savedURL": "https://example.test/\(index)", "savedTitle": "T"]]]]
        }
        let manyArc = try ArcSidebarImport(data: document(items: many, pinned: ids))
        #expect(manyArc.spaces[0].pinned.count == ArcSidebarImport.maximumItems - 1 && manyArc.skippedItemCount == 4)
    }

    @Test func aFailedSessionWriteLeavesNothingBehind() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try loadArc()
            let importedAt = importedAt
            let store = try BrowserStore(directory: directory, now: { importedAt })
            let standardID = store.state.profiles[0].id
            _ = store.createProfile(name: "WORK PROFILE")
            try store.save()
            let before = store.state
            let session = directory.appendingPathComponent("session.json")
            let backup = directory.appendingPathComponent("prior-session.json")
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) {
                try store.importArcSidebar(arc, profiles: allProfiles, standardProfileID: standardID)
            }
            #expect(store.state == before)
        }
    }

    @Test func importDoesNotChangeTheActiveSpaceAndAddsTwoProfiles() throws {
        try withImport { imported, _ in
            #expect(imported.store.activeSpaceID == imported.activeBefore)
            #expect(imported.state.profiles.count == imported.profilesBefore + 2)
            #expect(imported.state.profiles.first { $0.id == imported.standardID }?.name == "Default")
        }
    }

    @Test func everyArcSpaceBecomesANewSpaceInArcsOrder() throws {
        try withImport { imported, _ in
            let sideProjects = try #require(imported.state.profiles.first { $0.name == "Side Projects" })
            let empty = try #require(imported.state.profiles.first { $0.name == "Empty" })
            let created = imported.created
            #expect(created.map(\.title) == ["Work", nil, "Side", "Plain", "Odd", "Side Projects", "Empty"])
            #expect(created.map(\.profileID) == [imported.standardID, imported.standardID, imported.existingID,
                                                 imported.standardID, imported.standardID, sideProjects.id, empty.id])
        }
    }

    @Test func untitledSpaceTakesItsPositionalNameAndImportedSpacesUseTheDefaultSymbol() throws {
        try withImport { imported, _ in
            #expect(imported.created[1].name == "Space \(imported.spacesBefore + 2)")
            #expect(imported.created.allSatisfy { $0.symbol == "circle.fill" })
        }
    }

    @Test func iconAndThemeAreAppliedAndUnreadableThemeBecomesTheDefault() throws {
        try withImport { imported, _ in
            let created = imported.created
            #expect(created[0].customIcon == .icon(.planet) && created[0].theme == imported.arc.spaces[0].theme)
            #expect(created[4].theme == BrowserSpace(id: UUID(), name: "", symbol: "", color: "B9B5D4",
                                                     profileID: imported.standardID).theme)
        }
    }

    @Test func eachArcProfilesDestinationIsTheFirstSpaceCreatedForIt() throws {
        try withImport { imported, _ in
            let sideProjects = try #require(imported.state.profiles.first { $0.name == "Side Projects" })
            let empty = try #require(imported.state.profiles.first { $0.name == "Empty" })
            let created = imported.created
            let result = imported.result
            #expect(result[.standard] == .init(spaceID: created[0].id, profileID: imported.standardID))
            #expect(result[profileOne] == .init(spaceID: created[2].id, profileID: imported.existingID))
            #expect(result[profileTwo] == .init(spaceID: created[5].id, profileID: sideProjects.id))
            #expect(result[profileThree] == .init(spaceID: created[6].id, profileID: empty.id))
            #expect(result.values.allSatisfy { $0.isCurrent(in: imported.state) })
        }
    }

    @Test func pinnedRootOrderIsArcsOrderAndTheSplitSurvivesReconciliation() throws {
        try withImport { imported, _ in
            let state = imported.state
            let workID = imported.created[0].id
            let root = SidebarHierarchy.children(in: .init(spaceID: workID, folderID: nil, section: .pinned), state: state)
            let workTabs = state.tabs.filter { $0.spaceID == workID && $0.kind == .pinned }
            func tab(_ url: String) -> BrowserTab? { workTabs.first { $0.savedURL == url } }
            let projects = try #require(state.folders.first { $0.spaceID == workID && $0.parentID == nil })
            let groups = SidebarSplitItems.groups(in: state, spaceID: workID)
                .filter { !SidebarSplitItems.isFavorite($0, in: state, profileID: imported.standardID) }
            #expect(groups.count == 1 && groups[0].orientation == .vertical && groups[0].customTitle == "Compare"
                    && groups[0].customIcon == .emoji("\u{1F9EA}"))
            let alpha = try #require(tab("https://docs.example.test/a"))
            let settings = try #require(tab("parc://settings"))
            #expect(root == [.tab(alpha.id), .folder(projects.id), .split(groups[0].id), .tab(settings.id)])
        }
    }

    @Test func aTabKeepsItsTitleRenameAndMute() throws {
        try withImport { imported, _ in
            let state = imported.state
            let workID = imported.created[0].id
            let alpha = try #require(state.tabs.first {
                $0.spaceID == workID && $0.kind == .pinned && $0.savedURL == "https://docs.example.test/a"
            })
            #expect(alpha.title == "Alpha docs" && alpha.customTitle == "Renamed alpha" && alpha.isMuted
                    && alpha.profileID == imported.standardID && alpha.createdAt == importedAt)
        }
    }

    @Test func foldersKeepNameIconNestingAndOrder() throws {
        try withImport { imported, _ in
            let state = imported.state
            let workID = imported.created[0].id
            let workTabs = state.tabs.filter { $0.spaceID == workID && $0.kind == .pinned }
            func tab(_ url: String) -> BrowserTab? { workTabs.first { $0.savedURL == url } }
            let projects = try #require(state.folders.first { $0.spaceID == workID && $0.parentID == nil })
            #expect(projects.name == "Projects" && projects.customIcon == .icon(.star))
            let inner = try #require(state.folders.first { $0.parentID == projects.id })
            #expect(inner.name == "Imported folder" && tab("https://example.test/c")?.folderID == inner.id)
            let beta = try #require(tab("https://example.test/b"))
            #expect(SidebarHierarchy.children(in: .init(spaceID: workID, folderID: projects.id, section: .pinned), state: state)
                    == [.tab(beta.id), .folder(inner.id)])
        }
    }

    @Test func todayTabsComeInArcsOrderAndStartTheirArchiveClockAtTheImport() throws {
        try withImport { imported, _ in
            let state = imported.state
            let workID = imported.created[0].id
            let today = SidebarHierarchy.children(in: .init(spaceID: workID, folderID: nil, section: .today), state: state)
            let newer = try #require(state.tabs.first { $0.savedURL == "https://example.test/newer-today" })
            let older = try #require(state.tabs.first { $0.savedURL == "https://example.test/today" })
            #expect(today == [.tab(newer.id), .tab(older.id)] && newer.kind == .today && older.kind == .today
                    && older.spaceID == workID && older.folderID == nil)
            #expect(older.lastAccessed == importedAt)
        }
    }

    @Test func eachImportedSpaceRemembersItsArcSpace() throws {
        try withImport { imported, _ in
            #expect(imported.state.arcImportedSpaces["734FF6CE-5A92-54B8-8106-4F9A92236F11"] == imported.created[0].id)
        }
    }

    @Test func favoritesStopAtParcsLimitKeepArcsOrderAndSkipDuplicates() throws {
        try withImport { imported, _ in
            let state = imported.state
            let workID = imported.created[0].id
            let location = SidebarContainerLocation(spaceID: workID, folderID: nil, section: .favorite,
                                                    profileID: imported.standardID)
            let favorites = SidebarHierarchy.children(in: location, state: state)
            let favoriteTabs = state.tabs.filter { $0.kind == .favorite && $0.profileID == imported.standardID }
            #expect(favorites.count == 12)
            let mail = try #require(favoriteTabs.first { $0.savedURL == "https://mail.example.test/" })
            #expect(favorites.first == .tab(mail.id))
            #expect(!favoriteTabs.contains { $0.savedURL == "https://www.mail.example.test" })
            #expect(!favoriteTabs.contains { $0.savedURL == "https://f12.example.test/" })
        }
    }

    @Test func aFavoritesSplitSurvivesTheImport() throws {
        try withImport { imported, _ in
            let state = imported.state
            let location = SidebarContainerLocation(spaceID: imported.created[0].id, folderID: nil, section: .favorite,
                                                    profileID: imported.standardID)
            let favorites = SidebarHierarchy.children(in: location, state: state)
            guard case .split(let id) = favorites[1] else {
                Issue.record("The second Favorite is a split")
                return
            }
            #expect(state.splitLayouts.first { $0.id == id }?.tabIDs.count == 2)
        }
    }

    @Test func aFavoritesOnlyProfileGetsItsFavorites() throws {
        try withImport { imported, _ in
            let sideProjects = try #require(imported.state.profiles.first { $0.name == "Side Projects" })
            #expect(imported.state.tabs.filter { $0.kind == .favorite && $0.profileID == sideProjects.id }.map(\.savedURL)
                    == ["https://calendar.example.test/"])
        }
    }

    @Test func theImportIsDurable() throws {
        try withImport { imported, directory in
            let state = imported.state
            let reloaded = try BrowserStore(directory: directory)
            #expect(reloaded.state.spaces == state.spaces && reloaded.state.profiles == state.profiles
                    && reloaded.state.tabs == state.tabs && reloaded.state.folders == state.folders
                    && reloaded.state.splitLayouts == state.splitLayouts
                    && reloaded.state.sidebarItemOrder == state.sidebarItemOrder
                    && reloaded.state.arcImportedSpaces == state.arcImportedSpaces)
        }
    }

    @Test func importingTheSameSpacesAgainAddsNoCopies() throws {
        try withImport { imported, _ in
            let again = try imported.store.importArcSidebar(imported.arc, profiles: [(.standard, "Personal")],
                                                            standardProfileID: imported.standardID)
            let standardSpaces = imported.arc.spaces.filter { $0.profile == .standard }
            #expect(standardSpaces.count == 4 && imported.store.state.spaces.count == imported.state.spaces.count
                    && imported.store.state.tabs.count == imported.state.tabs.count)
            #expect(again[.standard] == imported.result[.standard])
        }
    }

    @Test func aLaterImportReusesTheSameParcProfileAndAnExistingSpace() throws {
        try withImport { imported, _ in
            let spacesBeforeReuse = imported.store.state.spaces.count
            let secondReuse = try imported.store.importArcSidebar(
                imported.arc, profiles: [(profileOne, "work profile"), (profileTwo, "Side Projects")],
                standardProfileID: imported.standardID)
            #expect(secondReuse[profileOne]?.profileID == imported.existingID)
            #expect(imported.store.state.spaces.count == spacesBeforeReuse && secondReuse[profileTwo]?.spaceID
                    == imported.state.spaces.first { $0.title == "Side Projects" }?.id)
        }
    }

    @Test func onlyArcsChromeSchemePagesBecomeParcPages() throws {
        let links = try ArcSidebarImport(data: document(items: [
            "N", ["id": "N", "data": ["tab": ["savedURL": "parc://note/0B3E", "savedTitle": "Note"]]],
            "C", ["id": "C", "data": ["tab": ["savedURL": "chrome://settings/", "savedTitle": "Settings"]]],
            "X", ["id": "X", "childrenIds": ["Y"], "data": ["splitView": [:]]],
            "Y", ["id": "Y", "childrenIds": ["Y1", "Y2"], "data": ["list": [:]]],
            "Y1", ["id": "Y1", "data": ["tab": ["savedURL": "https://example.test/y1"]]],
            "Y2", ["id": "Y2", "data": ["tab": ["savedURL": "https://example.test/y2"]]],
        ], pinned: ["N", "C", "X"]))
        #expect(links.spaces[0].pinned.map { if case .tab(let tab) = $0 { return tab.url } else { return "" } }
                == ["parc://settings/"])
        #expect(links.skippedItemCount == 4)
    }

    @Test func aSplitPageAlreadyInFavoritesIsNotAddedTwice() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let arc = try ArcSidebarImport(data: JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [[
                "items": ["F", ["id": "F", "childrenIds": ["A", "S"], "data": ["itemContainer": [:]]],
                          "A", ["id": "A", "data": ["tab": ["savedURL": "https://a.example.test/"]]],
                          "S", ["id": "S", "childrenIds": ["A2", "B"], "data": ["splitView": [:]]],
                          "A2", ["id": "A2", "data": ["tab": ["savedURL": "https://a.example.test/"]]],
                          "B", ["id": "B", "data": ["tab": ["savedURL": "https://b.example.test/"]]]],
                "spaces": [], "topAppsContainerIDs": [["default": true], "F"]]]]]))
            _ = try store.importArcSidebar(arc, profiles: [(.standard, "Personal")],
                                           standardProfileID: store.state.profiles[0].id)
            #expect(store.state.tabs.filter { $0.kind == .favorite }.map(\.savedURL)
                    == ["https://a.example.test/", "https://b.example.test/"] && store.state.splitLayouts.isEmpty)
        }
    }

    @Test func anUnknownStandardProfileIsRefused() throws {
        try withImport { imported, _ in
            #expect(throws: (any Error).self) {
                try imported.store.importArcSidebar(imported.arc, profiles: allProfiles, standardProfileID: UUID())
            }
        }
    }

    @Test func arcsPerProfileArchiveAgeWinsOverItsArcWideOne() {
        let preferences: [String: Any] = [
            "autoArchiveTimeThreshold": "\"sevenDays\"",
            "autoArchiveTimeThresholdsPerProfile": #"{"thresholds":[{"default":{}},"oneHour",{"custom":{"_0":{"directoryBasename":"Profile 1","machineID":"M"}}},{"never":{}}]}"#]
        let hours = ArcSidebarImport.autoArchiveHours(preferences: preferences, profiles: [.standard, profileOne, profileTwo])
        #expect(hours == [.standard: 1, profileOne: 0, profileTwo: 168])
    }

    @Test func withoutArcsArchiveSettingEachProfileKeepsParcs() {
        #expect(ArcSidebarImport.autoArchiveHours(preferences: ["autoArchiveTimeThresholdsPerProfile": #"{"thresholds":[]}"#],
                                                  profiles: [.standard]).isEmpty)
    }

    @Test func arcsArchiveAgeAppliesToTheProfileTheDefaultAndEducation() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let store = try BrowserStore(directory: directory)
            var timed = try loadArc()
            timed.autoArchiveHours = [.standard: 168]
            _ = try store.importArcSidebar(timed, profiles: [(.standard, "Personal")],
                                           standardProfileID: store.state.profiles[0].id)
            #expect(store.state.profiles[0].autoArchiveHours == 168 && store.state.autoArchiveDefaultHours == 168
                    && !store.state.autoArchiveEducationEligible)
        }
    }

    @Test func anImportFromBeforeTheRecordMatchesSpacesByNameAndPinnedPages() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try loadArc()
            let store = try BrowserStore(directory: directory)
            let profile = store.state.profiles[0].id
            _ = try store.importArcSidebar(arc, profiles: [(.standard, "Personal")], standardProfileID: profile)
            var legacy = store.state
            legacy.arcImportedSpaces = [:]
            let result = try arc.inserting(into: legacy, profiles: [(.standard, "Personal")], standardProfileID: profile,
                                           at: importedAt)
            let pinnedSpaces = arc.spaces.filter { $0.profile == .standard && !$0.pinned.isEmpty }.count
            #expect(result.state.spaces.count == legacy.spaces.count + 4 - pinnedSpaces
                    && result.state.arcImportedSpaces.count == 4)
        }
    }

    @Test func aChosenTargetProfileTakesTheArcProfilesSpaces() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try loadArc()
            let store = try BrowserStore(directory: directory)
            let original = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
            let chosenID = store.createProfile(name: "Elsewhere")
            try store.save()
            let profilesBeforeChoice = store.state.profiles.count
            let result = try store.importArcSidebar(arc, profiles: [(profileOne, "Work Profile")],
                standardProfileID: original.profileID, primary: profileOne, into: chosenID)
            let workSpaces = arc.spaces.filter { $0.profile == profileOne }.count
            #expect(result[profileOne]?.profileID == chosenID && store.state.profiles.count == profilesBeforeChoice
                    && store.state.spaces.filter { $0.profileID == chosenID }.count == workSpaces)
        }
    }

    @Test func aTargetProfileThatDoesNotExistIsRefusedAndWritesNothing() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try loadArc()
            let store = try BrowserStore(directory: directory)
            let profileID = store.activeSpace.profileID
            let before = store.state
            #expect(throws: (any Error).self) {
                try store.importArcSidebar(arc, profiles: [(.standard, "Personal")], standardProfileID: profileID,
                                           primary: .standard, into: UUID())
            }
            #expect(store.state == before)
        }
    }

    @Test func aTargetProfileBeingRemovedIsRefused() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try loadArc()
            let store = try BrowserStore(directory: directory)
            let profileID = store.activeSpace.profileID
            let chosenID = store.createProfile(name: "Elsewhere")
            var retiring = store.state
            retiring.profileRemovals.append(.init(id: UUID(), profileID: chosenID, profileName: "Elsewhere"))
            #expect(throws: (any Error).self) {
                try arc.inserting(into: retiring, profiles: [(.standard, "Personal")], standardProfileID: profileID,
                                  target: (.standard, chosenID), at: importedAt)
            }
        }
    }

    struct CustomPrimary {
        let before: BrowserState
        let state: BrowserState
        let result: Destinations
        let openedID: UUID
        let namesake: UUID
    }

    func withCustomPrimary(_ body: (CustomPrimary) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try loadArc()
            let store = try BrowserStore(directory: directory)
            let opened = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
            let namesake = store.createProfile(name: "Work Profile")
            try store.save()
            let before = store.state
            let result = try store.importArcSidebar(arc, profiles: [(profileOne, "Work Profile"), (profileTwo, "Side Projects")],
                standardProfileID: opened.profileID, primary: profileOne, into: opened.profileID)
            try body(CustomPrimary(before: before, state: store.state, result: result,
                                   openedID: opened.profileID, namesake: namesake))
        }
    }

    @Test func aPrimaryProfilesSpacesJoinTheOpenedProfile() throws {
        try withCustomPrimary { custom in
            let projects = try #require(custom.state.profiles.first { $0.name == "Side Projects" })
            let spaces = Array(custom.state.spaces.dropFirst(custom.before.spaces.count))
            #expect(spaces.map(\.title) == ["Side", "Side Projects"]
                    && spaces.map(\.profileID) == [custom.openedID, projects.id])
            #expect(custom.result[profileOne]?.profileID == custom.openedID
                    && custom.result[profileTwo]?.profileID == projects.id && custom.result[.standard] == nil)
        }
    }

    @Test func aParcProfileNamedLikeThePrimaryIsLeftAloneAndTheOpenedProfileKeepsItsName() throws {
        try withCustomPrimary { custom in
            #expect(custom.state.profiles.count == custom.before.profiles.count + 1
                    && !custom.state.spaces.contains { $0.profileID == custom.namesake }
                    && custom.state.profiles.first { $0.id == custom.openedID }?.name
                        == custom.before.profiles.first { $0.id == custom.openedID }?.name)
        }
    }

    @Test func favoritesFollowTheirOwnArcProfile() throws {
        try withCustomPrimary { custom in
            let projects = try #require(custom.state.profiles.first { $0.name == "Side Projects" })
            #expect(custom.state.tabs.filter { $0.kind == .favorite && $0.profileID == projects.id }.map(\.savedURL)
                    == ["https://calendar.example.test/"]
                    && !custom.state.tabs.contains { $0.kind == .favorite && $0.profileID == custom.openedID })
        }
    }
}
