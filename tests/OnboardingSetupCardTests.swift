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
            ("Welcome to Parc, Ada Lovelace.", "Here’s your Parc Card. Show it off to the world or keep it to yourself.\n\nAnd with that, you’re now ready to experience your upgraded internet.")
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
        let confetti = OnboardingConfettiView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView?.addSubview(confetti)
        confetti.burst(using: [.red])
        precondition(confetti.emitterBirthRate == 1)
        confetti.stop()
        precondition(confetti.emitterBirthRate == 0)
        confetti.burst(using: [.red])
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        confetti.burst(using: [.blue])
        precondition(confetti.emitterBirthRate == 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(confetti.emitterBirthRate == 1, "A stale burst must not zero the live emitter")
        window.close()
        print("PASS: all five setup layouts, grain/border chrome, native compact-display scaling and light/dark optical composition")
    }
}
