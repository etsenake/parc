import Foundation

@main @MainActor
struct SidebarNoteDropTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        do { try run() } catch { failTest("\(error)") }
        print("SidebarNoteDropTests passed")
    }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-sidebar-note-drop-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = directory.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let plans = notes.appendingPathComponent("Plans.md"), ideas = notes.appendingPathComponent("Ideas.txt")
        try Data("# Plans\n".utf8).write(to: plans)
        try Data("ideas\n".utf8).write(to: ideas)

        let store = try BrowserStore(directory: directory.appendingPathComponent("tabs"))
        let profileID = store.activeSpace.profileID, spaceID = store.state.activeSpaceID
        expect(SidebarNotePlacement.opensNewTab([plans], state: store.state, profileID: profileID),
               "A note with no tab yet gets a fresh tab, so the drop shows where it lands")

        let first = store.open("https://example.test/one"), second = store.open("https://example.test/two")
        guard let plansTab = store.openNote(url: plans, title: "Plans") else { failTest("Plans opens") }
        expect(!SidebarNotePlacement.opensNewTab([plans], state: store.state, profileID: profileID),
               "A note that's already open just gets selected, so no insertion line promises a new spot")
        expect(!SidebarNotePlacement.opensNewTab([URL(string: plans.absoluteString + "#top")!], state: store.state, profileID: profileID),
               "An anchored address names the same open note")
        expect(SidebarNotePlacement.opensNewTab([plans, ideas], state: store.state, profileID: profileID),
               "One new note in the bunch is enough to show the line")
        expect(SidebarNotePlacement.opensNewTab([plans], state: store.state, profileID: UUID()),
               "Another Profile's tab for the file doesn't count")

        let today = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .today)
        guard let ideasTab = store.openNote(url: ideas, title: "Ideas"),
              let expected = SidebarHierarchySnapshot(state: store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true) else {
            failTest("Ideas opens with a readable sidebar")
        }
        let moved = try store.moveSidebarItems([.tab(ideasTab)], to: today, before: .tab(first), expected: expected)
        let order = SidebarHierarchy.children(in: today, state: store.state)
        expect(moved, "A freshly opened note moves to the dropped spot")
        guard let ideasIndex = order.firstIndex(of: .tab(ideasTab)), let firstIndex = order.firstIndex(of: .tab(first)) else {
            failTest("Both rows are in Today")
        }
        expect(ideasIndex + 1 == firstIndex, "It lands right above the row the line pointed at")
        expect(order.contains(.tab(second)) && order.contains(.tab(plansTab)), "Everything else stays put")
        expect(store.state.selectedTabIDs == [ideasTab], "The dropped note stays selected after it moves")
    }
}
