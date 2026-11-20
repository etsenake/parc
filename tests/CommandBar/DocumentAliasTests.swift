import Foundation

@main @MainActor
struct DocumentAliasTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func rejects(_ message: String, _ body: () throws -> Void) throws {
        count += 1; do { try body() } catch { return }
        throw NSError(domain: "Expected refusal: " + message, code: 1)
    }
    static func files(_ directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let values = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in values where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[url.path.replacingOccurrences(of: directory.path, with: "")] = try Data(contentsOf: url)
        }
        return result
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-document-alias-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space = BrowserSpace(id: UUID(), name: "Source", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Mixed", isExpanded: false)
        let destination = BrowserFolder(id: UUID(), spaceID: away.id, name: "Destination")
        let profileDirectory = root.appendingPathComponent("Profiles/" + profile.id.uuidString)
        let notesFolder = root.appendingPathComponent("Parc Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesFolder.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        let easels = try EaselStore(directory: profileDirectory.appendingPathComponent("Easels"))
        let easel = try easels.create(title: "Original Easel")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        try png.write(to: notesFolder.appendingPathComponent("Attachments/pixel.png"))
        let noteURL = InternalPage.noteFile(notesFolder.appendingPathComponent("Original Note.md"))!
        let noteBytes = Data("# Plans\n\n![pixel](Attachments/pixel.png)\n".utf8)
        try noteBytes.write(to: noteURL)
        let validateNote: @MainActor () throws -> Void = {
            guard FileManager.default.fileExists(atPath: noteURL.path) else { throw CocoaError(.fileNoSuchFile) }
        }
        let inline = EaselRichText.Image(data: png, fileType: "public.png", width: 1, height: 1)
        let richText = EaselRichText(runs: [.init(location: 0, length: 1, attributes: .init(font: .init(name: "Helvetica", size: 15), ink: "#252525FF", image: inline))])
        let asset = try easel.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 5, y: 10, width: 100, height: 80), assetID: asset)
        let rich = EaselItem(kind: .text, frame: .init(x: 30, y: 50, width: 120, height: 100), text: "\u{fffc}", richText: richText)
        let browser = EaselItem(kind: .browser, frame: .init(x: 40, y: 90, width: 300, height: 200), url: "https://original.invalid/")
        try easel.perform("Original content") { $0.items = [image, rich, browser] }
        func tab(_ title: String, _ url: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title,
                kind: .pinned, folderID: folder.id, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }
        let noteTab = tab("Note", InternalPage.note(noteURL).urlString)
        let easelTab = tab("Easel", InternalPage.easel(easel.document.id).urlString)
        let webTab = tab("Web", "https://saved.invalid/")
        let split = BrowserSplitLayout(sidebarAnchorID: noteTab.id, customTitle: "Mixed split", spaceID: space.id,
            tabIDs: [noteTab.id, easelTab.id], orientation: .vertical, widthFactors: [0.3, 0.7])
        var state = BrowserState(profiles: [profile], spaces: [space, away], activeSpaceID: space.id)
        state.folders = [folder, destination]; state.tabs = [noteTab, easelTab, webTab]; state.splitLayouts = [split]
        state.selectedTabIDs = split.tabIDs; state.selectionBySpace = [space.id.uuidString: split.tabIDs]
        let sessionURL = root.appendingPathComponent("session.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: sessionURL)
        let store = try BrowserStore(directory: root)
        let initial = store.state
        let noteReference = SidebarDocumentReference(page: .note(noteURL), profileID: profile.id, validate: validateNote)
        let easelReference = SidebarDocumentReference(page: .easel(easel.document.id), profileID: profile.id) { try easels.validateReference(easel.document.id) }
        let urls = [noteTab.id: noteTab.savedURL, easelTab.id: easelTab.savedURL, webTab.id: "https://materialized.invalid/"]
        let references = [noteTab.id: noteReference, easelTab.id: easelReference]
        let sources = SidebarCopySources(destinations: urls, documents: references)
        try check(sources.validates(initial.tabs), "Original typed stores validate the complete mixed set")
        try check(!SidebarCopySources(destinations: urls).validates(initial.tabs), "A local URL alone is not a typed reference")
        var wrong = references
        wrong[noteTab.id] = SidebarDocumentReference(page: .note(noteURL), profileID: UUID(), validate: validateNote)
        try check(!SidebarCopySources(destinations: urls, documents: wrong).validates(initial.tabs), "Same file in another Profile cannot authorize a reference")
        var wrongURLs = urls; wrongURLs[noteTab.id] = InternalPage.easel(easel.document.id).urlString
        try check(!SidebarCopySources(destinations: wrongURLs, documents: references).validates(initial.tabs), "Typed destination cannot change the document or its kind")
        wrongURLs = urls; wrongURLs[webTab.id] = noteTab.savedURL
        try check(!SidebarCopySources(destinations: wrongURLs, documents: references).validates(initial.tabs), "Ordinary web item cannot turn into a document reference")
        let originalFiles = try files(profileDirectory), originalNoteFiles = try files(notesFolder)
        let originalEasel = easel.document
        let target = FolderDuplicateTarget(folderID: folder.id, spaceID: space.id, profileID: profile.id, state: initial)!
        let result = try store.duplicateFolder(target, destinations: urls, documents: references)!
        let copied = result.tabIDs.compactMap { id in store.state.tabs.first { $0.id == id } }
        try check(copied.count == 3 && Set(result.tabIDs).isDisjoint(with: initial.tabs.map(\.id)), "Fresh sidebar identities cover the full mixed tree")
        try check(copied.map(\.savedURL) == target.tabs.map { urls[$0.id]! }, "Actual typed documents and real web destination stay separate")
        try check(copied.contains { InternalPage(urlString: $0.url)?.noteURL.flatMap(InternalPage.noteFile) == noteURL }, "Note alias points at the very same file")
        try check(copied.contains { InternalPage(urlString: $0.url)?.easelID == originalEasel.id }, "Easel alias retains exact document ID")
        try check(result.openTabIDs.isEmpty, "Typed split children never create renderer pages")
        let copiedSplit = store.state.splitLayouts.first { $0.id != split.id }!
        try check(copiedSplit.widthFactors == split.widthFactors && copiedSplit.orientation == split.orientation, "Typed alias split preserves its actual layout")
        try check(try files(profileDirectory) == originalFiles && files(notesFolder) == originalNoteFiles,
                  "Alias transaction writes no note, attachment or asset files")
        try check(easel.document == originalEasel, "Original Easel session and revision are untouched")
        try check(store.state.tabs.prefix(initial.tabs.count).elementsEqual(initial.tabs), "Original sidebar records untouched")
        try check(store.state.selectedTabIDs == initial.selectedTabIDs, "Original selection does not become an alias")
        let aliasFiles = Set(store.state.tabs.compactMap { InternalPage(urlString: $0.savedURL)?.noteURL.flatMap(InternalPage.noteFile)?.path })
        try check(aliasFiles == [noteURL.path], "Every Note alias shares the one original file")
        try check(try easels.load(originalEasel.id) === easel, "Easel aliases share the real original session")
        let editedBytes = Data("# Plans, shared\n\n![pixel](Attachments/pixel.png)\n".utf8)
        try editedBytes.write(to: noteURL)
        try easel.perform("Shared change") { $0.items[0].frame.x += 10 }
        try check(try Data(contentsOf: noteURL) == editedBytes, "Original Note edits are what every alias opens")
        try check(try easels.load(originalEasel.id).document.items[0].frame.x == 15, "Original Easel edits are visible through alias session")
        try check(try Data(contentsOf: easel.assetURL(asset)) == png, "Same original PNG bytes remain owned")
        try check(try Data(contentsOf: notesFolder.appendingPathComponent("Attachments/pixel.png")) == png, "The shared Note's attachment stays put")
        try check(try easels.load(originalEasel.id).document.items.map(\.id) == originalEasel.items.map(\.id), "Easel content and embedded-page object IDs are shared, not cloned")
        let source = CommandBarFolderMoveSource(items: [.folder(folder.id)], spaceID: space.id, profileID: profile.id, state: store.state)!
        let move = CommandBarFolderMove.snapshot(source: source, state: store.state).first { $0.folder.folderID == destination.id }!
        let command = try store.copyCommandBarItemsToFolder(move, destinations: urls, documents: references)!
        try check(command.tabs.count == 3 && command.openTabIDs.isEmpty, "Contextual folder copy shares typed references and lazy ordinary children")
        try check(command.tabs.allSatisfy { $0.spaceID == away.id && $0.profileID == profile.id }, "Same-profile destination Space owns all fresh records")
        let reloaded = try BrowserStore(directory: root)
        try check(command.tabIDs.allSatisfy { id in reloaded.state.tabs.contains { $0.id == id } }, "Typed alias sidebar IDs survive real disk reload")
        try check(try Data(contentsOf: noteURL) == editedBytes, "Reopened alias reads the same original Note file")
        let stable = store.state, stableFiles = try files(profileDirectory)
        let freshSource = CommandBarFolderMoveSource(items: [.folder(folder.id)], spaceID: space.id, profileID: profile.id, state: stable)!
        let fresh = CommandBarFolderMove.snapshot(source: freshSource, state: stable).first { $0.folder.folderID == destination.id }!
        let sessionBytes = try Data(contentsOf: sessionURL)
        try FileManager.default.removeItem(at: sessionURL)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: false)
        try rejects("real sidebar save failure") { _ = try store.copyCommandBarItemsToFolder(fresh, destinations: urls, documents: references) }
        try check(store.state == stable && files(profileDirectory) == stableFiles, "Failed sidebar save publishes no aliases and mutates no documents")
        try FileManager.default.removeItem(at: sessionURL); try sessionBytes.write(to: sessionURL)
        let movedAside = notesFolder.appendingPathComponent("Moved aside.md")
        try FileManager.default.moveItem(at: noteURL, to: movedAside)
        try check(!noteReference.isCurrent(), "A Note file that went missing invalidates the captured capability")
        try check(try store.copyCommandBarItemsToFolder(fresh, destinations: urls, documents: references) == nil && store.state == stable, "A missing member refuses all mixed copies before persistence")
        try FileManager.default.moveItem(at: movedAside, to: noteURL)
        try check(noteReference.isCurrent(), "The returned Note file permits a fresh validation")
        let assetURL = try easel.assetURL(asset), assetBytes = try Data(contentsOf: assetURL)
        try FileManager.default.removeItem(at: assetURL)
        try check(!easelReference.isCurrent(), "Missing original asset rejects Easel reference")
        try assetBytes.write(to: assetURL)
        try check(easelReference.isCurrent(), "Recovered original asset permits a fresh validation")
        let blocked = easel.observeReplacement { _ in false }
        try rejects("shared embedded owner veto") { try easels.delete(originalEasel.id) }
        try check(easelReference.isCurrent(), "Deletion refusal preserves every alias's original document")
        easel.removeReplacementObserver(blocked)
        let noteIDs = Set(store.state.tabs.filter { InternalPage(urlString: $0.savedURL) == .note(noteURL) }.map(\.id))
        var requested: Set<UUID> = [], didDelete = false, deleteError: Error?
        store.requestPageRetirement = { ids, _, done in requested = ids; done(false) }
        let beforeDelete = store.state
        store.deleteLocalDocument(.note(noteURL), profileID: profile.id, ownerValid: { true }, deleteDocument: {
            didDelete = true; try FileManager.default.removeItem(at: noteURL)
        }, completion: { deleteError = $0 })
        try check(requested == noteIDs && noteIDs.count == 3, "Document deletion retires every original and copied alias across Spaces")
        try check(deleteError != nil && !didDelete && store.state == beforeDelete && noteReference.isCurrent(), "One retirement refusal preserves all aliases and the shared document")
        store.requestPageRetirement = { ids, authorize, done in requested = ids; done(authorize()) }
        let beforeDeleteBytes = try Data(contentsOf: sessionURL)
        try FileManager.default.removeItem(at: sessionURL)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: false)
        deleteError = nil
        store.deleteLocalDocument(.note(noteURL), profileID: profile.id, ownerValid: { true }, deleteDocument: {
            didDelete = true; try FileManager.default.removeItem(at: noteURL)
        }, completion: { deleteError = $0 })
        try check(deleteError != nil && !didDelete && store.state == beforeDelete && noteReference.isCurrent(), "Alias-removal save failure keeps document retryable and all model references intact")
        try FileManager.default.removeItem(at: sessionURL); try beforeDeleteBytes.write(to: sessionURL)
        deleteError = nil
        store.deleteLocalDocument(.note(noteURL), profileID: profile.id, ownerValid: { true }, deleteDocument: {
            didDelete = true; try FileManager.default.removeItem(at: noteURL)
        }, completion: { deleteError = $0 })
        try check(deleteError == nil && didDelete && requested == noteIDs, "Approved whole-set deletion removes the one shared file")
        try check(store.state.tabs.allSatisfy { !noteIDs.contains($0.id) }, "Document deletion removes every alias and preserves unrelated records")
        try check(store.state.tabs.filter { InternalPage(urlString: $0.savedURL)?.easelID == originalEasel.id }.count == 3, "Deleting Note aliases preserves the other typed document aliases")
        try check(try BrowserStore(directory: root).state.tabs.allSatisfy { !noteIDs.contains($0.id) }, "Whole-set alias deletion survives actual disk reload")
        try check(!noteReference.isCurrent() && !FileManager.default.fileExists(atPath: noteURL.path), "The deleted file invalidates every Note alias capability")
        try easels.delete(originalEasel.id)
        try check(!easelReference.isCurrent(), "Actual Easel deletion invalidates every alias capability")
        try rejects("deleted shared session cannot edit") { try easel.perform("Not allowed") { $0.title = "Resurrected" } }
        try check(try Data(contentsOf: assetURL) == png, "Existing shared asset retention policy remains unchanged by document deletion")
        print("\(count) document-alias assertions passed")
    }
}
