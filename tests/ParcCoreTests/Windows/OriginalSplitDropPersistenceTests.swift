import Foundation
import Testing
@testable import ParcCore

struct OriginalSplitDropPersistenceTests {
    private typealias Fixture = OriginalSplitDropTestsSupport.Fixture

    @MainActor @Test func aSavedSplitTransactionCommitsThroughTheStore() throws {
        let f = try Fixture()
        #expect(f.store.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home]))
    }

    @MainActor @Test func theHomeAndGroupPersistTogether() throws {
        let f = try Fixture()
        _ = f.store.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home])
        let disk = try BrowserStore(directory: f.root)
        #expect(disk.state.tabs.contains { $0.id == f.home })
        #expect(disk.state.selectedTabIDs == [f.a, f.b])
    }

    @MainActor private func groupedStore(_ f: Fixture) -> BrowserSplitLayout {
        _ = f.store.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home])
        return f.store.activeSplitLayout!
    }

    @MainActor @Test func aSaveFailureRefusesTheCommit() throws {
        let f = try Fixture()
        let current = groupedStore(f)
        _ = try f.breakWrites()
        #expect(!f.store.dropTabIntoSplit(f.c, expectedSelection: [f.a, f.b], expectedLayout: current,
            target: .insert(2), orientation: .horizontal, savedHomeIDs: [f.c: f.bHome]))
    }

    @MainActor @Test func aSaveFailureKeepsTheOriginalRecordsAndSelection() throws {
        let f = try Fixture()
        let current = groupedStore(f)
        let before = f.store.state
        _ = try f.breakWrites()
        _ = f.store.dropTabIntoSplit(f.c, expectedSelection: [f.a, f.b], expectedLayout: current,
            target: .insert(2), orientation: .horizontal, savedHomeIDs: [f.c: f.bHome])
        #expect(f.store.state == before)
        #expect(f.store.persistenceError != nil)
    }

    @MainActor @Test func retryingAfterASaveFailureCreatesExactlyOneHome() throws {
        let f = try Fixture()
        let current = groupedStore(f)
        let saved = try f.breakWrites()
        _ = f.store.dropTabIntoSplit(f.c, expectedSelection: [f.a, f.b], expectedLayout: current,
            target: .insert(2), orientation: .horizontal, savedHomeIDs: [f.c: f.bHome])
        try f.restoreWrites(saved)
        #expect(f.store.dropTabIntoSplit(f.c, expectedSelection: [f.a, f.b], expectedLayout: current,
            target: .insert(2), orientation: .horizontal, savedHomeIDs: [f.c: f.bHome]))
        #expect(f.store.state.tabs.filter { $0.id == f.bHome }.count == 1)
    }

    @MainActor private func typedStore(_ f: Fixture, note: Bool) throws -> (BrowserStore, SidebarDocumentReference, String) {
        let reference: SidebarDocumentReference
        let address: String
        if note {
            let file = f.root.appendingPathComponent("Shared Note.md")
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
        var typed = f.pinned()
        typed.tabs[f.aIndex].url = address
        typed.tabs[f.aIndex].savedURL = address
        return (try BrowserStore(directory: f.session(typed, "alias")), reference, address)
    }

    enum DocumentKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case note = "Note"
        case easel = "Easel"

        var testDescription: String { rawValue }
    }

    @MainActor @Test(arguments: DocumentKind.allCases)
    func aTypedOriginalRequiresDocumentValidation(_ document: DocumentKind) throws {
        let f = try Fixture()
        let (model, _, _) = try typedStore(f, note: document == .note)
        #expect(!model.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home]))
    }

    @MainActor @Test(arguments: DocumentKind.allCases)
    func aMissingDocumentReceiptPublishesNoAlias(_ document: DocumentKind) throws {
        let f = try Fixture()
        let (model, _, _) = try typedStore(f, note: document == .note)
        let initial = model.state
        _ = model.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home])
        #expect(model.state == initial)
    }

    @MainActor @Test(arguments: DocumentKind.allCases)
    func aValidatedTypedOriginalCommits(_ document: DocumentKind) throws {
        let f = try Fixture()
        let (model, reference, _) = try typedStore(f, note: document == .note)
        #expect(model.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home], documents: [f.a: reference]))
    }

    @MainActor @Test(arguments: DocumentKind.allCases)
    func theTypedOriginalAndItsHomeShareTheAuthoredDocument(_ document: DocumentKind) throws {
        let f = try Fixture()
        let (model, reference, address) = try typedStore(f, note: document == .note)
        _ = model.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home], documents: [f.a: reference])
        #expect(model.state.tabs.first { $0.id == f.home }?.url == address)
        #expect(model.state.tabs.first { $0.id == f.a }?.url == address)
    }
}
