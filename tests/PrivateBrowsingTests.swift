import Foundation

@main struct PrivateBrowsingChecks {
    @MainActor static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ParcPrivateChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let normal = try BrowserStore(directory: root)
        let normalID = normal.openResolvedURL(URL(string: "https://normal.example.test/")!)
        normal.updateTab(normalID, title: "Normal", url: "https://normal.example.test/visited")
        try normal.save()
        let originalState = normal.state
        let session = root.appendingPathComponent("session.json")
        let originalBytes = try Data(contentsOf: session)
        let parent = normal.activeSpace.profileID
        let enginePath = normal.independentEngineProfilePath(for: parent)
        let privateStore = BrowserStore(privateParentProfileID: parent, engineProfilePath: enginePath,
            directory: root, settings: normal.state.settings)
        expect(privateStore.isEphemeral && privateStore.privateParentProfileID == parent, "explicit original parent identity")
        expect(privateStore.state.tabs.isEmpty && privateStore.state.history.isEmpty && privateStore.state.downloads.isEmpty, "normal data is not imported into private model")
        expect(privateStore.activeSpace.profileID != parent && privateStore.activeSpaceID != normal.activeSpaceID, "private app identities are distinct from normal persisted objects")
        expect(privateStore.independentEngineProfilePath(for: privateStore.activeSpace.profileID) == enginePath, "explicit context path identifies the original parent without inventing an OTR disk profile")
        let id = privateStore.openResolvedURL(URL(string: "https://private.example.test/")!)
        privateStore.updateTab(id, title: "Private", url: "https://private.example.test/visited")
        expect(privateStore.state.tabs.count == 1 && privateStore.state.history.isEmpty, "private navigation remains an active in-memory tab without a history entry")
        var approve: (() -> Bool)?
        var finish: ((Bool) -> Void)?
        privateStore.requestPageRetirement = { ids, shouldCommit, completion in
            expect(ids == [id], "retirement targets the original private tab")
            approve = shouldCommit; finish = completion
        }
        var closed: Bool?
        privateStore.closeTabs([id], completion: { closed = $0 })
        expect(closed == nil && privateStore.state.tabs.contains { $0.id == id }, "close preserves private tab while native approval is pending")
        finish?(false)
        expect(closed == false && privateStore.state.tabs.contains { $0.id == id }, "refused beforeunload retains the private tab")
        privateStore.closeTabs([id], completion: { closed = $0 })
        expect(approve?() == true, "native approval revalidates the exact pending private transaction")
        finish?(true)
        expect(closed == true && privateStore.state.tabs.isEmpty, "approved close discards the private object")
        expect(privateStore.archivedTabs.isEmpty && privateStore.state.recentlyClosedIDs.isEmpty, "private close never enters Archive or restore history")
        try privateStore.saveSettingsSelection(pane: "general", profileID: nil)
        try privateStore.saveProfileName(privateStore.activeSpace.profileID, expectedName: "Incognito", name: "Memory only")
        try privateStore.save()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let resultingBytes = try Data(contentsOf: session)
        expect(resultingBytes == originalBytes, "explicit and delayed saves preserve the normal session bytes")
        expect(normal.state == originalState, "normal in-memory state is untouched")
        let adopted = privateStore.adoptNativePage(url: URL(string: "https://private.example.test/popup"), title: "Original popup", profilePath: enginePath, preferredSpaceID: privateStore.activeSpaceID, select: false)
        expect(adopted != nil && privateStore.state.tabs.last?.profileID == privateStore.activeSpace.profileID, "native-created page adopts the exact private model profile")
        expect(privateStore.adoptNativePage(url: nil, title: "", profilePath: enginePath + "-different", preferredSpaceID: privateStore.activeSpaceID, select: false) == nil, "foreign native parent path cannot be adopted")
        let absent = root.appendingPathComponent("must-not-be-created")
        let second = BrowserStore(privateParentProfileID: parent, engineProfilePath: enginePath,
            directory: absent, settings: normal.state.settings)
        _ = second.openResolvedURL(URL(string: "https://private.example.test/second")!)
        try second.save()
        expect(!FileManager.default.fileExists(atPath: absent.path), "ephemeral model initialization and save create no storage")
        expect(second.activeSpaceID != privateStore.activeSpaceID && second.activeSpace.profileID != privateStore.activeSpace.profileID, "physical private windows have distinct app-model identities")
        let context = normal.applicationContext(from: privateStore, spaceID: privateStore.activeSpaceID)
        expect(context?.profileID == parent && context?.spaceID == normal.activeSpaceID, "private application commands resolve the explicit normal parent and an actual normal Space")
        expect(context?.profileID != privateStore.activeSpace.profileID, "temporary private profile identity never escapes into application Settings")
        expect(privateStore.applicationContext(from: normal, spaceID: normal.activeSpaceID) == nil, "ephemeral store cannot become the application preference owner")
        let foreign = try BrowserStore(directory: root.appendingPathComponent("foreign"))
        expect(normal.applicationContext(from: foreign, spaceID: foreign.activeSpaceID) == nil, "another persistent store is not silently substituted")
        let stale = BrowserStore(privateParentProfileID: UUID(), engineProfilePath: enginePath,
            directory: absent, settings: normal.state.settings)
        expect(normal.applicationContext(from: stale, spaceID: stale.activeSpaceID) == nil, "missing original parent does not fall back to Default")
        let unassigned = normal.createProfile(name: "Unassigned")
        let unassignedPrivate = BrowserStore(privateParentProfileID: unassigned,
            engineProfilePath: normal.independentEngineProfilePath(for: unassigned), directory: absent, settings: normal.state.settings)
        let unassignedContext = normal.applicationContext(from: unassignedPrivate, spaceID: unassignedPrivate.activeSpaceID)
        expect(unassignedContext?.profileID == unassigned && unassignedContext?.spaceID == nil, "unassigned real profile remains a Settings owner without inventing a Space")
        let pending = try normal.stageProfileRemoval(unassigned, expectedName: "Unassigned", confirmation: "Unassigned")
        expect(normal.applicationContext(from: unassignedPrivate, spaceID: unassignedPrivate.activeSpaceID) == nil, "retiring original parent is rejected before app command dispatch")
        try normal.cancelProfileRemoval(pending)
        let privateSnapshot = privateStore.state
        try normal.saveSettingsSelection(pane: "Profiles", profileID: parent)
        expect(privateStore.state == privateSnapshot, "application Settings writes do not mutate the ephemeral session")
        let reloaded = try BrowserStore(directory: root)
        expect(reloaded.state.settings.settingsProfileID == parent, "explicit application Settings persistence belongs to the actual normal store")
        print("\(checks) private browsing model assertions passed; no browser or real profile used.")
    }
}
