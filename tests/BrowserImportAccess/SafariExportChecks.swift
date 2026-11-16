import AppKit

private func storedZip(_ entries: [(String, String)]) -> Data {
    var archive = [UInt8](), central = [UInt8]()
    func put<T: FixedWidthInteger>(_ value: T, _ bytes: inout [UInt8]) {
        for index in 0..<MemoryLayout<T>.size { bytes.append(UInt8(truncatingIfNeeded: value >> (8 * index))) }
    }
    func crc(_ data: [UInt8]) -> UInt32 {
        var value: UInt32 = 0xFFFF_FFFF
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        }
        return value ^ 0xFFFF_FFFF
    }
    for (name, text) in entries {
        let data = Array(text.utf8), path = Array(name.utf8), offset = UInt32(archive.count), sum = crc(data)
        put(UInt32(0x0403_4B50), &archive); put(UInt16(20), &archive); put(UInt16(0x0800), &archive)
        put(UInt16(0), &archive); put(UInt32(0), &archive); put(sum, &archive)
        put(UInt32(data.count), &archive); put(UInt32(data.count), &archive)
        put(UInt16(path.count), &archive); put(UInt16(0), &archive)
        archive += path + data
        put(UInt32(0x0201_4B50), &central); put(UInt16(0x031E), &central); put(UInt16(20), &central)
        put(UInt16(0x0800), &central); put(UInt16(0), &central); put(UInt32(0), &central); put(sum, &central)
        put(UInt32(data.count), &central); put(UInt32(data.count), &central); put(UInt16(path.count), &central)
        for _ in 0..<4 { put(UInt16(0), &central) }
        put(UInt32(0), &central); put(offset, &central)
        central += path
    }
    let start = UInt32(archive.count)
    archive += central
    put(UInt32(0x0605_4B50), &archive); put(UInt32(0), &archive)
    put(UInt16(entries.count), &archive); put(UInt16(entries.count), &archive)
    put(UInt32(central.count), &archive); put(start, &archive); put(UInt16(0), &archive)
    return Data(archive)
}

private func historyJSON(_ address: String) -> String {
    #"{"metadata":{"browser_name":"Safari","data_type":"history","schema_version":1},"history":[{"url":"\#(address)","time_usec":1751296375691668,"visit_count":1}]}"#
}

