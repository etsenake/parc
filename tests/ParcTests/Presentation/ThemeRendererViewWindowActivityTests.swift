import AppKit
import MetalKit
import Testing
import ParcCore
@testable import Parc

extension ThemeRendererViewTestsSupport {
    struct ThemeRendererViewWindowActivityTests {
        @MainActor private final class Pair {
            let parent = ActivityWindow(size: NSSize(width: 100, height: 100))
            let child = ActivityWindow(size: NSSize(width: 10, height: 10))
            init() { parent.addChildWindow(child, ordered: .above) }
            deinit { MainActor.assumeIsolated { parent.removeChildWindow(child) } }
        }

        @Test @MainActor func anInactiveOwnershipChainIsDimmed() {
            let pair = Pair()
            #expect(!ThemeWindowActivity.isActive(pair.child))
        }

        @Test @MainActor func aMainWindowAndItsDescendantsStayActive() {
            let pair = Pair()
            pair.parent.reportsMain = true
            #expect(ThemeWindowActivity.isActive(pair.parent) && ThemeWindowActivity.isActive(pair.child))
        }

        @Test @MainActor func aKeyChildIsActiveWithoutPromotingItsParent() {
            let pair = Pair()
            pair.child.reportsKey = true
            #expect(ThemeWindowActivity.isActive(pair.child))
            #expect(!ThemeWindowActivity.isActive(pair.parent))
        }

        @Test @MainActor func aParentsActivationTargetsTheChildSurfaceOnly() {
            let pair = Pair()
            #expect(ThemeWindowActivity.contains(pair.parent, in: pair.child))
            #expect(!ThemeWindowActivity.contains(pair.child, in: pair.parent))
        }

        @Test @MainActor func aReparentedSurfaceDropsItsPreviousOwner() {
            let pair = Pair()
            pair.parent.removeChildWindow(pair.child)
            #expect(!ThemeWindowActivity.contains(pair.parent, in: pair.child))
        }

        @Test @MainActor func aDetachedRendererHasNoActiveOwner() {
            #expect(!ThemeWindowActivity.isActive(nil))
        }
    }
}
