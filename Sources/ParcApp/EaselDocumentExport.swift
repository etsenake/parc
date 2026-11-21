import AppKit
import UniformTypeIdentifiers

@MainActor
enum EaselDocumentExport {
    static func vectorText(_ item: EaselItem) -> EaselVectorText {
        let layout = EaselTextLayout.Layout(EaselRichTextCodec.attributed(item), width: item.frame.width, height: item.frame.height)
        let manager = layout.manager, storage = layout.storage, container = layout.container
        let inset = EaselTextLayout.inset
        let hugging = item.resolvedTextStyle.resolvedFill == .contentHugging
        var result = EaselVectorText()
        if hugging {
            let rects = EaselTextLayout.lineRects(manager: manager, container: container)
            var shift = CGAffineTransform(translationX: inset.width, y: inset.height)
            let path = EaselTextLayout.fillPath(rects: rects, radius: EaselTextLayout.radius(item.resolvedTextStyle))
            if let moved = path.copy(using: &shift) { result.fillPath = svgPath(moved) }
        }
        let text = storage.string as NSString
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            storage.enumerateAttributes(in: characters) { attributes, range, _ in
                var value = text.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
                while let last = value.last, last.isNewline { value.removeLast() }
                guard !value.isEmpty else { return }
                let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { return }
                let location = manager.location(forGlyphAt: glyphRange.location)
                let font = attributes[.font] as? NSFont ?? EaselTextAppearance.font(item.resolvedTextStyle)
                let traits = font.fontDescriptor.symbolicTraits
                var run = EaselVectorTextRun(x: Double(inset.width + rect.minX + location.x), y: Double(inset.height + rect.minY + location.y),
                                             text: value, fontFamily: cssFamily(font), fontSize: Double(font.pointSize),
                                             weight: cssWeight(font), italic: traits.contains(.italic))
                run.color = hugging ? "#FFFFFF" : (attributes[.foregroundColor] as? NSColor).flatMap(hex)
                run.underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
                run.strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                if let link = attributes[.link] as? URL { run.link = link.absoluteString } else { run.link = attributes[.link] as? String }
                result.runs.append(run)
            }
        }
        return result
    }

    static func svgPath(_ path: CGPath) -> String {
        var data = ""
        let n = EaselVectorExport.number
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: data += "M" + n(points[0].x) + " " + n(points[0].y)
            case .addLineToPoint: data += "L" + n(points[0].x) + " " + n(points[0].y)
            case .addQuadCurveToPoint: data += "Q" + [points[0], points[1]].map { n($0.x) + " " + n($0.y) }.joined(separator: " ")
            case .addCurveToPoint: data += "C" + [points[0], points[1], points[2]].map { n($0.x) + " " + n($0.y) }.joined(separator: " ")
            case .closeSubpath: data += "Z"
            @unknown default: break
            }
        }
        return data
    }

    static func cssFamily(_ font: NSFont) -> String {
        let family = font.familyName ?? ""
        let sans = "-apple-system,BlinkMacSystemFont,\"SF Pro Text\",\"Helvetica Neue\",Arial,sans-serif"
        if family.isEmpty || family.hasPrefix(".") { return sans }
        let quoted = "\"" + family.replacingOccurrences(of: "\"", with: "") + "\","
        if font.fontDescriptor.symbolicTraits.contains(.monoSpace) { return quoted + "ui-monospace,Menlo,monospace" }
        if family.localizedCaseInsensitiveContains("Garamond") { return quoted + "\"Iowan Old Style\",Georgia,serif" }
        return quoted + sans
    }

    static func cssWeight(_ font: NSFont) -> Int {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        guard let weight = traits?[.weight] as? CGFloat else {
            return font.fontDescriptor.symbolicTraits.contains(.bold) ? 700 : 400
        }
        let steps: [(CGFloat, Int)] = [(-0.7, 100), (-0.5, 200), (-0.2, 300), (0.1, 400), (0.27, 500), (0.35, 600), (0.48, 700), (0.59, 800)]
        return steps.first { weight < $0.0 }?.1 ?? 900
    }

    static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }

    static func css(_ color: NSColor, in appearance: NSAppearance) -> String {
        var value = "#000000"
        appearance.performAsCurrentDrawingAppearance {
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { String(Int(($0 * 255).rounded())) }
            value = rgb.alphaComponent >= 0.999 ? hex(rgb) ?? value
                : "rgba(" + channels.joined(separator: ",") + "," + EaselVectorExport.number(Double(rgb.alphaComponent)) + ")"
        }
        return value
    }

    static var palette: EaselVectorPalette {
        func swatch(_ name: NSAppearance.Name) -> EaselVectorPalette.Swatch {
            let appearance = NSAppearance(named: name) ?? NSAppearance.currentDrawing()
            return .init(ink: css(NoteTheme.ink, in: appearance), card: css(EaselAppearance.cardFill, in: appearance),
                         cardLine: css(EaselAppearance.cardStroke, in: appearance), muted: css(EaselAppearance.secondaryText, in: appearance))
        }
        return EaselVectorPalette(light: swatch(.aqua), dark: swatch(.darkAqua))
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func webImage(_ data: Data) -> EaselVectorImage? {
        if let type = EaselVectorExport.imageMimeType(data) { return EaselVectorImage(data: data, mimeType: type) }
        guard let converted = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return nil }
        return EaselVectorImage(data: converted, mimeType: "image/png")
    }

    static func art(session: EaselSession, canvas: EaselCanvasView, pages: [UUID: EaselPageSnapshot]) -> EaselVectorArt {
        var art = EaselVectorArt()
        let scale = EaselImageExport.pixelDensity()
        for item in session.document.items {
            switch item.kind {
            case .text:
                art.texts[item.id] = vectorText(item)
            case .image:
                if let id = item.assetID, let data = try? session.assetData(id) { art.images[item.id] = webImage(data) }
            case .webCard, .browser:
                if let page = pages[item.id] {
                    art.images[item.id] = canvas.exportObjectImage(item, page: page, backingScale: scale).flatMap(png)
                        .map { EaselVectorImage(data: $0, mimeType: "image/png") }
                } else if let id = item.assetID, let data = try? session.assetData(id) {
                    art.images[item.id] = webImage(data)
                }
            case .rectangle, .circle, .arrow, .freehand, .link:
                break
            }
        }
        return art
    }
}

