import AppKit
import SwiftUI
import ParcKit
import ParcLibrary
import ParcSidebar

enum SiteControlCenterBlockedMetrics {
    static let visibleRows = 3
    static let glyph: CGFloat = 18
    static let actionHeight: CGFloat = 24
    static let actionPadding: CGFloat = 9
    static let allowHeight: CGFloat = 44
    static let quietOpacity: CGFloat = 0.55
    static let captionFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let actionFont = NSFont.systemFont(ofSize: 12, weight: .medium)
}

struct SiteControlCenterBlockedView: View {
    @ObservedObject var model: SiteControlCenterModel
    let content: BlockedPageContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = model.colors
        let items = content.displayItems
        let shown = model.blockedExpanded ? items : Array(items.prefix(SiteControlCenterBlockedMetrics.visibleRows))
        let hidden = items.count - shown.count
        SiteControlCenterSectionView(title: "Blocked", hoverAccessoryText: "Settings",
                                     tooltip: "Pop-up and Redirect Settings",
                                     colors: colors.menu, onHeaderClick: { model.onBlockedSettings?() }) {
            VStack(alignment: .leading, spacing: SiteControlCenterMetrics.spacing) {
                ForEach(shown) { item in
                    SiteControlCenterBlockedRow(item: item, colors: colors) { model.onBlockedOpen?(item) }
                }
                if hidden > 0 || content.popupCount > 1 {
                    HStack(alignment: .center, spacing: 0) {
                        if hidden > 0 {
                            SwiftUI.Button {
                                withAnimation(reduceMotion ? nil : SiteControlCenterMotion.rowHover) { model.blockedExpanded = true }
                            } label: {
                                Text("\(hidden) more").font(Font(SiteControlCenterBlockedMetrics.captionFont))
                                    .foregroundColor(Color(nsColor: colors.menu.title)
                                        .opacity(SiteControlCenterBlockedMetrics.quietOpacity))
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .parcTooltip(TooltipConfiguration("Show everything that was blocked"))
                            .accessibilityLabel("Show \(hidden) more blocked")
                        }
                        Spacer(minLength: 0)
                        if content.popupCount > 1 {
                            SwiftUI.Button("Open All") { model.onBlockedOpenAll?() }
                                .buttonStyle(SiteControlCenterCapsuleStyle(colors: colors))
                                .parcTooltip(TooltipConfiguration("Open all \(content.popupCount) pop-ups"))
                                .accessibilityLabel("Open all \(content.popupCount) blocked pop-ups")
                        }
                    }
                    .padding(.leading, SidebarPlusRowButton.titleOrigin.x)
                    .padding(.trailing, SidebarPlusMenuView.separatorInsets.left)
                }
                if content.allowed {
                    SiteControlCenterBlockedAllowedRow(colors: colors)
                } else if content.canAllow {
                    allow(colors)
                }
            }
        }
    }

