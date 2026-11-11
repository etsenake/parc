import AppKit

@main @MainActor struct LibraryWidthTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
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

        let pageChange = reports
        let work = store.createSpace(name: "Work")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        check(store.state.spaces.count == 2 && reports == pageChange && library.contentWidth == 480,
              "a Space added while Spaces is shown keeps the page-change width: \(reports)")
        library.layoutSubtreeIfNeeded()
        let strip = library.spaceManager.subviews.compactMap { $0 as? NSScrollView }.first!
        check(strip.hasHorizontalScroller && strip.documentView!.frame.width == Layout.contentWidth(count: 2)
              && strip.documentView!.frame.width > strip.contentSize.width,
              "the strip scrolls horizontally to the add item: \(strip.documentView!.frame.width) in \(strip.contentSize.width)")
        _ = store.setSpaceTheme(store.state.spaces[0].id, theme: SpaceTheme(primaryColor: ThemeColor(red: 0.5, green: 0.4, blue: 0.9),
                                                                              colorCount: 1, appearance: .dark))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        check(reports == pageChange && library.contentWidth == 480, "an unrelated Spaces reload reports nothing")
        store.requestPageRetirement = { _, valid, done in done(valid()) }
        var deleted: Bool?
        store.deleteSpace(SpaceDeletionTarget(spaceID: work, state: store.state)!, documents: [:], shouldCommit: { true },
                          didCommit: { _ in }) { if case .success(let value) = $0 { deleted = value } }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        check(deleted == true && store.state.spaces.count == 1, "the added Space is deleted")
        check(reports == pageChange && library.contentWidth == 480, "a Space removed while Spaces is shown keeps the page-change width: \(reports)")
        library.show(.archive)
        check(reports.last == 417 && library.contentWidth == 417, "leaving Spaces returns the Library to 417: \(reports)")
        _ = store.createSpace(name: "Later")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        library.show(.spaces)
        check(reports.last == 744 && library.contentWidth == 744, "returning to Spaces reads the current count: \(reports)")
        let returned = reports.count
        library.show(.spaces)
        check(reports.count == returned, "choosing the shown page again reports nothing")
        library.onContentWidthChange = nil
        print("LibraryWidth: \(count) assertions passed")
    }
}
