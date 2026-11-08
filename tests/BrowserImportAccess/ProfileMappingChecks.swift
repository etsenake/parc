import AppKit

@MainActor private final class StageLog { var stages: [BrowserImportCoordinator.Stage] = [] }

/// Every source profile starts ticked. The browser's main profile imports into
/// the Parc Profile import was opened from; each other one into a Parc Profile
/// of its name, made only when its turn comes. Neither flow has a destination step.
@MainActor
func profileMappingChecks(directory: URL, window: NSWindow) throws -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), message)
    }
    func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
    let accepted = PCNativeBrowserApplication.acceptsBrowserImport
    defer { PCNativeBrowserApplication.acceptsBrowserImport = accepted }
    PCNativeBrowserApplication.acceptsBrowserImport = true
    PCNativeBrowserApplication.browserCompletions = []
    func finishNext(_ bookmarks: [PCNativeImportedBookmark] = []) {
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed,
            bookmarks: bookmarks, warnings: [], error: nil))
    }
    /// Completes the background imports of every profile's other data.
    func drain() { while !PCNativeBrowserApplication.browserCompletions.isEmpty { finishNext() } }
    var requests: [PCNativeBrowserApplication.BrowserRequest] { PCNativeBrowserApplication.browserRequests }
    /// Each native import a source profile made since `start`, foreground and background.
    func paths(_ profile: PCNativeImportProfile, since start: Int) -> [String] {
        requests.dropFirst(start).filter { $0.profile === profile }.map(\.path)
    }
    let noPreferences = directory.appendingPathComponent("MappingNoArcPreferences.plist")
    func begin(_ name: String, onboarding: Bool, source: PCNativeImportSource, profiles: [PCNativeImportProfile],
               sidebar: URL? = nil, prepare: (BrowserStore) -> Void = { _ in }) throws
        -> (BrowserStore, BrowserImportDestination, BrowserImportCoordinator, StageLog) {
        let store = try BrowserStore(directory: directory.appendingPathComponent(name))
        prepare(store)
        let original = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
        let coordinator = BrowserImportCoordinator(store: store, destination: original, window: window,
            onboarding: onboarding, arcSidebarURL: sidebar ?? directory.appendingPathComponent("MappingNoArc/StorableSidebar.json"),
            arcPreferencesURL: noPreferences, ownerIsCurrent: { true })
        let log = StageLog()
        coordinator.onChange = { [unowned coordinator] in log.stages.append(coordinator.stage) }
        coordinator.discover()
        precondition(PCNativeBrowserApplication.sources.count == 1, "One source discovery is pending")
        PCNativeBrowserApplication.sources.removeFirst().complete([source])
        coordinator.selectSourceInline(source)
        precondition(PCNativeBrowserApplication.profiles.count == 1, "One profile discovery is pending")
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: profiles, access: .complete))
        return (store, original, coordinator, log)
    }

    let chrome = PCNativeImportSource("Google Chrome", directory.appendingPathComponent("Mapping Chrome.app"))
    let work = PCNativeImportProfile("chrome work", [.history, .bookmarks], .complete, name: "Work", directory: "Profile 1")
    let main = PCNativeImportProfile("chrome main", [.history, .bookmarks], .complete, name: "Josh", directory: "Default")
    let side = PCNativeImportProfile("chrome side", [.history, .bookmarks], .complete, name: "Side", directory: "Profile 2")
    let three = [work, main, side]

    var existingSide: UUID?
    let (store, original, windowImport, windowLog) = try begin("MappingWindow", onboarding: false, source: chrome,
        profiles: three, prepare: { existingSide = $0.createProfile(name: "SIDE") })
    let reused = existingSide!
    let originalPath = store.independentEngineProfilePath(for: original.profileID)
    expect(windowImport.selectedProfiles == Set(three.map(\.identifier)), "Every profile of the browser starts ticked")
    expect(windowImport.stage == .profiles && windowImport.canContinueSourceInline, "Next is ready with nothing more to choose")
    let profilesBefore = store.state.profiles, spacesBefore = store.state.spaces
    let start = requests.count
    windowImport.continueSourceInline()
    expect(windowImport.stage == .importing && requests.count == start + 1, "Next starts the import at once")
    expect(requests[start].profile === main && requests[start].path == originalPath,
           "The Default profile, though listed second, imports first into the Parc Profile import was opened from")
    expect(store.state.profiles == profilesBefore && store.state.spaces == spacesBefore,
           "No other profile's Parc Profile or Space exists before its turn")
    finishNext([PCNativeImportedBookmark("mapping main", title: "Main", url: URL(string: "https://example.test/main"))])
    let workProfile = store.state.profiles.first { $0.name == "Work" }
    expect(requests.count == start + 2 && requests[start + 1].profile === work && workProfile != nil
           && requests[start + 1].path == store.independentEngineProfilePath(for: workProfile!.id),
           "The next profile gets a new Parc Profile of its name when its turn comes")
    expect(store.state.spaces.contains { $0.profileID == workProfile!.id && $0.title == "Work" },
           "The new Profile has a Space of its name for its bookmarks")
    expect(store.state.profiles.count == profilesBefore.count + 1, "Only the profile being imported gets a Parc Profile")
    finishNext()
    let reusedPath = store.independentEngineProfilePath(for: reused)
    expect(requests.count == start + 3 && requests[start + 2].profile === side && requests[start + 2].path == reusedPath,
           "An unused Parc Profile of the same name, in any case, is reused")
    expect(store.state.profiles.count == profilesBefore.count + 1 && store.state.spaces.contains { $0.profileID == reused },
           "Reuse creates no Profile and adds only the Space its bookmarks need")
    finishNext([PCNativeImportedBookmark("mapping side", title: "Side", url: URL(string: "https://example.test/side"))])
    drain()
    expect(paths(main, since: start) == [originalPath, originalPath]
           && paths(work, since: start) == Array(repeating: store.independentEngineProfilePath(for: workProfile!.id), count: 2)
           && paths(side, since: start) == [reusedPath, reusedPath],
           "Each profile's bookmarks and its other data go to the same Parc Profile")
    expect(windowImport.stage == .bookmarks && windowImport.bookmarkPages.map(\.destination.profileID) == [original.profileID, reused]
           && windowImport.bookmarkPages.first?.destination == original,
           "Each profile's bookmarks go to its own Parc Profile; the main profile's to the original Space")
    expect(!windowLog.stages.contains(.destination), "The import window never shows a destination step")
    windowImport.cancel()

    let (setupStore, setupOriginal, setup, setupLog) = try begin("MappingSetup", onboarding: true, source: chrome, profiles: three)
    expect(setup.selectedProfiles == Set(three.map(\.identifier)), "Setup ticks every profile too")
    setup.selectProfile(work.identifier)
    expect(setup.selectedProfiles == [main.identifier, side.identifier], "One profile unticks on its own")
    let setupProfiles = setupStore.state.profiles.count, setupStart = requests.count
    setup.continueSourceInline()
    expect(setup.stage == .importing && requests.count == setupStart + 1 && requests[setupStart].profile === main
           && requests[setupStart].path == setupStore.independentEngineProfilePath(for: setupOriginal.profileID),
           "Setup imports the main profile into setup's own Profile")
    finishNext()
    let setupSide = setupStore.state.profiles.first { $0.name == "Side" }
    expect(requests.count == setupStart + 2 && requests[setupStart + 1].profile === side && setupSide != nil
           && requests[setupStart + 1].path == setupStore.independentEngineProfilePath(for: setupSide!.id),
           "Setup gives another ticked profile its own new Parc Profile")
    finishNext()
    drain()
    expect(setup.stage == .finished && paths(work, since: setupStart).isEmpty
           && setupStore.state.profiles.count == setupProfiles + 1 && !setupStore.state.profiles.contains { $0.name == "Work" },
           "An unticked profile is left behind with no Parc Profile and no import")
    expect(!setupLog.stages.contains(.destination), "Setup never shows a destination step")
    setup.cancel()

    let historyOnly = PCNativeImportProfile("chrome side history", [.history], .complete, name: "Side", directory: "Profile 2")
    let (otherStore, otherOriginal, other, otherLog) = try begin("MappingNoDefault", onboarding: false, source: chrome,
        profiles: [work, main, historyOnly])
    other.selectProfile(main.identifier)
    let otherStart = requests.count
    other.continueSourceInline()
    expect(other.stage == .importing && requests.count == otherStart + 1 && requests[otherStart].profile === work
           && requests[otherStart].path == otherStore.independentEngineProfilePath(for: otherOriginal.profileID),
           "Without Default, the first ticked profile imports into the original Profile")
    finishNext()
    drain()
    let otherSide = otherStore.state.profiles.first { $0.name == "Side" }
    expect(otherSide != nil && paths(historyOnly, since: otherStart) == [otherStore.independentEngineProfilePath(for: otherSide!.id)]
           && !otherStore.state.profiles.contains { $0.name == "Work" },
           "A profile with no bookmarks still gets its own Parc Profile; the original takes no Profile of the first one's name")
    expect(other.stage == .finished && !otherLog.stages.contains(.destination), "No destination step without Default either")
    other.cancel()

    let openedName = "Default"
    let workAgain = PCNativeImportProfile("chrome work again", [.history], .complete, name: "work", directory: "Profile 3")
    let namesake = PCNativeImportProfile("chrome namesake", [.history], .complete, name: openedName, directory: "Profile 4")
    let named = [main, work, workAgain, namesake]
    let (namesStore, namesOriginal, names, _) = try begin("MappingNames", onboarding: false, source: chrome, profiles: named)
    expect(namesStore.state.profiles.map(\.name) == [openedName], "The opened Profile has the name the namesake shares")
    let namesStart = requests.count
    names.continueSourceInline()
    drain()
    let namesPaths = named.map { Set(paths($0, since: namesStart)) }
    expect(namesPaths.allSatisfy { $0.count == 1 } && Set(namesPaths.map { $0.first! }).count == 4
           && namesPaths[0] == [namesStore.independentEngineProfilePath(for: namesOriginal.profileID)],
           "Profiles sharing a name, or named like the opened Profile, each get their own Parc Profile")
    expect(namesStore.state.profiles.filter { $0.name.caseInsensitiveCompare("Work") == .orderedSame }.count == 2
           && namesStore.state.profiles.filter { $0.name == openedName }.count == 2,
           "A Parc Profile already taken by this import is never reused by name")
    names.cancel()

    let sidebar = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../Fixtures/ArcSidebar/StorableSidebar.json").standardizedFileURL
    let arc = PCNativeImportSource(BrowserImportCoordinator.arcBundleIdentifier,
                                   directory.appendingPathComponent("Mapping Arc", isDirectory: true))
    let standard = PCNativeImportProfile("mapping arc standard", [.history, .bookmarks], .complete,
                                         name: "Person 1", directory: "Default")
    let arcSide = PCNativeImportProfile("mapping arc side", [.history, .bookmarks], .complete, name: "Side", directory: "Profile 1")
    let arcProjects = PCNativeImportProfile("mapping arc projects", [.history, .bookmarks], .complete,
                                            name: "Side Projects", directory: "Profile 2")
    let (arcStore, arcOriginal, arcSetup, arcLog) = try begin("MappingArc", onboarding: true, source: arc,
        profiles: [standard, arcSide, arcProjects], sidebar: sidebar)
    expect(arcSetup.selectedProfiles == [standard.identifier, arcSide.identifier, arcProjects.identifier],
           "Every Parc profile starts ticked")
    arcSetup.selectProfile(standard.identifier)
    let arcStart = requests.count, arcProfiles = arcStore.state.profiles.count
    arcSetup.continueSourceInline()
    wait { requests.count > arcStart }
    expect(arcSetup.stage == .importing && requests.count == arcStart + 1, "Next starts Arc's import at once")
    let projects = arcStore.state.profiles.first { $0.name == "Side Projects" }
    expect(arcStore.state.spaces.contains { $0.title == "Side" && $0.profileID == arcOriginal.profileID }
           && !arcStore.state.profiles.contains { $0.name == "Side" },
           "A custom Arc profile chosen first brings its Spaces into the original Profile")
    expect(!arcStore.state.spaces.contains { $0.title == "Work" }, "The unticked default Arc profile's Spaces stay behind")
    expect(projects != nil && arcStore.state.profiles.count == arcProfiles + 1
           && arcStore.state.tabs.contains { $0.kind == .favorite && $0.profileID == projects!.id },
           "Another Arc profile gets a Parc Profile of its name with its Favorites")
    let arcOriginalPath = arcStore.independentEngineProfilePath(for: arcOriginal.profileID)
    expect(requests[arcStart].profile === arcSide && requests[arcStart].path == arcOriginalPath,
           "The first chosen Arc profile's browser data imports into the original Profile")
    finishNext([PCNativeImportedBookmark("mapping arc", title: "Arc", url: URL(string: "https://example.test/arc"))])
    expect(requests.count == arcStart + 2 && requests[arcStart + 1].profile === arcProjects,
           "The other Arc profile imports next")
    finishNext()
    drain()
    let projectsPath = arcStore.independentEngineProfilePath(for: projects!.id)
    expect(paths(arcSide, since: arcStart) == [arcOriginalPath, arcOriginalPath]
           && paths(arcProjects, since: arcStart) == [projectsPath, projectsPath] && paths(standard, since: arcStart).isEmpty,
           "Each Arc profile's data imports into its own Parc Profile; the unticked one's not at all")
    expect(arcSetup.bookmarkPages.first?.destination == arcOriginal && !arcLog.stages.contains(.destination),
           "Arc's main bookmarks land in setup's Space, with no destination step")
    arcSetup.cancel()
    return checks
}
