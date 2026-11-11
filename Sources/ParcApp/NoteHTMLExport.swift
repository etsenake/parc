import AppKit

@MainActor
enum NoteHTMLExport {
    static func document(_ note: NoteDocument) throws -> NoteExportDocument {
        guard !note.deleted else { throw NoteError.deleted }
        try note.body.richText.validate(text: note.body.text)
        let value = NSMutableAttributedString(attributedString: EaselRichTextCodec.attributed(
            note.body.text, richText: note.body.richText, style: .init(), color: "#252525"))
        for run in note.body.richText.runs where run.attributes.semanticInk != nil {
            value.addAttribute(.foregroundColor, value: EaselRichTextCodec.color(run.attributes.ink),
                range: NSRange(location: run.location, length: run.length))
        }
        var images: [(NSRange, String, String)] = []
        for run in note.body.richText.runs {
            guard let image = run.attributes.image else { continue }
            let mime: String, bytes: Data
            switch image.fileType {
            case "public.png": mime = "image/png"; bytes = image.data
            case "public.jpeg": mime = "image/jpeg"; bytes = image.data
            case "public.tiff":
                guard let representation = NSBitmapImageRep(data: image.data),
                      let png = representation.representation(using: .png, properties: [:]) else {
                    throw NoteExportError.invalid
                }
                mime = "image/png"; bytes = png
            default: throw NoteExportError.invalid
            }
            var token = "PARCIMAGE" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            while note.body.text.contains(token) { token += "X" }
            let html = "<img alt=\"\" src=\"data:" + mime + ";base64," + bytes.base64EncodedString()
                + "\" width=\"" + String(Int(image.width.rounded())) + "\" height=\""
                + String(Int(image.height.rounded())) + "\" style=\"max-width:100%;height:auto\">"
            images.append((NSRange(location: run.location, length: run.length), token, html))
        }
        for (range, token, _) in images.reversed() {
            var attributes = value.attributes(at: range.location, effectiveRange: nil)
            attributes.removeValue(forKey: .attachment)
            value.replaceCharacters(in: range, with: NSAttributedString(string: token, attributes: attributes))
        }
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : note.title
        let data = try value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
            .title: title
        ])
        guard var html = String(data: data, encoding: .utf8) else { throw NoteExportError.invalid }
        for (_, token, image) in images {
            guard html.contains(token) else { throw NoteExportError.invalid }
            html = html.replacingOccurrences(of: token, with: image)
        }
        return NoteExportDocument(id: note.id, title: title, html: html, modifiedAt: note.modifiedAt)
    }
}
