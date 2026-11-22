import AppKit
import Testing
@testable import ParcCore
@testable import ParcLibrary

@MainActor
struct LibraryRailDownloadBadgeTests {
    @MainActor final class Badge {
        let rail: LibraryRailTileTests.Rail
        let tile: LibraryRailTile
        let badge: DownloadActivityBadge
        let profile = UUID()
        var retirements: [(delay: TimeInterval, body: @MainActor () -> Void)] = []

        init() throws {
            rail = try LibraryRailTileTests.Rail()
            tile = rail.tile("Downloads", .downloads, shown: true)
            badge = tile.progress!
            badge.after = { [weak self] delay, body in guard let self else { return }; retirements.append((delay, body)) }
        }

        func flight(_ id: String, received: Int64, total: Int64 = 100, started: Double) -> BrowserDownload {
            var item = BrowserDownload(id: id, name: id, path: "/nonexistent/" + id, receivedBytes: received, totalBytes: total, status: .downloading)
            item.profileID = profile; item.nativeID = id; item.nativeIdentity = id + "-1"; item.startedAt = Date(timeIntervalSince1970: started)
            return item
        }

        func update(_ downloads: [BrowserDownload], enabled: Bool = true) {
            badge.updateInFlight(downloads, profiles: [profile], enabled: enabled)
        }

        func completed() -> NSView? {
            update([flight("a", received: 40, started: 1)])
            let renderer = badge.subviews.first
            update([flight("a", received: 100, started: 1)])
            return renderer
        }

        var inked: Bool {
            let drawn = rail.capture(tile.progress!.superview!)
            let rect = badge.frame, stride = Int(badge.superview!.bounds.width * 2) * 4
            for y in Int(rect.minY * 2)..<Int(rect.maxY * 2) {
                for x in Int(rect.minX * 2)..<Int(rect.maxX * 2) where drawn[y * stride + x * 4 + 3] > 0 { return true }
            }
            return false
        }

        func displayOptionsChanged() {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        }
    }

    @Test func aBadgeThatFirstAppearsAtFullProgressDoesNotPlayItsCompletion() throws {
        let badge = try Badge()
        badge.update([badge.flight("full", received: 100, started: 1)])
        #expect(!badge.badge.isHidden)
        #expect(badge.badge.activity?.progress == 1 && badge.badge.activity?.completed == false)
        #expect(badge.retirements.isEmpty)
    }

    @Test func nothingInFlightRetiresTheRenderer() throws {
        let badge = try Badge()
        badge.update([badge.flight("full", received: 100, started: 1)])
        badge.update([])
        #expect(badge.badge.isHidden && badge.badge.subviews.isEmpty)
    }

    @Test func progressReachingOnePlaysTheCompletionOnTheSameRenderer() throws {
        let badge = try Badge()
        let renderer = badge.completed()
        #expect(renderer != nil && badge.badge.subviews.first === renderer)
        #expect(badge.badge.activity?.completed == true)
    }

    @Test func theCompletionSettlesAtAOnePointFourFiveSecondDeadline() throws {
        let badge = try Badge()
        _ = badge.completed()
        #expect(badge.retirements.count == 1 && badge.retirements.first?.delay == 1.45)
    }

    @Test func aNewerDownloadKeepsTheRendererWithoutReplayingOrUndoingTheCompletion() throws {
        let badge = try Badge()
        let renderer = badge.completed()
        badge.update([badge.flight("a", received: 100, started: 1), badge.flight("b", received: 10, started: 2)])
        #expect(badge.badge.activity?.identity == DownloadLibraryIdentity(badge.flight("b", received: 10, started: 2)))
        #expect(badge.badge.activity?.progress == 0.1 && badge.badge.activity?.completed == true)
        #expect(badge.badge.subviews.first === renderer && badge.retirements.count == 1)
    }

    @Test func thePlayedCheckmarkDrawsBeforeItsDeadline() throws {
        let badge = try Badge()
        _ = badge.completed()
        #expect(badge.inked)
    }

