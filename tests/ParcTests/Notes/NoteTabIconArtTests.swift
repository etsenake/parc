import AppKit
import Combine
import Testing
@testable import Parc
@testable import ParcCore

extension NoteEditorProcessWide {
    @MainActor
    final class NoteTabIconArtTests {
        let clock = NoteEditorManualClock()
        let jobs = NoteFileDeferredJobs()
        let folder: NoteEditorTemporaryFolder
        let icons = NoteTabIcons.shared

        init() throws {
            NoteFileSession.clock = clock
            NoteFileSession.worker = .inline
            NoteTabIcons.clock = clock
            NoteTabIcons.worker = .inline
            folder = try NoteEditorTemporaryFolder("tab-icon-art")
            icons.forget()
            icons.folderChanges = { _ in nil }
        }

        @discardableResult
        func png(_ name: String, width: Int, height: Int) throws -> URL {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(NSColor.systemOrange.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let image = try #require(context.makeImage())
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            let url = folder.url.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        }

        func note(_ name: String, icon: String) throws -> URL {
            try folder.write("---\nicon: \"\(icon)\"\n---\nBody\n", to: name)
        }

        func art() -> NoteTabIconArt { NoteTabIconArt(icons: icons) }

        var noteMark: NSImage { DocumentDefaultIcon.note.image(size: NoteTabIconArt.side) }

        @Test func wideImagesThumbnailCroppedSquare() throws {
            let wide = try #require(NoteTabIconArt.thumbnail(try png("Attachments/wide.png", width: 400, height: 200)))
            #expect(wide.width == wide.height)
            #expect(wide.width <= NoteTabIconArt.thumbnailPixels)
        }

        @Test func tallImagesCropSquareToo() throws {
            let tall = try #require(NoteTabIconArt.thumbnail(try png("Attachments/tall.png", width: 30, height: 90)))
            #expect(tall.width == tall.height)
        }

        @Test func missingImagesHaveNoThumbnail() {
            #expect(NoteTabIconArt.thumbnail(folder.url.appendingPathComponent("Attachments/missing.png")) == nil)
        }

        @Test func brokenImagesHaveNoThumbnail() throws {
            #expect(NoteTabIconArt.thumbnail(try folder.write("not a picture", to: "Attachments/junk.png")) == nil)
        }

        func roundedBitmap() throws -> (NSBitmapImageRep, NSImage) {
            let wide = try #require(NoteTabIconArt.thumbnail(try png("Attachments/wide.png", width: 400, height: 200)))
            let rounded = NoteTabIconArt.rounded(wide, size: 16)
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
                                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.size = NSSize(width: 16, height: 16)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            rounded.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
            NSGraphicsContext.restoreGraphicsState()
            return (bitmap, rounded)
        }

        @Test func roundedThumbnailsFillTheIconSlot() throws {
            #expect(try roundedBitmap().1.size == NSSize(width: 16, height: 16))
        }

        @Test func thumbnailCornersAreRoundedOff() throws {
            #expect((try roundedBitmap().0.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
        }

        @Test func theMiddleOfAThumbnailIsSolidPicture() throws {
            #expect((try roundedBitmap().0.colorAt(x: 16, y: 16)?.alphaComponent ?? 0) > 0.9)
        }

        @Test func emojiNotesGetAnImageThatFillsTheIconSlot() throws {
            guard case .image(let emoji) = art().art(forNote: try note("Rocket.md", icon: "🚀")) else {
                Issue.record("emoji notes get an image")
                return
            }
            #expect(emoji.size == NSSize(width: NoteTabIconArt.side, height: NoteTabIconArt.side))
        }

        @Test func theSameEmojiReusesItsImage() throws {
            let art = art()
            guard case .image(let emoji) = art.art(forNote: try note("Rocket.md", icon: "🚀")) else {
                Issue.record("emoji notes get an image")
                return
            }
            #expect(art.image(forNote: try note("Rocket 2.md", icon: "🚀")) === emoji)
        }

        @Test func wordsFallBackToTheLibraryNoteMark() throws {
            let art = art()
            guard case .standard = art.art(forNote: try note("Words.md", icon: "rocket")) else {
                Issue.record("words fall back to the library note mark")
                return
            }
            #expect(art.image(forNote: try note("Words 2.md", icon: "rocket")) === noteMark)
        }

        @Test func textNotesUseTheLibraryNoteMark() throws {
            guard case .standard = art().art(forNote: folder.url.appendingPathComponent("Plain.txt")) else {
                Issue.record("text notes use the library note mark")
                return
            }
        }

        @Test func imageIconsGetAThumbnailThatFillsTheIconSlot() throws {
            try png("Attachments/wide.png", width: 400, height: 200)
            guard case .image(let picture) = art().art(forNote: try note("Pictured.md", icon: "Attachments/wide.png")) else {
                Issue.record("image icons get a thumbnail")
                return
            }
            #expect(picture.size == NSSize(width: 16, height: 16))
        }

        @Test func brokenImageIconsFallBackToTheLibraryNoteMark() throws {
            try folder.write("not a picture", to: "Attachments/junk.png")
            guard case .standard = art().art(forNote: try note("Broken.md", icon: "Attachments/junk.png")) else {
                Issue.record("broken image icons fall back to the library note mark")
                return
            }
        }

        @Test func libraryEmojiRender() {
            #expect(art().image(emoji: "🌵") != nil)
        }

        @Test func libraryWordsDoNotRender() {
            #expect(art().image(emoji: "cactus") == nil)
        }

        @Test func noteAndEaselRowsResolveToTheirLibraryMarks() {
            #expect(DocumentDefaultIcon(symbol: InternalPage.noteFallbackSymbol) == .note)
            #expect(DocumentDefaultIcon(symbol: InternalPage.easelFallbackSymbol) == .easel)
            #expect(DocumentDefaultIcon(symbol: "globe") == nil)
        }

        @Test func iconlessEaselsDrawTheLibraryEaselMarkNotTheNoteMark() {
            let easel = DocumentDefaultIcon.easel.image(size: NoteTabIconArt.side)
            #expect(DocumentDefaultIcon.fallback(named: InternalPage.sidebarFallbackSymbol(urlString: InternalPage.easel(UUID()).urlString)) === easel)
            #expect(easel !== noteMark)
        }

        @Test func theEaselMarkReadsAsAnEasel() {
            #expect(DocumentDefaultIcon.easel.image(size: NoteTabIconArt.side).accessibilityDescription == "Easel")
        }

        func deferredArt() -> NoteTabIconArt {
            NoteTabIcons.worker = NoteFileWorker(deferred: jobs)
            return art()
        }

        @Test func coldRequestsWaitForTheBackground() throws {
            let art = deferredArt()
            var answered = false
            art.requestImage(forNote: try note("Later.md", icon: "🐢")) { _ in answered = true }
            #expect(!answered)
        }

        @Test func waitingEmojiRequestsSettle() throws {
            let art = deferredArt()
            var emoji: NSImage?
            art.requestImage(forNote: try note("Later.md", icon: "🐢")) { emoji = $0 }
            jobs.runAll()
            #expect(emoji != nil)
        }

        @Test func iconlessNotesAnswerTheLibraryNoteMark() throws {
            let art = deferredArt()
            var answer: NSImage?
            art.requestImage(forNote: try note("Never.md", icon: "nope")) { answer = $0 }
            jobs.runAll()
            #expect(answer === noteMark)
        }

        @Test func aThumbnailArrivesAfterItsOwnRead() throws {
            try png("Attachments/tall.png", width: 30, height: 90)
            let art = deferredArt()
            var picture: NSImage?
            art.requestImage(forNote: try note("Framed.md", icon: "Attachments/tall.png")) { picture = $0 }
            jobs.runAll()
            #expect(picture?.size == NSSize(width: 16, height: 16))
        }

        func firstImage(of art: NoteTabIconArt, _ url: URL) -> NSImage? {
            if case .image(let image) = art.art(forNote: url) { return image }
            return nil
        }

        @Test func anUnchangedPictureReusesItsArt() throws {
            try png("Attachments/swap.png", width: 40, height: 40)
            let art = art()
            let swapped = try note("Swapped.md", icon: "Attachments/swap.png")
            let first = try #require(firstImage(of: art, swapped))
            #expect(firstImage(of: art, swapped) === first)
        }

        @Test func aReplacedPictureRefreshesItsThumbnail() throws {
            try png("Attachments/swap.png", width: 40, height: 40)
            let art = art()
            let swapped = try note("Swapped.md", icon: "Attachments/swap.png")
            let first = try #require(firstImage(of: art, swapped))
            try png("Attachments/swap.png", width: 120, height: 60)
            clock.advance(NoteTabIconArt.restampInterval + 0.5)
            let replaced = try #require(firstImage(of: art, swapped))
            #expect(replaced !== first)
        }

        @Test func aMissingPictureShowsTheLibraryNoteMark() throws {
            guard case .standard = art().art(forNote: try note("Waiting.md", icon: "Attachments/later.png")) else {
                Issue.record("a missing picture shows the library note mark")
                return
            }
        }

        @Test func theFileIsNotRestampedOnEveryRequest() throws {
            let art = art()
            let waiting = try note("Waiting.md", icon: "Attachments/later.png")
            _ = art.art(forNote: waiting)
            try png("Attachments/later.png", width: 20, height: 20)
            guard case .standard = art.art(forNote: waiting) else {
                Issue.record("the file isn't restamped on every request")
                return
            }
        }

        @Test func aPictureThatShowsUpLaterIsPickedUp() throws {
            let art = art()
            let waiting = try note("Waiting.md", icon: "Attachments/later.png")
            _ = art.art(forNote: waiting)
            try png("Attachments/later.png", width: 20, height: 20)
            clock.advance(NoteTabIconArt.restampInterval + 0.5)
            #expect(firstImage(of: art, waiting) != nil)
        }

        func lockedPicture() throws -> (NoteTabIconArt, URL, URL) {
            let art = art()
            let locked = try png("Attachments/locked.png", width: 20, height: 20)
            let lockedNote = try note("Locked.md", icon: "Attachments/locked.png")
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
            _ = art.art(forNote: lockedNote)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
            return (art, lockedNote, locked)
        }

        @Test func anUnreadablePictureIsNotRetriedRightAway() throws {
            let (art, lockedNote, _) = try lockedPicture()
            clock.advance(NoteTabIconArt.restampInterval + 0.5)
            #expect(firstImage(of: art, lockedNote) == nil)
        }

        @Test func anUnreadablePictureIsRetriedAfterAShortWait() throws {
            let (art, lockedNote, _) = try lockedPicture()
            clock.advance(NoteTabIconArt.restampInterval + 0.5)
            clock.advance(NoteTabIconArt.unreadableRetryDelay)
            #expect(firstImage(of: art, lockedNote) != nil)
        }
    }
}