@MainActor
extension EaselEditorViewController {
    private var windowController: BrowserWindowController? { view.window?.windowController as? BrowserWindowController }

    func showExportToast(_ content: ParcToastContent) {
        windowController?.showToast(content)
    }

    var easelLink: URL? { URL(string: InternalPage.easel(session.document.id).urlString) }

    func copyLink() {
        guard let url = easelLink else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
        board.setString(url.absoluteString, forType: .string)
        showExportToast(.copiedLinks([url]))
    }

    func copyImage() {
        guard canExportImage, let window = view.window else { return }
        withExportPages(in: window) { [weak self] pages in
            guard let self else { return }
            let scale = EaselImageExport.pixelDensity()
            guard let image = self.canvas.exportImage(backingScale: scale, pages: pages),
                  let png = EaselDocumentExport.png(image) else { return EaselImageExport.showFailure(in: window) }
            let board = NSPasteboard.general
            board.clearContents()
            board.setData(png, forType: .png)
            self.showExportToast(.copiedImage)
        }
    }

    func export(_ format: EaselPageMenu.ExportFormat) {
        guard canExportImage, let window = view.window else { return }
        if format == .image { exportImage(); return }
        let panel = NSSavePanel()
        panel.title = "Export Easel"
        panel.allowedContentTypes = [format == .pdf ? .pdf : .html]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = EaselVectorExport.exportFileName(session.document.title, fileExtension: format == .pdf ? "pdf" : "html")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            MainActor.assumeIsolated { self?.write(format, to: destination, in: window) }
        }
    }

    private func write(_ format: EaselPageMenu.ExportFormat, to destination: URL, in window: NSWindow) {
        withExportPages(in: window) { [weak self] pages in
            guard let self else { return }
            let data: Data?
            if format == .pdf {
                data = self.canvas.exportPDF(title: self.session.document.title, pages: pages)
            } else {
                let art = EaselDocumentExport.art(session: self.session, canvas: self.canvas, pages: pages)
                data = Data(EaselVectorExport.htmlDocument(self.session.document, art: art, palette: EaselDocumentExport.palette).utf8)
            }
            do {
                guard let data else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: destination, options: .atomic)
                self.showExportToast(.standard("Exported \(destination.lastPathComponent)"))
            } catch {
                EaselImageExport.showFailure(in: window)
            }
        }
    }

    private func withExportPages(in window: NSWindow, _ completion: @escaping ([UUID: EaselPageSnapshot]) -> Void) {
        let documentID = session.document.id
        _ = canvas.collectExportPages { [weak self, weak window] pages in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let window, self.view.window === window, !self.session.isClosed,
                          self.session.document.id == documentID else { return }
                    completion(pages)
                }
            }
        }
    }
}

