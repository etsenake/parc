import AppKit
import ParcCore
import Testing
@testable import Parc

enum ExternalSplitDropHandoffSupport {
    @MainActor final class Scene {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1810, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        let host = ExternalSplitDropHost(frame: NSRect(x: 0, y: 0, width: 1810, height: 700))
        let split: ParcSplitView
        let pageA: SplitDropReservedPane, pageB: SplitDropReservedPane
        let drag: SplitDropDragInfo
        let router: SplitDropRouterDouble
        let originalFrames: [NSRect]
        var buttonDown = true
        var commits = 0, admits = 0
        var sessionValid = true
        var commitResult = true
        var geometryRestoredAtCommit = true
        var editing: [Bool] = []

        init() {
            window.isReleasedWhenClosed = false
            window.contentView = host
            split = ParcSplitView(frame: host.bounds)
            host.addSubview(split)
            pageA = SplitDropReservedPane(frame: host.bounds)
            pageB = SplitDropReservedPane(frame: host.bounds)
            split.addArrangedSubview(pageA)
            split.addArrangedSubview(pageB)
            split.configure(orientation: .horizontal, factors: [0.75, 0.25])
            split.constrain(to: host)
            originalFrames = split.arrangedSubviews.map(\.frame)
            drag = SplitDropDragInfo(window: window)
            drag.draggingPasteboard.setString("https://handoff.invalid/path", forType: .URL)
            router = SplitDropRouterDouble(view: pageA.body)
            split.primaryMouseButtonIsDown = { [weak self] in self?.buttonDown ?? false }
            split.onInteractivePaneEditing = { [weak self] in self?.editing.append($0) }
            host.makeSession = { [weak self] _, info in
                guard let self else { return nil }
                admits += 1
                let reservation = immediate(split.prepareDropReservation(in: host, contents: [pageA.body, pageB.body])!)
                return ExternalSplitDropSession(host: host, info: info,
                    frames: [pageA.body, pageB.body].map { $0.convert($0.bounds, to: self.host) }, orientation: .horizontal,
                    reservation: reservation, validate: { [weak self] in (self?.sessionValid ?? false) && reservation.isCurrent },
                    insertionColor: { .black }, canPropose: { _, _ in true },
                    commit: { [weak self] _, _ in
                        guard let self else { return false }
                        geometryRestoredAtCommit = geometryRestoredAtCommit && split.arrangedSubviews.map(\.frame) == originalFrames
                        commits += 1
                        return commitResult
                    })
            }
        }

        func place(_ point: NSPoint) { drag.draggingLocation = host.convert(point, to: nil) }

        func enterLeftEdge(with router: SplitDropRouterDouble? = nil) -> Bool {
            place(NSPoint(x: 1, y: 200))
            return (router ?? self.router).begin(drag)
        }

        func leaveToHostRegion() {
            place(NSPoint(x: 200, y: 200))
            router.exit(drag)
        }

        func beginHandoff() {
            #expect(enterLeftEdge() && router.operation == .copy)
            #expect(split.arrangedSubviews.map(\.frame) != originalFrames)
            #expect(split.arrangedSubviews.count == 2)
            leaveToHostRegion()
            #expect(host.draggingEntered(drag) == .copy)
        }

        func leaveThePage(with router: SplitDropRouterDouble? = nil) {
            place(NSPoint(x: 1700, y: 200))
            (router ?? self.router).exit(drag)
        }

        func continuingSessions() {
            let plain = host.makeSession
            host.makeSession = { view, info in
                let session = plain?(view, info)
                session?.admitsReceiver = { _, _ in true }
                return session
            }
        }
    }
}
