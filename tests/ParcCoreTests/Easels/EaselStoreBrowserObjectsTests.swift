import Foundation
import Testing
@testable import ParcCore

struct EaselStoreBrowserObjectsTests {
    @MainActor @Test
    func aBrowserObjectPersistsItsIdentityAndAuthoredURL() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let browser = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/authored")
            try session.perform("Add webpage") { $0.items = [browser] }
            #expect(try! EaselStore(directory: directory).load(session.document.id).document.items == [browser], "Actual browser object persists original identity and authored URL")
        }
    }

    @MainActor @Test
    func refusedRetirementLeavesTheSavedBoardAndHistoryUntouched() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let browser = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/authored")
            try session.perform("Add webpage") { $0.items = [browser] }
            let live = true
            let guardID = session.observeReplacement { next in
                !live || next?.items.contains { $0.id == browser.id && $0.kind == .browser && $0.url == browser.url } == true
            }
            let original = session.document
            EaselStoreTestsSupport.expectThrows("Live page prevents object deletion") { try session.perform("Delete") { $0.items = [] } }
            EaselStoreTestsSupport.expectThrows("Live page prevents destructive URL replacement") { try session.perform("URL") { $0.items[0].url = "https://example.org/" } }
            EaselStoreTestsSupport.expectThrows("Live page prevents document deletion") { try store.delete(original.id) }
            EaselStoreTestsSupport.expectThrows("Undo cannot bypass actual page retirement") { try session.undo() }
            #expect(session.document == original && session.canUndo && !session.canRedo, "Refused retirement leaves exact document and history unchanged")
            #expect(try! EaselStore(directory: directory).load(original.id).document == original, "Refused retirement leaves durable bytes semantically unchanged")
            session.removeReplacementObserver(guardID)
        }
    }

    @MainActor @Test
    func movingAndUndoingLeaveTheLivePageIntact() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let browser = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/authored")
            try session.perform("Add webpage") { $0.items = [browser] }
            let live = true
            let guardID = session.observeReplacement { next in
                !live || next?.items.contains { $0.id == browser.id && $0.kind == .browser && $0.url == browser.url } == true
            }
            try session.perform("Move same page") { $0.items[0].frame.x += 20 }
            #expect(session.document.items[0].id == browser.id && session.document.items[0].url == browser.url, "Geometry editing keeps live original identity and URL")
            try session.undo()
            #expect(session.document.items == [browser], "Non-destructive undo remains usable while page is live")
            session.removeReplacementObserver(guardID)
        }
    }

    @MainActor @Test
    func closingThePageAllowsCreationUndoAndRedo() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let browser = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/authored")
            try session.perform("Add webpage") { $0.items = [browser] }
            var live = true
            let guardID = session.observeReplacement { next in
                !live || next?.items.contains { $0.id == browser.id && $0.kind == .browser && $0.url == browser.url } == true
            }
            live = false
            try session.undo()
            #expect(session.document.items.isEmpty && session.canRedo, "Actual closure permits pending creation undo")
            try session.redo()
            #expect(session.document.items == [browser], "Redo restores durable original without inventing live runtime identity")
            session.removeReplacementObserver(guardID)
        }
    }

    @MainActor @Test
    func retiringTheObserverAllowsBoardDeletion() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let browser = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/authored")
            try session.perform("Add webpage") { $0.items = [browser] }
            let live = true
            let guardID = session.observeReplacement { next in
                !live || next?.items.contains { $0.id == browser.id && $0.kind == .browser && $0.url == browser.url } == true
            }
            let original = session.document
            session.removeReplacementObserver(guardID)
            try store.delete(original.id)
            #expect(try! store.list().isEmpty, "Retired observer no longer blocks document deletion")
        }
    }

    @MainActor @Test
    func navigationPersistsTheURLWithoutMovingOrReplacingTheObject() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let item = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/start")
            try session.perform("Add webpage") { $0.items.append(item) }
            try session.perform("Move webpage") { $0.items[0].frame.x += 40 }
            let token = session.observeReplacement { next in
                guard let next = next?.items.first(where: { $0.id == item.id && $0.kind == .browser }), let url = next.url else { return false }
                return url == session.document.items[0].url || session.isRecordingBrowserNavigation(item.id, from: session.document.items[0].url!, to: url)
            }
            #expect(try! session.recordBrowserNavigation(URL(string: "https://example.com/actual")!, itemID: item.id, expectedURL: item.url!), "Actual URL updates original browser metadata")
            #expect(session.document.items[0].id == item.id && session.document.items[0].frame.x == EaselStoreTestsSupport.frame.x + 40, "URL observation preserves exact object geometry and identity")
            #expect(!session.isRecordingBrowserNavigation(item.id, from: item.url!, to: "https://example.com/actual"), "Navigation admission scope ends after publication")
            #expect(try! EaselStore(directory: directory).load(session.document.id).document.items[0].url == "https://example.com/actual", "Real observed URL survives reopen")
            session.removeReplacementObserver(token)
        }
    }

    @MainActor @Test
    func canvasUndoAndRedoKeepTheLatestObservedURL() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let item = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/start")
            try session.perform("Add webpage") { $0.items.append(item) }
            try session.perform("Move webpage") { $0.items[0].frame.x += 40 }
            let token = session.observeReplacement { next in
                guard let next = next?.items.first(where: { $0.id == item.id && $0.kind == .browser }), let url = next.url else { return false }
                return url == session.document.items[0].url || session.isRecordingBrowserNavigation(item.id, from: session.document.items[0].url!, to: url)
            }
            _ = try session.recordBrowserNavigation(URL(string: "https://example.com/actual")!, itemID: item.id, expectedURL: item.url!)
            try session.undo()
            #expect(session.document.items[0].frame == EaselStoreTestsSupport.frame && session.document.items[0].url == "https://example.com/actual", "Canvas Undo preserves latest real page URL without new navigation step")
            try session.redo()
            #expect(session.document.items[0].frame.x == EaselStoreTestsSupport.frame.x + 40 && session.document.items[0].url == "https://example.com/actual", "Canvas Redo preserves page URL metadata")
            session.removeReplacementObserver(token)
        }
    }

    @MainActor @Test
    func staleAndNonWebObservationsLeaveTheDocumentUntouched() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let item = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/start")
            try session.perform("Add webpage") { $0.items.append(item) }
            try session.perform("Move webpage") { $0.items[0].frame.x += 40 }
            let token = session.observeReplacement { next in
                guard let next = next?.items.first(where: { $0.id == item.id && $0.kind == .browser }), let url = next.url else { return false }
                return url == session.document.items[0].url || session.isRecordingBrowserNavigation(item.id, from: session.document.items[0].url!, to: url)
            }
            _ = try session.recordBrowserNavigation(URL(string: "https://example.com/actual")!, itemID: item.id, expectedURL: item.url!)
            let before = session.document
            #expect(!(try! session.recordBrowserNavigation(URL(string: "https://example.com/stale")!, itemID: item.id, expectedURL: item.url!)), "Stale source URL cannot overwrite original item")
            #expect(!(try! session.recordBrowserNavigation(URL(string: "file:///tmp/private")!, itemID: item.id, expectedURL: before.items[0].url!)), "Non-web observation is not persisted as an embedded navigation")
            #expect(session.document == before, "Rejected observation preserves complete document")
            session.removeReplacementObserver(token)
        }
    }

    @MainActor @Test
    func navigationApprovalDoesNotAllowDirectURLReplacement() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let item = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/start")
            try session.perform("Add webpage") { $0.items.append(item) }
            try session.perform("Move webpage") { $0.items[0].frame.x += 40 }
            let token = session.observeReplacement { next in
                guard let next = next?.items.first(where: { $0.id == item.id && $0.kind == .browser }), let url = next.url else { return false }
                return url == session.document.items[0].url || session.isRecordingBrowserNavigation(item.id, from: session.document.items[0].url!, to: url)
            }
            _ = try session.recordBrowserNavigation(URL(string: "https://example.com/actual")!, itemID: item.id, expectedURL: item.url!)
            EaselStoreTestsSupport.expectThrows("Direct replacement does not inherit observation approval") { try session.perform("Replace URL") { $0.items[0].url = "https://other.example/" } }
            session.removeReplacementObserver(token)
        }
    }

    @MainActor @Test
    func aPageOwnerCanRefuseNavigationMetadata() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let item = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/start")
            try session.perform("Add webpage") { $0.items.append(item) }
            try session.perform("Move webpage") { $0.items[0].frame.x += 40 }
            let token = session.observeReplacement { next in
                guard let next = next?.items.first(where: { $0.id == item.id && $0.kind == .browser }), let url = next.url else { return false }
                return url == session.document.items[0].url || session.isRecordingBrowserNavigation(item.id, from: session.document.items[0].url!, to: url)
            }
            _ = try session.recordBrowserNavigation(URL(string: "https://example.com/actual")!, itemID: item.id, expectedURL: item.url!)
            let before = session.document
            let refusal = session.observeReplacement { _ in false }
            EaselStoreTestsSupport.expectThrows("Another original page owner can refuse metadata publication") { _ = try session.recordBrowserNavigation(URL(string: "https://example.com/refused")!, itemID: item.id, expectedURL: before.items[0].url!) }
            #expect(session.document == before, "Refusal keeps original durable state")
            session.removeReplacementObserver(refusal)
            session.removeReplacementObserver(token)
        }
    }

    @MainActor @Test
    func aFailedNavigationSaveClearsApprovalAndKeepsTheDocument() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let item = EaselItem(kind: .browser, frame: EaselStoreTestsSupport.frame, url: "https://example.com/start")
            try session.perform("Add webpage") { $0.items.append(item) }
            try session.perform("Move webpage") { $0.items[0].frame.x += 40 }
            let token = session.observeReplacement { next in
                guard let next = next?.items.first(where: { $0.id == item.id && $0.kind == .browser }), let url = next.url else { return false }
                return url == session.document.items[0].url || session.isRecordingBrowserNavigation(item.id, from: session.document.items[0].url!, to: url)
            }
            _ = try session.recordBrowserNavigation(URL(string: "https://example.com/actual")!, itemID: item.id, expectedURL: item.url!)
            let before = session.document
            let documentFile = EaselStoreTestsSupport.file(directory, session.document.id)
            try FileManager.default.removeItem(at: documentFile)
            try FileManager.default.createDirectory(at: documentFile, withIntermediateDirectories: false)
            EaselStoreTestsSupport.expectThrows("Failed URL save does not publish") { _ = try session.recordBrowserNavigation(URL(string: "https://example.com/failed")!, itemID: item.id, expectedURL: before.items[0].url!) }
            #expect(session.document == before && !session.isRecordingBrowserNavigation(item.id, from: before.items[0].url!, to: "https://example.com/failed"), "Failed persistence retires approval and preserves original")
            session.removeReplacementObserver(token)
        }
    }
}
