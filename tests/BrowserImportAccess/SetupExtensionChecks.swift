import AppKit

@MainActor
func setupExtensionChecks(directory: URL) throws -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), message)
    }
    struct Refusal: Error {}
    while ImportedExtensionFailures.take() != nil {}
    PCNativeBrowserApplication.setupChanges = []
    func next() -> PCNativeBrowserApplication.SetupChange { PCNativeBrowserApplication.setupChanges.removeFirst() }
    let store = try BrowserStore(directory: directory.appendingPathComponent("SetupExtensions"))
    let destination = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
    let work = store.createProfile(name: "Work")
    let home = store.state.profiles.first { $0.id == destination.profileID }?.name ?? ""

    func shown(_ notice: ImportedExtensionFailures.Notice?) -> [String] {
        notice?.failures.map { $0.name + ($0.profile.map { " @ " + $0 } ?? "") } ?? []
    }
    var admitted = false
    SetupExtensionChanges.addICloudPasswords(to: destination, store: store, connects: { admitted })
    let refused = ImportedExtensionFailures.take()
    expect(PCNativeBrowserApplication.setupChanges.isEmpty && shown(refused) == ["iCloud Passwords"] && refused?.canRetry == false,
           "When Apple's helper won't admit Parc, nothing is installed and the notice offers no pointless Retry")
    admitted = true
    SetupExtensionChanges.addICloudPasswords(to: destination, store: store, connects: { admitted })
    let install = next()
    expect(install.kind == "iCloud Passwords" && install.path == store.independentEngineProfilePath(for: destination.profileID),
           "An admitted install goes to the chosen Profile")
    install.complete(nil)
    expect(ImportedExtensionFailures.pending.isEmpty, "A successful install says nothing")
    SetupExtensionChanges.addICloudPasswords(to: destination, store: store, connects: { admitted })
    next().complete(Refusal())
    let failedInstall = ImportedExtensionFailures.take()
    expect(shown(failedInstall) == ["iCloud Passwords"] && failedInstall?.canRetry == true,
           "A failed install can be retried from its notice")
    failedInstall?.retry()
    let retried = next()
    expect(retried.kind == "iCloud Passwords" && PCNativeBrowserApplication.setupChanges.isEmpty,
           "Retry runs the same install again, once")
    retried.complete(Refusal())
    let again = ImportedExtensionFailures.take()
    expect(again?.canRetry == true, "A retry that fails again brings back a notice that can retry")
    admitted = false
    again?.retry()
    let refusedNow = ImportedExtensionFailures.take()
    expect(PCNativeBrowserApplication.setupChanges.isEmpty && shown(refusedNow) == ["iCloud Passwords"] && refusedNow?.canRetry == false,
           "If Apple's helper starts refusing Parc, Retry installs nothing and the notice drops Retry")

    ImportedExtensionFailures.record(.init(name: "uBlock Origin Lite"))
    SetupExtensionChanges.addAdBlocker(to: destination, store: store)
    next().complete(Refusal())
    let imported = ImportedExtensionFailures.take(), blocker = ImportedExtensionFailures.take()
    expect(shown(imported) == ["uBlock Origin Lite"] && imported?.canRetry == false
           && shown(blocker) == ["uBlock Origin Lite"] && blocker?.canRetry == true,
           "The same name failing during the import and in setup stays two notices, and only setup's offers Retry")
    blocker?.retry()
    expect(next().kind == "uBlock Origin", "Retry asks for uBlock Origin again, with its Lite fallback")

    let adBlock = "gighmmpiobklfepjocnamgkkbiglidom", chromeAdBlock = "cfhdojbkjhnklbpkdaibdccddilifddb"
    let ghostery = "mlomiejdfkolichcflejclcbmpeaniij"
    let names = [adBlock: "AdBlock", chromeAdBlock: "AdBlock", ghostery: "Ghostery"]
    SetupExtensionChanges.removeAdBlockers([destination.profileID: [adBlock, chromeAdBlock], work: [chromeAdBlock, ghostery],
                                            UUID(): [adBlock]], names: names, store: store)
    let removals = PCNativeBrowserApplication.setupChanges
    PCNativeBrowserApplication.setupChanges = []
    expect(removals.map(\.kind) == ["remove", "remove", "remove", "remove"]
           && removals.map(\.identifiers) == [[chromeAdBlock], [adBlock], [chromeAdBlock], [ghostery]]
           && removals.map(\.path) == [destination.profileID, destination.profileID, work, work]
                .map(store.independentEngineProfilePath(for:)),
           "Each blocker is removed from each existing Profile on its own")
    store.renameProfile(work, name: "Office")
    removals.forEach { $0.complete(Refusal()) }
    let stayed = ImportedExtensionFailures.take()
    expect(shown(stayed) == ["AdBlock @ " + home, "AdBlock @ " + home, "AdBlock @ Office", "Ghostery"]
           && stayed?.canRetry == true && ImportedExtensionFailures.take() == nil,
           "A blocker that stayed in several Profiles names each by its name when it failed, a single one names none, and no copy is lost")
    stayed?.retry()
    expect(PCNativeBrowserApplication.setupChanges.map(\.identifiers) == [[chromeAdBlock], [adBlock], [chromeAdBlock], [ghostery]],
           "Retry removes every copy again from the Profile it stayed in")
    PCNativeBrowserApplication.setupChanges.forEach { $0.complete(nil) }
    PCNativeBrowserApplication.setupChanges = []
    expect(ImportedExtensionFailures.pending.isEmpty, "Removals that succeed on retry say nothing")
    SetupExtensionChanges.removeAdBlockers([work: [adBlock, chromeAdBlock]], names: names, store: store)
    PCNativeBrowserApplication.setupChanges.forEach { $0.complete(Refusal()) }
    PCNativeBrowserApplication.setupChanges = []
    expect(shown(ImportedExtensionFailures.take()) == ["AdBlock", "AdBlock"],
           "Two copies of one blocker in a single Profile don't name it")
    SetupExtensionChanges.removeAdBlockers([work: [ghostery]], names: names, store: store)
    next().complete(PCNativeRestrictedExtensionError(restriction: .otherApp))
    SetupExtensionChanges.addAdBlocker(to: destination, store: store)
    next().complete(PCNativeRestrictedExtensionError(restriction: .administrator))
    SetupExtensionChanges.addAdBlocker(to: destination, store: store)
    next().complete(Refusal())
    let kept = ImportedExtensionFailures.take(), blocked = ImportedExtensionFailures.take()
    let retryable = ImportedExtensionFailures.take()
    expect(kept?.failures.map(\.reason) == [.otherApp] && kept?.failures.map(\.change) == [.removal] && kept?.canRetry == false
           && blocked?.failures.map(\.reason) == [.administrator] && blocked?.canRetry == false
           && shown(retryable) == ["uBlock Origin Lite"] && retryable?.canRetry == true && ImportedExtensionFailures.take() == nil,
           "Changes another app or the administrator rules out get notices of their own that say so, without Retry")

    let lab = store.createProfile(name: "Lab")
    SetupExtensionChanges.removeAdBlocker(adBlock, named: "AdBlock", from: lab, namingProfile: false, store: store)
    next().complete(Refusal())
    let leaving = ImportedExtensionFailures.take()
    _ = try store.stageProfileRemoval(lab, expectedName: "Lab")
    leaving?.retry()
    expect(leaving?.canRetry == true && PCNativeBrowserApplication.setupChanges.isEmpty,
           "Retry leaves alone a Profile that is on its way out")
    let gone = store.createProfile(name: "Gone")
    _ = try store.stageProfileRemoval(gone, expectedName: "Gone")
    expect(SetupExtensionChanges.removableProfiles([destination.profileID, gone, UUID(), work], in: store.state)
           == [destination.profileID, work], "Profiles that are gone or on their way out are left alone")
    SetupExtensionChanges.removeAdBlocker(adBlock, named: "AdBlock", from: gone, namingProfile: false, store: store)
    expect(PCNativeBrowserApplication.setupChanges.isEmpty, "Nothing is removed from a Profile on its way out")
    return checks
}
