import AppKit

@main @MainActor struct PageCaptureEdgeGuardChecks {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        let host = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let hidden = NSRect(x: 10, y: 10, width: 1180, height: 780)
        precondition(PageCaptureEdgeReach.guardFrame(source: hidden, host: host) == host,
                     "A hidden sidebar's page reaches every window edge")
        let hairline = NSRect(x: 3, y: 3, width: 1194, height: 794)
        precondition(PageCaptureEdgeReach.guardFrame(source: hairline, host: host) == host)
        let locked = NSRect(x: 260, y: 10, width: 930, height: 780)
        precondition(PageCaptureEdgeReach.guardFrame(source: locked, host: host) == NSRect(x: 260, y: 0, width: 940, height: 800),
                     "A shown sidebar keeps its own events")
        let toolbar = NSRect(x: 10, y: 50, width: 1180, height: 740)
        precondition(PageCaptureEdgeReach.guardFrame(source: toolbar, host: host) == NSRect(x: 0, y: 50, width: 1200, height: 750),
                     "The page toolbar keeps its own events")
        let leftSplit = NSRect(x: 10, y: 10, width: 585, height: 780)
        precondition(PageCaptureEdgeReach.guardFrame(source: leftSplit, host: host) == NSRect(x: 0, y: 0, width: 595, height: 800),
                     "The neighbouring split pane keeps its own events")
        let peek = NSRect(x: 150, y: 80, width: 900, height: 640)
        precondition(PageCaptureEdgeReach.guardFrame(source: peek, host: host) == peek)
        precondition(PageCaptureEdgeReach.guardFrame(source: host, host: host) == host, "Fullscreen pages already reach the edges")
        precondition(PageCaptureEdgeReach.guardFrame(source: .zero, host: host) == .zero)
        precondition(PageCaptureEdgeReach.guardFrame(source: NSRect(x: 2000, y: 0, width: 10, height: 10), host: host) == .zero)
        print("Page capture edge guard passed: window-edge reach, sidebar, toolbar, split, Peek and fullscreen geometry.")
    }
}