@MainActor
func safariExportChecks(window: NSWindow, safari: PCNativeImportSource) throws -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), message)
    }
    func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent("ParcExportChecks-" + UUID().uuidString)
    defer { try? files.removeItem(at: directory) }
    _ = ImportedBrowserDataFailures.take()
    let root = directory.appendingPathComponent("SafariExportRoot")
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    let abandoned = root.appendingPathComponent("ParcSafariExport-abandoned")
    try files.createDirectory(at: abandoned, withIntermediateDirectories: true)
    try files.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: abandoned.path)
    let opening = root.appendingPathComponent("ParcSafariExport-opening")
    try files.createDirectory(at: opening, withIntermediateDirectories: true)
    func leftovers() -> [String] {
        ((try? files.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasPrefix("ParcSafariExport-") }
    }
    let store = try BrowserStore(directory: directory.appendingPathComponent("SafariExportStore"))
    let destination = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
    PCNativeBrowserApplication.acceptsBrowserImport = true
    defer { PCNativeBrowserApplication.acceptsBrowserImport = false }
    PCNativeBrowserApplication.browserCompletions.removeAll(); PCNativeBrowserApplication.passwordRequests.removeAll()
    PCNativeBrowserApplication.exportRequests.removeAll()
    func start() -> BrowserImportCoordinator {
        let coordinator = BrowserImportCoordinator(store: store, destination: destination, window: window,
            onboarding: true, safariExportRoot: root, ownerIsCurrent: { true })
        coordinator.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([safari])
        coordinator.selectSourceInline(safari)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(
            profiles: [PCNativeImportProfile("Safari", [], .restricted)], access: .restricted))
        return coordinator
    }
    func save(_ name: String, _ data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name); try data.write(to: url); return url
    }
    let archive = try save("Safari Export.zip", storedZip([
        ("Safari Export/Bookmarks.html", """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DT><H3 id="BookmarksBar">Favorites</H3>
            <DL><p>
            <DT><A HREF="https://kept.example.test/">Kept</A>
            </DL><p>
            """),
        ("Safari Export/Passwords.csv", "Title,URL,Username,Password,Notes,OTPAuth\nExample,https://kept.example.test/,me,secret,,\n"),
        ("Safari Export/History.json", historyJSON("https://default.example.test/")),
        ("Safari Export/History - Work.json", historyJSON("https://work.example.test/")),
        ("Safari Export/PaymentCards.json", #"{"metadata":{"data_type":"payment_cards"},"payment_cards":[]}"#),
    ]))

    let coordinator = start()
    expect(coordinator.stage == .profiles && coordinator.canChooseSafariExport,
           "Choosing Safari, even without Full Disk Access, can take Safari's export file instead")
    coordinator.importSafariExport(directory.appendingPathComponent("Passwords.csv"))
    expect(coordinator.stage == .profiles && coordinator.error != nil && PCNativeBrowserApplication.exportRequests.isEmpty,
           "Only a .zip file is accepted as Safari's export")
    coordinator.importSafariExport(archive)
    expect(coordinator.stage == .loading, "Opening the export shows the loading state")
    wait { !PCNativeBrowserApplication.exportRequests.isEmpty }
    let request = PCNativeBrowserApplication.exportRequests.removeFirst()
    expect(request.names == ["Safari", "Work"] && request.directories.count == 2,
           "The default Safari Profile comes first and the named one follows")
    expect(!files.fileExists(atPath: abandoned.path) && files.fileExists(atPath: opening.path) && leftovers().count == 2,
           "Opening an export clears an old interrupted import's folder but not one another import may still be opening")
    try files.removeItem(at: opening)
    request.complete(.init(profiles: [
        PCNativeImportProfile("export-default", [.history], .complete, name: "Safari", directory: "profile-0"),
        PCNativeImportProfile("export-work", [.history], .complete, name: "Work", directory: "profile-1")], access: .complete))
    expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.count == 1
           && coordinator.bookmarkPages[0].destination == destination,
           "The export's bookmarks become the usual bookmark page for the original Space")
    expect(coordinator.passwordDestination == nil && coordinator.stage != .safariPasswords,
           "Passwords from the export need no password page")
    expect(coordinator.setupPage == .bookmarks && coordinator.setupPagesAhead.isEmpty,
           "Setup counts the export's bookmarks page and no password page")
    expect(PCNativeBrowserApplication.passwordRequests.count == 1
           && PCNativeBrowserApplication.passwordRequests[0].path == store.independentEngineProfilePath(for: destination.profileID),
           "The export's passwords go to the original Profile through the native CSV importer")
    let passwords = PCNativeBrowserApplication.passwordRequests.removeFirst()
    expect(files.fileExists(atPath: passwords.url.path) && PCNativeBrowserApplication.browserCompletions.isEmpty
           && coordinator.hasBackgroundWork, "History waits until the passwords have the original Profile to themselves")
    let work = store.state.profiles.first { $0.name == "Work" }
    expect(work != nil, "The named Safari Profile gets its own Parc Profile")
    coordinator.commitBookmarks()
    expect(coordinator.stage == .importing && coordinator.message == "Importing your Safari passwords…"
           && store.state.tabs.contains { $0.url == "https://kept.example.test/" },
           "Accepting the bookmarks first saves them and keeps the import open until the passwords are in")
    expect(coordinator.setupPage == .progress && coordinator.setupPagesAhead.isEmpty,
           "Waiting on the export's passwords is a progress page with nothing after it")
    passwords.complete(.init(outcome: .completed, importedCount: 1))
    expect(coordinator.stage == .finished, "The import finishes once the passwords are in")
    expect(!files.fileExists(atPath: passwords.url.path), "Parc deletes its copy of the passwords as soon as they're in")
    expect(PCNativeBrowserApplication.browserCompletions.count == 2, "Each Safari Profile's history then imports")
    let requests = PCNativeBrowserApplication.browserRequests.suffix(2)
    expect(requests.map(\.path) == [store.independentEngineProfilePath(for: destination.profileID),
                                    store.independentEngineProfilePath(for: work!.id)]
           && requests.allSatisfy { $0.categories == [.history] },
           "The default Profile's history goes to the original Profile and Work's to its own")
    expect(leftovers().count == 1, "The export folder stays while its history is still being read")
    while !PCNativeBrowserApplication.browserCompletions.isEmpty {
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
    }
    wait { leftovers().isEmpty }
    expect(leftovers().isEmpty && !coordinator.hasBackgroundWork, "The export folder is removed once its import ends")
    expect(ImportedBrowserDataFailures.take() == nil, "A clean export import reports no failure")
    coordinator.cancel()

    let partial = start()
    partial.importSafariExport(try save("Passwords only.zip", storedZip([
        ("Passwords.csv", "Title,URL,Username,Password,Notes,OTPAuth\nExample,https://only.example.test/,me,secret,,\n")])))
    wait { !PCNativeBrowserApplication.passwordRequests.isEmpty }
    expect(PCNativeBrowserApplication.exportRequests.isEmpty && partial.stage == .importing && partial.hasBackgroundWork,
           "An export with only passwords stays on its progress page while they import, with no bookmark step")
    PCNativeBrowserApplication.passwordRequests.removeFirst().complete(.init(outcome: .partial, importedCount: 1, invalidCount: 1))
    expect(partial.stage == .finished, "The passwords-only import finishes when its passwords are done")
    wait { leftovers().isEmpty }
    expect(ImportedBrowserDataFailures.take() == .partial, "A partly imported password file shows the import failure notice")
    partial.cancel()

    let stopped = start()
    stopped.importSafariExport(try save("Stopped.zip", storedZip([
        ("Passwords.csv", "Title,URL,Username,Password,Notes,OTPAuth\nExample,https://stop.example.test/,me,secret,,\n")])))
    wait { !PCNativeBrowserApplication.passwordRequests.isEmpty }
    let stoppedPasswords = PCNativeBrowserApplication.passwordRequests.removeFirst()
    stopped.stopImport()
    expect(stoppedPasswords.lease.cancelled && stopped.stage == .finished, "Stop Import cancels the export's password import")
    stoppedPasswords.complete(.init(outcome: .cancelled, importedCount: 0))
    wait { leftovers().isEmpty }
    expect(leftovers().isEmpty && ImportedBrowserDataFailures.take() == nil,
           "A stopped export leaves no folder and isn't reported as a failure")
    stopped.cancel()

    let closed = start()
    closed.importSafariExport(try save("Closed.zip", storedZip([
        ("Passwords.csv", "Title,URL,Username,Password,Notes,OTPAuth\nExample,https://closed.example.test/,me,secret,,\n")])))
    wait { !PCNativeBrowserApplication.passwordRequests.isEmpty }
    PCNativeBrowserApplication.passwordRequests.removeFirst().complete(.init(outcome: .cancelled, importedCount: 0))
    wait { leftovers().isEmpty }
    expect(closed.stage == .finished && ImportedBrowserDataFailures.take() == .failed,
           "Passwords lost because the window closed, not because of Stop, show the import failure notice")
    closed.cancel()

    let broken = start()
    broken.importSafariExport(try save("Broken.zip", Data("not a zip".utf8)))
    wait { broken.stage != .loading }
    expect(broken.stage == .profiles && broken.error?.contains("Export Browsing Data") == true && leftovers().isEmpty,
           "A file that isn't Safari's export returns to the browser choice with an explanation")
    broken.cancel()

    let abandonedImport = start()
    abandonedImport.importSafariExport(archive)
    abandonedImport.cancel()
    wait { leftovers().isEmpty && PCNativeBrowserApplication.exportRequests.isEmpty }
    expect(leftovers().isEmpty && PCNativeBrowserApplication.exportRequests.isEmpty,
           "Closing the import while the export opens leaves no folder behind")
    return checks
}
