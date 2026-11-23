import AppKit
import Testing
@testable import Parc

struct BrowserToolbarTeardownTests {
    private final class LastReference: @unchecked Sendable {
        var button: BrowserToolbarActionButton?
        init(_ button: BrowserToolbarActionButton) { self.button = button }
    }

    @Test func actionButtonReleasedOffTheMainThreadTearsDownQuietly() async {
        let holder = await MainActor.run { LastReference(BrowserToolbarActionButton("Copy Current URL", symbol: "link")) }
        await Task.detached { holder.button = nil }.value
        #expect(holder.button == nil)
    }
}
