import AppKit

@main @MainActor
struct DownloadPointerTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1; precondition(value(), message)
    }
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Downloads pointer component — synthetic rows"
        let table = DownloadLibraryTable(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let source = Rows()
        window.contentView = table
        table.addTableColumn(NSTableColumn(identifier: .init("fixture")))
        table.dataSource = source; table.delegate = source
        table.allowsMultipleSelection = false; table.reloadData()
        table.target = table; table.action = #selector(DownloadLibraryTable.activateOriginalClick)
        var commits: [Int] = [], released = false
        table.prepareClick = { original in
            return {
                expect(released, "Native click cannot output before mouse-up or before drag admission")
                expect(table.selectedRow == original, "Native cursor is selected before original click commits")
                commits.append(original)
            }
        }
        table.activateOriginalClick()
        expect(commits.isEmpty, "Unowned table action cannot manufacture a click")
        func mouse(_ type: NSEvent.EventType, row: Int, count: Int = 1,
                   flags: NSEvent.ModifierFlags = []) -> NSEvent {
            let point = table.convert(NSPoint(x: 80, y: table.rect(ofRow: row).midY), to: nil)
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        func click(row: Int, count: Int = 1, flags: NSEvent.ModifierFlags = [],
                   intervention: (() -> Void)? = nil) {
            released = false
            let timer = Timer(timeInterval: 0.03, repeats: false) { _ in
                MainActor.assumeIsolated {
                    intervention?(); released = true; NSApp.postEvent(mouse(.leftMouseUp, row: row, count: count, flags: flags), atStart: true)
                }
            }
            RunLoop.main.add(timer, forMode: .eventTracking)
            table.mouseDown(with: mouse(.leftMouseDown, row: row, count: count, flags: flags))
            timer.invalidate()
        }
        NSApp.setActivationPolicy(.regular)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            expect(window.isKeyWindow && NSApp.isActive,
                "Positive native input check requires its exact key and active component window")
            click(row: 1)
            expect(commits == [1], "Native single mouse sequence commits one original row")
            table.activateOriginalClick()
            expect(commits == [1], "Finished mouse sequence cannot replay an output")
            click(row: 2, flags: .shift)
            expect(commits == [1], "Modified native selection does not execute ordinary click output")
            click(row: 2, count: 2)
            expect(commits == [1], "Second double-click event cannot duplicate the first single-click output")
            click(row: 1, intervention: { table.retireOriginalClick() })
            expect(commits == [1], "Original drag/owner retirement during tracking revokes click output")
            table.makeMenu = { NSMenu(title: "Inert item context") }
            click(row: 1, intervention: { _ = table.menu(for: mouse(.rightMouseDown, row: 1)) })
            expect(commits == [1], "Context-menu intervention retires the tracked click")
            print("Download Library pointer: \(assertions) assertions passed")
            window.orderOut(nil); NSApp.terminate(nil)
        }
        NSApp.run()
    }
    @MainActor final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        func numberOfRows(in tableView: NSTableView) -> Int { 3 }
        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            "Synthetic row \(row)"
        }
    }
}
