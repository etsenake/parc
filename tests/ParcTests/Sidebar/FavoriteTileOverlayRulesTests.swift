import AppKit
import QuartzCore
import Testing
@testable import Parc

struct FavoriteTileOverlayRulesTests {
    typealias Rules = FavoriteTileOverlayRules
    typealias G = FavoriteTileOverlayGeometry

    private func music(_ url: String) -> Bool { Rules.isMusicHost(URL(string: url)?.host) }
    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }
    private let spotify = "https://open.spotify.com/playlist/1"
    private let tileBounds = CGRect(x: 0, y: 0, width: 60, height: 47)

    @Test func thereAreEightMusicHosts() {
        #expect(Rules.musicHosts.count == 8)
    }

    @Test(arguments: Rules.musicHosts.sorted())
    func everyListedHostMatchesExactly(host: String) {
        #expect(music("https://\(host)/x"))
    }

    @Test(arguments: ["https://open.spotify.com/track/1", "https://www.music.apple.com/album", "https://www.nts.live"])
    func aSubdomainOfAListedHostMatches(url: String) {
        #expect(music(url))
    }

    @Test(arguments: ["https://youtube.com/watch", "https://apple.com/music", "https://notspotify.com", "https://spotify.com.example.test",
                      "https://example.test/?next=spotify.com", "https://tidal.co", "about:blank", "file:///tmp/x", "not a url", ""])
    func anythingElseDoesNotMatch(url: String) {
        #expect(!music(url))
    }

    @Test func matchingIsCaseSensitive() {
        #expect(!Rules.isMusicHost("SPOTIFY.COM"))
    }

    @Test func aNilHostNeverMatches() {
        #expect(!Rules.isMusicHost(nil))
    }

    @Test func anActiveSinglePageMusicFavoriteShowsParticles() {
        #expect(Rules.showsMusic(singlePage: true, status: .active, savedURL: spotify))
    }

    @Test func splitFavoritesNeverShowParticles() {
        #expect(!Rules.showsMusic(singlePage: false, status: .active, savedURL: spotify))
    }

    @Test(arguments: [FavoriteMediaSessionStatus.ducking, .suspended, .inactive])
    func aStatusOtherThanActiveShowsNoParticles(status: FavoriteMediaSessionStatus) {
        #expect(!Rules.showsMusic(singlePage: true, status: status, savedURL: spotify))
    }

    @Test func noEngineSelectorKeepsParticlesHidden() {
        #expect(!Rules.showsMusic(singlePage: true, status: nil, savedURL: spotify))
    }

    @Test func aSavedHostOffTheListShowsNoParticles() {
        #expect(!Rules.showsMusic(singlePage: true, status: .active, savedURL: "https://example.test"))
    }

    @Test(arguments: [(0, FavoriteMediaSessionStatus.active), (1, .ducking), (2, .suspended), (3, .inactive)])
    func theMediaSessionStatusFollowsTheEngineOrder(raw: Int, expected: FavoriteMediaSessionStatus) {
        #expect(FavoriteMediaSessionStatus(rawStatus: raw) == expected)
    }

    @Test(arguments: [7, -1])
    func anOutOfRangeStatusIsInactive(raw: Int) {
        #expect(FavoriteMediaSessionStatus(rawStatus: raw) == .inactive)
    }

    private func recording(camera: Bool = false, microphone: Bool = false, tab: Bool = false, window: Bool = false,
                           display: Bool = false, mirrored: Bool = false, shared: Bool = false) -> Bool {
        Rules.isRecording(camera: camera, microphone: microphone, tab: tab, window: window, display: display, mirrored: mirrored, shared: shared)
    }

    @Test func aCameraOrMicrophoneIsRecording() {
        #expect(recording(camera: true))
        #expect(recording(microphone: true))
        #expect(recording(camera: true, microphone: true))
    }

    @Test func beingMirroredIsCapturing() {
        #expect(recording(mirrored: true))
    }

    @Test func noCaptureShowsNoDot() {
        #expect(!recording())
    }

    @Test func desktopCapturingAloneShowsNoDot() {
        #expect(!recording(window: true))
        #expect(!recording(display: true))
    }

    @Test func capturingAnotherTabShowsNoDot() {
        #expect(!recording(tab: true))
    }

    @Test func aDisplayMediaSourceFlagFeedsNoDot() {
        #expect(!recording(shared: true))
    }

    @Test func aTestedTraitShowsAlongsideDesktopCapture() {
        #expect(recording(display: true, mirrored: true))
    }

    @Test func theDotSitsAtTheTopRightCorner() {
        #expect(G.dot(in: tileBounds) == CGRect(x: 46, y: 33, width: 8, height: 8))
    }

    @Test func theBadgeSitsAtTheBottomRightCorner() {
        #expect(G.badge(in: tileBounds) == CGRect(x: 44, y: -4, width: 20, height: 20))
    }

    @Test func theBadgeImageIsCentredAtSixteenPoints() {
        #expect(G.badgeIcon(in: CGRect(x: 0, y: 0, width: 20, height: 20)) == CGRect(x: 2, y: 2, width: 16, height: 16))
    }

    @Test func theParticlesAreInsetThirtyAndRaisedEight() {
        #expect(G.particles(in: tileBounds) == CGRect(x: -30, y: -38, width: 120, height: 107))
    }

    @Test func aFlippedHostUsesTheRectangleDirectly() {
        #expect(G.place(G.dot(in: tileBounds), in: tileBounds, flipped: true) == G.dot(in: tileBounds))
    }

    @Test func anUnflippedHostKeepsTheDotAtTheBottomRight() {
        #expect(G.place(G.dot(in: tileBounds), in: tileBounds, flipped: false) == CGRect(x: 46, y: 6, width: 8, height: 8))
    }

    @Test func anUnflippedHostKeepsTheBadgeAtTheTopRight() {
        #expect(G.place(G.badge(in: tileBounds), in: tileBounds, flipped: false) == CGRect(x: 44, y: 31, width: 20, height: 20))
    }

    @Test func aCollapsedBadgeScalesToATenth() {
        let collapsed = G.collapsedBadgeTransform(tileBounds: tileBounds, badgePosition: CGPoint(x: 54, y: 6))
        #expect(close(collapsed.m11, 0.1))
        #expect(close(collapsed.m22, 0.1))
        #expect(close(collapsed.m33, 1))
    }

    @Test func aCollapsedBadgeMovesOntoTheTileCentre() {
        let collapsed = G.collapsedBadgeTransform(tileBounds: tileBounds, badgePosition: CGPoint(x: 54, y: 6))
        #expect(close(collapsed.m41, -24))
        #expect(close(collapsed.m42, 17.5))
    }

    @Test func theBadgeSpringHasItsRecoveredParameters() {
        let spring = FavoriteTileSpring.make(keyPath: "opacity")
        #expect(close(spring.mass, 1))
        #expect(close(spring.stiffness, pow(2 * .pi / 0.4, 2)))
        #expect(close(spring.damping, 4 * .pi * 0.6 / 0.4))
        #expect(close(spring.duration, spring.settlingDuration))
    }

    @Test func theParticleCellsAreTwoWithTheirBirthRates() {
        #expect(FavoriteParticleCellConfiguration.cells.map(\.birthRate) == [1.4, 1.0])
    }

    @MainActor @Test func theEmitterIsASixBySixCircleBackingTheView() {
        let view = FavoriteMusicParticlesView(dark: true)
        #expect(view.layer === view.emitter)
        #expect(view.emitter.emitterShape == .circle)
        #expect(view.emitter.emitterSize == CGSize(width: 6, height: 6))
    }

    @MainActor @Test func theParticleViewIsUnflippedSoItsLongitudeRises() {
        #expect(!FavoriteMusicParticlesView(dark: true).isFlipped)
    }

    @MainActor @Test func theEmitterKeepsItsLayerDefaults() {
        let emitter = FavoriteMusicParticlesView(dark: true).emitter
        #expect(emitter.renderMode == .unordered)
        #expect(emitter.emitterMode == .volume)
        #expect(emitter.birthRate == 1)
        #expect(emitter.velocity == 1)
        #expect(emitter.scale == 1)
    }

    @MainActor private var particleCells: [CAEmitterCell] { FavoriteMusicParticlesView(dark: true).emitter.emitterCells ?? [] }

    @MainActor @Test func theEmitterHasTwoCellsInSpriteOrder() {
        let cells = particleCells
        #expect(cells.count == 2)
        #expect(cells[0].birthRate == 1.4)
        #expect(cells[1].birthRate == 1.0)
    }

    @MainActor @Test(arguments: [0, 1])
    func eachCellKeepsItsRecoveredMotion(index: Int) {
        let cell = particleCells[index]
        #expect(cell.lifetime == 2)
        #expect(cell.lifetimeRange == 0)
        #expect(cell.scale == 0)
        #expect(close(cell.scaleRange, 0.2))
        #expect(cell.scaleSpeed == 1)
        #expect(cell.alphaRange == 0.15)
        #expect(cell.alphaSpeed == -0.5)
        #expect(cell.emissionLatitude == 0)
        #expect(cell.emissionLongitude == .pi / 2)
        #expect(cell.emissionRange == 1.0471975511965976)
        #expect(cell.velocity == 20)
        #expect(cell.velocityRange == 5)
    }

    @MainActor @Test(arguments: [0, 1])
    func eachCellHasNoSpinAccelerationOrOtherOverrides(index: Int) {
        let cell = particleCells[index]
        #expect(cell.spin == 0)
        #expect(cell.spinRange == 0)
        #expect(cell.xAcceleration == 0)
        #expect(cell.yAcceleration == 0)
        #expect(cell.zAcceleration == 0)
        #expect(cell.contentsScale == 1)
        #expect(cell.name == nil)
    }

    @MainActor @Test(arguments: [0, 1])
    func eachCellDrawsAParcSprite(index: Int) {
        #expect(particleCells[index].contents != nil)
    }

    @MainActor @Test func theDarkTintIsWhiteAtPointEight() throws {
        let cell = try #require(particleCells.first)
        let cgColor = try #require(cell.color)
        let color = try #require(NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB))
        #expect(close(color.redComponent, 1))
        #expect(close(color.alphaComponent, 0.8))
    }

    @MainActor @Test func theLightTintIsBlackAtPointSix() throws {
        let cell = try #require(FavoriteMusicParticlesView(dark: false).emitter.emitterCells?.first)
        let cgColor = try #require(cell.color)
        let color = try #require(NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB))
        #expect(close(color.redComponent, 0))
        #expect(close(color.alphaComponent, 0.6))
    }

    @MainActor @Test func theNoteSpritesAreSixBySixTemplates() {
        #expect(FavoriteNoteSprites.single.size == NSSize(width: 6, height: 6))
        #expect(FavoriteNoteSprites.pair.size == NSSize(width: 6, height: 6))
        #expect(FavoriteNoteSprites.single.isTemplate)
        #expect(FavoriteNoteSprites.pair.isTemplate)
    }

    @MainActor @Test func theTwoNoteShapesDiffer() {
        #expect(FavoriteNoteSprites.single.tiffRepresentation != FavoriteNoteSprites.pair.tiffRepresentation)
    }

    @Test(arguments: [(false, false, true), (true, false, false), (false, true, false), (true, true, false)])
    func aTileDimsOnlyWhenItsWindowIsNeitherKeyNorMain(isKey: Bool, isMain: Bool, dims: Bool) {
        #expect(Rules.shouldDim(isKey: isKey, isMain: isMain) == dims)
    }

    typealias Skip = FavoriteOverlayPresentationSkip

    @Test func aFirstFingerprintNeverSkips() {
        #expect(!Skip.shouldSkip(previous: nil, next: "a"))
    }

    @Test func anIdenticalFingerprintSkips() {
        #expect(Skip.shouldSkip(previous: "a", next: "a"))
    }

    @Test func aChangedFingerprintDoesNotSkip() {
        #expect(!Skip.shouldSkip(previous: "a", next: "b"))
    }

    @Test func anIdenticalGatedTokenSkips() {
        #expect(Skip.shouldSkip(previous: Skip.gatedToken, next: Skip.gatedToken))
    }

    @Test func aListedMusicHostWithTheBridgeMayReadTheStatus() {
        #expect(Skip.needsMediaSessionRead(savedURL: spotify, engineRespondsToStatus: true))
    }

    @Test func withoutTheBridgeTheStatusIsNotRead() {
        #expect(!Skip.needsMediaSessionRead(savedURL: spotify, engineRespondsToStatus: false))
    }

    @Test func aNonMusicHostNeverReadsTheStatus() {
        #expect(!Skip.needsMediaSessionRead(savedURL: "https://example.test", engineRespondsToStatus: true))
    }

    private let tileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let peekID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func token(recording: Bool = false, music: Bool = false) -> String {
        Skip.tileToken(id: tileID, pageIdentifier: "page-a", recording: recording, badge: nil, developerTab: false, music: music)
    }

    @Test func anIdleTileTokenIsAStableNoOp() {
        #expect(Skip.shouldSkip(previous: token(), next: token()))
    }

    @Test func aRecordingBitChangeDoesNotSkip() {
        #expect(!Skip.shouldSkip(previous: token(), next: token(recording: true)))
    }

    @Test func aMusicBitChangeDoesNotSkip() {
        #expect(!Skip.shouldSkip(previous: token(), next: token(music: true)))
    }

    @Test func distinctPeekBadgePixelsProduceDistinctTokens() {
        #expect(Skip.badgeToken(peekID: peekID, tiffData: Data([1, 2, 3])) != Skip.badgeToken(peekID: peekID, tiffData: Data([1, 2, 4])))
    }

    @Test func samePeekBadgePixelsAreStable() {
        #expect(Skip.badgeToken(peekID: peekID, tiffData: Data([1, 2, 3])) == Skip.badgeToken(peekID: peekID, tiffData: Data([1, 2, 3])))
    }

    @Test func anEmptyTiffTokenIsFNVOneAOverZeroBytes() {
        #expect(Skip.tiffDataToken(Data()) == "0.cbf29ce484222325")
    }

    typealias LayerSkip = FavoriteOverlayLayerLayoutSkip

    private let dotBounds = CGRect(x: 0, y: 0, width: 8, height: 8)
    private var dotInner: CGRect { dotBounds.insetBy(dx: FavoriteTileOverlayGeometry.dotStroke, dy: FavoriteTileOverlayGeometry.dotStroke) }

    private func dotSkips(outerFrame: CGRect? = nil, outerRadius: CGFloat? = nil) -> Bool {
        LayerSkip.shouldSkipDot(outerFrame: outerFrame ?? dotBounds, innerFrame: dotInner,
                                outerRadius: outerRadius ?? dotBounds.height / 2, innerRadius: dotInner.height / 2, bounds: dotBounds)
    }

    @Test func matchingDotFramesAndRadiiSkip() {
        #expect(dotSkips())
    }

    @Test func aMismatchedOuterDotFrameDoesNotSkip() {
        #expect(!dotSkips(outerFrame: .zero))
    }

    @Test func aMismatchedOuterDotRadiusDoesNotSkip() {
        #expect(!dotSkips(outerRadius: 0))
    }

    private let ringBounds = CGRect(x: 0, y: 0, width: 60, height: 47)
    private var ringPath: CGPath { FavoriteTilePaths.highlightRing(bounds: ringBounds) }

    @Test func matchingRingFramesAndPathsSkip() {
        #expect(LayerSkip.shouldSkipRing(ringFrame: ringBounds, foregroundFrame: ringBounds, ringPath: ringPath,
                                         foregroundPath: ringPath, bounds: ringBounds, path: ringPath))
    }

    @Test func aMismatchedRingFrameDoesNotSkip() {
        #expect(!LayerSkip.shouldSkipRing(ringFrame: .zero, foregroundFrame: ringBounds, ringPath: ringPath,
                                          foregroundPath: ringPath, bounds: ringBounds, path: ringPath))
    }

    @Test func aMissingRingPathDoesNotSkip() {
        #expect(!LayerSkip.shouldSkipRing(ringFrame: ringBounds, foregroundFrame: ringBounds, ringPath: nil,
                                          foregroundPath: ringPath, bounds: ringBounds, path: ringPath))
    }
}
