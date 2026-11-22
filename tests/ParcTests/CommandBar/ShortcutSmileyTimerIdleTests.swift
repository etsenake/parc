import AppKit
import Testing
@testable import ParcCommandBar

struct ShortcutSmileyTimerIdleTests {
    private static let drawing = Data("""
        {"w":100,"h":100,"fr":10,"op":50,"layers":[
          {"ks":{"p":{"a":1,"k":[
            {"t":0,"s":[0,0]},{"t":10,"s":[0,0]},{"t":20,"s":[15,0]},{"t":30,"s":[0,0]}
          ]}},"shapes":[{"it":[
            {"ty":"st","w":{"k":5}},
            {"ty":"sh","ks":{"k":{"c":false,"v":[[30,30],[70,30]],"i":[[0,0],[0,0]],"o":[[0,0],[0,0]]}}}
          ]}]}
        ]}
        """.utf8)

    @MainActor private final class Recorder {
        var requests = 0
    }

    @MainActor private final class Fixture {
        let view: ShortcutSmileyView
        let window: NSWindow
        let redraws = Recorder()
        var now: CFTimeInterval = 0
        private(set) var timer: Timer?

        init(reduceMotion: Bool = false, data: Data = drawing) throws {
            let artwork = try #require(ShortcutSmileyArtwork(data: data))
            var scheduled: Timer?
            let recorder = redraws
            view = ShortcutSmileyView(frame: NSRect(x: 0, y: 0, width: 50, height: 50), artwork: artwork,
                                      reduceMotion: { reduceMotion }, schedule: { scheduled = $0 },
                                      redraw: { view in recorder.requests += 1; view.needsDisplay = true })
            window = CommandBarTestSupport.borderlessWindow(width: 50, height: 50)
            window.isReleasedWhenClosed = false
            view.now = { [weak self] in self?.now ?? 0 }
            window.contentView = view
            timer = scheduled
        }

        func fire(at time: CFTimeInterval) {
            now = time
            timer?.fire()
        }
    }

    @Test @MainActor func reduceMotionKeepsTheCueTimerIdle() throws {
        let fixture = try Fixture(reduceMotion: true)
        #expect(fixture.timer == nil)
    }

    @Test @MainActor func hidingTheCueStopsItsTimerOnTheNextFrame() throws {
        let fixture = try Fixture()
        let timer = try #require(fixture.timer)
        fixture.view.isHidden = true
        fixture.fire(at: 0.5)
        #expect(!timer.isValid)
    }

    @Test @MainActor func identicalFramesKeepTheDisplayClean() throws {
        let fixture = try Fixture()
        let timer = try #require(fixture.timer)
        let before = fixture.redraws.requests
        fixture.fire(at: 0.5)
        #expect(fixture.redraws.requests == before)
        #expect(timer.isValid)
    }

    @Test @MainActor func movementInvalidatesTheDisplay() throws {
        let fixture = try Fixture()
        let before = fixture.redraws.requests
        fixture.fire(at: 2)
        #expect(fixture.redraws.requests == before + 1)
    }

    @Test @MainActor func returningToRestStopsTheTimerBeforeTheCompositionEnds() throws {
        let fixture = try Fixture()
        let timer = try #require(fixture.timer)
        fixture.fire(at: 2)
        fixture.fire(at: 3)
        #expect(!timer.isValid)
    }

    @Test func resizingChangesThePresentationFingerprint() throws {
        let artwork = try #require(ShortcutSmileyArtwork(data: Self.drawing))
        #expect(artwork.presentationFingerprint(seconds: 0, size: CGSize(width: 50, height: 50))
                != artwork.presentationFingerprint(seconds: 0, size: CGSize(width: 64, height: 64)))
    }

    @Test(arguments: [(0.5, true), (2.0, false), (3.5, true)])
    func onlyTheRestingPoseSharesTheOriginalFingerprint(seconds: Double, matches: Bool) throws {
        let artwork = try #require(ShortcutSmileyArtwork(data: Self.drawing))
        let size = CGSize(width: 50, height: 50)
        #expect((artwork.presentationFingerprint(seconds: 0, size: size)
                 == artwork.presentationFingerprint(seconds: seconds, size: size)) == matches)
    }

    @Test @MainActor func theViewDrawsTheBundledArtwork() throws {
        let url = try #require(Bundle.module.url(forResource: "smiley", withExtension: "json", subdirectory: "CommandBarFixtures"))
        let fixture = try Fixture(reduceMotion: true, data: Data(contentsOf: url))
        let image = try #require(fixture.view.bitmapImageRepForCachingDisplay(in: fixture.view.bounds))
        fixture.view.cacheDisplay(in: fixture.view.bounds, to: image)
        #expect((0..<image.pixelsHigh).contains { row in
            (0..<image.pixelsWide).contains { column in (image.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0 }
        })
    }
}

extension ShortcutSmileyTimerIdleTests {
    @Test @MainActor func aSettledCueLeavesItsLastFrameInPlace() throws {
        let fixture = try Fixture()
        let timer = try #require(fixture.timer)
        fixture.fire(at: 2)
        fixture.fire(at: 3)
        let settled = fixture.redraws.requests
        fixture.fire(at: 4)
        #expect(!timer.isValid)
        #expect(fixture.redraws.requests == settled)
    }

    @Test(arguments: [(0.0, 0.5, true), (0.0, 1.5, false), (4.2, 5.0, true), (0.0, 5.0, false)])
    func theBundledCueKeepsItsHoldAndMotionFrames(first: Double, second: Double, matches: Bool) throws {
        let url = try #require(Bundle.module.url(forResource: "smiley", withExtension: "json", subdirectory: "CommandBarFixtures"))
        let data = try Data(contentsOf: url)
        let artwork = try #require(ShortcutSmileyArtwork(data: data))
        let size = CGSize(width: 50, height: 50)
        #expect((artwork.presentationFingerprint(seconds: first, size: size)
                 == artwork.presentationFingerprint(seconds: second, size: size)) == matches)
    }
}
