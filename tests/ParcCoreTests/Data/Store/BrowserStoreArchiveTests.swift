import Combine
import Foundation
import Testing
@testable import ParcCore

extension BrowserStoreTests {
    @Test static func typedInternalEaselAddresses() throws {
        let id = UUID()
        let canonical = InternalPage.easel(id).urlString
        #expect(canonical == "parc://easel/" + id.uuidString.lowercased(), "Easel routes must use a canonical opaque document ID")
        #expect(InternalPage(urlString: canonical) == .easel(id), "The internal route must round-trip its typed identity")
        #expect(InternalPage.easel(id).sidebarFallbackSymbol == InternalPage.easelFallbackSymbol
                   && InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).sidebarFallbackSymbol == InternalPage.noteFallbackSymbol
                   && InternalPage.sidebarFallbackSymbol(urlString: "https://example.org") == "globe", "Easel and Note rows keep distinct still glyphs; web rows keep the globe fallback")
        #expect(CommandBarCommandPresentation.symbol(forCommandID: "createEasel:") == InternalPage.easelFallbackSymbol
                   && CommandBarCommandPresentation.symbol(forCommandID: "createNote:") == InternalPage.noteFallbackSymbol, "New Easel and New Note commands show the same Library marks as their rows")
        for address in ["parc://easel/not-a-uuid", "parc://easel/" + id.uuidString + "/more",
                        canonical + "?profile=other", canonical + "#fragment", "parc://user@easel/" + id.uuidString,
                        "parc://easel:88/" + id.uuidString, "parc://other/" + id.uuidString,
                        "https://easel/" + id.uuidString] {
            #expect(InternalPage(urlString: address) == nil, "Internal document routes must reject unsupported components")
        }
        for address in [canonical, "PARC://easel/" + id.uuidString, "parc://easel/not-a-uuid"] {
            #expect(NavigationInput.resolve(address) == nil, "General navigation must never send an internal Parc address to a web engine or search provider")
        }
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let tabID = store.open("https://example.org")
            let before = store.state
            store.navigate(tabID, input: canonical)
            #expect(store.state == before, "A pasted internal route must not mutate a web tab through ordinary navigation")
        }
    }

    @Test static func easelTabsAndSavedTitle() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let documentID = UUID()
            let profileID = store.activeSpace.profileID
            let originalSpace = store.activeSpaceID
            _ = store.open("https://already.example")
            let tabID = store.openEasel(id: documentID, title: "Research")!
            let created = try tab(tabID, in: store)
            #expect(created.kind == .today && created.title == "Research" && created.savedTitle == "Research", "A new Easel is a Today tab with its saved title")
            #expect(SidebarHierarchy.children(in: .init(spaceID: originalSpace, folderID: nil, section: .today),
                                                 state: store.state).first == .tab(tabID), "A new Easel enters at the top of Today")
            #expect(created.url == InternalPage.easel(documentID).urlString && created.savedURL == created.url, "The Easel tab must save the typed internal destination")
            #expect(store.state.history.isEmpty, "Opening an Easel must not create a fabricated web history entry")
            store.createSpace(name: "Other")
            let again = store.openEasel(id: documentID, title: "Research")
            #expect(again == tabID && store.activeSpaceID == originalSpace && store.state.tabs.count == 2, "Opening the same profile's Easel again must select its existing tab and Space")
            store.updateEaselTitle(id: documentID, profileID: profileID, title: "Renamed board")
            #expect(try tab(tabID, in: store).title == "Renamed board" && (try tab(tabID, in: store)).savedTitle == "Renamed board", "Document renaming must update both live and saved titles")
            store.setKind(tabID, .pinned)
            store.updateTab(tabID, title: "A web page", url: "https://example.org/reference")
            store.updateEaselTitle(id: documentID, profileID: profileID, title: "Latest board name")
            #expect(try tab(tabID, in: store).title == "A web page" && (try tab(tabID, in: store)).savedTitle == "Latest board name", "Renaming a saved Easel must not overwrite the title of a web page currently occupying that tab")
            store.closeTab(tabID)
            #expect(try tab(tabID, in: store).url == created.savedURL && (try tab(tabID, in: store)).title == "Latest board name"
                       && (try tab(tabID, in: store)).archivedAt == nil && (try tab(tabID, in: store)).kind == .pinned, "Closing a pinned Easel that navigated away resets to the saved document")
            store.closeTab(tabID)
            #expect(try tab(tabID, in: store).archivedAt == nil && (try tab(tabID, in: store)).kind == .pinned
                       && (try tab(tabID, in: store)).url == created.savedURL, "Closing a pinned Easel that is showing the document unloads it in place, like a deselect")
            #expect(try store.openEasel(id: documentID, title: "Latest board name") == tabID && (try tab(tabID, in: store)).kind == .pinned, "Opening it again selects the same pinned tab")
            let folder = store.createFolder(name: "Boards")
            store.moveTab(tabID, toSpace: store.activeSpaceID, folderID: folder)
            #expect(try tab(tabID, in: store).folderID == folder && (try tab(tabID, in: store)).kind == .pinned, "An Easel can be pinned into a folder")
            store.closeTab(tabID)
            #expect(try tab(tabID, in: store).archivedAt == nil && (try tab(tabID, in: store)).kind == .pinned
                       && (try tab(tabID, in: store)).folderID == folder, "Closing a folder-pinned Easel keeps it in its folder")
            store.setKind(tabID, .today)
            store.closeTab(tabID)
            #expect(try tab(tabID, in: store).archivedAt != nil, "Closing a Today Easel archives it")
            store.openEasel(id: documentID, title: "Latest board name")
            #expect(try tab(tabID, in: store).kind == .today && (try tab(tabID, in: store)).archivedAt == nil, "Library reopen restores the archived Easel as Today")
            let web = store.open("https://example.org/alongside")
            try savedSplit(store, [tabID, web], in: .init(spaceID: store.activeSpaceID, folderID: nil, section: .pinned))
            store.selectTab(tabID)
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2])
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state == store.state, "A split containing a native Easel and real web tab must persist without a separate window model")
            reopened.closeTab(tabID)
            #expect(try tab(tabID, in: reopened).archivedAt == nil && (try tab(tabID, in: reopened)).kind == .pinned, "Closing a pinned Easel pane unloads it like any pinned tab")
            #expect(try reopened.openEasel(id: documentID, title: "Latest board name") == tabID
                       && (try tab(tabID, in: reopened)).kind == .pinned, "Opening it again selects its existing pinned tab")
        }
    }

    @Test static func easelProfileDirectoriesAndIdentity() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let documentID = UUID()
            let firstProfile = store.activeSpace.profileID
            let firstID = store.openEasel(id: documentID, title: "Personal")!
            let firstPath = store.activeEaselsDirectory
            #expect(firstPath == URL(fileURLWithPath: store.profilePath(for: (try tab(firstID, in: store))), isDirectory: true).appendingPathComponent("Easels", isDirectory: true), "Easel storage must live under the same explicit browser profile path")
            let secondSpace = store.createSpace(name: "Work")
            let secondProfile = store.createProfile(name: "Work")
            store.assignProfile(secondProfile, toSpace: secondSpace)
            let secondID = store.openEasel(id: documentID, title: "Work board")!
            #expect(firstID != secondID && store.activeEaselsDirectory != firstPath, "Matching document UUIDs in distinct profiles must remain separate tabs and directories")
            #expect(store.activeEaselsDirectory == store.easelsDirectory(for: secondProfile), "The active Easel directory must follow the active Space's profile")
            store.updateEaselTitle(id: documentID, profileID: secondProfile, title: "Changed work board")
            #expect(try tab(firstID, in: store).savedTitle == "Personal" && (try tab(secondID, in: store)).savedTitle == "Changed work board", "A document's title notification must not rename another profile's same-ID document")
            let before = store.state
            store.updateEaselTitle(id: documentID, profileID: firstProfile, title: "  ")
            #expect(store.state == before, "An empty native title must not erase the pinned destination name")
            #expect(!FileManager.default.fileExists(atPath: firstPath.path), "Path resolution and tab creation must not silently create or copy document files")
        }
    }

    @Test static func archivePolicyIsProfileScoped() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstProfile = store.activeSpace.profileID
            let firstSpace = store.activeSpaceID
            #expect(store.autoArchiveInterval(for: firstProfile) == .twelveHours, "New profiles must use the 12-hour Today default")
            store.setAutoArchiveInterval(.twentyFourHours, for: firstProfile)
            let secondProfile = store.createProfile(name: "Second")
            store.assignProfile(secondProfile, toSpace: firstSpace)
            store.updateSettings { $0.sidebarWidth = 260; $0.searchEngine = "https://www.bing.com/search?q=" }
            #expect(store.autoArchiveInterval(for: secondProfile) == .twentyFourHours, "A new Profile inherits the chosen shared default; assignment and unrelated preferences preserve it")
            #expect(store.autoArchiveInterval(for: firstProfile) == .twentyFourHours, "Unrelated settings must preserve the original profile's policy too")
            let secondSpace = store.createSpace(name: "Shared profile")
            store.setAutoArchiveInterval(.sevenDays, for: secondProfile)
            store.selectSpace(firstSpace)
            #expect(store.autoArchiveInterval(for: store.activeSpace.profileID) == .sevenDays, "All Spaces assigned to one profile must share its archive choice")
            store.assignProfile(firstProfile, toSpace: secondSpace)
            store.setAutoArchiveInterval(.thirtyDays, for: firstProfile)
            #expect(store.activeSpaceID == firstSpace && store.autoArchiveInterval(for: secondProfile) == .sevenDays, "Updating an explicitly displayed profile must not depend on whichever Space became active")
            let expected = store.state
            #expect(!store.setAutoArchiveInterval(.never, for: UUID()) && store.state == expected, "A stale or unknown profile target must not change another profile")
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state == expected, "Independent per-profile archive policies must survive restart")
        }
    }

    @Test static func legacyArchivePolicyMirrorIsIgnored() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let profile = store.activeSpace.profileID
            store.setAutoArchiveInterval(.sixHours, for: profile)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var settings = json["settings"] as! [String: Any]
            settings["autoArchiveHours"] = 720
            json["settings"] = settings
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.autoArchiveInterval(for: profile) == .sixHours, "Legacy profile policy must remain authoritative over a stale global mirror")
            reopened.updateSettings { $0.sidebarWidth = 280 }
            #expect(reopened.autoArchiveInterval(for: profile) == .sixHours, "Changing general settings after migration must preserve a hidden older duration")
            try reopened.save()
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            #expect((saved["settings"] as! [String: Any])["autoArchiveHours"] == nil, "New saves must remove the redundant global policy field")
            for interval in [AutoArchiveInterval.never, .oneHour, .sixHours] {
                reopened.setAutoArchiveInterval(interval, for: profile)
                try reopened.save()
                let again = try BrowserStore(directory: directory)
                #expect(again.autoArchiveInterval(for: profile) == interval, "Older supported Parc values must round-trip without silently changing user preference")
            }
            #expect(AutoArchiveInterval.settingsChoices == [.twelveHours, .twentyFourHours, .sevenDays, .thirtyDays], "Normal Settings choices must match the archive menu, excluding hidden and debug cases")
            #expect(AutoArchiveInterval.never.seconds == nil && AutoArchiveInterval.twentyFourHours.seconds == 86400, "Never must be no threshold, and a day must be exactly 86400 seconds")
        }
    }

    @Test static func invalidArchivePoliciesPreserveSession() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            for hours in [-1.0, 2.0, 20.0 / 3600, 999.0] {
                var state = store.state
                state.profiles[0].autoArchiveHours = hours
                let bytes = try encoder.encode(state)
                try bytes.write(to: file)
                var rejected = false
                do { _ = try BrowserStore(directory: directory) } catch { rejected = true }
                #expect(rejected, "Invalid or debug-only persisted policies must not become accidental Never or arbitrary timers")
                #expect(try Data(contentsOf: file) == bytes, "Rejecting an invalid archive policy must preserve the existing session file")
            }
        }
    }

    @Test static func archiveStartMigrationAndStrictBoundary() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let old = store.open("https://old.example")
            let selected = store.open("https://selected.example")
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json.removeValue(forKey: "autoArchiveStartedAt")
            var tabs = json["tabs"] as! [[String: Any]]
            for index in tabs.indices { tabs[index].removeValue(forKey: "isUnread") }
            json["tabs"] = tabs
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            now.addTimeInterval(100 * 86400)
            let migrated = try BrowserStore(directory: directory, now: { now })
            #expect(migrated.state.autoArchiveStartedAt == nil && migrated.state.tabs.allSatisfy { !$0.isUnread }, "Older Parc sessions must migrate absent start to unset and previously selected tabs to read")
            #expect(migrated.archiveExpiredTabs().isEmpty && migrated.state.autoArchiveStartedAt == now, "The first archive run must initialize the global start gate without immediately closing old tabs")
            let started = now
            try migrated.save()
            now.addTimeInterval(12 * 3600)
            let reopened = try BrowserStore(directory: directory, now: { now })
            #expect(reopened.state.autoArchiveStartedAt == started, "Restart must preserve, not reset, the global archive start")
            #expect(reopened.archiveExpiredTabs().isEmpty, "The start gate uses strict greater-than, not equality")
            now.addTimeInterval(1)
            #expect(reopened.archiveExpiredTabs() == [old], "A read inactive tab older than both gates must expire after the boundary")
            #expect(try tab(selected, in: reopened).archivedAt == nil, "The existing selected-item exemption must remain intact")
            let startAfter = reopened.state.autoArchiveStartedAt
            reopened.refreshVisibleTabs([selected])
            reopened.archiveExpiredTabs()
            #expect(reopened.state.autoArchiveStartedAt == startAfter, "Activity and later sweeps must not reset the persisted start gate")
        }
    }

    @Test static func visibleActivityPreventsImmediateArchive() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.setAutoArchiveInterval(.twentyFourHours, for: store.activeSpace.profileID)
            store.archiveExpiredTabs()
            let viewed = store.open("https://viewed.example")
            now.addTimeInterval(48 * 3600)
            store.refreshVisibleTabs([viewed, UUID()])
            let lastViewed = now
            let next = store.open("https://next.example")
            #expect(try store.archiveExpiredTabs().isEmpty && (try tab(viewed, in: store)).lastAccessed == lastViewed, "Periodic visible-page refresh must prevent a long-viewed page from expiring immediately after switching away")
            now.addTimeInterval(24 * 3600)
            #expect(store.archiveExpiredTabs().isEmpty, "A tab at exactly the configured inactivity threshold must remain")
            now.addTimeInterval(1)
            #expect(store.archiveExpiredTabs() == [viewed], "A formerly visible page must expire after a full interval without another refresh")
            store.restoreArchivedTab(viewed, destination: .previousSpace(fallbackSpaceID: nil))
            #expect(try store.selectedTabID == viewed && (try tab(viewed, in: store)).lastAccessed == now, "Restoring an automatically archived page must reset its activity and select it")
            store.selectTab(next)
            now.addTimeInterval(12 * 3600)
            #expect(store.archiveExpiredTabs().isEmpty, "A restored page must get a fresh full inactivity interval")
        }
    }

    @Test static func visibleActivityPersistsWithoutPublishing() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let viewed = store.open("https://activity-only.example")
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            let revision = store.stateRevision
            now.addTimeInterval(60)
            store.refreshVisibleTabs([viewed])
            #expect(publications == 0 && store.stateRevision == revision, "Activity-only lastAccessed stamps must not publish BrowserState or bump stateRevision")
            #expect((try tab(viewed, in: store)).lastAccessed == now, "In-memory lastAccessed must still advance for archive eligibility")
            try store.save()
            let reopened = try BrowserStore(directory: directory, now: { now })
            #expect((try tab(viewed, in: reopened)).lastAccessed == now, "Activity-only stamps must still persist into the session file")
            let afterPublish = publications
            now.addTimeInterval(1)
            store.selectTab(viewed)
            #expect(publications > afterPublish, "A real selection publish must still emit after an activity-only stamp")
            #expect((try tab(viewed, in: store)).lastAccessed == now, "Publishing after an activity overlay must keep the stamped access date")
        }
    }

    @Test static func batchedMutationPublishesOnce() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000_000_000) })
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }

            publications = 0
            let first = store.openResolvedURL(URL(string: "https://batch.example/a")!, kind: .today)
            #expect(publications == 1, "Opening a URL publishes once after append+place+select")
            #expect(store.state.selectedTabIDs == [first], "Open selects the new tab")

            publications = 0
            let second = store.openResolvedURL(URL(string: "https://batch.example/b")!, kind: .today)
            #expect(publications == 1, "A second open also publishes once")

            publications = 0
            store.setSplit([first, second])
            #expect(publications == 1, "Forming a split publishes once after activate+stamp")
            #expect(store.state.selectedTabIDs == [first, second] && store.activeSplitLayout?.tabIDs == [first, second], "Split end state matches a single activation")

            publications = 0
            store.closeSplit()
            #expect(publications == 1, "Closing a split publishes once after dissolve+stamp")
            #expect(store.state.selectedTabIDs == [first] && store.activeSplitLayout == nil, "Close-split end state keeps the focused pane alone")

            publications = 0
            let space = store.createSpace(name: "Batched")
            #expect(publications == 1, "Creating a Space publishes once after append+select")
            #expect(store.activeSpaceID == space, "Create selects the new Space")

            let other = store.openResolvedURL(URL(string: "https://batch.example/c")!, kind: .today)
            publications = 0
            store.removeTab(other)
            #expect(publications == 1, "Removing a tab publishes once after normalize+stamp")
            #expect(!store.state.tabs.contains { $0.id == other }, "Removed tab is gone from the model")
        }
    }

    @Test static func identicalStateAssignDoesNotPublish() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_100)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let id = store.open("https://identical-assign.example")
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            store.updateTab(id, title: "Once", url: "https://identical-assign.example/once")
            #expect(publications == 1, "Distinct metadata publishes once; changed() does not republish")
            let revision = store.stateRevision
            now.addTimeInterval(60)
            store.refreshVisibleTabs([id])
            #expect(publications == 1 && store.stateRevision == revision, "Activity overlay must still avoid publish after an identical-assign gate")
            store.selectTab(id)
            #expect(publications == 1 && store.stateRevision == revision, "Identical selectTab assign must not fan out @Published observers")
            #expect((try tab(id, in: store)).lastAccessed == now, "Activity overlay must remain readable across identical assigns")
        }
    }

    @Test static func unreadAndNativeProtectionGates() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let unread = store.open("https://unread.example")
            let protected = store.open("https://media-or-edit.example")
            let ordinary = store.open("https://ordinary.example")
            let selected = store.open("https://selected.example")
            var fixture = store.state
            fixture.tabs[fixture.tabs.firstIndex { $0.id == unread }!].isUnread = true
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(fixture).write(to: directory.appendingPathComponent("session.json"))
            now.addTimeInterval(13 * 3600)
            let loaded = try BrowserStore(directory: directory, now: { now })
            #expect(loaded.archiveExpiredTabs(protectedTabIDs: [protected]) == [ordinary], "Unread pages, native-protected or unknown-content pages, and current selection must survive an otherwise eligible sweep")
            loaded.refreshVisibleTabs([unread])
            #expect(try tab(unread, in: loaded).isUnread, "The timer must not invent an unread-clear action; explicit selection owns it")
            loaded.selectTab(unread)
            #expect(!(try tab(unread, in: loaded).isUnread), "Selecting a page must clear persisted unread state")
            loaded.selectTab(selected)
            try loaded.save()
            let restored = try BrowserStore(directory: directory, now: { now })
            #expect(!(try tab(unread, in: restored).isUnread), "Read state must survive restart")
            now.addTimeInterval(12 * 3600 + 1)
            let expired = Set(restored.archiveExpiredTabs())
            #expect(expired == [unread, protected], "Read and formerly protected pages must become eligible once no protection remains and activity is old")
        }
    }

    @Test static func archiveAcrossSpacesAndProfiles() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let firstSpace = store.activeSpaceID
            let short = store.open("https://short.example")
            let secondSpace = store.createSpace(name: "Day-long")
            let profile = store.createProfile(name: "Day-long")
            store.assignProfile(profile, toSpace: secondSpace)
            store.setAutoArchiveInterval(.twentyFourHours, for: profile)
            let long = store.open("https://long.example")
            _ = store.open("https://selected.example")
            now.addTimeInterval(13 * 3600)
            #expect(store.archiveExpiredTabs() == [short], "A background Space must expire by its own profile's shorter duration")
            #expect(store.state.selectionBySpace[firstSpace.uuidString]?.isEmpty == true, "Automatic closure must remove stale remembered selection in inactive Spaces")
            #expect(try tab(long, in: store).archivedAt == nil, "A different profile's longer interval must remain independent")
            now.addTimeInterval(11 * 3600)
            #expect(store.archiveExpiredTabs().isEmpty, "The second profile's exact day boundary must be retained")
            now.addTimeInterval(1)
            #expect(store.archiveExpiredTabs() == [long], "The second profile must expire only beyond its own day threshold")
        }
    }

    @Test static func archiveSavedSplitConstituents() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let first = store.open("https://first.example")
            let second = store.open("https://second.example")
            store.setSplit([first, second])
            _ = store.open("https://outside.example")
            now.addTimeInterval(13 * 3600)
            #expect(store.archiveExpiredTabs(protectedTabIDs: [second]).isEmpty, "One protected constituent must keep the saved pane group from partial automatic closure")
            store.refreshVisibleTabs([second])
            #expect(store.archiveExpiredTabs().isEmpty, "A recently active constituent must preserve an otherwise old saved pane group")
            now.addTimeInterval(12 * 3600)
            #expect(store.archiveExpiredTabs().isEmpty, "Every constituent must be strictly older than the interval")
            now.addTimeInterval(1)
            #expect(Set(store.archiveExpiredTabs()) == [first, second], "An entirely inactive unprotected Today pane group must expire together")
            #expect(store.state.splitLayouts.isEmpty, "Expired pane groups must leave no dangling saved geometry")
        }
    }

    @Test static func archiveTypedItemsAndMixedGroups() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let first = store.open("https://mixed-today.example")
            let second = store.open("https://mixed-pinned.example")
            store.setSplit([first, second])
            let note = store.openResolvedURL(URL(string: InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).urlString)!)
            let easel = store.openResolvedURL(URL(string: InternalPage.easel(UUID()).urlString)!)
            let malformed = store.openResolvedURL(URL(string: "parc://note/not-a-document")!)
            let folder = store.createFolder(name: "Saved")
            let nested = store.open("https://saved-child.example")
            store.moveTab(nested, toSpace: store.activeSpaceID, folderID: folder)
            let favorite = store.open("https://favorite.example", kind: .favorite)
            _ = store.open("https://current.example")
            store.moveTab(second, toSpace: store.activeSpaceID, folderID: folder)
            now.addTimeInterval(13 * 3600)
            #expect(store.state.splitLayouts.contains { $0.tabIDs == [first, second] }, "The original mixed split is retained by the model before eligibility")
            #expect(Set(store.archiveExpiredTabs()) == [note, easel], "Eligible Note/Easel roots archive; structural/saved/malformed items and a mixed split remain whole")
            #expect([first, second, malformed, nested, favorite].allSatisfy { id in
                store.state.tabs.contains { $0.id == id && $0.archivedAt == nil }
            }, "Automatic archive cannot detach a Today pane from a retained saved sibling")
            #expect(store.state.splitLayouts.contains { $0.tabIDs == [first, second] }, "An excluded split keeps its original identity and geometry")
        }
    }

    @Test static func archiveOriginalItemRevalidation() throws {
        for change in ["space", "document", "title"] {
            try withDirectory { directory in
                var now = Date(timeIntervalSince1970: 1_800_000_000)
                let store = try BrowserStore(directory: directory, now: { now })
                let source = store.activeSpaceID
                let destination = store.createSpace(name: "Destination")
                store.selectSpace(source)
                let original = store.open("https://original.example")
                _ = store.open("https://current.example")
                store.archiveExpiredTabs()
                now.addTimeInterval(13 * 3600)
                var request: (() -> Bool)?, finish: ((Bool) -> Void)?
                var result: [[UUID]] = []
                store.requestPageRetirement = { ids, validate, complete in
                    if ids == [original] { request = validate; finish = complete }
                }
                store.archiveExpiredTabs(protectedTabIDs: []) { result.append($0) }
                #expect(request != nil && result.isEmpty, "The original item waits for native retirement")
                switch change {
                case "space": store.moveTab(original, toSpace: destination)
                case "document": store.updateTab(original, url: "https://replacement.example")
                default: store.updateTab(original, title: "Updated page title")
                }
                let accepted = request?() == true
                #expect(accepted == (change == "title"), "A changed original \(change) is distinguished from a metadata-only title refresh")
                finish?(accepted)
                finish?(accepted)
                #expect(result == [accepted ? [original] : []] && store.retiringTabIDs.isEmpty, "Original-item revalidation completes once and releases its reservation")
                #expect(((try tab(original, in: store)).archivedAt != nil) == accepted, "Only an unchanged original item follows accepted retirement into Archive")
            }
        }
    }

    @Test static func archiveNoOpDoesNotWriteOrReset() async throws {
        try await withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let selected = store.open("https://selected.example")
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let original = try Data(contentsOf: file)
            let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
            #expect(store.archiveExpiredTabs().isEmpty, "No eligible tabs must produce no archived IDs")
            store.refreshVisibleTabs([selected])
            store.setAutoArchiveInterval(.twelveHours, for: store.activeSpace.profileID)
            try await Task.sleep(nanoseconds: 400_000_000)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect(try attributes[.modificationDate] as? Date == oldDate && (try Data(contentsOf: file)) == original, "No-op checks, identical activity timestamps and unchanged policies must not rewrite the session")
        }
    }
}
