import AppKit
import SwiftUI

///
///
/// `BannerHeaderView`, `SecondaryButton` rows and `BannerBackgroundContainer`.
/// Content only: `SidebarBannerHost` owns lifetime and motion. The recovered
/// values and the open ones are in docs/software-update.md.
@MainActor
final class UpdateCompleteCard: NSView {
    var onSeeWhatsNew: (() -> Void)?
    var onShare: (() -> Void)?
    var onDismiss: (() -> Void)?
    private let model = UpdateCompleteModel()
    private var hosting: NSHostingController<UpdateCompleteBanner>!
    private var measured: (width: CGFloat, height: CGFloat)?
    override var isFlipped: Bool { true }
    var keyViewControls: [NSView] { [hosting.view] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        model.seeWhatsNew = { [weak self] in self?.perform(self?.onSeeWhatsNew) }
        model.share = { [weak self] in self?.perform(self?.onShare) }
        model.dismiss = { [weak self] in self?.perform(self?.onDismiss) }
        hosting = NSHostingController(rootView: UpdateCompleteBanner(model: model))
        // The sidebar sizes the slot; the content must not add constraints.
        hosting.sizingOptions = []
        hosting.view.frame = bounds
        hosting.view.autoresizingMask = [.width, .height]
        addSubview(hosting.view)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyPalette(_ palette: ThemeChromePalette) {
        model.dark = palette.isDark
        model.gradientBase = Color(nsColor: UpdateCompleteModel.gradientBase(palette))
    }
    func setInteractionEnabled(_ enabled: Bool) { model.interactive = enabled }
    /// Asked on every sidebar layout while the banner occupies the slot.
    func preferredHeight(for width: CGFloat) -> CGFloat {
        if let measured, measured.width == width { return measured.height }
        let height = ceil(hosting.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        measured = (width, height)
        return height
    }
    private func perform(_ action: (() -> Void)?) {
        guard model.interactive, window?.isKeyWindow == true, !isHiddenOrHasHiddenAncestor else { return }
        action?()
    }
}

@MainActor
final class UpdateCompleteModel: ObservableObject {
    @Published var dark = false
    @Published var interactive = false
    @Published var gradientBase = Color.accentColor
    var seeWhatsNew: () -> Void = {}
    var share: () -> Void = {}
    var dismiss: () -> Void = {}

    /// `ButtonBackground` fills from the theme palette and falls back to a
    ///
    /// entries it reads is inferred; see the doc.
    static func gradientBase(_ palette: ThemeChromePalette) -> NSColor {
        guard let color = (palette.isDark ? palette.maxContrastColor : palette.minContrastColor).usingColorSpace(.sRGB)
        else { return .controlAccentColor }
        // HSL saturation: the palette lifts the theme colour's lightness,
        // which keeps it but drains HSB saturation from a pastel.
        let high = max(color.redComponent, color.greenComponent, color.blueComponent)
        let low = min(color.redComponent, color.greenComponent, color.blueComponent)
        let spread = 1 - abs(high + low - 1)
        return spread > 0 && (high - low) / spread > 0.1 ? color : .controlAccentColor
    }
}

struct UpdateCompleteBanner: View {
    @ObservedObject var model: UpdateCompleteModel
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            UpdateBannerHeader(title: "Update Complete!", dark: model.dark, sparkles: !reduceMotion, sparkleColor: model.gradientBase,
                               close: model.dismiss)
            VStack(alignment: .leading) {
                //
                //
                UpdateBannerRow(title: "See What’s New", icon: "heart.circle.fill", dark: model.dark,
                                gradient: hovered && model.interactive && !reduceMotion, base: model.gradientBase,
                                action: model.seeWhatsNew)
                UpdateBannerRow(title: "Share Parc", icon: "gift", dark: model.dark,
                                gradient: false, base: model.gradientBase, action: model.share)
            }
            .padding(.horizontal, 8)
        }
        .padding(.bottom, 8)
        .background(UpdateBannerCard(dark: model.dark))
        .onHover { hovered = $0 }
        // No hover exit arrives once hit testing stops.
        .onReceive(model.$interactive) { if !$0 { hovered = false } }
        // Not .disabled: that would dim the rows through the exit fade.
        .allowsHitTesting(model.interactive)
        .environment(\.colorScheme, model.dark ? .dark : .light)
    }
}

///
struct UpdateBannerCard: View {
    let dark: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill((dark ? Color.black : .white).opacity(0.9))
            .shadow(color: .black.opacity(dark ? 0.15 : 0.05), radius: 2, x: 0, y: 2)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(dark ? 0.1 : 0), lineWidth: 1)
                    .padding(-0.5)
            }
    }
}

///
/// leading once it no longer fits beside the close button, over a hairline.
struct UpdateBannerHeader: View {
    let title: String
    let dark: Bool
    let sparkles: Bool
    let sparkleColor: Color
    ///
    let close: (() -> Void)?
    /// Collapsed, the header is the whole banner: its own fill, no divider.
    var expanded = true
    var hovered = false
    // Kept here, not in the label, so a switch between the two layouts
    //
    @State private var sparkling = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            //
            ViewThatFits(in: .horizontal) {
                label.fixedSize().padding(.horizontal, 20)
                // A long title truncates rather than leaving the card.
                label.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 24)
            if let close { UpdateBannerCloseButton(dark: dark, action: close) }
        }
        .overlay(alignment: .bottom) {
            if expanded {
                Rectangle().fill(dark ? Color.white.opacity(0.15) : Color.black.opacity(0.07)).frame(height: 1)
            }
        }
        .background {
            //
            if !expanded {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                shape.fill((dark ? Color.white : .black).opacity((dark ? 0.1 : 0.03) * (hovered ? 2 : 1)))
                    .overlay { shape.stroke(Color.black.opacity(0.08), lineWidth: 1) }
            }
        }
        .onAppear {
            // Always scheduled: sparkles turned on later still time out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                withAnimation(.easeOut(duration: 0.4)) { sparkling = false }
            }
        }
    }

    private var label: some View {
        Text(title)
            .foregroundStyle(dark ? Color.white : .black)
            .padding(.vertical, 4)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .lineLimit(1)
            .overlay {
                // The gradient's palette treatment, so a pastel stays visible on the light card.
                if sparkles && sparkling {
                    UpdateBannerSparkles(color: sparkleColor).brightness(dark ? 0.6 : -0.2).saturation(dark ? 1 : 2)
                        .padding(-2).opacity(0.7)
                        .transition(.opacity)
                }
            }
    }
}

