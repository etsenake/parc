import AppKit
import Combine

@main @MainActor
struct NoteTabIconArtTests {
    static let clock = ManualNoteClock()
    static var folder: URL!

    static func main() {
        exitOnFailure {
            NoteFileSession.clock = clock
            NoteFileSession.worker = .inline
            NoteTabIcons.clock = clock
            NoteTabIcons.worker = .inline
            folder = NoteFileTestSupport.makeFolder("tab-icon-art")
            defer { NoteFileTestSupport.remove(folder) }
            let icons = NoteTabIcons.shared
            icons.folderChanges = { _ in nil }
            try thumbnails()
            try art(icons)
            try waiting(icons)
            try refreshing(icons)
            print("NoteTabIconArtTests passed")
        }
    }

    static func png(_ name: String, width: Int, height: Int) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemOrange.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        return NoteFileTestSupport.write(data, to: folder.appendingPathComponent(name))
    }

    static func note(_ name: String, icon: String) -> URL {
        NoteFileTestSupport.write("---\nicon: \"\(icon)\"\n---\nBody\n", to: folder.appendingPathComponent(name))
    }

    static func thumbnails() throws {
        let wide = try XCTUnwrap(NoteTabIconArt.thumbnail(try png("Attachments/wide.png", width: 400, height: 200)), "wide images thumbnail")
        expectEqual(wide.width, wide.height, "thumbnails are cropped square")
        expect(wide.width <= NoteTabIconArt.thumbnailPixels, "thumbnails stay small")
        let tall = try XCTUnwrap(NoteTabIconArt.thumbnail(try png("Attachments/tall.png", width: 30, height: 90)), "tall images thumbnail")
        expectEqual(tall.width, tall.height, "tall images crop square too")
        expect(NoteTabIconArt.thumbnail(folder.appendingPathComponent("Attachments/missing.png")) == nil, "missing images have no thumbnail")
        let junk = NoteFileTestSupport.write("not a picture", to: folder.appendingPathComponent("Attachments/junk.png"))
        expect(NoteTabIconArt.thumbnail(junk) == nil, "broken images have no thumbnail")
        let rounded = NoteTabIconArt.rounded(wide, size: 16)
        expectEqual(rounded.size, NSSize(width: 16, height: 16), "rounded thumbnails fill the icon slot")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: 16, height: 16)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        rounded.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        NSGraphicsContext.restoreGraphicsState()
        expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1, "thumbnail corners are rounded off")
        expect((bitmap.colorAt(x: 16, y: 16)?.alphaComponent ?? 0) > 0.9, "the middle is solid picture")
    }

    static func art(_ icons: NoteTabIcons) throws {
        let art = NoteTabIconArt(icons: icons)
        guard case .image(let emoji) = art.art(forNote: note("Rocket.md", icon: "🚀")) else { failTest("emoji notes get an image") }
        expectEqual(emoji.size, NSSize(width: NoteTabIconArt.side, height: NoteTabIconArt.side), "emoji fill the icon slot")
        expect(art.image(forNote: note("Rocket 2.md", icon: "🚀")) === emoji, "the same emoji reuses its image")
        guard case .standard = art.art(forNote: note("Words.md", icon: "rocket")) else { failTest("words fall back to the library note mark") }
        expect(art.image(forNote: note("Words 2.md", icon: "rocket")) === DocumentDefaultIcon.note.image(size: NoteTabIconArt.side), "iconless notes draw the library note mark")
        guard case .standard = art.art(forNote: folder.appendingPathComponent("Plain.txt")) else { failTest("text notes use the library note mark") }
        guard case .image(let picture) = art.art(forNote: note("Pictured.md", icon: "Attachments/wide.png")) else {
            failTest("image icons get a thumbnail")
        }
        expectEqual(picture.size, NSSize(width: 16, height: 16), "image icons fill the icon slot")
        guard case .standard = art.art(forNote: note("Broken.md", icon: "Attachments/junk.png")) else {
            failTest("broken image icons fall back to the library note mark")
        }
        expect(art.image(emoji: "🌵") != nil, "library emoji render")
        expect(art.image(emoji: "cactus") == nil, "library words don't")
        expect(DocumentDefaultIcon(symbol: InternalPage.noteFallbackSymbol) == .note
               && DocumentDefaultIcon(symbol: InternalPage.easelFallbackSymbol) == .easel
               && DocumentDefaultIcon(symbol: "globe") == nil, "note and Easel rows resolve to their Library marks")
        let easel = DocumentDefaultIcon.easel.image(size: NoteTabIconArt.side)
        expect(DocumentDefaultIcon.fallback(named: InternalPage.sidebarFallbackSymbol(urlString: InternalPage.easel(UUID()).urlString)) === easel
               && easel !== DocumentDefaultIcon.note.image(size: NoteTabIconArt.side), "iconless Easels draw the Library Easel mark, not the note mark")
        expectEqual(easel.accessibilityDescription, "Easel", "the Easel mark reads as an Easel")
    }

    static func waiting(_ icons: NoteTabIcons) throws {
        icons.forget()
        icons.folderChanges = { _ in nil }
        NoteTabIcons.clock = NoteFileSystemClock.shared
        NoteTabIcons.worker = NoteFileWorker(label: "org.parc.tests.tab-icon-art")
        defer {
            NoteTabIcons.clock = clock
            NoteTabIcons.worker = .inline
        }
        let art = NoteTabIconArt(icons: icons)
        var emoji: NSImage?, emojiDone = false, symbolDone = false, picture: NSImage?
        art.requestImage(forNote: note("Later.md", icon: "🐢")) { emoji = $0; emojiDone = true }
        art.requestImage(forNote: note("Never.md", icon: "nope")) { expect($0 === DocumentDefaultIcon.note.image(size: NoteTabIconArt.side), "iconless notes answer the library note mark"); symbolDone = true }
        art.requestImage(forNote: note("Framed.md", icon: "Attachments/tall.png")) { picture = $0 }
        expect(!emojiDone && !symbolDone && picture == nil, "cold requests wait for the background")
        expect(NoteFileTestSupport.spin(timeout: 5) { emojiDone && symbolDone && picture != nil }, "waiting requests settle")
        expect(emoji != nil, "the emoji arrives")
        expectEqual(picture?.size, NSSize(width: 16, height: 16), "the thumbnail arrives after its own read")
    }

    static func refreshing(_ icons: NoteTabIcons) throws {
        icons.forget()
        icons.folderChanges = { _ in nil }
        let art = NoteTabIconArt(icons: icons)
        _ = try png("Attachments/swap.png", width: 40, height: 40)
        let swapped = note("Swapped.md", icon: "Attachments/swap.png")
        guard case .image(let first) = art.art(forNote: swapped) else { failTest("the first picture thumbnails") }
        guard case .image(let again) = art.art(forNote: swapped), again === first else { failTest("an unchanged picture reuses its art") }
        _ = try png("Attachments/swap.png", width: 120, height: 60)
        clock.advance(NoteTabIconArt.restampInterval + 0.5)
        guard case .image(let replaced) = art.art(forNote: swapped) else { failTest("the replaced picture thumbnails") }
        expect(replaced !== first, "a replaced picture refreshes its thumbnail")

        let pending = folder.appendingPathComponent("Attachments/later.png")
        let waiting = note("Waiting.md", icon: "Attachments/later.png")
        guard case .standard = art.art(forNote: waiting) else { failTest("a missing picture shows the library note mark") }
        _ = try png("Attachments/later.png", width: 20, height: 20)
        guard case .standard = art.art(forNote: waiting) else { failTest("the file isn't restamped on every request") }
        clock.advance(NoteTabIconArt.restampInterval + 0.5)
        guard case .image = art.art(forNote: waiting) else { failTest("a picture that shows up later is picked up") }
        expect(FileManager.default.fileExists(atPath: pending.path), "the late picture is on disk")

        let locked = try png("Attachments/locked.png", width: 20, height: 20)
        let lockedNote = note("Locked.md", icon: "Attachments/locked.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        guard case .standard = art.art(forNote: lockedNote) else { failTest("an unreadable picture shows the library note mark") }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
        clock.advance(NoteTabIconArt.restampInterval + 0.5)
        guard case .standard = art.art(forNote: lockedNote) else { failTest("an unreadable picture isn't retried right away") }
        clock.advance(NoteTabIconArt.unreadableRetryDelay)
        guard case .image = art.art(forNote: lockedNote) else { failTest("an unreadable picture is retried after a short wait") }
    }

    static func XCTUnwrap<Value>(_ value: Value?, _ message: String) throws -> Value {
        guard let value else { failTest(message) }
        return value
    }
}