    @Test func atTheDeadlineTheCompletionSettlesWithTheSlotKeptAndNothingDrawn() throws {
        let badge = try Badge()
        _ = badge.completed()
        badge.retirements[0].body()
        #expect(!badge.badge.isHidden && badge.badge.activity?.completed == true)
        #expect(badge.badge.subviews.isEmpty)
        #expect(!badge.inked)
    }

    @Test func neitherAProgressTickNorADisplayChangeBringsASettledCompletionBack() throws {
        let badge = try Badge()
        _ = badge.completed()
        badge.update([badge.flight("a", received: 100, started: 1), badge.flight("b", received: 10, started: 2)])
        badge.retirements[0].body()
        badge.update([badge.flight("b", received: 20, started: 2)])
        badge.displayOptionsChanged()
        #expect(badge.badge.activity?.progress == 0.2 && badge.badge.activity?.completed == true)
        #expect(badge.badge.subviews.isEmpty && badge.retirements.count == 1)
    }

    @Test func theBadgeLeavesWhenTheWindowCannotBadge() throws {
        let badge = try Badge()
        badge.update([badge.flight("b", received: 10, started: 2)], enabled: false)
        #expect(badge.badge.isHidden && badge.badge.activity == nil)
    }

    @Test func anUnknownTotalGetsAFreshRendererWithNoCompletion() throws {
        let badge = try Badge()
        let renderer = badge.completed()
        badge.update([], enabled: false)
        badge.update([badge.flight("c", received: 5, total: 0, started: 3)])
        let fresh = badge.badge.subviews.first
        #expect(!badge.badge.isHidden && badge.badge.activity?.progress == nil && badge.badge.activity?.completed == false)
        #expect(fresh != nil && fresh !== renderer)
    }

    @Test func aDisplayChangeRebuildsALiveBadgesRenderer() throws {
        let badge = try Badge()
        badge.update([badge.flight("c", received: 5, total: 0, started: 3)])
        let fresh = badge.badge.subviews.first
        badge.displayOptionsChanged()
        #expect(badge.badge.subviews.count == 1 && badge.badge.subviews.first !== fresh)
    }

    @Test func aNewerDownloadReachingOnePlaysItsOwnCompletion() throws {
        let badge = try Badge()
        _ = badge.completed()
        badge.update([], enabled: false)
        badge.update([badge.flight("d", received: 40, started: 4)])
        badge.update([badge.flight("d", received: 100, started: 4)])
        #expect(badge.badge.activity?.completed == true)
        #expect(badge.retirements.count == 2 && badge.retirements.last?.delay == 1.45)
    }

    @Test func aStaleDeadlineLeavesANewerCompletionPlaying() throws {
        let badge = try Badge()
        _ = badge.completed()
        badge.update([], enabled: false)
        badge.update([badge.flight("d", received: 40, started: 4)])
        badge.update([badge.flight("d", received: 100, started: 4)])
        let playing = badge.badge.subviews.first
        badge.retirements[0].body()
        #expect(badge.badge.activity?.completed == true && playing != nil && badge.badge.subviews.first === playing)
    }

    @Test func theNewerCompletionSettlesAtItsOwnDeadline() throws {
        let badge = try Badge()
        _ = badge.completed()
        badge.update([], enabled: false)
        badge.update([badge.flight("d", received: 40, started: 4)])
        badge.update([badge.flight("d", received: 100, started: 4)])
        badge.retirements[0].body()
        badge.retirements[1].body()
        #expect(!badge.badge.isHidden && badge.badge.subviews.isEmpty)
    }

    @Test func leavingTheWindowRetiresTheBadge() throws {
        let badge = try Badge()
        badge.update([badge.flight("b", received: 10, started: 2)])
        badge.tile.removeFromSuperview()
        #expect(badge.badge.isHidden && badge.badge.activity == nil)
    }
}