@MainActor
extension BrowserWindowController {
    func configureEaselPageMenu(_ editor: EaselEditorViewController, tab: BrowserTab, documentID: UUID) {
        let profileID = tab.profileID
        let current: () -> Bool = { [weak self, weak editor] in
            guard let self, let editor else { return false }
            return self.currentEaselEditor === editor && self.easelEditors[tab.id]?.documentID == documentID
                && self.activeProfileID == profileID && !self.isClosing && !self.wholeWindowClose
        }
        editor.pageMenu.actions = .init(showInLibrary: { [weak self] in
            guard let self, current() else { return }
            self.showLibrary(.documents)
        }, duplicate: { [weak self] in
            guard let self, current() else { return }
            self.duplicateEasel(documentID, profileID: profileID)
        }, delete: { [weak self] in
            guard let self, current() else { return }
            self.confirmDeleteEasel(documentID, profileID: profileID, current: current)
        })
    }

    func duplicateEasel(_ documentID: UUID, profileID: UUID) {
        do {
            let easels = try EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: profileID))
            let original = try easels.load(documentID).document
            let copy = try easels.create(title: original.title + " copy")
            try copy.perform("Duplicate Easel") { document in
                document.items = original.items.map { item in
                    var next = item
                    next.id = UUID()
                    return next
                }
            }
            openEasel(id: copy.document.id, title: copy.document.title)
        } catch { showEaselError(error) }
    }

    func confirmDeleteEasel(_ documentID: UUID, profileID: UUID, current: @escaping () -> Bool) {
        guard let window, window.attachedSheet == nil else { return }
        ParcDialog.confirm(in: window, title: "Are you sure you want to delete this Easel?",
                           message: "Doing so will delete the Easel permanently.",
                           confirm: "Delete", destructive: true) { [weak self] (approved: Bool) in
            guard let self, approved, current() else { return }
            do {
                let easels = try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: profileID))
                let snapshot = try easels.load(documentID).document
                self.store.deleteLocalDocument(.easel(documentID), profileID: profileID, ownerValid: { [weak self] in
                    guard let self, !self.isClosing, !self.wholeWindowClose else { return false }
                    return (try? easels.load(documentID).document) == snapshot
                }, deleteDocument: {
                    try easels.delete(documentID)
                }, completion: { [weak self] error in
                    guard let self, let error, (error as? CocoaError)?.code != .userCancelled else { return }
                    self.showEaselError(error)
                })
            } catch { self.showEaselError(error) }
        }
    }
}
