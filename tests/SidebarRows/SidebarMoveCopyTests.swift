import AppKit

@MainActor final class BrowserWindowController {}

@main @MainActor
struct SidebarMoveCopyTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        let location = SidebarContainerLocation(spaceID: UUID(), folderID: nil, section: .pinned)
        var valid = true, moves = 0, copies = 0
        func session(copy: Bool) -> SidebarMoveSession {
            SidebarMoveSession(items: [.split(UUID())], window: window, validate: { valid },
                               allowsCopy: copy, propose: { _, _ in true }, commit: { _, _ in moves += 1; return true })
        }
        let moveOnly = session(copy: false)
        check(!moveOnly.allowsCopy && !moveOnly.copy({ copies += 1; return true }) && copies == 0 && !moveOnly.ended,
              "A move-only session never runs a copy and stays live")
        check(moveOnly.move(to: location, before: nil) && moves == 1 && moveOnly.ended, "Its move still commits once")
        let copyable = session(copy: true)
        valid = false
        check(!copyable.copy({ copies += 1; return true }) && copies == 0 && !copyable.ended, "An invalid source refuses the copy")
        valid = true
        check(copyable.copy({ copies += 1; return true }) && copies == 1 && copyable.ended, "A valid copy runs once and ends the drag")
        check(!copyable.copy({ copies += 1; return true }) && copies == 1 && moves == 1, "An ended session cannot copy or move again")
        check(!copyable.move(to: location, before: nil) && moves == 1, "Copying never also moves the originals")
        let failing = session(copy: true)
        check(!failing.copy({ false }) && failing.ended, "A refused commit still ends the one-shot session")

        let handle = SidebarMoveHandle(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        window.contentView?.addSubview(handle)
        check(handle.makeDragImage == nil, "Handles capture their preview unless a renderer is supplied")
        var rendered = 0
        handle.makeDragImage = { rendered += 1; return NSImage(size: NSSize(width: 120, height: 36)) }
        check(handle.makeDragImage?()?.size == NSSize(width: 120, height: 36) && rendered == 1, "A supplied renderer provides the drag image")
        print("\(count) sidebar move copy assertions passed")
    }
}
