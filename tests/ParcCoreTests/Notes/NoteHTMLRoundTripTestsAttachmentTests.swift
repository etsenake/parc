import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLRoundTripTestsAttachmentTests {
    private typealias Fixture = NoteHTMLRoundTripTestsSupport

    private func withAttachmentPage(_ check: (NotePage, (String) -> URL?, URL, Data) -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NoteHTML-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pixel = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        let file = folder.appendingPathComponent("dot.png")
        try? pixel.write(to: file)
        var settings = NotePageSettings()
        settings.icon = "Attachments/dot.png"
        let note = NotePage(settings: settings, blocks: [Fixture.block(.image) { $0.source = "Attachments/dot.png" },
                                                          Fixture.block(.video) { $0.source = "Attachments/dot.png" },
                                                          Fixture.block(.image) { $0.source = "https://cdn.example/remote.png" }])
        let resolve: (String) -> URL? = { $0.hasPrefix("Attachments/") ? folder.appendingPathComponent(($0 as NSString).lastPathComponent) : nil }
        check(note, resolve, file, pixel)
    }

    @Test
    func localImagesAndTheIconEmbedAsDataURIs() {
        withAttachmentPage { note, resolve, _, pixel in
            let embedded = NotePageHTML.document(note, title: "Dots", assets: resolve, embedImages: true)
            let uri = "data:image/png;base64," + pixel.base64EncodedString()
            #expect(embedded.components(separatedBy: uri).count == 3, "local images and the icon embed as data URIs")
        }
    }

    @Test
    func videoStillLinksToItsFileWhenEmbeddingImages() {
        withAttachmentPage { note, resolve, file, _ in
            let embedded = NotePageHTML.document(note, title: "Dots", assets: resolve, embedImages: true)
            #expect(embedded.contains("<video src=\"" + file.absoluteString + "\""), "video stays a link")
        }
    }

    @Test
    func remoteImagesKeepTheirURLsWhenEmbeddingImages() {
        withAttachmentPage { note, resolve, _, _ in
            let embedded = NotePageHTML.document(note, title: "Dots", assets: resolve, embedImages: true)
            #expect(embedded.contains("src=\"https://cdn.example/remote.png\""), "remote images stay remote")
        }
    }

    @Test
    func localImagesLinkToTheirFilesWhenEmbeddingIsOff() {
        withAttachmentPage { note, resolve, file, _ in
            let linked = NotePageHTML.document(note, title: "Dots", assets: resolve, embedImages: false)
            #expect(!linked.contains("data:image") && linked.contains("src=\"" + file.absoluteString + "\""), "without embedding, files link")
        }
    }
}
