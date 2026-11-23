import AppKit
import Testing
@testable import ParcNotes

@MainActor
struct NoteMenuListPressTests {
    private func list(_ ids: [String]) -> (NoteMenuList, () -> [String]) {
        let list = NoteMenuList()
        list.fixedWidth = 273
        list.maximumHeight = 2000
        var activated: [String] = []
        list.onActivate = { activated.append($0.id) }
        list.setItems(ids.map { NoteMenuList.Item(id: $0, title: $0.uppercased()) }, keepingHighlight: false)
        return (list, { activated })
    }

    private func centre(of index: Int, in list: NoteMenuList) throws -> NSPoint {
        let frame = try #require(list.frame(forItem: index))
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    @Test func aPressFollowsItsRowWhenTheListRefreshesUnderIt() throws {
        let (list, activated) = list(["a", "b", "c"])
        list.pointerDown(at: try centre(of: 1, in: list))
        list.setItems(["new", "a", "b", "c"].map { NoteMenuList.Item(id: $0, title: $0) }, keepingHighlight: true)
        list.pointerUp(at: try centre(of: 2, in: list))
        #expect(activated() == ["b"])
    }

    @Test func aPressOnARowThatDisappearsActivatesNothing() throws {
        let (list, activated) = list(["a", "b", "c"])
        list.pointerDown(at: try centre(of: 1, in: list))
        list.setItems(["a", "c"].map { NoteMenuList.Item(id: $0, title: $0) }, keepingHighlight: true)
        list.pointerUp(at: try centre(of: 1, in: list))
        #expect(activated().isEmpty)
    }
}
