import Foundation
import Combine
import ParcCore

@MainActor
package final class EaselPageSession {
    let base: EaselSession
    private(set) var page: UUID?
    var adoptedGroup: UUID?
    private var cache: (base: EaselDocument, page: UUID?, view: EaselDocument)?

    init(_ base: EaselSession, page: UUID? = nil) {
        self.base = base
        self.page = page
    }

    var fullDocument: EaselDocument { base.document }

    var currentPage: UUID? { EaselPages.resolvedPage(page, in: base.document) }

    package var document: EaselDocument {
        let full = base.document
        guard full.pages != nil else { return full }
        if let cache, cache.page == page, cache.base == full { return cache.view }
        let view = EaselPages.view(full, page: page)
        cache = (full, page, view)
        return view
    }

    var documentPublisher: Published<EaselDocument>.Publisher { base.$document }
    var isClosed: Bool { base.isClosed }
    var isDeleted: Bool { base.isDeleted }
    var canUndo: Bool { base.canUndo }
    var canRedo: Bool { base.canRedo }
    var undoDestination: EaselDocument? { base.undoDestination.map { EaselPages.view($0, page: page) } }
    var redoDestination: EaselDocument? { base.redoDestination.map { EaselPages.view($0, page: page) } }

    func show(_ next: UUID?) {
        page = next
        cache = nil
    }

    func view(of document: EaselDocument) -> EaselDocument { EaselPages.view(document, page: page) }

    func perform(_ name: String, coalescing group: UUID? = nil, _ mutation: (inout EaselDocument) throws -> Void) throws {
        let page = currentPage
        try base.perform(name, coalescing: group ?? adoptedGroup) { document in
            var view = EaselPages.view(document, page: page)
            try mutation(&view)
            document = EaselPages.merging(view, page: page, into: document)
        }
    }

    func performOnDocument(_ name: String, _ mutation: (inout EaselDocument) throws -> Void) throws {
        try base.perform(name, mutation)
    }

    var onFollow: ((UUID?) -> Void)?

    func undo() throws {
        let before = base.document
        try base.undo()
        follow(from: before)
    }

    func redo() throws {
        let before = base.document
        try base.redo()
        follow(from: before)
    }

    private func follow(from before: EaselDocument) {
        let after = base.document
        guard after.pages != nil || before.pages != nil else { return }
        let shown = EaselPages.resolvedPage(page, in: before)
        let target = EaselPages.followedPage(from: before, to: after, showing: shown)
        guard target != EaselPages.resolvedPage(page, in: after) || page != target else { return }
        onFollow?(target)
    }
    func assetData(_ id: String) throws -> Data { try base.assetData(id) }
    func assetURL(_ id: String) throws -> URL { try base.assetURL(id) }
    func importPNG(_ data: Data) throws -> String { try base.importPNG(data) }
    func importAsset(_ data: Data, type: EaselAssetType, fileExtension: String? = nil) throws -> String {
        try base.importAsset(data, type: type, fileExtension: fileExtension)
    }
    func discardUnusedAssets(_ ids: [String]) { base.discardUnusedAssets(ids) }
}
