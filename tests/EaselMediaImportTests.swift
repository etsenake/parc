import Foundation

@main
struct EaselMediaImportTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    static let pdf = Data("%PDF-1.4\n".utf8)
    static let wav = Data("RIFF....WAVEfmt ".utf8)
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!

    @MainActor static func main() {
        typealias Plan = EaselMediaImportPlan
        expect(Plan.classify(sniffed: EaselAssetType.sniff(png), fileExtension: "png", isImage: true, isMovie: false, byteCount: png.count) == .image, "png")
        expect(Plan.classify(sniffed: nil, fileExtension: "jpg", isImage: true, isMovie: false, byteCount: 10) == .image, "jpeg by type")
        expect(Plan.classify(sniffed: EaselAssetType.sniff(pdf), fileExtension: "pdf", isImage: false, isMovie: false, byteCount: pdf.count) == .pdf, "pdf")
        expect(Plan.classify(sniffed: EaselAssetType.sniff(wav), fileExtension: "wav", isImage: false, isMovie: false, byteCount: wav.count) == .audio(.wav), "wav")
        expect(Plan.classify(sniffed: nil, fileExtension: "MP3", isImage: false, isMovie: false, byteCount: 10) == .audio(.mp3), "audio by extension")
        expect(Plan.classify(sniffed: nil, fileExtension: "mov", isImage: false, isMovie: true, byteCount: 10) == .video(.mp4), "movie by type")
        expect(Plan.classify(sniffed: .mov, fileExtension: "parcx", isImage: false, isMovie: false, byteCount: 10) == .video(.mov), "video by bytes")
        let frame = EaselAssetType.sniff(Data([0xFF, 0xFB, 0x90, 0x64]) + Data(repeating: 0, count: 16))
        expect(Plan.classify(sniffed: frame, fileExtension: "zip", isImage: false, isMovie: false, byteCount: 20) == .file, "known extension beats a frame sniff")
        expect(Plan.classify(sniffed: frame, fileExtension: "txt", isImage: false, isMovie: false, byteCount: 20) == .file, "text is not an mp3")
        expect(Plan.classify(sniffed: frame, fileExtension: nil, isImage: false, isMovie: false, byteCount: 20) == .audio(.mp3), "unknown extension sniffs mp3")
        expect(EaselAssetType.sniff(Data([0xFF, 0xFB, 0xF0, 0x64])) == nil && EaselAssetType.sniff(Data([0xFF, 0xFB, 0x9C, 0x64])) == nil, "reserved bitrate and sample rate are not mp3")
        expect(Plan.classify(sniffed: .mov, fileExtension: "mov", isImage: false, isMovie: true, byteCount: 10) == .video(.mov), "mov keeps its type")
        expect(Plan.classify(sniffed: nil, fileExtension: "zip", isImage: false, isMovie: false, byteCount: 10) == .file, "other file")
        expect(Plan.classify(sniffed: nil, fileExtension: nil, isImage: false, isMovie: false, byteCount: 10) == .file, "no extension")
        expect(Plan.classify(sniffed: nil, fileExtension: "zip", isImage: false, isMovie: false, byteCount: 0) == nil, "empty refused")

        expect(Plan.Source.audio(.m4a).itemKind == .audio && Plan.Source.file.itemKind == .file, "kinds")
        expect(Plan.Source.video(.mp4).needsFacts && Plan.Source.audio(.mp3).needsFacts && !Plan.Source.pdf.needsFacts, "facts")
        if case .pdfTooLarge = Plan.tooLargeError(for: .pdf) { expect(true, "pdf limit") } else { expect(false, "pdf limit") }
        if case .audioTooLarge = Plan.tooLargeError(for: .audio(.mp3)) { expect(true, "audio limit") } else { expect(false, "audio limit") }

        expect(Plan.cleanFileName("  Song\u{7}.mp3 ") == "Song.mp3", "name cleaned")
        expect(Plan.cleanFileName("   ") == nil, "blank name")
        expect(Plan.cleanFileName(String(repeating: "a", count: 3000))?.utf8.count == 1024, "long name")
        expect(Plan.linkFileName(URL(string: "https://x.test/a/My%20Song.mp3")!) == "My Song.mp3", "link name")
        expect(Plan.linkFileName(URL(string: "https://x.test/")!) == nil, "no link name")

        expect(Plan.isLinkable(URL(string: "https://x.test/a.mp4")!, kind: .video), "https video")
        expect(Plan.isLinkable(URL(string: "http://x.test/a.mp3")!, kind: .audio), "http audio")
        expect(!Plan.isLinkable(URL(string: "ftp://x.test/a.mp3")!, kind: .audio), "ftp")
        expect(!Plan.isLinkable(URL(string: "https://x.test/a.pdf")!, kind: .pdf), "pdf link")
        expect(!Plan.isLinkable(URL(string: "file:///a.mp3")!, kind: .audio), "file url")

        expect(Plan.pageSize(width: 100, height: 200, rotation: 90)?.width == 200, "rotated page")
        expect(Plan.pageSize(width: 100, height: 200, rotation: 0)?.width == 100, "upright page")
        expect(Plan.pageSize(width: 0, height: 200, rotation: 0) == nil, "empty page")

        let sizes = [EaselMediaPlacement.filledSize(for: .audio), EaselMediaPlacement.filledSize(for: .pdf, natural: (600, 800)),
                     EaselMediaPlacement.filledSize(for: .file)]
        let row = Plan.layout(sizes, centre: EaselPoint(x: 1000, y: 500))
        expect(row.count == 3, "row count")
        expect(row[0].x < row[1].x && row[1].x < row[2].x, "row order")
        expect(row[1].x >= row[0].x + row[0].width + 24 - 1, "row gap")
        let middle = row.map { $0.y + $0.height / 2 }
        expect(middle.allSatisfy { abs($0 - 500) <= 1 }, "row centred vertically")
        expect(Plan.layout([], centre: EaselPoint(x: 0, y: 0)).isEmpty, "empty row")
        print("EaselMediaImportTests passed (\(assertions) assertions)")
    }
}
