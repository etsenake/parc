import AppKit
@testable import Parc
@testable import ParcNotes
@testable import ParcLibrary
@testable import ParcSidebar

private extension PageCaptureOverlay {
    var harnessActionTitles: [String] { palette.rows.map(\.title) }
    var harnessPaletteFrame: NSRect { palette.card.frame }
    func harnessRowFrame(_ index: Int) -> NSRect {
        guard palette.rows.indices.contains(index), let row = palette.view.list.rowFrame(forItemID: palette.rows[index].id) else { return .zero }
        return convert(row, from: palette.view.list)
    }
    func harnessHover(_ index: Int?) { palette.view.list.highlightedIndex = index }
    func harnessPress(_ index: Int, _ pressed: Bool) { harnessHover(pressed ? index : nil) }
}

@MainActor final class CaptureFilm {
    let scene: BrowserScene
    let overlay: PageCaptureOverlay
    let page: NSImage
    let grey: NSImage
    let card: NSRect
    let p0 = NSPoint(x: 228, y: 361)
    let p1 = NSPoint(x: 745, y: 643)
    let pageColor = NSColor(srgbRed: 0.231, green: 0.506, blue: 0.333, alpha: 1)
    let defaults: UserDefaults
    var image: CapturedImage?
    var portrait: PortraitCaptureView?
    var ghost: NSImageView?
    var ghostStart = 0.0
    var lastFraction = 0.95
    var toast: ToastSprite
    var phase = 0
    var region: NSRect?
    var regionReported = false
    lazy var capCursor: NSCursor = {
        guard let art = CaptureArtwork.image("camera-cross-cursor") else { print("camera cursor missing"); return .crosshair }
        return NSCursor(image: art, hotSpot: NSPoint(x: 24, y: 25))
    }()

    init(scene: BrowserScene, pagePath: String) {
        self.scene = scene
        page = NSImage(contentsOfFile: pagePath)!
        grey = PageArt.desaturated(page)
        card = scene.surface.pageCard
        defaults = UserDefaults(suiteName: "parc.film.portrait.\(UUID().uuidString)")!
        defaults.set(0, forKey: "parc.capture.portrait.background")
        overlay = PageCaptureOverlay(frame: card)
        overlay.appearance = NSAppearance(named: .aqua)
        toast = ToastSprite(content: .copiedImage, theme: scene.scenario.work.theme, frame: NSRect(origin: .zero, size: scene.windowRect.size))
        toast.cornerTarget = NSPoint(x: card.maxX - 8, y: card.minY + 8)
        overlay.onRegion = { [unowned self] rect in self.region = rect }
        overlay.isHidden = true
        scene.insert(overlay)
        scene.insert(toast)
        let page = self.page, grey = self.grey
        scene.surface.drawPage = { [unowned self] rect in
            PageArt.draw(page, in: rect)
            guard self.overlay.superview != nil, !self.overlay.isHidden, self.overlay.harnessLensShown else { return }
            let clip = NSBezierPath(rect: rect)
            if let selection = self.overlay.harnessSelection {
                clip.append(NSBezierPath(roundedRect: selection.offsetBy(dx: rect.minX, dy: rect.minY), xRadius: 3, yRadius: 3))
                clip.windingRule = .evenOdd
            }
            NSGraphicsContext.saveGraphicsState(); clip.addClip(); PageArt.draw(grey, in: rect); NSGraphicsContext.restoreGraphicsState()
        }
        overlay.harnessGrayscale(false)
    }

    func s(_ p: NSPoint) -> NSPoint { NSPoint(x: p.x + card.minX, y: p.y + card.minY) }
    func center(_ r: NSRect) -> NSPoint { NSPoint(x: r.midX + card.minX - 40, y: r.midY + card.minY) }

    func capturedPNG(_ selection: NSRect) -> Data {
        let full = PageArt.bitmap(size: card.size, scale: 2) { PageArt.draw(page, in: $0) }
        let crop = full.cropping(to: CGRect(x: selection.minX * 2, y: selection.minY * 2, width: selection.width * 2, height: selection.height * 2))!
        return PageArt.png(crop)
    }

    func knob(_ fraction: Double) -> NSPoint {
        guard let portrait else { return .zero }
        let slider = portrait.harnessSlider
        let saved = slider.doubleValue
        slider.doubleValue = fraction
        let rect = (slider.cell as! NSSliderCell).knobRect(flipped: true)
        slider.doubleValue = saved
        let local = overlay.convert(NSPoint(x: rect.midX, y: rect.midY), from: slider)
        return center(NSRect(origin: local, size: .zero))
    }

    func row(_ index: Int) -> NSPoint { center(overlay.harnessRowFrame(index)) }

