import Foundation
import Testing
@testable import ParcCore

enum TabPeekTestsSupport {
    final class FakePage {
        let identifier: String
        init(_ identifier: String) { self.identifier = identifier }
    }

    struct FakeWindow {
        var pane: FakePage?
        var card: FakePage?
        var cardShown = false
        var exits = 0
        var created = 0

        mutating func apply(_ effects: [TabPeekSession.Effect]) {
            for effect in effects {
                switch effect {
                case .createPage:
                    #expect(pane == nil && card == nil, "a page is created only for a tab that has none")
                    created += 1
                    pane = FakePage("created-\(created)")
                case .presentPage(let id):
                    #expect(pane?.identifier == id && card == nil, "the card takes the tab's own page \(id)")
                    card = pane; pane = nil; cardShown = true
                case .returnPage(let id):
                    #expect(card?.identifier == id && pane == nil, "the tab gets back the page \(id) from the card")
                    pane = card; card = nil
                case .exit:
                    #expect(cardShown, "only a shown card plays the dismissal motion")
                    exits += 1
                case .finish:
                    #expect(card == nil, "a card is never removed while it still holds the tab's page")
                    cardShown = false
                }
            }
        }
    }

    static let id = UUID()

    static func liveSession() throws -> (page: FakePage, window: FakeWindow, session: TabPeekSession) {
        let original = FakePage("page-a")
        var window = FakeWindow(pane: original)
        let session = try #require(TabPeekSession(tabID: UUID(), plan: .present(original.identifier)))
        window.apply(session.opening)
        return (original, window, session)
    }
}
