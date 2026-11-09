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
    var seeWhatsNew: () -> Void = {}
    var share: () -> Void = {}
    var dismiss: () -> Void = {}
}

struct UpdateCompleteBanner: View {
    @ObservedObject var model: UpdateCompleteModel

    var body: some View {
        VStack(spacing: 8) {
            UpdateBannerHeader(title: "Update Complete!", dark: model.dark, close: model.dismiss)
            VStack(alignment: .leading) {
                //
                //
                UpdateBannerRow(title: "See What’s New", icon: "heart.circle.fill", dark: model.dark, action: model.seeWhatsNew)
                UpdateBannerRow(title: "Share Parc", icon: "gift", dark: model.dark, action: model.share)
            }
            .padding(.horizontal, 8)
        }
        .padding(.bottom, 8)
        .background(UpdateBannerCard(dark: model.dark))
        // Not .disabled: that would dim the rows through the exit fade.
        .allowsHitTesting(model.interactive)
        .environment(\.colorScheme, model.dark ? .dark : .light)
    }
}

///
private struct UpdateBannerCard: View {
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
private struct UpdateBannerHeader: View {
    let title: String
    let dark: Bool
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            //
            ViewThatFits(in: .horizontal) {
                label.padding(.horizontal, 20)
                label.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 24)
            UpdateBannerCloseButton(dark: dark, action: close)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(dark ? Color.white.opacity(0.15) : Color.black.opacity(0.07)).frame(height: 1)
        }
    }

    private var label: some View {
        Text(title)
            .foregroundStyle(dark ? Color.white : .black)
            .padding(.vertical, 4)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .lineLimit(1)
            .fixedSize()
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
/// hovered.
private struct UpdateBannerRow: View {
    let title: String
    let icon: String
    let dark: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hovered ? 1 : 0.75)
        .animation(.easeOut(duration: 0.1), value: hovered)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