///
private struct UpdateBannerCloseButton: View {
    let dark: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            ZStack {
                CloseButtonPlate()
                    .fill((dark ? Color.white : .black).opacity(dark ? 0.15 : 0.1))
                    .opacity(hovered ? 1 : 0)
                    .frame(width: 20, height: 20)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle((dark ? Color.white : .black).opacity(hovered ? 1 : 0.4))
            }
            // The whole 24-point button takes the hover and click, not only the glyph.
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Dismiss")
    }
}

///
/// bottom-left 2): the plate follows the card's 12-point corner.
private struct CloseButtonPlate: Shape {
    func path(in rect: CGRect) -> Path {
        let topLeft: CGFloat = 2, topRight: CGFloat = 11, bottomRight: CGFloat = 2, bottomLeft: CGFloat = 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight), radius: topRight,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addArc(center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight), radius: bottomRight,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addArc(center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft), radius: bottomLeft,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addArc(center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft), radius: topLeft,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

///
/// hovered; a gradient row paints its label with `ButtonBackground`.
struct UpdateBannerRow: View {
    let title: String
    let icon: String
    let dark: Bool
    let gradient: Bool
    let base: Color
    var alignment = Alignment.leading
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .opacity(gradient ? 0 : 1)
                .overlay {
                    // Built only while shown, so its endless turn stops with it.
                    if gradient {
                        UpdateBannerGradient(base: base)
                            .brightness(dark ? 0.6 : -0.2)
                            .saturation(dark ? 1 : 2)
                            .mask { label }
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hovered ? 1 : 0.75)
        .animation(.easeOut(duration: 0.1), value: [hovered, gradient])
        .onHover { hovered = $0 }
    }

    private var label: some View {
        //
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title).font(.system(size: 12))
        }
        .foregroundStyle((dark ? Color.white : .black).opacity(dark ? 1 : 0.8))
        .frame(height: 16)
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}

///
/// hue-shifted capsules turning over the base colour. The turn durations were
/// not recovered.
struct UpdateBannerGradient: View {
    let base: Color
    /// `SecondaryButton` passes 6 and 1, `PrimaryButtonStyle` 12 and 0.5.
    var blurRadius: CGFloat = 6
    var blurOpacity = 1.0
    @State private var size = CGSize.zero
    @State private var turned = false

    var body: some View {
        ZStack {
            base
            ZStack {
                Capsule(style: .continuous)
                    .frame(width: size.width / 1.5, height: size.height)
                    .scaleEffect(2)
                    .rotationEffect(.degrees(turned ? 360 : 0))
                    .foregroundStyle(base)
                    .hueRotation(.degrees(40))
                    .saturation(5)
                    .brightness(1.25)
                    .blur(radius: blurRadius * 2)
                    .blendMode(.hardLight)
                Capsule(style: .continuous)
                    .frame(width: size.width * 0.5, height: size.height)
                    .scaleEffect(2)
                    .rotationEffect(.degrees(turned ? -360 : 0))
                    .foregroundStyle(base.opacity(0.6))
                    .hueRotation(.degrees(-40))
                    .saturation(2)
                    .brightness(-0.5)
                    .offset(y: size.height / -1.75)
                    .blur(radius: blurRadius)
                    .blendMode(.hardLight)
            }
            .opacity(blurOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background { GeometryReader { Color.clear.preference(key: Size.self, value: $0.size) } }
        .onPreferenceChange(Size.self) { size = $0 }
        .onAppear { withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { turned = true } }
    }
    private struct Size: PreferenceKey {
        static let defaultValue = CGSize.zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
    }
}

///
/// `update-complete-sparkle-timeout-in-seconds` (15). Their glyph, count and
/// timing were not recovered; they take the theme colour the view reads.
private struct UpdateBannerSparkles: View {
    let color: Color
    private struct Sparkle: Identifiable {
        let id = UUID()
        let x: CGFloat, y: CGFloat, size: CGFloat, delay: Double
    }
    @State private var sparkles: [Sparkle] = []
    @State private var lit = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(sparkles) { sparkle in
                    Image(systemName: "sparkle")
                        .font(.system(size: sparkle.size))
                        .foregroundStyle(color)
                        .opacity(lit ? 1 : 0)
                        .transition(.opacity)
                        .scaleEffect(lit ? 1 : 0.3)
                        .position(x: sparkle.x * proxy.size.width, y: sparkle.y * proxy.size.height)
                        .animation(.easeInOut(duration: 0.8).repeatForever().delay(sparkle.delay), value: lit)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            sparkles = (0..<6).map { _ in
                Sparkle(x: .random(in: 0...1), y: .random(in: 0...1), size: .random(in: 5...8), delay: .random(in: 0...0.8))
            }
            // Inserted dark first, so the repeating animation sees lit change.
            DispatchQueue.main.async { lit = true }
        }
    }
}
