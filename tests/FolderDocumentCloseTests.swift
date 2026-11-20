import AppKit

@main @MainActor
struct FolderDocumentCloseTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func files(_ directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for case let url as URL in FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
            where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[url.path.replacingOccurrences(of: directory.path, with: "")] = try Data(contentsOf: url)
        }
        return result
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-folder-documents-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Mixed", isExpanded: false)
        let nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: folder.id)
        let empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty", parentID: nested.id)
        let dataDirectory = root.appendingPathComponent("Profiles/" + profile.id.uuidString)
        let notesFolder = root.appendingPathComponent("Parc Notes")
        try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
        let noteURL = notesFolder.appendingPathComponent("Shared.md"), noteOriginal = Data("Original note\n".utf8)
        try noteOriginal.write(to: noteURL)
        let noteAvailable: @MainActor () throws -> Void = {
            guard FileManager.default.fileExists(atPath: noteURL.path) else { throw CocoaError(.fileNoSuchFile) }
        }
        let easels = try EaselStore(directory: dataDirectory.appendingPathComponent("Easels"))
        let easel = try easels.create(title: "Shared Easel")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try easel.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 1, y: 2, width: 30, height: 40), assetID: asset)
        try easel.perform("Original image") { $0.items = [image] }
        func tab(_ title: String, _ url: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title,
                kind: .pinned, folderID: nested.id, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }
        let n = tab("Note", InternalPage.note(noteURL).urlString)
        let e = tab("Easel", InternalPage.easel(easel.document.id).urlString)
        let w = tab("Web", "https://original.invalid/")
        var alias = n; alias.id = UUID(); alias.spaceID = away.id; alias.folderID = nil
        var easelAlias = e; easelAlias.id = UUID(); easelAlias.spaceID = away.id; easelAlias.folderID = nil
        let split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Original mixed split", spaceID: space.id,
            tabIDs: [n.id, w.id, e.id], orientation: .vertical, widthFactors: [0.2, 0.3, 0.5])
        var state = BrowserState(profiles: [profile], spaces: [space, away], activeSpaceID: space.id)
        state.tabs = [n,w,e,alias,easelAlias]; state.folders = [folder,nested,empty]; state.splitLayouts = [split]
        state.selectedTabIDs = split.tabIDs; state.selectionBySpace = [space.id.uuidString: split.tabIDs]
        let sessionURL = root.appendingPathComponent("session.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: sessionURL)
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let initial = store.state, originalData = try files(dataDirectory)
        let target = FolderRemovalTarget(folderID: folder.id, spaceID: space.id, profileID: profile.id, state: initial)!
        let documents = [n.id: SidebarDocumentReference(page: .note(noteURL), profileID: profile.id, validate: noteAvailable),
            e.id: SidebarDocumentReference(page: .easel(easel.document.id), profileID: profile.id) { try easels.validateReference(easel.document.id) }]
        try check(target.tabs.count == 3 && target.groups == [split], "Mixed subtree retains complete original typed split")
        try check(!SidebarDocumentReference.validates(target.tabs, references: [:]), "Internal URLs alone cannot authorize document references")
        var wrong = documents
        wrong[n.id] = SidebarDocumentReference(page: .note(noteURL), profileID: UUID(), validate: noteAvailable)
        try check(!SidebarDocumentReference.validates(target.tabs, references: wrong), "Exact original Profile is required")
        wrong = documents; wrong[w.id] = documents[n.id]
        try check(!SidebarDocumentReference.validates(target.tabs, references: wrong), "Ordinary page cannot acquire a typed capability")
        var requested: Set<UUID> = [], authorize: (() -> Bool)?, finish: ((Bool) -> Void)?, calls = 0
        store.requestPageRetirement = { ids, admission, done in requested = ids; authorize = admission; finish = done; calls += 1 }
        var result: Result<Bool, Error>?, record: FolderDeletionUndo?
        store.deleteFolder(target, shouldCommit: { true }) { result = $0 }
        try check((try result?.get()) == false && calls == 0 && store.state == initial, "Missing capability refuses before any native retirement")
        let selection = FolderRemovalSelection.resolve(target: target, state: initial, selected: split.tabIDs, focused: e.id, available: { _ in true })!
        func remove(_ t: FolderRemovalTarget) {
            result = nil
            store.deleteFolder(t, selection: selection, documents: documents, shouldCommit: { true }, didCommit: { record = $0 }) { result = $0 }
        }
        remove(target)
        try check(requested == Set(split.tabIDs) && result == nil && store.state == initial, "Whole original set awaits genuine close callback")
        finish?(false)
        try check((try result?.get()) == false && store.state == initial && files(dataDirectory) == originalData, "Close refusal preserves hierarchy, references and all document bytes")
        remove(target)
        let movedNote = notesFolder.appendingPathComponent("Moved away.md")
        try FileManager.default.moveItem(at: noteURL, to: movedNote)
        try check(authorize?() == false, "Original document becomes unavailable during consent")
        finish?(false); try FileManager.default.moveItem(at: movedNote, to: noteURL)
        try check(store.state == initial && record == nil, "Expired typed capability cannot publish or register Undo")
        remove(target)
        try check(authorize?() == true, "Recovered original owners authorize actual close")
        finish?(true)
        let undo = record!
        try check((try result?.get()) == true && store.state.folders.isEmpty, "Approved ordinary Delete removes the exact complete tree")
        try check(store.state.tabs.filter { $0.archivedAt != nil }.map(\.id) == [n.id,w.id,e.id], "Only original subtree aliases are archived")
        try check(store.state.tabs.first { $0.id == alias.id } == alias && store.state.tabs.first { $0.id == easelAlias.id } == easelAlias, "Aliases in another Space remain untouched")
        try check(try files(dataDirectory) == originalData && Data(contentsOf: noteURL) == noteOriginal, "Delete writes no Note/Easel content or asset")
        try check(undo.focusedTabID == e.id && undo.groups == [split] && undo.folders.map(\.id).contains(empty.id), "Undo retains focus, exact split geometry and empty descendants")
        try check(undo.documentsAreAvailable && store.canUndoFolderDeletion(undo), "Exact typed Undo is admitted")
        try check(FileManager.default.fileExists(atPath: noteURL.path) && easels.load(easel.document.id) === easel, "Shared documents retain original identity after alias archive")
        try Data("Edited through surviving alias\n".utf8).write(to: noteURL)
        try easel.perform("Shared image edit") { $0.items[0].frame.x = 17 }
        let changedData = try files(dataDirectory), archived = store.state
        let manager = FolderUndoManager(), operation = FolderUndoOperation(undo)
        let entry = FolderUndoManager.Entry(name: undo.actionName,
            isValid: { direction in direction == .undo ? store.canUndoFolderDeletion(operation.record) : operation.record.redoTarget(in: store.state) != nil },
            isAvailable: { _ in operation.record.documentsAreAvailable },
            perform: { direction, done in
                if direction == .undo { done((try? store.undoFolderDeletion(operation.record, shouldCommit: { true })) == true) }
                else if let redo = operation.record.redoTarget(in: store.state) {
                    store.deleteFolder(redo, documents: operation.record.documentReferences, shouldCommit: { true }, didCommit: { operation.record = $0 }) { done((try? $0.get()) == true) }
                } else { done(false) }
            })
        try check(manager.append(entry) && manager.canUndo, "Real native Undo stack accepts committed mixed close")
        let assetURL = try easel.assetURL(asset)
        try FileManager.default.removeItem(at: assetURL)
        try check(!manager.canUndo && store.canUndoFolderDeletion(undo), "Missing asset disables, but does not prune, structurally valid Undo")
        try check(try !store.undoFolderDeletion(undo, shouldCommit: { true }) && store.state == archived, "Direct Undo also refuses missing original content")
        try png.write(to: assetURL)
        try check(manager.canUndo, "Recovered original file restores retry eligibility")
        let sessionBytes = try Data(contentsOf: sessionURL)
        try FileManager.default.removeItem(at: sessionURL); try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: false)
        manager.undo()
        try check(manager.canUndo && !manager.canRedo && store.state == archived, "Real durable Undo failure preserves stack and exact archive state")
        try FileManager.default.removeItem(at: sessionURL); try sessionBytes.write(to: sessionURL)
        manager.undo()
        try check(manager.canRedo && !manager.canUndo, "One committed mixed Undo advances native stack")
        try check(target.tabs.allSatisfy { original in store.state.tabs.contains(original) } && store.state.splitLayouts.contains(split), "Original alias and whole-split identities return without URL replay")
        try check(store.state.folders == initial.folders && store.state.selectedTabIDs == archived.selectedTabIDs, "Tree returns; store does not steal another physical window's focus")
        try check(try files(dataDirectory) == changedData && String(contentsOf: noteURL, encoding: .utf8) == "Edited through surviving alias\n"
                  && easel.document.items[0].frame.x == 17, "Undo preserves shared edits and exact asset bytes")
        let beforeRedo = store.state, beforeCalls = calls
        manager.redo()
        try check(manager.isBusy && calls == beforeCalls + 1 && requested == Set(split.tabIDs), "Redo reenters actual whole-set consent")
        finish?(false)
        try check(manager.canRedo && store.state == beforeRedo, "Redo refusal remains retryable")
        manager.redo(); try check(authorize?() == true, "Redo revalidates typed original content")
        finish?(true)
        try check(manager.canUndo && store.state.tabs.filter { $0.archivedAt != nil }.count == 3, "Accepted Redo archives same original aliases")
        store.requestPageRetirement = { _, admission, done in done(admission()) }
        var deletedError: Error?
        store.deleteLocalDocument(.note(noteURL), profileID: profile.id, ownerValid: { true }, deleteDocument: {
            try FileManager.default.removeItem(at: noteURL)
        }, completion: { deletedError = $0 })
        try check(deletedError == nil && !undo.documentsAreAvailable && !store.canUndoFolderDeletion(undo), "Actual Library document deletion invalidates old alias Undo")
        try check(!manager.canUndo && !(try store.undoFolderDeletion(undo, shouldCommit: { true })), "Old cache cannot restore a deleted original Note")
        try check(try Data(contentsOf: assetURL) == png && easels.load(easel.document.id) === easel, "Unrelated Easel and its original image remain")
        print("\(count) mixed-folder document close assertions passed")
    }
}