    func run(out: String, stills: Bool) {
        let recorder = FilmRecorder(scene: scene, name: "capture", out: out)
        let start = NSPoint(x: 1090, y: 780)
        let drift = NSPoint(x: 540, y: 430)
        var path = PointerPath(keys: [(0, start), (0.7, drift), (0.9, s(p0))])
        var dragPoint = s(p0)
        var frameRowPoint = NSPoint.zero, savePoint = NSPoint.zero, copyPoint = NSPoint.zero
        var applyPoint = NSPoint.zero
        var applyPathSet = false
        recorder.beat(0, "rest", "Work Space, article page at rest; pointer drifts onto the article")
        recorder.beat(0.7, "capture-portion", "overlay.showSelection(): hint, Capture Visible Area, Cancel appear at once; desaturated page + black 0.25 veil")
        recorder.beat(0.9, "drag-began", "handleCaptureGesture(.began) at overlay \(p0)")
        recorder.beat(2.3, "drag-ended", "handleCaptureGesture(.ended) at overlay \(p1); onRegion fires; showBusy() for 6 frames")
        recorder.beat(2.4, "preview", "showPreview(pixels, sourceRect:) — picture alpha 0→1 over 1.0 s cubic(0.215,0.61,0.355,1); frame, shadow, palette appear at once")
        recorder.beat(4.0, "click-frame", "click Frame in Portrait Mode")
        recorder.beat(4.1, "portrait-open", "showFramePage(): the Frame page pushes inside the palette card and the captured image shows the live framed result")
        recorder.beat(4.4, "slider-drag", "slider 0.95→0.35; refresh every 50 ms; old thumbnail fades out with spring response 0.5 damping 0.7")
        recorder.beat(6.1, "apply", "Apply Frame pressed face 8 frames, then applyFrame + setFramed(true) + showPreview (no reveal)")
        recorder.beat(6.5, "save", "Save to Library: setLibraryBusy(true), then setLibrarySaved(true) at 6.75")
        recorder.beat(7.1, "copy", "Copy: overlay removed at once; Copied Image toast spring response 0.4 damping 0.7, scale+opacity from 0")
        let keyTimes = [0.8, 1.6, 2.35, 2.6, 3.4, 4.2, 5.0, 6.3, 6.8, 7.3, 8.0]
        recorder.record(duration: 9.0, keyTimes: keyTimes, onlyStills: stills) { t, frame in
            if t >= 0.7 && phase == 0 {
                phase = 1
                overlay.isHidden = false
                overlay.showSelection()
                overlay.harnessGrayscale(false)
                scene.pointer.cursor = capCursor
            }
            if t >= 0.9 && phase == 1 {
                phase = 2
                overlay.handleCaptureGesture(state: .began, point: p0)
            }
            if phase == 2 {
                let f = Curve.easeInOut(Curve.progress(t, 0.9, 2.2))
                let p = Curve.mix(p0, p1, f)
                dragPoint = s(p)
                if t >= 2.3 {
                    overlay.handleCaptureGesture(state: .ended, point: p1)
                    phase = 3
                    overlay.showBusy()
                } else if t > 0.9 {
                    overlay.handleCaptureGesture(state: .changed, point: p)
                }
            }
            if phase == 3 && t >= 2.4 - 1e-6 {
                phase = 4
                let selection = region ?? NSRect(x: p0.x, y: p0.y, width: p1.x - p0.x, height: p1.y - p0.y)
                region = selection
                image = try! CapturedImage(pngData: capturedPNG(selection), backingScale: 2)
                overlay.showPreview(image!.pixels, sourceRect: selection)
                overlay.layoutSubtreeIfNeeded()
                scene.pointer.cursor = .arrow
                print("selection", selection, "palette", overlay.harnessPaletteFrame, "image", overlay.imageRect, "rows", overlay.harnessActionTitles)
                frameRowPoint = row(overlay.harnessActionTitles.firstIndex(of: "Frame in Portrait Mode") ?? 6)
                path = PointerPath(keys: [(3.5, s(p1)), (4.0, frameRowPoint)])
            }
            if phase == 4 {
                overlay.harnessPicture.alphaValue = CGFloat(Curve.reveal(Curve.progress(t, 2.4, 3.4)))
                let frameIndex = overlay.harnessActionTitles.firstIndex(of: "Frame in Portrait Mode") ?? 6
                overlay.harnessHover(overlay.harnessRowFrame(frameIndex).offsetBy(dx: card.minX, dy: card.minY).contains(path.at(t)) ? frameIndex : nil)
                overlay.harnessPress(frameIndex, t >= 4.0)
                if t >= 4.1 - 1e-6 {
                    phase = 5
                    overlay.harnessPress(frameIndex, false); overlay.harnessHover(nil)
                    let view = PortraitCaptureView(source: image!.unframedPixels, pageColor: pageColor, backingScale: image!.backingScale,
                                                   composition: image!.frame, defaults: defaults)
                    view.onPreview = { [weak overlay] image in overlay?.showDraft(image) }
                    overlay.showFramePage(view, preview: view.previewImage)
                    overlay.layoutSubtreeIfNeeded()
                    portrait = view
                    applyPoint = center(overlay.convert(view.captureButton.bounds, from: view.captureButton))
                    path = PointerPath(keys: [(4.1, frameRowPoint), (4.35, knob(0.95)), (4.45, knob(0.95))])
                    print("portrait card", view.frame, "slider", view.harnessSlider.frame, "apply", view.captureButton.frame)
                }
            }
            if phase == 5 {
                if t >= 4.45 && t <= 5.65 {
                    let f = 0.95 + (0.35 - 0.95) * Curve.easeInOut(Curve.progress(t, 4.45, 5.6))
                    dragPoint = knob(f)
                    if frame % 3 == 0 && abs(f - lastFraction) > 0.0005, let portrait {
                        ghostStart = t
                        portrait.harnessFraction(f)
                        lastFraction = f
                    }
                    if t >= 5.6, abs(lastFraction - 0.35) > 0.0005, let portrait {
                        ghostStart = t
                        portrait.harnessFraction(0.35); lastFraction = 0.35
                    }
                }
                if t > 5.64 && !applyPathSet { applyPathSet = true; path = PointerPath(keys: [(5.65, knob(0.35)), (6.0, applyPoint)]) }
                ghost?.alphaValue = ghost?.image == nil ? 0 : CGFloat(min(1, max(0, 1 - Curve.spring(response: 0.5, damping: 0.7, t - ghostStart))))
                portrait?.captureButton.isHighlighted = t >= 6.1
                if t >= 6.1 + 8.0 / 60 - 1e-6, let portrait {
                    phase = 6
                    portrait.captureButton.isHighlighted = false
                    try! image!.applyFrame(portrait.composition)
                    portrait.removeFromSuperview(); self.portrait = nil
                    overlay.setFramed(true)
                    overlay.showPreview(image!.pixels, sourceRect: region)
                    overlay.harnessPicture.alphaValue = 1
                    overlay.layoutSubtreeIfNeeded()
                    print("framed image", overlay.imageRect, "palette", overlay.harnessPaletteFrame, "rows", overlay.harnessActionTitles)
                    savePoint = row(overlay.harnessActionTitles.firstIndex(of: "Save to Library") ?? 0)
                    copyPoint = row(overlay.harnessActionTitles.firstIndex(of: "Copy") ?? 1)
                    path = PointerPath(keys: [(6.25, applyPoint), (6.48, savePoint), (6.8, savePoint), (7.05, copyPoint)])
                }
            }
            if phase == 6 {
                let titles = overlay.harnessActionTitles
                let saveIndex = titles.firstIndex(where: { $0.contains("Library") }) ?? 0
                let copyIndex = titles.firstIndex(of: "Copy") ?? 1
                let here = path.at(t)
                let hovered = titles.indices.first { overlay.harnessRowFrame($0).offsetBy(dx: card.minX, dy: card.minY).contains(here) }
                overlay.harnessHover(hovered)
                overlay.harnessPress(saveIndex, t >= 6.5 && t < 6.5 + 6.0 / 60)
                if t >= 6.5 && !regionReported { regionReported = true; overlay.setLibraryBusy(true) }
                if t >= 6.75 && regionReported { overlay.setLibraryBusy(false); overlay.setLibrarySaved(true); phase = 7 }
                _ = copyIndex
            }
            if phase == 7 {
                let titles = overlay.harnessActionTitles
                let copyIndex = titles.firstIndex(of: "Copy") ?? 1
                let here = path.at(t)
                overlay.harnessHover(titles.indices.first { overlay.harnessRowFrame($0).offsetBy(dx: card.minX, dy: card.minY).contains(here) })
                overlay.harnessPress(copyIndex, t >= 7.05)
                if t >= 7.1 - 1e-6 {
                    phase = 8
                    overlay.removeFromSuperview()
                    path = PointerPath(keys: [(7.1, copyPoint), (8.6, NSPoint(x: copyPoint.x - 30, y: copyPoint.y + 26))])
                }
            }
            if phase >= 8 {
                toast.progress = Curve.spring(response: 0.4, damping: 0.7, t - 7.1)
            }
            let pointerPoint: NSPoint
            if phase == 2 || (phase == 5 && t >= 4.45 && t <= 5.64) { pointerPoint = dragPoint } else { pointerPoint = path.at(t) }
            scene.pointer.location = pointerPoint
            scene.surface.needsDisplay = true
        }
    }
}
