import Foundation

package struct EaselPage: Codable, Equatable, Identifiable {
    package static let maximumCount = 100
    package static let maximumNameLength = 100
    package static let maximumNameBytes = 4096
    package static let dividerName = "-"

    package var id: UUID
    package var name: String

    package init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

package struct EaselPageChange: Equatable {
    package var document: EaselDocument
    package var page: UUID?
    package var items: Set<UUID> = []
}

package enum EaselPages {
    package static let firstPageName = "Page 1"

    package static func pages(in document: EaselDocument) -> [EaselPage] { document.pages ?? [] }

    package static func firstPageID(_ document: EaselDocument) -> UUID? { document.pages?.first?.id }

    package static func pageID(of item: EaselItem, in document: EaselDocument) -> UUID? { item.page ?? firstPageID(document) }

    package static func isOnPage(_ item: EaselItem, _ page: UUID?, first: UUID?) -> Bool {
        guard let page, page != first else { return item.page == nil || item.page == first }
        return item.page == page
    }

    package static func items(on page: UUID?, in document: EaselDocument) -> [EaselItem] {
        guard document.pages != nil else { return document.items }
        let first = firstPageID(document)
        return document.items.filter { isOnPage($0, page, first: first) }
    }

    package static func itemCount(on page: UUID?, in document: EaselDocument) -> Int {
        guard document.pages != nil else { return document.items.count }
        let first = firstPageID(document)
        return document.items.reduce(0) { $0 + (isOnPage($1, page, first: first) ? 1 : 0) }
    }

    package static func isDivider(_ page: EaselPage, in document: EaselDocument) -> Bool {
        page.name == EaselPage.dividerName && itemCount(on: page.id, in: document) == 0
    }

    package static func contentPages(_ document: EaselDocument) -> [EaselPage] {
        pages(in: document).filter { !isDivider($0, in: document) }
    }

    package static func resolvedPage(_ page: UUID?, in document: EaselDocument) -> UUID? {
        guard let pages = document.pages else { return nil }
        if let page, let match = pages.first(where: { $0.id == page }), !isDivider(match, in: document) { return page }
        return contentPages(document).first?.id ?? pages.first?.id
    }

    package static func page(_ id: UUID?, in document: EaselDocument) -> EaselPage? {
        guard let id = resolvedPage(id, in: document) else { return nil }
        return document.pages?.first { $0.id == id }
    }

    package static func view(_ document: EaselDocument, page: UUID?) -> EaselDocument {
        guard document.pages != nil else { return document }
        var view = document
        view.items = items(on: resolvedPage(page, in: document), in: document)
        return view
    }

    package static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= EaselPage.maximumNameLength
            && name.utf8.count <= EaselPage.maximumNameBytes
            && !name.unicodeScalars.contains { $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0) }
    }

    package static func validationProblem(_ document: EaselDocument) -> String? {
        var ids = Set<UUID>()
        if let pages = document.pages {
            guard !pages.isEmpty, pages.count <= EaselPage.maximumCount else { return "page count" }
            for page in pages {
                guard ids.insert(page.id).inserted else { return "duplicate page ID" }
                guard isValidName(page.name) else { return "page name" }
            }
            guard !contentPages(document).isEmpty else { return "every page is a divider" }
        }
        for item in document.items {
            guard let page = item.page else { continue }
            guard ids.contains(page) else { return "object on a missing page" }
        }
        return nil
    }
}
