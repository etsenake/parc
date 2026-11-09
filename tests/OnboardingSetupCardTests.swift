import AppKit
import CoreText

/// Inert AppKit presentation checks. No browser, engine, imports or user profile.
@main
struct OnboardingSetupCardTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let fontURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Onboarding/MarlinSoftSQ-ExtraBold.otf")
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        guard let font = NSFont(name: "MarlinSoftSQ-ExtraBold", size: 35) else {
            fatalError("The production onboarding font must be available")
        }
        let card = OnboardingSetupCard(frame: NSRect(origin: .zero, size: OnboardingSetupLayout.size))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(card)
        card.frame = OnboardingSetupLayout.frame(in: window.contentView!.bounds)
        card.setBoundsSize(OnboardingSetupLayout.size)
        precondition(card.frame.size == NSSize(width: 967, height: 548))
        precondition(card.frame.midX == 640 && card.frame.midY == 400)
        let back = NSButton(), skip = NSButton(), progress = NSTextField()
        let next = OnboardingProgressionControl(frame: .zero)
        next.title = "Next"
        next.configure(background: OnboardingSetupPalette.action, foreground: .white, reduceMotion: true)
        let name = NSTextField()
        let stages = [
            ("Welcome to Parc.", "A place for your tabs, your projects, and the way you browse.\nLet’s make it yours."),
            ("Add some flair with a theme.", "Pick a color, any color—add your favorite shade to your new home on the internet."),
            ("Choose the apps you use most.", "Favorites stay close at hand across your Spaces.\nChoose a few, or add your own while you browse."),
            ("Treat your bookmarks to an upgrade.", "Bring your browsing from another browser.\nChoose the bookmarks you want to keep in your sidebar."),
            ("Welcome to Parc, Ada Lovelace", "Here’s your Parc Card. Show it off to the world or keep it to yourself.\n\nAnd with that, you’re now ready to experience your upgraded internet.")
        ]
        for (index, stage) in stages.enumerated() {
            //
            back.isHidden = index == 0 || index == 4
            skip.isHidden = !(1...3).contains(index)
            // OnboardingThemeEditorLayout.spaceNameHeight
            card.configure(title: stage.0, subtitle: stage.1, font: font,
                           back: back, next: next, skip: skip, progress: progress,
                           accessory: index == 1 ? name : nil, accessoryHeight: index == 1 ? 36 : 30)
            card.layoutSubtreeIfNeeded()
            precondition(card.instructions.frame.width == 257)
            precondition(card.content.frame == NSRect(x: 357, y: 0, width: 610, height: 548))
            precondition(card.heading.frame.maxY < card.message.frame.minY)
            precondition(card.message.frame.maxY < next.frame.minY)
            if !skip.isHidden { precondition(card.message.frame.maxY < skip.frame.minY) }
            if index == 1 {
                precondition(name.superview === card.instructions)
                precondition(name.frame.minY > card.message.frame.maxY && name.frame.maxY < next.frame.minY)
                // The card keeps 967×548 bounds at every fit, so this holds at the smallest size too.
                precondition(name.frame.maxY + 12 <= skip.frame.minY, "Space name clears Skip on the theme step")
            } else { precondition(name.superview == nil) }
            precondition(next.superview === card.instructions && progress.superview === card.instructions)
            precondition(next.frame.width == 257 && next.frame.height == 40)
            precondition(next.subviews.count == 1 && next.subviews[0].frame == next.bounds)
            precondition(next.keyboardView === next.subviews[0], "Tab loop uses the SwiftUI host, not the wrapper")
            precondition(card.heading.accessibilityRole()?.rawValue == "AXHeading")
            precondition(card.accessibilityLabel() == stage.0)
            precondition(next.acceptsFirstResponder)
        }
        // Regular 1280×800 window, screen−72 of 1024×768, and tighter fits.
        for size in [NSSize(width: 1280, height: 800), NSSize(width: 952, height: 696),
                     NSSize(width: 1208, height: 648), NSSize(width: 760, height: 500),
                     NSSize(width: 400, height: 300)] {
            let bounds = NSRect(origin: .zero, size: size)
            let fit = OnboardingSetupLayout.frame(in: bounds)
            precondition(bounds.contains(fit) && fit.minX >= OnboardingSetupLayout.horizontalInset - 0.001
                            && fit.minY >= OnboardingSetupLayout.verticalInset - 0.001,
                         "Screen fit: \(bounds) → \(fit)")
            precondition(abs(fit.width / fit.height - 967 / 548.0) < 0.0001)
            if size.width >= OnboardingSetupLayout.size.width + 2 * OnboardingSetupLayout.horizontalInset
                && size.height >= OnboardingSetupLayout.size.height + 2 * OnboardingSetupLayout.verticalInset {
                precondition(abs(fit.width - OnboardingSetupLayout.size.width) < 0.001
                             && abs(fit.height - OnboardingSetupLayout.size.height) < 0.001,
                             "Ordinary windows keep the recovered 967×548 card")
            }
            // Actual NSView coordinate scaling preserves controls and content,
            // rather than creating a second compact layout for another stage.
            card.frame = fit
            card.setBoundsSize(OnboardingSetupLayout.size)
            card.needsLayout = true
            card.layoutSubtreeIfNeeded()
            precondition(abs(card.content.bounds.width - 610) < 0.001 && abs(card.content.bounds.height - 548) < 0.001, "Native content size: \(card.content.bounds)")
            precondition(card.instructions.convert(next.bounds, from: next).maxY <= card.instructions.bounds.maxY + 0.001)
            precondition(card.chrome.frame == card.bounds && card.borders.frame == card.bounds, "Chrome and borders fill the scaled card")
            precondition(card.chrome.grain.frame == card.chrome.bounds, "Tiled grain fills the clipped chrome")
            precondition(abs(card.borders.inner.frame.minX) < 0.001 && abs(card.borders.inner.frame.maxX - card.borders.bounds.maxX) < 0.001,
                         "Inner 1pt border on full bounds has centerline 0.5")
            precondition(abs(card.borders.inner.cornerRadius - OnboardingSetupLayout.cornerRadius) < 0.001)
            precondition(abs(card.chrome.grain.tileSize.width - OnboardingSetupLayout.grainTileSize.width) < 0.001)
            precondition(abs(card.borders.outer.frame.minX + OnboardingSetupLayout.outerStrokeInset) < 0.001)
            precondition(card.chrome.hitTest(NSPoint(x: card.bounds.midX, y: card.bounds.midY)) == nil)
            precondition(card.borders.hitTest(NSPoint(x: card.bounds.midX, y: card.bounds.midY)) == nil)
            // One coordinate space: scaled frame, original 967×548 bounds.
            precondition(abs(card.bounds.width - OnboardingSetupLayout.size.width) < 0.001
                         && abs(card.bounds.height - OnboardingSetupLayout.size.height) < 0.001,
                         "Small-screen fit keeps the original card bounds: \(card.bounds.size)")
        }
        card.frame = OnboardingSetupLayout.frame(in: window.contentView!.bounds)
        card.setBoundsSize(OnboardingSetupLayout.size)
        card.needsLayout = true
        card.layoutSubtreeIfNeeded()
        precondition(card.layer?.cornerRadius == OnboardingSetupLayout.cornerRadius)
        precondition(card.layer?.cornerCurve == .continuous)
        precondition(card.layer?.masksToBounds == false, "Shadow stays outside the continuous clip")
        precondition(card.layer?.backgroundColor == nil || card.layer?.backgroundColor?.alpha == 0,
                     "Fill lives on chrome so grain can composite against it")
        precondition(card.chrome.layer?.masksToBounds == true)
        precondition(card.chrome.layer?.cornerRadius == OnboardingSetupLayout.cornerRadius)
        precondition(card.chrome.layer?.cornerCurve == .continuous)
        precondition(card.chrome.grain.superlayer === card.chrome.layer, "Grain composites inside the filled chrome")
        precondition(card.subviews.last === card.borders, "Strokes paint above the content column")
        precondition(card.borders.inner.superlayer === card.borders.layer, "Inner stroke is above full-bleed content")
        precondition(card.borders.inner.cornerCurve == .continuous)
        precondition(card.borders.inner.borderWidth == OnboardingSetupLayout.borderWidth)
        precondition(card.borders.inner.miterLimit == OnboardingSetupLayout.strokeMiterLimit)
        precondition(card.borders.inner.lineCap == .butt && card.borders.inner.lineJoin == .miter)
        precondition(card.borders.inner.lineWidth == OnboardingSetupLayout.borderWidth)
        precondition(card.borders.layer?.masksToBounds == false, "Outer stroke is not clipped to the fill")
        precondition((card.borders.layer?.borderWidth ?? 0) == 0, "Outer stroke is not an inset layer border")
        precondition(card.borders.outer.superlayer === card.borders.layer)
        precondition(card.borders.outer.borderWidth == OnboardingSetupLayout.borderWidth)
        precondition(card.borders.outer.cornerCurve == .continuous,
                     "Outer stroke follows the continuous card, not a circular path")
        precondition(card.borders.outer.miterLimit == OnboardingSetupLayout.strokeMiterLimit)
        precondition(card.borders.outer.lineCap == .butt && card.borders.outer.lineJoin == .miter)
        precondition(!(card.chrome.layer?.sublayers ?? []).contains { $0 === card.borders.inner },
                     "Inner stroke is not behind the content column on chrome")
        precondition(abs(card.borders.outer.frame.minX + OnboardingSetupLayout.outerStrokeInset) < 0.001
                     && abs(card.borders.outer.cornerRadius
                            - (OnboardingSetupLayout.cornerRadius + OnboardingSetupLayout.outerStrokeInset)) < 0.001,
                     "Inset 1pt outer border occupies −1…0 (net path −0.5)")
        precondition(card.layer?.shadowPath == nil,
                     "Shadow follows the continuous layer, not a circular path")
        precondition(OnboardingSetupPalette.cardBackgroundName == "CardBackground")
        precondition(OnboardingSetupPalette.innerBorderName == "CardInnerBorder")
        precondition(OnboardingSetupPalette.outerBorderName == "CardOuterBorder")
        card.chrome.grain.display()
        precondition(card.chrome.grain.tile == nil && card.chrome.grain.isHidden, "No theme draws no grain")
        var themed = SpaceTheme.singleColor(ThemeColor(red: 0.2, green: 0.4, blue: 0.9)!)
        themed.noise = 0.5
        card.grainTheme = themed
        precondition(OnboardingSetupCard.grainTile(.grain) != nil, "The grain is the theme renderer's ThemeTextures file")
        precondition(card.chrome.grain.tile === OnboardingSetupCard.grainTile(.grain) && !card.chrome.grain.isHidden)
        precondition(abs(Double(card.chrome.grain.opacity) - themed.textureStrength(isActive: true)) < 0.0001
                     && abs(Double(card.chrome.grain.opacity) - 0.4) < 0.0001, "Grain strength is the sidebar's: dial × 0.8")
        precondition(card.chrome.grain.compositingFilter as? String == "multiplyBlendMode", "Multiply is themeComposite on the opaque fill")
        precondition(card.chrome.grain.tileSize == OnboardingSetupLayout.grainTileSize
                     && OnboardingSetupLayout.grainTileSize.width == ThemeTexturePitch.points,
                     "Grain repeats at the theme renderer's 100-point pitch")
        card.grainIsActive = false
        precondition(abs(Double(card.chrome.grain.opacity) - 0.1) < 0.0001, "An inactive window draws a quarter, as the sidebar")
        card.grainIsActive = true
        themed.texture = .sand
        card.grainTheme = themed
        precondition(card.chrome.grain.tile === OnboardingSetupCard.grainTile(.sand)
                     && OnboardingSetupCard.grainTile(.sand) !== OnboardingSetupCard.grainTile(.grain)
                     && abs(Double(card.chrome.grain.opacity) - 0.075) < 0.0001, "Each texture uses its own file and maximum")
        themed.texture = .grain
        themed.noise = 0
        card.grainTheme = themed
        precondition(card.chrome.grain.isHidden, "A zero grain dial draws no grain, as in the sidebar")
        themed.noise = 0.5
        card.grainTheme = themed
        func components(_ color: CGColor?) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            let ns = NSColor(cgColor: color!)!.usingColorSpace(.sRGB)!
            return (ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            card.appearance = NSAppearance(named: appearance)
            card.chrome.appearance = card.appearance
            card.borders.appearance = card.appearance
            card.viewDidChangeEffectiveAppearance()
            card.effectiveAppearance.performAsCurrentDrawingAppearance {
                let color = OnboardingSetupPalette.card.usingColorSpace(.sRGB)!
                precondition(abs(color.redComponent - (appearance == .aqua ? 230 : 140) / 255.0) < 0.001)
                precondition(card.chrome.layer?.backgroundColor == color.cgColor)
                let inner = components(card.borders.inner.borderColor)
                let outer = components(card.borders.outer.borderColor)
                if appearance == .aqua {
                    precondition(abs(inner.0 - 1) < 0.001 && abs(inner.3) < 0.001, "Light inner border is white/0")
                    precondition(abs(outer.0) < 0.001 && abs(outer.3) < 0.001, "Light outer border is black/0")
                    precondition(card.chrome.grain.compositingFilter as? String == "multiplyBlendMode")
                } else {
                    precondition(abs(inner.0 - 1) < 0.001 && abs(inner.3 - 0.2) < 0.001, "Dark inner border is white/0.2")
                    precondition(abs(outer.0) < 0.001 && abs(outer.3 - 0.61) < 0.001, "Dark outer border is black/0.61")
                    precondition(card.chrome.grain.compositingFilter as? String == "multiplyBlendMode",
                                 "Dark uses the same composite as the sidebar")
                }
            }
        }
        checkStepMotion(card, font: font, back: back, next: next, skip: skip, progress: progress)
        for ink in [NSColor(srgbRed: 0.02, green: 0.2, blue: 0.1, alpha: 1),
                    NSColor(srgbRed: 0.96, green: 0.9, blue: 1, alpha: 1)] {
            card.themeTextColor = ink
            precondition(card.titleColor == ink && card.messageColor == ink && card.chromeColor == ink,
                         "Every themed card text role follows sidebar page-title ink")
            for field in [card.heading, card.message] {
                precondition(field.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == ink,
                             "Live theme changes replace the already-rendered heading and message ink")
            }
        }
        card.themeTextColor = nil
        precondition(card.titleColor == OnboardingSetupPalette.title && card.messageColor == OnboardingSetupPalette.message,
                     "Clearing the Space theme restores setup's semantic text colors")
        card.themeBackground = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        precondition(card.chrome.layer?.backgroundColor == card.themeBackground?.cgColor)
        card.effectiveAppearance.performAsCurrentDrawingAppearance {
            let inner = components(card.borders.inner.borderColor)
            precondition(abs(inner.3 - 0.2) < 0.001, "Themed fill does not replace CardInnerBorder")
        }
        card.themeBackground = nil
        card.effectiveAppearance.performAsCurrentDrawingAppearance {
            precondition(card.chrome.layer?.backgroundColor == OnboardingSetupPalette.card.cgColor)
        }
        do { try checkReady(in: window) } catch { fatalError("Ready step checks: \(error)") }
        window.close()
        print("PASS: all five setup layouts, grain/border chrome, native compact-display scaling and light/dark optical composition")
    }

    @MainActor static func checkReady(in window: NSWindow) throws {
        typealias Config = OnboardingConfettiView.Config
        let bounds = NSRect(x: 0, y: 0, width: 1_280, height: 800)
        precondition(OnboardingConfettiView.cannonPoints(in: bounds).map(\.x) == [140, 340, 540, 740, 940, 1_140])
        precondition(OnboardingConfettiView.cannonPoints(in: bounds).allSatisfy { $0.y == 400 })
        var generator = SystemRandomNumberGenerator()
        let pieces = OnboardingConfettiView.makePieces(using: &generator)
        precondition(pieces.count == 96 && Set(pieces.map(\.cannon)).count == 6)
        precondition(Config.glyphs == ["●", "●", "♥︎"] && Config.colors.count == 5)
        precondition(Config.rainDuration == 5.5 && Config.size == 12 && Config.opacity == 0.7)
        for piece in pieces {
            precondition(piece.offset.dy >= 150 * sin(.pi / 3) - 0.01, "Pieces fan upward between 60° and 120°")
            precondition(abs(piece.offset.dx) <= 600 * cos(.pi / 3) + 0.01)
            precondition(piece.sample(at: 0).opacity == 0)
            let peak = piece.sample(at: 0.6)
            precondition(peak.offset.dy > 0 && peak.opacity > 0.6, "Burst rises and appears")
            precondition(piece.sample(at: 5.5).offset.dy < -100, "Then falls 800 pt")
            precondition(piece.sample(at: 4.6).opacity == 0, "And has faded by 4.5 s")
        }
        precondition(OnboardingConfettiView.glyphImages(scale: 2).joined().allSatisfy { $0 != nil })

        let confetti = OnboardingConfettiView(frame: bounds)
        window.contentView?.addSubview(confetti)
        window.orderBack(nil)
        confetti.fire(after: 0.05)
        precondition(confetti.isPending && !confetti.hasFired)
        confetti.cancelPending()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        precondition(!confetti.hasFired && confetti.livePieceCount == 0, "Leaving before 0.4 s cancels the burst")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            confetti.fire(after: 0.05)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            precondition(confetti.hasFired && confetti.livePieceCount == 96)
            confetti.fire(after: 0.05)
            precondition(!confetti.isPending, "Confetti fires once per onboarding window")
            confetti.stop()
            precondition(confetti.livePieceCount == 0)
        }
        confetti.fire(after: 0.05)
        confetti.stop()
        precondition(!confetti.isPending)
        confetti.removeFromSuperview()

        let ready = OnboardingReadyContent(frame: NSRect(x: 0, y: 0, width: 967, height: 548))
        func buttons(_ view: NSView) -> [NSButton] { view.subviews.compactMap { $0 as? NSButton } }
        precondition(buttons(ready).map { $0.toolTip ?? "" } == ["Share", "Download", "Randomize"])
        precondition(buttons(ready).map { $0.accessibilityLabel() ?? "" }
                     == ["Share card", "Download card", "Randomize card design"])
        ready.layoutSubtreeIfNeeded()
        let frames = buttons(ready).map(\.frame)
        let card = try require(ready.subviews.first { $0 is MembershipCardView })
        precondition(frames.allSatisfy { $0.size == NSSize(width: 32, height: 32) && $0.minY == card.frame.maxY + 25 })
        precondition(frames[1].minX - frames[0].maxX == 10 && frames[2].minX - frames[1].maxX == 10)
        precondition(OnboardingReadyContent.downloadName(cardName: "Ada Lovelace") == "Ada Lovelace_Parc.png")
        precondition(OnboardingReadyContent.downloadName(cardName: " ") == "Parc.png")
        precondition(OnboardingReadyContent.shareText == "I just set up Parc!")

        let squish = MembershipCardView.squishCurve(step: 1.0 / 120)
        precondition(squish.first == 1 && squish.last == 1 && squish.min()! < 0.985 && squish.min()! >= 0.93,
                     "Randomize springs the card toward 0.93 and back")
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.featureUnsupported) }
        return value
    }

    /// NewSetupView's description typography and step motion: the old text
    /// springs out while the new springs in, and the content only crossfades.
    @MainActor static func checkStepMotion(_ card: OnboardingSetupCard, font: NSFont, back: NSView, next: NSView,
                                           skip: NSView, progress: NSView) {
        card.configure(title: "Choose the apps you use most.", subtitle: "Select your favorite apps to keep them handy in your sidebar.",
                       font: font, back: back, next: next, skip: skip, progress: progress, accessory: nil)
        card.layoutSubtreeIfNeeded()
        let attributes = card.message.attributedStringValue.attributes(at: 0, effectiveRange: nil)
        let messageFont = attributes[.font] as? NSFont
        let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
        precondition(messageFont?.pointSize == 15 && attributes[.kern] as? Double == -0.3,
                     "The setup message is 15 pt with -0.3 kerning")
        if let messageFont, let paragraph {
            precondition(abs(messageFont.ascender - messageFont.descender + messageFont.leading + paragraph.lineSpacing - 21) < 0.001,
                         "The setup message sets a 21 pt line")
        } else { preconditionFailure("The setup message carries a paragraph style") }
        guard let snapshot = card.captureText() else { preconditionFailure("A visible heading and message can be captured") }
        card.configure(title: "Go steady with Parc?", subtitle: "Make Parc your default browser so links open here.",
                       font: font, back: back, next: next, skip: skip, progress: progress, accessory: nil)
        card.animateStepChange(from: snapshot, direction: .forward, slides: true, fades: true)
        for (field, spring) in [(card.heading, OnboardingStepMotion.titleSpring), (card.message, OnboardingStepMotion.messageSpring)] {
            guard let slide = field.layer?.animation(forKey: "step") as? CASpringAnimation else {
                preconditionFailure("New setup text springs in")
            }
            precondition(slide.keyPath == "transform.translation.x" && slide.fromValue as? Double == 400
                         && slide.toValue as? Double == 0 && slide.mass == 1
                         && abs(slide.stiffness - spring.stiffness) < 0.001 && abs(slide.damping - spring.damping) < 0.001
                         && slide.duration == slide.settlingDuration, "New text comes from +400 on its spring")
        }
        let outgoing = card.outgoingText.subviews
        precondition(outgoing.count == 2 && outgoing.allSatisfy {
            ($0.layer?.animation(forKey: "step") as? CASpringAnimation)?.toValue as? Double == -400
        }, "The old heading and message leave to -400, still drawn")
        precondition(outgoing.allSatisfy { $0.layer?.animation(forKey: "opacity") == nil } && card.outgoingText.hitTest(.zero) == nil,
                     "Outgoing text stays opaque and never takes clicks")
        guard let fade = card.content.layer?.animation(forKey: kCATransition) as? CATransition else {
            preconditionFailure("The step content crossfades")
        }
        precondition(fade.type == .fade && fade.duration == OnboardingStepMotion.contentFadeDuration,
                     "Step content crossfades in place, no push")
        outgoing.forEach { $0.removeFromSuperview() }
        card.heading.layer?.removeAllAnimations(); card.message.layer?.removeAllAnimations()
        card.content.layer?.removeAllAnimations()
        card.animateStepChange(from: nil, direction: .back, slides: false, fades: true)
        precondition(card.heading.layer?.animation(forKey: "step") == nil && card.outgoingText.subviews.isEmpty
                     && card.content.layer?.animation(forKey: kCATransition) != nil,
                     "Reduce Motion keeps the crossfade and drops the slides")
    }
}
