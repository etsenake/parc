import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteMediaLayoutTests {
    let retina = CGSize(width: 1200, height: 600)
    let plain = CGSize(width: 300, height: 200)

    @Test func pixelsAt144DpiHalveIntoPoints() {
        #expect(NoteMediaLayout.pointSize(pixelWidth: 2400, pixelHeight: 1200, dpiWidth: 144, dpiHeight: 144) == retina)
    }

    @Test func missingDpiReadsAs72() {
        #expect(NoteMediaLayout.pointSize(pixelWidth: 300, pixelHeight: 200, dpiWidth: nil, dpiHeight: nil) == plain)
    }

    @Test func zeroDpiFallsBackTo72() {
        #expect(NoteMediaLayout.pointSize(pixelWidth: 100, pixelHeight: 50, dpiWidth: 0, dpiHeight: 0) == CGSize(width: 100, height: 50))
    }

    @Test(arguments: [
        (nil, 1200.0, 700.0, 700.0), (nil, 64, 700, 72), (nil, 300, 700, 300), (0.5, 1200, 700, 350), (1.4, 0, 700, 700),
        (0.01, 0, 700, 72), (.nan, 0, 640, 640), (0.5, 0, 40, 40),
    ] as [(Double?, CGFloat, CGFloat, CGFloat)])
    func displayWidthFollowsFractionNaturalWidthAndTheColumn(fraction: Double?, natural: CGFloat, column: CGFloat, expected: CGFloat) {
        let size: CGSize? = natural > 0 ? CGSize(width: natural, height: natural / 2) : nil
        #expect(NoteMediaLayout.displayWidth(fraction: fraction, natural: size, columnWidth: column) == expected)
    }

    @Test func heightFollowsAspectRatio() {
        #expect(NoteMediaLayout.displayHeight(width: 350, natural: retina) == 175)
    }

    @Test func unknownSizesUseSixteenByNine() {
        #expect(NoteMediaLayout.displayHeight(width: 320, natural: nil) == 180)
    }

    @Test(arguments: [(NoteAlignment.left, 0.0), (.center, 200), (.right, 400)] as [(NoteAlignment, CGFloat)])
    func alignmentPlacesTheImageInTheColumn(alignment: NoteAlignment, x: CGFloat) {
        #expect(NoteMediaLayout.originX(width: 300, alignment: alignment, columnWidth: 700) == x)
    }

    @Test(arguments: [
        (20.0, NoteMediaEdge.trailing, NoteAlignment.center, 340.0), (20, .leading, .center, 260), (20, .trailing, .left, 320),
        (-20, .leading, .left, 320), (-30, .leading, .right, 330),
    ] as [(CGFloat, NoteMediaEdge, NoteAlignment, CGFloat)])
    func dragsResizeFromTheEdgeTheAlignmentImplies(delta: CGFloat, edge: NoteMediaEdge, alignment: NoteAlignment, width: CGFloat) {
        #expect(NoteMediaLayout.rawResize(start: 300, dragDelta: delta, edge: edge, alignment: alignment) == width)
    }

    @Test func insideTheLimitsThereIsNoRubberBand() {
        #expect(NoteMediaLayout.rubberBanded(500, columnWidth: 700) == 500)
    }

    @Test func pastTheColumnTheDragResists() {
        let over = NoteMediaLayout.rubberBanded(900, columnWidth: 700)
        #expect(over > 700)
        #expect(over < 700 + NoteMediaLayout.rubberBandDimension)
    }

    @Test func underTheMinimumTheDragResists() {
        let under = NoteMediaLayout.rubberBanded(10, columnWidth: 700)
        #expect(under < 72)
        #expect(under > 72 - NoteMediaLayout.rubberBandDimension)
    }

    @Test(arguments: [0.0, -4])
    func noExcessMeansNoStretch(excess: CGFloat) {
        #expect(NoteMediaLayout.rubberBand(excess) == 0)
    }

    @Test func stretchNeverPassesItsDimension() {
        #expect(NoteMediaLayout.rubberBand(1000) < NoteMediaLayout.rubberBandDimension)
    }

    @Test func clampingCapsAtTheColumn() {
        #expect(NoteMediaLayout.clamped(900, columnWidth: 700) == 700)
    }

    @Test func clampingFloorsAtTheMinimum() {
        #expect(NoteMediaLayout.clamped(5, columnWidth: 700) == 72)
    }

    @Test(arguments: [
        (350.0, 700.0, 0.5), (696, 700, 1), (233.3333, 700, 0.333), (2000, 700, 1), (300, 0, 1),
    ] as [(CGFloat, CGFloat, Double)])
    func storedFractionsSnapAndKeepThreeDecimals(width: CGFloat, column: CGFloat, fraction: Double) {
        #expect(NoteMediaLayout.storedFraction(width: width, columnWidth: column) == fraction)
    }

    @Test func storedFractionsRoundTripToTheDraggedWidth() {
        let restored = NoteMediaLayout.displayWidth(fraction: NoteMediaLayout.storedFraction(width: 413, columnWidth: 700), natural: nil, columnWidth: 700)
        #expect(abs(restored - 413) <= 1)
    }

    @Test(arguments: [
        (0, "0 bytes"), (1, "1 byte"), (999, "999 bytes"), (1000, "1 KB"), (1536, "1.5 KB"), (250_000, "250 KB"), (999_960, "1 MB"),
        (4_200_000, "4.2 MB"), (3_000_000_000, "3 GB"), (-5, ""),
    ] as [(Int64, String)])
    func fileSizesReadInPlainUnits(bytes: Int64, text: String) {
        #expect(NoteMediaFormat.fileSize(bytes) == text)
    }

    @Test(arguments: [(0.0, "0:00"), (5.9, "0:05"), (65, "1:05"), (3723, "1:02:03"), (.infinity, "0:00")] as [(TimeInterval, String)])
    func durationsReadAsClockTimes(seconds: TimeInterval, text: String) {
        #expect(NoteMediaFormat.duration(seconds) == text)
    }

    @Test(arguments: [("https://www.Example.com/a", "example.com"), ("https://docs.swift.org", "docs.swift.org")])
    func hostsDropWwwButKeepSubdomains(address: String, host: String) throws {
        #expect(NoteMediaFormat.displayHost(try #require(URL(string: address))) == host)
    }

    func resolver(_ document: URL?) -> (String) -> URL? {
        let environment = NoteDetachedEnvironment(documentURL: document)
        return { environment.resolve($0) }
    }

    let note = URL(fileURLWithPath: "/Users/me/Notes/Trip.md")

    @Test(arguments: [nil, "   "] as [String?])
    func nilAndBlankSourcesAreEmpty(text: String?) {
        #expect(NoteMediaSource(text, resolve: resolver(note)) == .empty)
    }

    @Test func relativePathsResolveBesideTheNote() {
        #expect(NoteMediaSource("Attachments/Beach%20Day.png", resolve: resolver(note)) == .local(URL(fileURLWithPath: "/Users/me/Notes/Attachments/Beach Day.png")))
    }

    @Test func localFileNamesDecode() {
        #expect(NoteMediaSource("Attachments/Beach%20Day.png", resolve: resolver(note)).fileName == "Beach Day.png")
    }

    @Test func displayPathsAreReadable() {
        #expect(NoteMediaSource("Attachments/Beach%20Day.png", resolve: resolver(note)).displayPath(original: nil).hasSuffix("Attachments/Beach Day.png"))
    }

    @Test func parentPathsStandardize() {
        #expect(NoteMediaSource("../Shared/map.jpg", resolve: resolver(note)).url?.path == "/Users/me/Shared/map.jpg")
    }

    @Test func webSourcesStayRemote() {
        #expect(NoteMediaSource("https://example.com/cat.gif", resolve: resolver(note)) == .remote(URL(string: "https://example.com/cat.gif")!))
    }

    @Test func remoteNamesComeFromThePath() {
        #expect(NoteMediaSource("https://example.com/cat.gif", resolve: resolver(note)).fileName == "cat.gif")
    }

    @Test func bareHostsNameThemselves() {
        #expect(NoteMediaSource("https://example.com/", resolve: resolver(note)).fileName == "example.com")
    }

    @Test func fileURLsAreLocal() {
        #expect(NoteMediaSource("file:///tmp/x.png", resolve: resolver(note)) == .local(URL(fileURLWithPath: "/tmp/x.png")))
    }

    @Test func otherSchemesNeverLoad() {
        #expect(NoteMediaSource("javascript:alert(1)", resolve: resolver(note)) == .unresolved("javascript:alert(1)"))
    }

    @Test func relativePathsNeedADocument() {
        let orphan = NoteMediaSource("pics/a.png", resolve: resolver(nil))
        #expect(orphan == .unresolved("pics/a.png"))
        #expect(orphan.url == nil)
    }

    @Test func unresolvedPathsShowWhatWasWritten() {
        let orphan = NoteMediaSource("pics/a.png", resolve: resolver(nil))
        #expect(orphan.displayPath(original: "pics/a.png") == "pics/a.png")
        #expect(orphan.fileName == "a.png")
    }

    @Test(arguments: [
        ("example.com/page", "https://example.com/page"), (" http://a.io ", "http://a.io"),
    ])
    func webAddressesGetHttpsUnlessExplicit(text: String, address: String) {
        #expect(NoteMediaSource.webURL(from: text)?.absoluteString == address)
    }

    @Test(arguments: ["not a url", "hello", "ftp://a.io/x", ".com"])
    func textThatIsNotAWebLinkIsRefused(text: String) {
        #expect(NoteMediaSource.webURL(from: text) == nil)
    }

    @Test(arguments: [
        ("PNG", NoteBlockKind.image), ("heic", .image), ("mov", .video), ("mp4", .video), ("m4a", .audio), ("mp3", .audio),
        ("pdf", .pdf), ("", .file),
    ] as [(String, NoteBlockKind)])
    func extensionsMapToBlockKinds(ext: String, kind: NoteBlockKind) {
        #expect(NoteMediaFileType.blockKind(forExtension: ext) == kind)
    }

    @Test(arguments: [
        ("/a.pdf", NoteBlockKind.pdf, true), ("/a.png", .pdf, false), ("/a.pdf", .file, true), ("/a.zip", .file, true), ("/a.zip", .image, false),
    ] as [(String, NoteBlockKind, Bool)])
    func blocksAcceptTheFilesTheyCanShow(path: String, kind: NoteBlockKind, accepted: Bool) {
        #expect(NoteMediaFileType.accepts(URL(fileURLWithPath: path), for: kind) == accepted)
    }

    @Test func thePdfPickerShowsOnlyPdfs() {
        #expect(NoteMediaFileType.contentTypes(for: .pdf) == [.pdf])
    }

    @Test(arguments: [("/a.GIF", true), ("/a.jpg", false)])
    func onlyGifsAnimate(path: String, animatable: Bool) {
        #expect(NoteMediaFileType.isAnimatable(URL(fileURLWithPath: path)) == animatable)
    }
}
