import CoreGraphics
import Foundation
import UniformTypeIdentifiers

@main @MainActor
struct NoteMediaLayoutTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func near(_ lhs: CGFloat, _ rhs: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool { abs(lhs - rhs) <= tolerance }

    static func main() {
        widths()
        resizing()
        formatting()
        sources()
        fileTypes()
        print("NoteMediaLayoutTests passed")
    }

    static func widths() {
        let retina = NoteMediaLayout.pointSize(pixelWidth: 2400, pixelHeight: 1200, dpiWidth: 144, dpiHeight: 144)
        expect(retina == CGSize(width: 1200, height: 600), "144 dpi pixels halve into points")
        let plain = NoteMediaLayout.pointSize(pixelWidth: 300, pixelHeight: 200, dpiWidth: nil, dpiHeight: nil)
        expect(plain == CGSize(width: 300, height: 200), "missing dpi reads as 72")
        let zero = NoteMediaLayout.pointSize(pixelWidth: 100, pixelHeight: 50, dpiWidth: 0, dpiHeight: 0)
        expect(zero == CGSize(width: 100, height: 50), "zero dpi falls back to 72")
        expect(NoteMediaLayout.displayWidth(fraction: nil, natural: retina, columnWidth: 700) == 700, "big images cap at the column")
        expect(NoteMediaLayout.displayWidth(fraction: nil, natural: CGSize(width: 64, height: 64), columnWidth: 700) == 72,
               "tiny images still get a grabbable minimum")
        expect(NoteMediaLayout.displayWidth(fraction: nil, natural: plain, columnWidth: 700) == 300, "small images keep natural width")
        expect(NoteMediaLayout.displayWidth(fraction: 0.5, natural: retina, columnWidth: 700) == 350, "fractions scale with the column")
        expect(NoteMediaLayout.displayWidth(fraction: 1.4, natural: nil, columnWidth: 700) == 700, "fractions over one cap")
        expect(NoteMediaLayout.displayWidth(fraction: 0.01, natural: nil, columnWidth: 700) == 72, "fractions under the minimum floor")
        expect(NoteMediaLayout.displayWidth(fraction: .nan, natural: nil, columnWidth: 640) == 640, "NaN falls back to natural")
        expect(NoteMediaLayout.displayWidth(fraction: 0.5, natural: nil, columnWidth: 40) == 40, "narrow columns win over the minimum")
        expect(NoteMediaLayout.displayHeight(width: 350, natural: retina) == 175, "height follows aspect ratio")
        expect(NoteMediaLayout.displayHeight(width: 320, natural: nil) == 180, "unknown sizes use 16:9")
        expect(NoteMediaLayout.originX(width: 300, alignment: .left, columnWidth: 700) == 0, "left aligns to zero")
        expect(NoteMediaLayout.originX(width: 300, alignment: .center, columnWidth: 700) == 200, "centre splits the slack")
        expect(NoteMediaLayout.originX(width: 300, alignment: .right, columnWidth: 700) == 400, "right hugs the trailing edge")
    }

    static func resizing() {
        expect(NoteMediaLayout.rawResize(start: 300, dragDelta: 20, edge: .trailing, alignment: .center) == 340,
               "centred images grow on both sides")
        expect(NoteMediaLayout.rawResize(start: 300, dragDelta: 20, edge: .leading, alignment: .center) == 260,
               "dragging the leading edge inward shrinks a centred image twice as fast")
        expect(NoteMediaLayout.rawResize(start: 300, dragDelta: 20, edge: .trailing, alignment: .left) == 320,
               "left-aligned images grow from the trailing edge")
        expect(NoteMediaLayout.rawResize(start: 300, dragDelta: -20, edge: .leading, alignment: .left) == 320,
               "pulling the leading edge outward grows a left-aligned image")
        expect(NoteMediaLayout.rawResize(start: 300, dragDelta: -30, edge: .leading, alignment: .right) == 330,
               "right-aligned images grow leftward")
        expect(NoteMediaLayout.rubberBanded(500, columnWidth: 700) == 500, "inside the limits there is no rubber band")
        let over = NoteMediaLayout.rubberBanded(900, columnWidth: 700)
        expect(over > 700 && over < 700 + NoteMediaLayout.rubberBandDimension, "past the column the drag resists")
        let under = NoteMediaLayout.rubberBanded(10, columnWidth: 700)
        expect(under < 72 && under > 72 - NoteMediaLayout.rubberBandDimension, "under the minimum the drag resists")
        expect(NoteMediaLayout.rubberBand(0) == 0 && NoteMediaLayout.rubberBand(-4) == 0, "no excess means no stretch")
        expect(NoteMediaLayout.rubberBand(1000) < NoteMediaLayout.rubberBandDimension, "stretch never passes its dimension")
        expect(NoteMediaLayout.clamped(900, columnWidth: 700) == 700, "clamping caps at the column")
        expect(NoteMediaLayout.clamped(5, columnWidth: 700) == 72, "clamping floors at the minimum")
        expect(NoteMediaLayout.storedFraction(width: 350, columnWidth: 700) == 0.5, "half the column stores 0.5")
        expect(NoteMediaLayout.storedFraction(width: 696, columnWidth: 700) == 1, "near-full width snaps to one")
        expect(NoteMediaLayout.storedFraction(width: 233.3333, columnWidth: 700) == 0.333, "fractions keep three decimals")
        expect(NoteMediaLayout.storedFraction(width: 2000, columnWidth: 700) == 1, "overshoot stores full width")
        expect(NoteMediaLayout.storedFraction(width: 300, columnWidth: 0) == 1, "zero columns store full width")
        let restored = NoteMediaLayout.displayWidth(fraction: NoteMediaLayout.storedFraction(width: 413, columnWidth: 700),
                                                    natural: nil, columnWidth: 700)
        expect(near(restored, 413, 1), "stored fractions round-trip to the dragged width")
    }

    static func formatting() {
        expect(NoteMediaFormat.fileSize(0) == "0 bytes", "zero bytes")
        expect(NoteMediaFormat.fileSize(1) == "1 byte", "one byte is singular")
        expect(NoteMediaFormat.fileSize(999) == "999 bytes", "bytes under a kilobyte")
        expect(NoteMediaFormat.fileSize(1000) == "1 KB", "a round kilobyte drops the decimal")
        expect(NoteMediaFormat.fileSize(1536) == "1.5 KB", "kilobytes keep one decimal")
        expect(NoteMediaFormat.fileSize(250_000) == "250 KB", "three digits drop decimals")
        expect(NoteMediaFormat.fileSize(999_960) == "1 MB", "rounding up rolls into the next unit")
        expect(NoteMediaFormat.fileSize(4_200_000) == "4.2 MB", "megabytes")
        expect(NoteMediaFormat.fileSize(3_000_000_000) == "3 GB", "gigabytes")
        expect(NoteMediaFormat.fileSize(-5) == "", "negative sizes say nothing")
        expect(NoteMediaFormat.duration(0) == "0:00", "zero duration")
        expect(NoteMediaFormat.duration(5.9) == "0:05", "durations round down")
        expect(NoteMediaFormat.duration(65) == "1:05", "minutes and seconds")
        expect(NoteMediaFormat.duration(3723) == "1:02:03", "hours appear when needed")
        expect(NoteMediaFormat.duration(.infinity) == "0:00", "infinite durations read as zero")
        expect(NoteMediaFormat.displayHost(URL(string: "https://www.Example.com/a")!) == "example.com", "hosts drop www")
        expect(NoteMediaFormat.displayHost(URL(string: "https://docs.swift.org")!) == "docs.swift.org", "subdomains stay")
    }

    static func sources() {
        let note = URL(fileURLWithPath: "/Users/me/Notes/Trip.md")
        let environment = NoteDetachedEnvironment(documentURL: note)
        let resolve: (String) -> URL? = { environment.resolve($0) }
        expect(NoteMediaSource(nil, resolve: resolve) == .empty, "nil is empty")
        expect(NoteMediaSource("   ", resolve: resolve) == .empty, "blank is empty")
        let local = NoteMediaSource("Attachments/Beach%20Day.png", resolve: resolve)
        expect(local == .local(URL(fileURLWithPath: "/Users/me/Notes/Attachments/Beach Day.png")), "relative paths resolve beside the note")
        expect(local.fileName == "Beach Day.png", "file names decode")
        expect(local.displayPath(original: nil).hasSuffix("Attachments/Beach Day.png"), "display paths are readable")
        let parent = NoteMediaSource("../Shared/map.jpg", resolve: resolve)
        expect(parent.url?.path == "/Users/me/Shared/map.jpg", "parent paths standardize")
        let remote = NoteMediaSource("https://example.com/cat.gif", resolve: resolve)
        expect(remote == .remote(URL(string: "https://example.com/cat.gif")!), "web sources stay remote")
        expect(remote.fileName == "cat.gif", "remote names come from the path")
        expect(NoteMediaSource("https://example.com/", resolve: resolve).fileName == "example.com", "bare hosts name themselves")
        expect(NoteMediaSource("file:///tmp/x.png", resolve: resolve) == .local(URL(fileURLWithPath: "/tmp/x.png")), "file URLs are local")
        expect(NoteMediaSource("javascript:alert(1)", resolve: resolve) == .unresolved("javascript:alert(1)"), "other schemes never load")
        let detached = NoteDetachedEnvironment(documentURL: nil)
        let orphan = NoteMediaSource("pics/a.png", resolve: { detached.resolve($0) })
        expect(orphan == .unresolved("pics/a.png") && orphan.url == nil, "relative paths need a document")
        expect(orphan.displayPath(original: "pics/a.png") == "pics/a.png", "unresolved paths show what was written")
        expect(orphan.fileName == "a.png", "unresolved names still read")
        expect(NoteMediaSource.webURL(from: "example.com/page")?.absoluteString == "https://example.com/page", "bare domains get https")
        expect(NoteMediaSource.webURL(from: " http://a.io ")?.absoluteString == "http://a.io", "explicit schemes stay")
        expect(NoteMediaSource.webURL(from: "not a url") == nil, "spaces are not links")
        expect(NoteMediaSource.webURL(from: "hello") == nil, "words are not links")
        expect(NoteMediaSource.webURL(from: "ftp://a.io/x") == nil, "ftp is not a web link")
        expect(NoteMediaSource.webURL(from: ".com") == nil, "leading dots are not hosts")
    }

    static func fileTypes() {
        expect(NoteMediaFileType.blockKind(forExtension: "PNG") == .image, "png is an image")
        expect(NoteMediaFileType.blockKind(forExtension: "heic") == .image, "heic is an image")
        expect(NoteMediaFileType.blockKind(forExtension: "mov") == .video, "mov is a video")
        expect(NoteMediaFileType.blockKind(forExtension: "mp4") == .video, "mp4 is a video")
        expect(NoteMediaFileType.blockKind(forExtension: "m4a") == .audio, "m4a is audio")
        expect(NoteMediaFileType.blockKind(forExtension: "mp3") == .audio, "mp3 is audio")
        expect(NoteMediaFileType.blockKind(forExtension: "pdf") == .pdf, "dropped PDFs read inline")
        expect(NoteMediaFileType.accepts(URL(fileURLWithPath: "/a.pdf"), for: .pdf), "PDF blocks take PDFs")
        expect(!NoteMediaFileType.accepts(URL(fileURLWithPath: "/a.png"), for: .pdf), "PDF blocks turn away pictures")
        expect(NoteMediaFileType.accepts(URL(fileURLWithPath: "/a.pdf"), for: .file), "file blocks still take PDFs")
        expect(NoteMediaFileType.contentTypes(for: .pdf) == [.pdf], "the picker shows only PDFs")
        expect(NoteMediaFileType.blockKind(forExtension: "") == .file, "no extension is a file")
        expect(NoteMediaFileType.accepts(URL(fileURLWithPath: "/a.zip"), for: .file), "file blocks take anything")
        expect(!NoteMediaFileType.accepts(URL(fileURLWithPath: "/a.zip"), for: .image), "image blocks refuse zips")
        expect(NoteMediaFileType.isAnimatable(URL(fileURLWithPath: "/a.GIF")), "gifs can animate")
        expect(!NoteMediaFileType.isAnimatable(URL(fileURLWithPath: "/a.jpg")), "jpegs never animate")
    }
}
