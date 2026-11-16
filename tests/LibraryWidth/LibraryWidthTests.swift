import AppKit

@main @MainActor struct LibraryWidthTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        typealias Layout = SpaceManagementLayout
        let window = NSRect(x: 0, y: 0, width: 1470, height: 831)
        func frames(_ content: CGFloat, in bounds: NSRect = window) -> SidebarChromeFrames {
            SidebarChromeFrames(bounds: bounds, sidebarWidth: 228, presentation: .locked, placement: .locked,
                                library: true, libraryContentWidth: content)
        }
        for spaces in 1...6 {
            let width = Layout.libraryWidth(count: spaces)
            check(width == 216 + 264 * CGFloat(spaces), "\(spaces) Spaces' page is 216 + 264 × \(spaces): \(width)")
            check(LibraryRailLayout.width + 2 * Layout.pageInset + Layout.contentWidth(count: spaces) == width,
                  "\(spaces) Spaces' strip fills the page column inside the 4-point insets")
        }
        check(frames(Layout.libraryWidth(count: 1)).library.width == 480 && frames(Layout.libraryWidth(count: 1)).pageHost.minX == 480,
              "one Space's Library is 480 and its page starts there")
        check(frames(Layout.libraryWidth(count: 5)).library.width == 1414, "five Spaces stop at the window width − 56")
        check(frames(Layout.libraryWidth(count: 2), in: NSRect(x: 0, y: 0, width: 760, height: 540)).library.width == 704,
              "two Spaces in the narrowest window stop at its width − 56")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let profile = store.state.profiles[0].id
        for kind in [LibraryView.Kind.archive, .downloads, .captures, .documents] {
            let page = LibraryView(store: store, kind: kind, profileID: profile)
            check(page.contentWidth == SidebarChromeFrames.libraryMinimumWidth && frames(page.contentWidth).library.width == 417,
                  "\(kind) keeps the 417 Library")
        }

        let library = LibraryView(store: store, kind: .archive, profileID: profile)
        var reports: [CGFloat] = []
        library.onContentWidthChange = { [unowned library] in reports.append(library.contentWidth) }
        library.show(.spaces)
        check(reports.last == 480 && library.contentWidth == 480, "showing Spaces reports one Space's width: \(reports)")
        library.frame = frames(library.contentWidth).library
        library.layoutSubtreeIfNeeded()
        check(library.spaceManager.frame == NSRect(x: 116, y: 0, width: 360, height: 831),
              "the strip sits 4 points inside the page column: \(library.spaceManager.frame)")
        let add = Layout.addItemFrame(count: 1, height: library.spaceManager.bounds.height)
            .offsetBy(dx: library.spaceManager.frame.minX, dy: 0)
        check(add.maxX + Layout.horizontalInset + Layout.pageInset == library.frame.maxX,
              "the add item ends 28 points before the page: \(add)")

        let strip = library.spaceManager.subviews.compactMap { $0 as? NSScrollView }.first!
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)) }
        func fits(_ count: Int, _ name: String) {
            library.frame = frames(library.contentWidth).library
            library.layoutSubtreeIfNeeded()
            let add = Layout.addItemFrame(count: count, height: library.spaceManager.bounds.height)
                .offsetBy(dx: library.spaceManager.frame.minX, dy: 0)
            check(store.state.spaces.count == count && library.contentWidth == Layout.libraryWidth(count: count)
                  && add.maxX + Layout.horizontalInset + Layout.pageInset == library.frame.maxX
                  && strip.documentView!.frame.width == strip.contentSize.width,
                  "\(name): \(count) Spaces fill the page with no gap or overflow: \(add), \(library.frame), \(reports)")
        }

        let work = store.createSpace(name: "Work")
        settle()
        check(reports.suffix(2) == [480, 744], "a Space created elsewhere while Spaces is shown re-measures: \(reports)")
        fits(2, "created elsewhere")
        var reported = reports.count
        _ = store.setSpaceTheme(store.state.spaces[0].id, theme: SpaceTheme(primaryColor: ThemeColor(red: 0.5, green: 0.4, blue: 0.9),
                                                                              colorCount: 1, appearance: .dark))
        settle()
        check(reports.count == reported, "a theme change on the shown page reports nothing: \(reports)")
        let order = store.state.spaces.map(\.id)
        let reordered = try store.reorderSpace(work, before: order[0], expectedOrder: order)
        check(reordered, "the Spaces reorder")
        settle()
        check(reports.count == reported && library.contentWidth == 744, "reordering Spaces reports nothing: \(reports)")

        store.requestPageRetirement = { _, valid, done in done(valid()) }
        var deletion: SpaceDeletionUndo?
        func delete(_ target: SpaceDeletionTarget) {
            var committed: Bool?
            deletion = nil
            store.deleteSpace(target, documents: [:], shouldCommit: { true }, didCommit: { deletion = $0 }) {
                if case .success(let value) = $0 { committed = value }
            }
            settle()
            check(committed == true && deletion != nil, "\(target.space.name) is deleted with an Undo record")
        }
        delete(SpaceDeletionTarget(spaceID: work, state: store.state)!)
        check(reports.count == reported + 1 && reports.last == 480, "deleting a Space re-measures: \(reports)")
        fits(1, "deleted")
        let restored = try store.undoSpaceDeletion(deletion!, shouldCommit: { true })
        settle()
        check(restored && reports.count == reported + 2 && reports.last == 744, "Undo of a deletion re-measures: \(reports)")
        fits(2, "undone deletion")
        let card = strip.documentView!.subviews.first { $0.accessibilityLabel() == "Work" }
        check(card.map { strip.documentVisibleRect.contains($0.frame) } == true,
              "the restored card stays inside the visible strip: \(String(describing: card?.frame)) in \(strip.documentVisibleRect)")
        delete(deletion!.redoTarget(in: store.state)!)
        check(reports.count == reported + 3 && reports.last == 480, "Redo of a deletion re-measures: \(reports)")
        fits(1, "redone deletion")

        let later = store.createSpace(name: "Later")
        settle()
        fits(2, "created again")
        reported = reports.count
        let conversion = SpaceFolderConversion(source: later, destination: store.state.spaces[0].id, state: store.state, documents: [:])!
        let folding = try store.convertSpaceToFolder(conversion)!
        settle()
        check(reports.count == reported + 1 && reports.last == 480, "Turn into Folder re-measures: \(reports)")
        fits(1, "turned into a folder")
        let unfolded = try store.undoSpaceFolderConversion(folding)
        settle()
        check(unfolded && reports.count == reported + 2 && reports.last == 744, "Undo of Turn into Folder re-measures: \(reports)")
        fits(2, "undone folder")
        _ = try store.convertSpaceToFolder(folding.redo(in: store.state)!)!
        settle()
        check(reports.count == reported + 3 && reports.last == 480, "Redo of Turn into Folder re-measures: \(reports)")
        fits(1, "redone folder")

        let other = LibraryView(store: store, kind: .spaces, profileID: profile)
        var otherReports: [CGFloat] = []
        other.onContentWidthChange = { [unowned other] in otherReports.append(other.contentWidth) }
        check(other.contentWidth == 480, "another window's Spaces page opens at one Space's width")
        let shared = store.createSpace(name: "Shared")
        settle()
        check(reports.last == 744 && otherReports == [744], "both windows' Spaces pages follow a Space created in one: \(reports), \(otherReports)")
        fits(2, "shared creation")
        delete(SpaceDeletionTarget(spaceID: shared, state: store.state)!)
        check(reports.last == 480 && otherReports == [744, 480], "both windows' Spaces pages follow a Space deleted in one: \(reports), \(otherReports)")
        fits(1, "shared deletion")
        other.onContentWidthChange = nil

        library.show(.archive)
        check(reports.last == 417 && library.contentWidth == 417, "leaving Spaces returns the Library to 417: \(reports)")
        reported = reports.count
        library.show(.downloads)
        check(reports.count == reported && library.contentWidth == 417, "moving between 417 pages reports nothing: \(reports)")
        library.show(.archive)
        _ = store.createSpace(name: "Elsewhere")
        settle()
        check(reports.count == reported && library.contentWidth == 417, "a Space created while another page shows reports nothing: \(reports)")
        library.show(.spaces)
        check(reports.last == 744 && library.contentWidth == 744, "returning to Spaces reads the current count: \(reports)")
        let returned = reports.count
        library.show(.spaces)
        check(reports.count == returned, "choosing the shown page again reports nothing")
        library.onContentWidthChange = nil
        print("LibraryWidth: \(count) assertions passed")
    }
}
