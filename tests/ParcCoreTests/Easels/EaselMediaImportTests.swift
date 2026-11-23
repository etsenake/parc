import Foundation
import Testing
@testable import ParcCore

struct EaselMediaImportTests {
    typealias Plan = EaselMediaImportPlan

    struct Classification: CustomTestStringConvertible, Sendable {
        let name: String
        let sniffed: EaselAssetType?
        let fileExtension: String?
        let isImage: Bool
        let isMovie: Bool
        let byteCount: Int
        let source: Plan.Source?
        var testDescription: String { name }

        init(_ name: String, sniffed: EaselAssetType? = nil, _ fileExtension: String?, image: Bool = false, movie: Bool = false,
             bytes: Int = 10, _ source: Plan.Source?) {
            self.name = name
            self.sniffed = sniffed
            self.fileExtension = fileExtension
            isImage = image
            isMovie = movie
            byteCount = bytes
            self.source = source
        }
    }

    private static let pdf = Data("%PDF-1.4\n".utf8)
    private static let wav = Data("RIFF....WAVEfmt ".utf8)
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
    private static let frame = EaselAssetType.sniff(Data([0xFF, 0xFB, 0x90, 0x64]) + Data(repeating: 0, count: 16))

    @Test(arguments: [
        Classification("png", sniffed: EaselAssetType.sniff(png), "png", image: true, bytes: png.count, .image),
        Classification("jpeg by type", "jpg", image: true, .image),
        Classification("pdf", sniffed: EaselAssetType.sniff(pdf), "pdf", bytes: pdf.count, .pdf),
        Classification("wav", sniffed: EaselAssetType.sniff(wav), "wav", bytes: wav.count, .audio(.wav)),
        Classification("audio by extension", "MP3", .audio(.mp3)),
        Classification("movie by type", "mov", movie: true, .video(.mp4)),
        Classification("video by bytes", sniffed: .mov, "parcx", .video(.mov)),
        Classification("known extension beats a frame sniff", sniffed: frame, "zip", bytes: 20, .file),
        Classification("text is not an mp3", sniffed: frame, "txt", bytes: 20, .file),
        Classification("unknown extension sniffs mp3", sniffed: frame, nil, bytes: 20, .audio(.mp3)),
        Classification("mov keeps its type", sniffed: .mov, "mov", movie: true, .video(.mov)),
        Classification("other file", "zip", .file),
        Classification("no extension", nil, .file),
        Classification("empty refused", "zip", bytes: 0, nil),
    ])
    func importsAreClassifiedByBytesTypeAndExtension(entry: Classification) {
        #expect(Plan.classify(sniffed: entry.sniffed, fileExtension: entry.fileExtension, isImage: entry.isImage,
                              isMovie: entry.isMovie, byteCount: entry.byteCount) == entry.source)
    }

    @Test(arguments: [Data([0xFF, 0xFB, 0xF0, 0x64]), Data([0xFF, 0xFB, 0x9C, 0x64])])
    func reservedBitrateAndSampleRateAreNotMP3(bytes: Data) {
        #expect(EaselAssetType.sniff(bytes) == nil)
    }

    @Test func sourcesMapToTheirItemKinds() {
        #expect(Plan.Source.audio(.m4a).itemKind == .audio)
        #expect(Plan.Source.file.itemKind == .file)
    }

    @Test func videoAndAudioNeedFactsButPDFsDoNot() {
        #expect(Plan.Source.video(.mp4).needsFacts)
        #expect(Plan.Source.audio(.mp3).needsFacts)
        #expect(!Plan.Source.pdf.needsFacts)
    }

    @Test func pdfsHaveTheirOwnSizeLimitError() {
        guard case .pdfTooLarge = Plan.tooLargeError(for: .pdf) else {
            Issue.record("a PDF over the limit reports the PDF limit")
            return
        }
    }

    @Test func audioHasItsOwnSizeLimitError() {
        guard case .audioTooLarge = Plan.tooLargeError(for: .audio(.mp3)) else {
            Issue.record("audio over the limit reports the audio limit")
            return
        }
    }

    @Test func fileNamesAreCleaned() {
        #expect(Plan.cleanFileName("  Song\u{7}.mp3 ") == "Song.mp3")
    }

    @Test func blankFileNamesAreDropped() {
        #expect(Plan.cleanFileName("   ") == nil)
    }

    @Test func longFileNamesAreCapped() {
        #expect(Plan.cleanFileName(String(repeating: "a", count: 3000))?.utf8.count == 1024)
    }

    @Test func linkFileNamesAreDecodedFromThePath() {
        #expect(Plan.linkFileName(URL(string: "https://x.test/a/My%20Song.mp3")!) == "My Song.mp3")
    }

    @Test func aLinkWithoutAPathHasNoFileName() {
        #expect(Plan.linkFileName(URL(string: "https://x.test/")!) == nil)
    }

    @Test(arguments: [("https://x.test/a.mp4", EaselItemKind.video), ("http://x.test/a.mp3", .audio)])
    func webMediaLinksAreLinkable(link: String, kind: EaselItemKind) {
        #expect(Plan.isLinkable(URL(string: link)!, kind: kind))
    }

    @Test(arguments: [("ftp://x.test/a.mp3", EaselItemKind.audio), ("https://x.test/a.pdf", .pdf), ("file:///a.mp3", .audio)])
    func otherLinksAreNotLinkable(link: String, kind: EaselItemKind) {
        #expect(!Plan.isLinkable(URL(string: link)!, kind: kind))
    }

    @Test func aRotatedPageSwapsItsSides() {
        #expect(Plan.pageSize(width: 100, height: 200, rotation: 90)?.width == 200)
    }

    @Test func anUprightPageKeepsItsSides() {
        #expect(Plan.pageSize(width: 100, height: 200, rotation: 0)?.width == 100)
    }

    @Test(arguments: [-90, 270, -270, 450])
    func anyQuarterTurnSwapsItsSides(rotation: Int) {
        #expect(Plan.pageSize(width: 100, height: 200, rotation: rotation)?.width == 200)
    }

    @Test func aPageWithAnOutlandishRotationStillGetsASize() {
        #expect(Plan.pageSize(width: 100, height: 200, rotation: Int.min)?.width == 100)
    }

    @Test func anEmptyPageHasNoSize() {
        #expect(Plan.pageSize(width: 0, height: 200, rotation: 0) == nil)
    }

    private static var row: [EaselRect] {
        let sizes = [EaselMediaPlacement.filledSize(for: .audio), EaselMediaPlacement.filledSize(for: .pdf, natural: (600, 800)),
                     EaselMediaPlacement.filledSize(for: .file)]
        return Plan.layout(sizes, centre: EaselPoint(x: 1000, y: 500))
    }

    @Test func importsAreLaidOutLeftToRightWithAGap() throws {
        let row = Self.row
        try #require(row.count == 3)
        #expect(row[0].x < row[1].x && row[1].x < row[2].x)
        #expect(row[1].x >= row[0].x + row[0].width + 24 - 1)
    }

    @Test func theImportRowIsCentredVertically() {
        #expect(Self.row.allSatisfy { abs($0.y + $0.height / 2 - 500) <= 1 })
    }

    @Test func nothingToImportLaysOutNothing() {
        #expect(Plan.layout([], centre: EaselPoint(x: 0, y: 0)).isEmpty)
    }
}
