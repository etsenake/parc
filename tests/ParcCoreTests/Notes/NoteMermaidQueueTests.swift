import Foundation
import Testing
@testable import ParcCore

struct NoteMermaidQueueTests {
    @Test func twoClientsRequestingTheSameDiagramShareOneRender() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let one = request("graph TD\nA")
        queue.submit(one, client: 1)
        queue.submit(one, client: 2)
        #expect(queue.pendingKeys == [one.key], "two blocks with the same diagram share one render")
    }

    @Test func onlyOneRenderCanRunAtATime() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let one = request("graph TD\nA")
        queue.submit(one, client: 1)
        queue.submit(one, client: 2)
        #expect(queue.start() == one && queue.start() == nil, "one render runs at a time")
    }

    @Test func editingReplacesThePendingRequestForThatClient() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let one = request("graph TD\nA"), two = request("graph TD\nAB"), three = request("graph TD\nABC")
        queue.submit(one, client: 1)
        queue.submit(one, client: 2)
        _ = queue.start()
        queue.submit(two, client: 1)
        queue.submit(three, client: 1)
        #expect(queue.pendingKeys == [three.key], "typing replaces a block's stale request")
    }

    @Test func onlyClientsStillWaitingReceiveTheCompletedRender() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let one = request("graph TD\nA"), two = request("graph TD\nAB"), three = request("graph TD\nABC")
        queue.submit(one, client: 1)
        queue.submit(one, client: 2)
        _ = queue.start()
        queue.submit(two, client: 1)
        queue.submit(three, client: 1)
        #expect(queue.finish(one.key) == [2], "only blocks still waiting on a drawing hear about it")
    }

    @Test func theLatestRequestRunsAfterTheCurrentRender() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let one = request("graph TD\nA"), two = request("graph TD\nAB"), three = request("graph TD\nABC")
        queue.submit(one, client: 1)
        queue.submit(one, client: 2)
        _ = queue.start()
        queue.submit(two, client: 1)
        queue.submit(three, client: 1)
        _ = queue.finish(one.key)
        #expect(queue.isIdle && queue.start() == three, "the latest request runs next")
    }

    @Test func aWithdrawnClientDoesNotReceiveItsInFlightRender() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let three = request("graph TD\nABC")
        queue.submit(three, client: 1)
        _ = queue.start()
        queue.withdraw(1)
        #expect(!queue.wants(three.key) && queue.finish(three.key).isEmpty, "a withdrawn block hears nothing")
    }

    @Test func withdrawingAPendingRequestRemovesItFromTheQueue() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let one = request("graph TD\nA")
        let two = request("graph TD\nAB")
        queue.submit(one, client: 3)
        queue.submit(two, client: 4)
        queue.withdraw(3)
        #expect(queue.pendingKeys == [two.key], "withdrawn requests leave the line")
    }

    @Test func theNextPendingRequestCanStart() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let two = request("graph TD\nAB")
        queue.submit(two, client: 4)
        #expect(queue.start() == two, "the next request starts")
    }

    @Test func requeueingACrashedRenderReturnsItToPending() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let two = request("graph TD\nAB")
        queue.submit(two, client: 4)
        _ = queue.start()
        queue.requeueRunning()
        #expect(queue.isIdle && queue.pendingKeys == [two.key], "a crashed render goes back to the front")
    }

    @Test func aRequeuedRenderRunsBeforeLaterRequests() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let two = request("graph TD\nAB")
        let three = request("graph TD\nABC")
        queue.submit(two, client: 4)
        _ = queue.start()
        queue.requeueRunning()
        queue.submit(three, client: 5)
        #expect(queue.start() == two, "requeued renders run first")
    }

    @Test func aCrashedRenderWithNoClientsIsDropped() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let two = request("graph TD\nAB")
        let three = request("graph TD\nABC")
        queue.submit(two, client: 4)
        _ = queue.start()
        queue.submit(three, client: 5)
        queue.withdraw(4)
        queue.requeueRunning()
        #expect(queue.pendingKeys == [three.key], "nobody wants a crashed render, so it isn't retried")
    }

    @Test func aWaitingClientCanLookUpItsRenderKey() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let three = request("graph TD\nABC")
        queue.submit(three, client: 5)
        #expect(queue.key(for: 5) == three.key, "clients know what they wait for")
    }

    @Test func failingAllRequestsNotifiesClientsAndClearsTheQueue() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let three = request("graph TD\nABC")
        queue.submit(three, client: 5)
        #expect(queue.failAll() == [5] && queue.isIdle && queue.pendingKeys.isEmpty, "a dead renderer tells everyone and clears the line")
    }
}