    @ViewBuilder private func allow(_ colors: SiteControlCenterColors) -> some View {
        let quiet = Color(nsColor: colors.menu.title).opacity(SiteControlCenterBlockedMetrics.quietOpacity)
        SwiftUI.Button { model.onBlockedAllow?() } label: {
            VStack(alignment: .center, spacing: 1) {
                Text(content.allowTitle).font(Font(SidebarPlusRowButton.titleFont))
                if !content.siteName.isEmpty {
                    HStack(spacing: 0) {
                        Text("from ").layoutPriority(1)
                        Text(content.siteName).truncationMode(.head)
                    }
                    .font(Font(SiteControlCenterBlockedMetrics.captionFont))
                    .foregroundColor(quiet).lineLimit(1)
                }
            }
            .padding(.horizontal, SiteControlCenterMetrics.spacing)
            .frame(maxWidth: .infinity)
            .frame(height: SiteControlCenterBlockedMetrics.allowHeight)
        }
        .buttonStyle(SiteControlCenterTileStyle(colors: colors))
        .parcTooltip(TooltipConfiguration(content.allowTooltip))
        .accessibilityLabel(content.allowTitle)
        .accessibilityValue(content.allowDetail)
        .accessibilityHint(BlockedPageContent.allowHint)
        Text(BlockedPageContent.allowHint)
            .font(Font(SiteControlCenterBlockedMetrics.captionFont))
            .foregroundColor(quiet)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

struct SiteControlCenterBlockedGlyph: View {
    let name: String
    let colors: SiteControlCenterColors

    var body: some View {
        let side = SiteControlCenterMetrics.settingIcon
        Group {
            if let image = SiteControlCenterArtwork.image(name) {
                Image(nsImage: image).renderingMode(.template).resizable()
                    .frame(width: SiteControlCenterBlockedMetrics.glyph, height: SiteControlCenterBlockedMetrics.glyph)
            }
        }
        .foregroundColor(Color(nsColor: colors.menu.title))
        .frame(width: side, height: side)
        .background(Color(nsColor: colors.offPlate))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct SiteControlCenterBlockedLeading<Plate: View>: View {
    let plate: Plate
    let title: String
    let subtitle: String
    let colors: SiteControlCenterColors

    var body: some View {
        let side = SiteControlCenterMetrics.settingIcon
        let icon = SidebarPlusRowButton.iconCenter
        HStack(alignment: .center, spacing: 0) {
            plate
                .padding(.leading, icon.x - side / 2)
                .padding(.trailing, SidebarPlusRowButton.titleOrigin.x - icon.x - side / 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Font(SidebarPlusRowButton.titleFont))
                    .foregroundColor(Color(nsColor: colors.menu.title))
                    .truncationMode(.head)
                Text(subtitle).font(Font(SidebarPlusRowButton.shortcutFont))
                    .foregroundColor(Color(nsColor: colors.menu.subtitle))
            }
            .lineLimit(1)
        }
    }
}

struct SiteControlCenterBlockedRow: View {
    let item: BlockedPageContent.Item
    let colors: SiteControlCenterColors
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            SiteControlCenterBlockedLeading(plate: SiteControlCenterBlockedGlyph(name: item.glyphName, colors: colors),
                                            title: item.title, subtitle: item.subtitle, colors: colors)
                .accessibilityElement(children: .combine)
                .parcTooltip(TooltipConfiguration(item.url?.absoluteString ?? item.title))
            Spacer(minLength: 4)
            SwiftUI.Button(item.actionTitle, action: action)
                .buttonStyle(SiteControlCenterCapsuleStyle(colors: colors))
                .parcTooltip(TooltipConfiguration(item.actionHelp))
                .accessibilityLabel(item.actionTitle)
                .accessibilityHint(item.actionHelp)
        }
        .frame(height: SidebarPlusMenuView.rowHeight)
        .padding(.trailing, SidebarPlusMenuView.separatorInsets.left)
        .accessibilityElement(children: .contain)
    }
}

struct SiteControlCenterBlockedAllowedRow: View {
    let colors: SiteControlCenterColors

    var body: some View {
        let side = SiteControlCenterMetrics.settingIcon
        let plate = Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(nsColor: colors.menu.title))
            .frame(width: side, height: side)
            .background(Color(nsColor: colors.onPlate))
            .clipShape(Circle())
            .accessibilityHidden(true)
        HStack(spacing: 0) {
            SiteControlCenterBlockedLeading(plate: plate, title: BlockedPageContent.allowedTitle,
                                            subtitle: BlockedPageContent.allowedDetail, colors: colors)
            Spacer(minLength: 0)
        }
        .frame(height: SidebarPlusMenuView.rowHeight)
        .accessibilityElement(children: .combine)
    }
}

struct SiteControlCenterCapsuleStyle: ButtonStyle {
    let colors: SiteControlCenterColors

    func makeBody(configuration: Configuration) -> some View {
        Face(label: configuration.label, isPressed: configuration.isPressed, colors: colors)
    }

    private struct Face: View {
        let label: ButtonStyleConfiguration.Label
        let isPressed: Bool
        let colors: SiteControlCenterColors
        @State private var hovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let state: SiteControlCenterTileState = !isEnabled ? .rest : isPressed ? .pressed : hovered ? .hovered : .rest
            let fill = state == .rest ? colors.restingFill : colors.menu.hover
            label
                .font(Font(SiteControlCenterBlockedMetrics.actionFont))
                .foregroundColor(Color(nsColor: isEnabled ? colors.menu.title : colors.menu.disabledTitle))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, SiteControlCenterBlockedMetrics.actionPadding)
                .frame(height: SiteControlCenterBlockedMetrics.actionHeight)
                .background(Capsule(style: .continuous).fill(Color(nsColor: fill)))
                .scaleEffect(state == .pressed && !reduceMotion ? 0.96 : 1)
                .animation(reduceMotion ? nil : .spring(response: LibraryRailTile.pressResponse,
                                                        dampingFraction: LibraryRailTile.pressDamping), value: state == .pressed)
                .animation(reduceMotion ? nil : SiteControlCenterMotion.interaction, value: state == .hovered)
                .contentShape(Capsule(style: .continuous))
                .onHover { hovered = $0 }
                .pointingHandCursor()
        }
    }
}
