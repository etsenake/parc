import Foundation
import Testing
@testable import ParcCore

struct ExternalSplitDropDocumentsAndRejectionTests {
    private typealias Fixture = ExternalSplitDropTestsSupport.Fixture

    struct DocumentCase: Sendable, CustomTestStringConvertible {
        let isNote: Bool
        let isFavorite: Bool
        var testDescription: String { (isNote ? "note " : "easel ") + (isFavorite ? "favorite" : "pinned") }
        static let all = [DocumentCase(isNote: true, isFavorite: true), DocumentCase(isNote: true, isFavorite: false),
                          DocumentCase(isNote: false, isFavorite: true), DocumentCase(isNote: false, isFavorite: false)]
    }

    @MainActor private struct SharedDocument {
        let reference: SidebarDocumentReference
        let address: String

        init(_ f: Fixture, note: Bool) throws {
            if note {
                let file = f.root.appendingPathComponent("Shared Note.md")
                try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
                try Data().write(to: file)
                reference = SidebarDocumentReference(page: .note(file), profileID: f.profile) {
                    guard FileManager.default.fileExists(atPath: file.path) else { throw CocoaError(.fileNoSuchFile) }
                }
                address = InternalPage.note(file).urlString
            } else {
                let easels = try EaselStore(directory: f.root.appendingPathComponent("easels"))
                let easel = try easels.create()
                reference = SidebarDocumentReference(page: .easel(easel.document.id), profileID: f.profile) { try easels.validateReference(easel.document.id) }
                address = "parc://easel/" + easel.document.id.uuidString
            }
        }
    }

    @MainActor private func documentStore(_ f: Fixture, _ item: DocumentCase) throws -> (BrowserStore, SharedDocument) {
        let document = try SharedDocument(f, note: item.isNote)
        var state = item.isFavorite ? f.favorite() : f.pinned()
        state.tabs[f.aIndex].url = document.address
        state.tabs[f.aIndex].savedURL = document.address
        let directory = try f.session(state, item.testDescription.replacingOccurrences(of: " ", with: "-"))
        return (try BrowserStore(directory: directory), document)
    }

    @MainActor @Test(arguments: DocumentCase.all)
    func aTypedSavedHomeNeedsTheOriginalDocumentToBeValidated(_ item: DocumentCase) throws {
        let f = try Fixture()
        let (store, _) = try documentStore(f, item)
        #expect(try !f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical, savedHomeID: f.homeID))
    }

    @MainActor @Test(arguments: DocumentCase.all)
    func anUnvalidatedDocumentAliasPublishesNothing(_ item: DocumentCase) throws {
        let f = try Fixture()
        let (store, _) = try documentStore(f, item)
        let before = store.state
        _ = try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical, savedHomeID: f.homeID)
        #expect(store.state == before)
    }

    @MainActor @Test(arguments: DocumentCase.all)
    func aValidatedTypedSavedHomeCommits(_ item: DocumentCase) throws {
        let f = try Fixture()
        let (store, document) = try documentStore(f, item)
        #expect(try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical,
                             savedHomeID: f.homeID, documents: [f.a: document.reference]))
    }

    @MainActor @Test(arguments: DocumentCase.all)
    func theTypedOriginalAndItsHomeShareTheSameDocument(_ item: DocumentCase) throws {
        let f = try Fixture()
        let (store, document) = try documentStore(f, item)
        _ = try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical,
                         savedHomeID: f.homeID, documents: [f.a: document.reference])
        #expect(store.state.tabs.first { $0.id == f.homeID }?.url == document.address)
        #expect(store.state.tabs.first { $0.id == f.a }?.url == document.address)
    }

    @MainActor @Test func aSplitKeepsItsCustomTitleAndIconWhenAURLReplacesAPane() throws {
        let f = try Fixture()
        var decorated = f.original
        var decoratedGroup = f.group
        decoratedGroup.customTitle = "Original group"
        decoratedGroup.customIcon = .emoji("🌙")
        decorated.splitLayouts = [decoratedGroup]
        let preserved = try #require(f.proposal(decorated, .replace(0), [f.a, f.b], decoratedGroup))
        #expect(preserved.splitLayouts.first?.customTitle == decoratedGroup.customTitle)
        #expect(preserved.splitLayouts.first?.customIcon == decoratedGroup.customIcon)
    }

    @MainActor @Test func replacingAPaneLeavesLocalDocumentReferencesUntouched() throws {
        let f = try Fixture()
        var documents = f.original
        documents.tabs[0].url = "parc://note/" + UUID().uuidString
        documents.tabs[0].savedURL = documents.tabs[0].url
        documents.tabs[1].url = "parc://easel/" + UUID().uuidString
        documents.tabs[1].savedURL = documents.tabs[1].url
        let replacement = try #require(f.proposal(documents, .replace(1), [f.a, f.b], f.group))
        #expect(replacement.tabs.first { $0.id == f.b } == documents.tabs.first { $0.id == f.b })
        #expect(replacement.tabs.first { $0.id == f.a }?.url == documents.tabs.first { $0.id == f.a }?.url)
    }

    @MainActor @Test func anOriginalFromAnotherProfileRefuses() throws {
        let f = try Fixture()
        var moved = f.original
        moved.tabs[0].profileID = UUID()
        #expect(f.proposal(moved, .insert(1), [f.a, f.b], f.group) == nil)
    }

    @MainActor @Test func anArchivedOriginalRefuses() throws {
        let f = try Fixture()
        var archived = f.original
        archived.tabs[0].archivedAt = Date()
        #expect(f.proposal(archived, .insert(1), [f.a, f.b], f.group) == nil)
    }

    enum OutOfRangeTarget: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case insertion = "Insertion after the last pane"
        case replacement = "Replacement before the first pane"

        var testDescription: String { rawValue }
        var target: SplitDropTarget { self == .insertion ? .insert(8) : .replace(-1) }
    }

    @MainActor @Test(arguments: OutOfRangeTarget.allCases)
    func anOutOfRangeTargetRefuses(_ position: OutOfRangeTarget) throws {
        let f = try Fixture()
        #expect(f.proposal(f.original, position.target, [f.a, f.b], f.group) == nil)
    }

    @MainActor @Test func aFailedWriteKeepsTheOriginalStateAndReportsTheError() throws {
        let f = try Fixture()
        let current = f.store.state, currentGroup = try #require(f.store.activeSplitLayout)
        try f.store.save()
        try f.breakWrites(in: f.root)
        #expect(throws: (any Error).self) {
            _ = try f.commit(f.store, selection: current.selectedTabIDs, layout: currentGroup, target: .insert(0))
        }
        #expect(f.store.state == current)
        #expect(f.store.persistenceError != nil)
    }
}
