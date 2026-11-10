import AppKit
import Combine
import SwiftUI

//
// order and actions, presented and styled as the dock plus HUD by user
// direction (November 1): its card, tail, motion, colours and row plates.
// Recovered layout, values and adaptations are in
// docs/web-interactions.md#site-control-center--web14. Boosts are excluded
// scope, so the Boost section, the New Boost button and the Boost menu items
// are not built.

///
///
/// (provenance in its README): the compiled 1× and 2× bitmaps plus a vector PDF
/// of the catalog's SVG rendition, at the 1× point size, as a template.
@MainActor enum SiteControlCenterArtwork {
    static let directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("SiteControlCenter", isDirectory: true)
    private static var cache: [String: NSImage] = [:]

    ///
    static var controlCenter: NSImage? { image("icon-control-center") }

    static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name + ".png")),
              let base = NSBitmapImageRep(data: data) else { return nil }
        let size = NSSize(width: base.pixelsWide, height: base.pixelsHigh)
        base.size = size
        let image = NSImage(size: size)
        image.addRepresentation(base)
        if let data = try? Data(contentsOf: directory.appendingPathComponent(name + "@2x.png")),
           let double = NSBitmapImageRep(data: data) {
            double.size = NSSize(width: CGFloat(double.pixelsWide) / 2, height: CGFloat(double.pixelsHigh) / 2)
            image.addRepresentation(double)
        }
        if let vector = NSImage(contentsOf: directory.appendingPathComponent(name + ".pdf")) {
            for representation in vector.representations { image.addRepresentation(representation) }
        }
        image.isTemplate = true
        cache[name] = image
        return image
    }
}

///
///
/// that inset: two insets, three spacings and four 48-point buttons.
enum SiteControlCenterMetrics {
    static let padding = SidebarPlusMenuView.inset
    static let sectionSpacing: CGFloat = 10
    static let spacing: CGFloat = 8
    static let button = CGSize(width: 48, height: 32)
    static let width = padding * 2 + spacing * 3 + button.width * 4
    static let columns = 4
    static let settingIcon: CGFloat = 32
    static let extensionIcon: CGFloat = 16
    /// The engine's action image canvas (extension_action_bridge.mm).
    static let extensionCanvas: CGFloat = 32
    static let pin: CGFloat = 14
    static let footerHeight: CGFloat = 32
}

///
/// tile's fills, each resolved by the Site Control Center's own appearance.
struct SiteControlCenterColors {
    let menu: PArcMenuColors
    let restingFill = Self.libraryFill(LibraryRailTile.fillOpacity(selected: false, hovered: true))
    let selectedFill = Self.libraryFill(LibraryRailTile.fillOpacity(selected: true, hovered: true))
    /// An on setting's or pinned badge's plate: the theme's focus, which keeps
    /// the title-colour glyph above 6:1 in the green and purple themes.
    let onPlate: NSColor
    /// An off setting's or unpinned badge's plate.
    var offPlate: NSColor { selectedFill }

    init(theme: SpaceTheme) {
        menu = PArcMenuColors(theme: theme)
        let light = ThemeChromePalette(theme: theme, isDark: false), dark = ThemeChromePalette(theme: theme, isDark: true)
        func either(_ light: NSColor, _ dark: NSColor) -> NSColor {
            NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
        }
        onPlate = either(light.focus, dark.focus)
    }

    private static func libraryFill(_ opacity: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            var color = NSColor.clear
            appearance.performAsCurrentDrawingAppearance {
                color = NSColor(cgColor: LibraryRailTile.fill(opacity: opacity).cgColor) ?? .clear
            }
            return color
        }
    }
}

@MainActor
final class SiteControlCenterModel: ObservableObject {
    ///
    enum Button: Int, CaseIterable, Identifiable {
        case share, copyURL, capture, captureFullPage, captureVisiblePage
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .share: return "Share"
            case .copyURL: return "Copy URL"
            case .capture: return "Capture a portion of this page"
            case .captureFullPage: return "Capture the full page"
            case .captureVisiblePage: return "Capture the visible area"
            }
        }
        /// The command whose live binding the tooltip's keycaps show.
        var commandID: String? {
            switch self {
            case .share: return nil
            case .copyURL: return "copyCurrentURL:"
            case .capture: return "capturePage:"
            case .captureFullPage: return "captureFullPage:"
            case .captureVisiblePage: return "captureVisiblePage:"
            }
        }
    }
    struct Extension: Identifiable, Equatable {
        let id: String
        let name: String
        let tooltip: String
        let accessibilityLabel: String
        let icon: NSImage?
        let isPinned: Bool
        let canChangePin: Bool
        /// The shell-drawn badge over an unbadged `icon`; nil with a baked one.
        var badge: ExtensionActionBadge? = nil
        /// The action's badge text, whichever canvas shows it.
        var badgeText = ""
        static func == (lhs: Extension, rhs: Extension) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs.tooltip == rhs.tooltip && lhs.icon === rhs.icon
                && lhs.isPinned == rhs.isPinned && lhs.canChangePin == rhs.canChangePin
                && lhs.accessibilityLabel == rhs.accessibilityLabel && lhs.badge == rhs.badge && lhs.badgeText == rhs.badgeText
        }
    }
    ///
    struct Setting: Identifiable, Equatable {
        let id: String
        let symbol: String
        let symbolSize: CGFloat
        let symbolWeight: Font.Weight
        let title: String
        let subtitle: String
        let isOn: Bool
        let isEnabled: Bool
    }

    @Published var canShare = false
    @Published var canCopy = false
    ///
    @Published var captureAvailable = false
    @Published var canCapture = false
    @Published var extensions: [Extension] = []
    /// ExtensionPickerState.focusedExtension; nil outside the picker.
    @Published var focusedExtension: String?
    /// The extension whose menu is open; its tile stays lit, as a menu's row
    /// does beside its open submenu.
    @Published var menuExtension: String?
    @Published var settings: [Setting] = []
    /// FooterView.State?: nil hides the divider and footer.
    @Published var isSecure: Bool?
    @Published var colors = SiteControlCenterColors(theme: SpaceTheme())
    /// Each button's frame in the content's coordinate space, for anchoring.
    var buttonFrames: [Button: CGRect] = [:]
    var shortcuts: [Button: String] = [:]

    var onButton: ((Button) -> Void)?
    var onExtension: ((String) -> Void)?
    var onExtensionContextMenu: ((String) -> Void)?
    var onExtensionPin: ((String) -> Void)?
    var onManageExtensions: (() -> Void)?
    var onAddExtension: (() -> Void)?
    var onSetting: ((String) -> Void)?
    var onSiteSettings: (() -> Void)?
    var onSecurity: (() -> Void)?
    var onMore: (() -> Void)?

    var buttons: [Button] {
        //
        // slot (whose reference fallback is Copy URL), retaining four columns.
        captureAvailable ? [.share, .captureVisiblePage, .capture, .captureFullPage]
            : [.share, .copyURL]
    }
    func isEnabled(_ button: Button) -> Bool {
        switch button {
        case .share: return canShare
        case .copyURL: return canCopy
        case .capture, .captureFullPage, .captureVisiblePage: return canCapture
        }
    }
    func help(_ button: Button) -> String {
        guard let shortcut = shortcuts[button], !shortcut.isEmpty else { return button.title }
        return button.title + "  " + shortcut
    }

    /// Picker focus moves through the extension order and wraps.
    func moveFocus(_ step: Int) {
        guard !extensions.isEmpty else { focusedExtension = nil; return }
        guard let index = focusedExtension.flatMap({ id in extensions.firstIndex { $0.id == id } }) else {
            focusedExtension = extensions.first?.id
            return
        }
        focusedExtension = extensions[(index + step + extensions.count) % extensions.count].id
    }

    func invalidate() {
        onButton = nil; onExtension = nil; onExtensionContextMenu = nil; onExtensionPin = nil
        onManageExtensions = nil; onAddExtension = nil; onSetting = nil; onSiteSettings = nil
        onSecurity = nil; onMore = nil
    }
}

//

struct SiteControlCenterView: View {
    static let coordinateSpace = "SiteControlCenter"
    @ObservedObject var model: SiteControlCenterModel

    var body: some View {
        let colors = model.colors
        VStack(alignment: .center, spacing: SiteControlCenterMetrics.sectionSpacing) {
            HStack(alignment: .center, spacing: SiteControlCenterMetrics.spacing) {
                ForEach(model.buttons) { button in
                    SiteControlCenterActionButton(button: button, colors: colors, help: model.help(button)) {
                        model.onButton?(button)
                    }
                    .disabled(!model.isEnabled(button))
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: SiteControlCenterFrames.self,
                            value: [button: proxy.frame(in: .named(Self.coordinateSpace))])
                    })
                }
            }
            SiteControlCenterExtensionsView(model: model)
            if !model.settings.isEmpty { SiteControlCenterSettingsView(model: model) }
            if let isSecure = model.isSecure {
                SiteControlCenterSeparator(colors: colors.menu)
                SiteControlCenterFooterView(isSecure: isSecure, colors: colors, onSecurity: { model.onSecurity?() },
                                            onMore: { model.onMore?() })
            }
        }
        .padding(SiteControlCenterMetrics.padding)
        .frame(width: SiteControlCenterMetrics.width)
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(SiteControlCenterFrames.self) { model.buttonFrames = $0 }
    }
}

private struct SiteControlCenterFrames: PreferenceKey {
    static let defaultValue: [SiteControlCenterModel.Button: CGRect] = [:]
    static func reduce(value: inout [SiteControlCenterModel.Button: CGRect],
                       nextValue: () -> [SiteControlCenterModel.Button: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A Site Control Center item's state as its face draws it.
enum SiteControlCenterTileState: Equatable { case rest, hovered, pressed }

///
/// button style) on the plus HUD's card, by user direction. Rows rest bare
/// and take the rail's selected fill while hovered or highlighted. Tiles rest
///
///
///
/// spring. Content is the plus HUD's title colour at full strength.
struct SiteControlCenterTileStyle: ButtonStyle {
    let colors: SiteControlCenterColors
    var highlighted = false
    var restingPlate = true

    func makeBody(configuration: Configuration) -> some View {
        Tracker(label: configuration.label, isPressed: configuration.isPressed, colors: colors,
                highlighted: highlighted, raised: restingPlate)
    }

    private struct Tracker: View {
        let label: ButtonStyleConfiguration.Label
        let isPressed: Bool
        let colors: SiteControlCenterColors
        let highlighted: Bool
        let raised: Bool
        @State private var hovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let state: SiteControlCenterTileState = !isEnabled ? .rest
                : isPressed ? .pressed : hovered || highlighted ? .hovered : .rest
            SiteControlCenterTileFace(label: label, state: state, colors: colors, raised: raised)
                .animation(reduceMotion ? nil : SiteControlCenterMotion.interaction, value: state)
                .onHover { hovered = $0 }
                .pointingHandCursor()
        }
    }
}

/// An item's plate, edge and shadow in `state`.
struct SiteControlCenterTileFace<Label: View>: View {
    let label: Label
    let state: SiteControlCenterTileState
    let colors: SiteControlCenterColors
    let raised: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LibraryRailTile.cornerRadius, style: .continuous)
        let lifted = raised && state != .rest
        let pressed = state == .pressed
        let fill = state == .rest ? (raised ? colors.restingFill : .clear) : raised ? colors.menu.hover : colors.selectedFill
        let depth: CGFloat = pressed ? 1 : 3
        label
            .foregroundColor(Color(nsColor: isEnabled ? colors.menu.title : colors.menu.disabledTitle))
            .background {
                shape.fill(Color(nsColor: fill))
                    .overlay {
                        if lifted {
                            shape.inset(by: -0.5).offset(y: 1)
                                .stroke(Color.white.opacity(scheme == .dark ? 0.22 : 0.08), lineWidth: 1)
                                .clipShape(shape)
                        }
                    }
                    .shadow(color: lifted ? Color.black.opacity(0.15) : .clear, radius: depth, x: 0, y: depth)
                    .padding(pressed ? LibraryRailTile.pressedInset : 0)
                    .animation(reduceMotion ? nil : .spring(response: LibraryRailTile.pressResponse,
                                                            dampingFraction: LibraryRailTile.pressDamping), value: pressed)
            }
            .contentShape(Rectangle())
    }
}

/// The plus HUD's separator (SidebarPlusMenuView): one point of the hover
/// colour, rounded, inset 4 inside the edge inset.
struct SiteControlCenterSeparator: View {
    let colors: PArcMenuColors

    var body: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color(nsColor: colors.hover))
            .frame(height: 1)
            .padding(.horizontal, SidebarPlusMenuView.separatorInsets.left)
            .accessibilityHidden(true)
    }
}

///
/// in a 48 × 32 item.
struct SiteControlCenterActionButton: View {
    let button: SiteControlCenterModel.Button
    let colors: SiteControlCenterColors
    let help: String
    let action: () -> Void

    var body: some View {
        SwiftUI.Button(action: action) {
            icon.frame(width: SiteControlCenterMetrics.button.width, height: SiteControlCenterMetrics.button.height)
                .fixedSize()
        }
        .buttonStyle(SiteControlCenterTileStyle(colors: colors))
        .parcTooltip(TooltipConfiguration(button.title, shortcut: button.commandID.map { .command($0) }))
        .accessibilityLabel(button.title)
        .accessibilityHint(help)
    }

    /// Offsets put each glyph's ink centroid on the tile's centre (measured
    /// at 2x). Visible Area takes the full-strength `photo.artframe` symbol:
    ///
    @ViewBuilder private var icon: some View {
        switch button {
        case .share:
            Image(systemName: "square.and.arrow.up").font(.system(size: 16)).offset(y: -2)
        case .copyURL: artwork("copy-url", height: 17)
        case .capture: Image(systemName: "camera").font(.system(size: 16)).offset(y: -1)
        case .captureFullPage: artwork("capture-full-page", height: 19)
        case .captureVisiblePage: Image(systemName: "photo.artframe").font(.system(size: 16)).offset(y: -1)
        }
    }
    @ViewBuilder private func artwork(_ name: String, height: CGFloat) -> some View {
        if let image = SiteControlCenterArtwork.image(name) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(height: height)
        }
    }
}

///
/// header and the content, 5 points of bottom padding. The header's title and
/// its hover text (shown while the section is hovered) take the plus HUD's
/// title font and its trailing shortcut font. Parc draws them in the menu's
///
/// a pale theme.
struct SiteControlCenterSectionView<Content: View>: View {
    let title: String
    let hoverAccessoryText: String
    let tooltip: String
    let colors: PArcMenuColors
    let onHeaderClick: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .center, spacing: SiteControlCenterMetrics.sectionSpacing) {
            HStack {
                Text(title).font(Font(SidebarPlusRowButton.titleFont))
                Spacer()
                if isHovered {
                    Text(hoverAccessoryText).font(Font(SidebarPlusRowButton.shortcutFont))
                }
            }
            .foregroundColor(Color(nsColor: colors.title))
            .padding(.horizontal, SidebarPlusMenuView.separatorInsets.left)
            .contentShape(Rectangle())
            .pointingHandCursor()
            .onTapGesture(perform: onHeaderClick)
            .parcTooltip(TooltipConfiguration(tooltip))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityHint(hoverAccessoryText)
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityAction { onHeaderClick() }
            content()
        }
        .padding(.bottom, 5)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : SiteControlCenterMotion.rowHover) { isHovered = hovering }
        }
    }
}

///
enum SiteControlCenterMotion {
    ///
    static let interaction = Animation.easeOut(duration: 0.1)
    ///
    static let rowHover = Animation.easeOut(duration: 0.12)
    ///
    static func pinHover(_ hovering: Bool, reduceMotion: Bool = false) -> Animation {
        // The dwell is hover intent, so Reduce Motion keeps it and drops only the fade.
        (reduceMotion ? Animation.linear(duration: 0) : .easeInOut(duration: 0.12)).delay(hovering ? 0.36 : 0)
    }
}

///
/// then rows of four 48 × 32 items (the extensions, then Add Extension) with
///
struct SiteControlCenterExtensionsView: View {
    @ObservedObject var model: SiteControlCenterModel

    private enum Item: Identifiable {
        case ext(SiteControlCenterModel.Extension)
        case add
        var id: String {
            switch self { case .ext(let item): return "extension:" + item.id; case .add: return "add" }
        }
    }
    private struct Row: Identifiable { let id: Int; let items: [Item] }
    private var rows: [Row] {
        let items = model.extensions.map(Item.ext) + [.add]
        return stride(from: 0, to: items.count, by: SiteControlCenterMetrics.columns).map {
            Row(id: $0, items: Array(items[$0..<min($0 + SiteControlCenterMetrics.columns, items.count)]))
        }
    }

    var body: some View {
        let colors = model.colors
        SiteControlCenterSectionView(title: "Extensions", hoverAccessoryText: "Manage", tooltip: "Manage Extensions",
                                     colors: colors.menu, onHeaderClick: { model.onManageExtensions?() }) {
            VStack(alignment: .center, spacing: SiteControlCenterMetrics.spacing) {
                ForEach(rows) { row in
                    HStack(alignment: .center, spacing: SiteControlCenterMetrics.spacing) {
                        ForEach(row.items) { item in
                            switch item {
                            case .ext(let item):
                                SiteControlCenterExtensionButton(item: item,
                                    isHighlighted: model.focusedExtension == item.id || model.menuExtension == item.id,
                                    colors: colors,
                                    onClick: { model.onExtension?(item.id) },
                                    onRightClick: { model.onExtensionContextMenu?(item.id) },
                                    onPin: { model.onExtensionPin?(item.id) })
                            case .add:
                                SiteControlCenterAddExtensionButton(colors: colors) { model.onAddExtension?() }
                            }
                        }
                        if row.items.count < SiteControlCenterMetrics.columns { Spacer(minLength: 0) }
                    }
                }
            }
        }
    }
}

///
///
/// focuses it, and the pin badge at the bottom-trailing corner, offset (3, 3),
///
struct SiteControlCenterExtensionButton: View {
    let item: SiteControlCenterModel.Extension
    let isHighlighted: Bool
    let colors: SiteControlCenterColors
    let onClick: () -> Void
    let onRightClick: () -> Void
    let onPin: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.Button(action: onClick) {
            let canvas = SiteControlCenterMetrics.extensionCanvas
            ZStack {
                // Chromium centres the 16-point action icon in the requested
                // canvas (IconWithBadgeImageSource), so that canvas is shown at
                // its own size, as the toolbar strips do; any other image at 16.
                if let icon = item.icon, icon.size == NSSize(width: canvas, height: canvas) {
                    Image(nsImage: icon).resizable().frame(width: canvas, height: canvas)
                } else {
                    Image(nsImage: item.icon ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil) ?? NSImage())
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: SiteControlCenterMetrics.extensionIcon, height: SiteControlCenterMetrics.extensionIcon)
                }
                SiteControlCenterAlternateClick(extensionID: item.id, action: onRightClick)
            }
                .frame(width: SiteControlCenterMetrics.button.width, height: SiteControlCenterMetrics.button.height)
                .fixedSize()
        }
        .buttonStyle(SiteControlCenterTileStyle(colors: colors, highlighted: isHighlighted))
        .fixedSize()
        .parcTooltip(TooltipConfiguration(item.tooltip.isEmpty ? item.name : item.tooltip))
        .overlay(alignment: .topLeading) {
            if let badge = item.badge {
                // The pinned strips' badge over the centred icon's top-right corner.
                let frame = ExtensionActionBadgeMetrics.frame(text: badge.text, in: NSRect(origin: .zero, size: SiteControlCenterMetrics.button))
                SiteControlCenterBadge(badge: badge)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(item.accessibilityLabel.isEmpty ? item.name : item.accessibilityLabel)
        .accessibilityValue(item.badgeText)
        .accessibilityHint(item.tooltip.isEmpty ? item.name : item.tooltip)
        .accessibilityIdentifier("extension-action-" + item.id)
        .accessibilityAction(named: "Show Menu", onRightClick)
        .accessibilityActions {
            // The hover-only badge must not be the only way to pin using AX.
            if item.canChangePin {
                SwiftUI.Button(item.isPinned ? "Unpin" : "Pin", action: onPin)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isHovered || item.isPinned {
                SiteControlCenterExtensionPinButton(name: item.name, isPinned: item.isPinned,
                                                    colors: colors, action: onPin)
                    .disabled(!item.canChangePin)
                    .offset(x: 3, y: 3)
            }
        }
        .onHover { hovering in
            withAnimation(SiteControlCenterMotion.pinHover(hovering, reduceMotion: reduceMotion)) { isHovered = hovering }
        }
    }
}

/// The grid's Add Extension item: a 13-point semibold plus.
struct SiteControlCenterAddExtensionButton: View {
    let colors: SiteControlCenterColors
    let action: () -> Void

    var body: some View {
        SwiftUI.Button(action: action) {
            Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                .frame(width: SiteControlCenterMetrics.button.width, height: SiteControlCenterMetrics.button.height)
                .fixedSize()
        }
        .buttonStyle(SiteControlCenterTileStyle(colors: colors))
        .fixedSize()
        .parcTooltip(TooltipConfiguration("Add Extension"))
        .accessibilityLabel("Add Extension")
    }
}

///
/// weight, turned 33°, in the title colour on a 14-point circle: the theme's
/// focus when pinned, the rail's selected fill otherwise; tooltip Pin / Unpin.
struct SiteControlCenterExtensionPinButton: View {
    let name: String
    let isPinned: Bool
    let colors: SiteControlCenterColors
    let action: () -> Void

    var body: some View {
        SwiftUI.Button(action: action) {
            Image(systemName: "pin.fill").font(.system(size: 8, weight: .black))
                .rotationEffect(.radians(0.5759586531581288))
                .frame(width: SiteControlCenterMetrics.pin, height: SiteControlCenterMetrics.pin)
                .foregroundColor(Color(nsColor: colors.menu.title))
                .background(Color(nsColor: isPinned ? colors.onPlate : colors.offPlate))
                .clipShape(Circle())
                .contentShape(Circle())
                .pointingHandCursor()
        }
        .buttonStyle(.plain)
        .parcTooltip(TooltipConfiguration(isPinned ? "Unpin" : "Pin"))
        .accessibilityHint(isPinned ? "Unpin" : "Pin")
        .accessibilityLabel((isPinned ? "Unpin " : "Pin ") + name)
    }
}

/// The pinned strips' badge view (ExtensionControls.swift) in a tile.
struct SiteControlCenterBadge: NSViewRepresentable {
    let badge: ExtensionActionBadge
    func makeNSView(context: Context) -> ExtensionActionBadgeView { ExtensionActionBadgeView() }
    func updateNSView(_ view: ExtensionActionBadgeView, context: Context) { view.badge = badge }
}

///
/// extension's genuine context menu; ordinary clicks pass to the button.
struct SiteControlCenterAlternateClick: NSViewRepresentable {
    let extensionID: String
    let action: () -> Void
    func makeNSView(context: Context) -> ClickView { ClickView() }
    func updateNSView(_ view: ClickView, context: Context) {
        view.action = action
        view.identifier = Self.identifier(extensionID)
    }
    /// Names the tile for its menu's anchor.
    static func identifier(_ extensionID: String) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("extension-tile:" + extensionID)
    }

    final class ClickView: NSView {
        var action: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp: return super.hitTest(point)
            case .leftMouseDown, .leftMouseUp:
                return event.modifierFlags.contains(.control) ? super.hitTest(point) : nil
            default: return nil
            }
        }
        override func rightMouseDown(with event: NSEvent) { let perform = action; perform?() }
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { let perform = action; perform?() }
        }
        override func menu(for event: NSEvent) -> NSMenu? { nil }
        override func isAccessibilityElement() -> Bool { false }
    }
}

///
/// rows, eight points apart like the tiles.
struct SiteControlCenterSettingsView: View {
    @ObservedObject var model: SiteControlCenterModel

    var body: some View {
        let colors = model.colors
        SiteControlCenterSectionView(title: "Settings", hoverAccessoryText: "More", tooltip: "All Site Settings",
                                     colors: colors.menu, onHeaderClick: { model.onSiteSettings?() }) {
            VStack(alignment: .leading, spacing: SiteControlCenterMetrics.spacing) {
                ForEach(model.settings) { setting in
                    SiteControlCenterSettingRow(setting: setting, colors: colors) { model.onSetting?(setting.id) }
                }
            }
        }
    }
}

///
/// laid out as a plus HUD row in the Library tile treatment: the symbol
/// in the title colour on a 32-point circle (the theme's focus when on, the
/// rail's selected fill when off) centred on the row's icon point, then the
/// title over the state line at the row's title inset.
struct SiteControlCenterSettingRow: View {
    let setting: SiteControlCenterModel.Setting
    let colors: SiteControlCenterColors
    let action: () -> Void

    var body: some View {
        let side = SiteControlCenterMetrics.settingIcon
        let icon = SidebarPlusRowButton.iconCenter
        let symbol = Image(systemName: setting.symbol).font(.system(size: setting.symbolSize, weight: setting.symbolWeight))
            .frame(width: side, height: side)
        SwiftUI.Button(action: action) {
            HStack(alignment: .center, spacing: 0) {
                symbol.background(Color(nsColor: setting.isOn ? colors.onPlate : colors.offPlate))
                    .clipShape(Circle())
                    .padding(.leading, icon.x - side / 2)
                    .padding(.trailing, SidebarPlusRowButton.titleOrigin.x - icon.x - side / 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(setting.title).font(Font(SidebarPlusRowButton.titleFont))
                    Text(setting.subtitle).font(Font(SidebarPlusRowButton.shortcutFont))
                        .foregroundColor(Color(nsColor: setting.isEnabled ? colors.menu.subtitle : colors.menu.disabledSubtitle))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: SidebarPlusMenuView.rowHeight)
        }
        .buttonStyle(SiteControlCenterTileStyle(colors: colors, restingPlate: false))
        .disabled(!setting.isEnabled)
        .parcTooltip(TooltipConfiguration(setting.title))
        .accessibilityLabel(setting.title)
        .accessibilityValue(setting.subtitle)
    }
}

///
/// Secure / Insecure, padded 8 / 10, 32 high) and the 32-point ellipsis, as
/// Library tiles in the plus HUD's title font.
struct SiteControlCenterFooterView: View {
    let isSecure: Bool
    let colors: SiteControlCenterColors
    let onSecurity: () -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            SwiftUI.Button(action: onSecurity) {
                Text("\(Image(systemName: isSecure ? "lock.fill" : "lock.slash.fill")) \(isSecure ? "Secure" : "Insecure")")
                    // BaseAssets BrandRed (Display P3) at 0.9 when insecure.
                    .foregroundColor(isSecure ? Color(nsColor: colors.menu.title)
                        : Color(.displayP3, red: 0.8431372549, green: 0.2823529412, blue: 0.0274509804).opacity(0.9))
                    .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 10))
                    .frame(height: SiteControlCenterMetrics.footerHeight)
            }
            .buttonStyle(SiteControlCenterTileStyle(colors: colors))
            .parcTooltip(TooltipConfiguration(isSecure ? "Secure" : "Insecure"))
            Spacer()
            SwiftUI.Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .frame(width: SiteControlCenterMetrics.footerHeight, height: SiteControlCenterMetrics.footerHeight)
            }
            .buttonStyle(SiteControlCenterTileStyle(colors: colors))
            .parcTooltip(TooltipConfiguration("More"))
            .accessibilityLabel("More")
        }
        .font(Font(SidebarPlusRowButton.titleFont))
    }
}

// MARK: - Presentation

/// A Site Control Center presentation as its window's dismissal sees it.
@MainActor
protocol SiteControlCenterPresentation: AnyObject {
    /// True from the start of closing until the window is gone.
    var isAwaitingNativeClose: Bool { get }
    var onDidClose: (() -> Void)? { get set }
    func close()
}

/// The window removes its current PageInfo session as the card starts
/// closing, but a new action must still cross that card's exit animation.
/// Keep that barrier separate, and let every later dismissal cancel queued work.
@MainActor
final class SiteControlCenterDismissal {
    private var retiring: [ObjectIdentifier: any SiteControlCenterPresentation] = [:]
    private var generation = UUID()
    private var pendingAction: (() -> Void)?

    func track(_ controller: any SiteControlCenterPresentation) {
        guard controller.isAwaitingNativeClose else { return }
        let identity = ObjectIdentifier(controller)
        retiring[identity] = controller
        controller.onDidClose = { [weak self] in
            guard let self else { return }
            self.retiring.removeValue(forKey: identity)
            if self.retiring.isEmpty { self.enqueueAction() }
        }
    }

    func close(_ current: (any SiteControlCenterPresentation)?, then action: (() -> Void)? = nil) {
        close(current, when: { true }, then: action)
    }
    func close(_ current: (any SiteControlCenterPresentation)?, when valid: @escaping () -> Bool,
               then action: (() -> Void)? = nil) {
        let token = UUID()
        generation = token
        pendingAction = action.map { action in { if valid() { action() } } }
        let hadSession = current != nil || !retiring.isEmpty
        current?.close()
        guard generation == token, retiring.isEmpty else { return }
        if hadSession { enqueueAction() }
        else { runAction(token) }
    }

    private func enqueueAction() {
        guard pendingAction != nil else { return }
        let token = generation
        DispatchQueue.main.async { [weak self] in self?.runAction(token) }
    }

    private func runAction(_ token: UUID) {
        guard generation == token, retiring.isEmpty else { return }
        let action = pendingAction
        pendingAction = nil
        generation = UUID()
        action?()
    }
}

///
/// popover centres on the button with its arrow on the button's midpoint
///
/// card hangs from the button inside the part of the window on screen, on
/// the button's other side when its own has no room there; failing both, it
/// hangs from the button on the screen past the window. Only with room on
/// neither side of the button anywhere does it take the roomier side and
/// move onto the screen over the button.
@MainActor
enum SiteControlCenterPlacement {
    static func windowFrame(anchor: CGRect, card: CGSize, below: Bool, parent: CGRect,
                            screen: CGRect?) -> (frame: CGRect, tailX: CGFloat, below: Bool) {
        let height = card.height + SidebarPlusMenuPlacement.tailHeight
        let regions = Self.regions(window: parent, screen: screen)
        func fits(_ below: Bool, in region: CGRect) -> Bool {
            below ? anchor.minY - height >= region.minY : anchor.maxY + height <= region.maxY
        }
        let region = regions.first { card.width <= $0.width && (fits(below, in: $0) || fits(!below, in: $0)) } ?? regions[regions.count - 1]
        let side = fits(below, in: region) ? below
            : fits(!below, in: region) ? !below : anchor.minY - region.minY >= region.maxY - anchor.maxY
        let y = max(region.minY, min(side ? anchor.minY - height : anchor.maxY, region.maxY - height))
        // Across, the card keeps to the window wherever it is wide enough.
        let across = regions.first { card.width <= $0.width } ?? region
        let x = max(across.minX, min(anchor.midX - card.width / 2, across.maxX - card.width))
        let frame = CGRect(x: x, y: y, width: card.width, height: height)
        let edge = SidebarPlusMenuPlacement.cornerRadius + SidebarPlusMenuPlacement.tailBase / 2
        let tailX = min(card.width - edge, max(edge, anchor.midX - x))
        return (frame, tailX, side)
    }

    /// Where a card or menu looks for room, in order: the part of `window` on
    /// `screen` (a visible frame), then the screen.
    static func regions(window: CGRect, screen: CGRect?) -> [CGRect] {
        guard let screen else { return [window] }
        let visible = window.intersection(screen)
        return visible.isNull || visible.isEmpty ? [screen] : [visible, screen]
    }

    /// The visible frame of the display showing `point`; a window across two
    /// displays opens its card on the button's.
    static func screen(at point: CGPoint) -> CGRect? {
        NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame
    }
}

/// The plus HUD's window. A drag that starts on the card's background, not
///
///
@MainActor
final class SiteControlCenterWindow: SidebarPlusMenuWindow {
    /// Starts the window drag with the press that began it.
    var onDragOut: ((NSEvent) -> Void)?
    private var press: NSEvent?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            press = Self.isItem(at: event.locationInWindow, in: contentView) ? nil : event
        case .leftMouseDragged:
            if let press, hypot(event.locationInWindow.x - press.locationInWindow.x,
                                event.locationInWindow.y - press.locationInWindow.y) > 3 {
                self.press = nil
                onDragOut?(press)
                return
            }
        case .leftMouseUp: press = nil
        default: break
        }
        super.sendEvent(event)
    }

    /// Every item carries a tooltip anchor over its frame.
    static func isItem(at point: NSPoint, in view: NSView?) -> Bool {
        guard let view else { return false }
        if view is TooltipAnchorView, view.convert(view.bounds, to: nil).contains(point) { return true }
        return view.subviews.contains { isItem(at: point, in: $0) }
    }
}

/// The card: the plus HUD's background and corners around the hosted view.
///
@MainActor
final class SiteControlCenterCard: NSView {
    var colors: PArcMenuColors { didSet { needsDisplay = true } }
    var onEscape: (() -> Void)?

    init(content: NSView, colors: PArcMenuColors) {
        self.colors = colors
        super.init(frame: content.frame)
        SidebarPlusMenuView.shapeCard(self)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        colors.fillBackground(NSBezierPath(rect: bounds))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class SiteControlCenterController: NSObject, SiteControlCenterPresentation {
    let model: SiteControlCenterModel
    private let host: NSHostingController<SiteControlCenterView>
    private let card: SiteControlCenterCard
    private var panel: SiteControlCenterWindow?
    private var chrome: PArcMenuChrome?
    /// The button's rectangle in its own coordinates, that rectangle in its
    /// window at opening (if the button goes), and the side the card hangs from.
    private var placement: (rect: CGRect, opened: CGRect, below: Bool)?
    /// Torn off its button: an ordinary window that stays open.
    private(set) var isDetached = false
    /// Dismissals that end once the card detaches.
    nonisolated(unsafe) private var transientObservers: [NSObjectProtocol] = []
    private var pickerMonitor: Any?
    // The owner drops its controller at onClose. Keep this controller alive
    // until the card's exit animation finishes and delivers onDidClose.
    private var closingLifetime: SiteControlCenterController?
    private var closing = false
    private(set) var isAwaitingNativeClose = false
    private var pickerSelection: ((String) -> Void)?
    private weak var anchorView: NSView?
    private weak var anchorWindow: NSWindow?
    private var resignActiveObserver: NSObjectProtocol?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var modelChange: AnyCancellable?
    private var sizeCheck: Timer?
    /// The open extension menu; it closes with the card.
    private weak var extensionMenu: PArcContextMenu?
    private var keptOpen = 0
    private var pendingShow: UUID?
    var onClose: (() -> Void)?
    var onDidClose: (() -> Void)?
    var onDetach: (() -> Void)?
    /// Capture the original action leases once per held-Command gesture.
    var preparePickerSelection: (() -> ((String) -> Void)?)?
    /// The window's live theme; an open card recolours with it.
    var theme = SpaceTheme() {
        didSet { if theme != oldValue { applyTheme() } }
    }

    /// The press on a window's button that closed its card; the same press's
    /// action must not reopen it, as with the plus HUD.
    private static var closingPresses: [ObjectIdentifier: Int] = [:]

    init(model: SiteControlCenterModel) {
        self.model = model
        host = NSHostingController(rootView: SiteControlCenterView(model: model))
        host.sizingOptions = []
        card = SiteControlCenterCard(content: host.view, colors: model.colors.menu)
        super.init()
        card.onEscape = { [weak self] in self?.close() }
        modelChange = model.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSizeCheck() }
        }
        applyTheme()
    }

    deinit {
        sizeCheck?.invalidate()
        if let pickerMonitor { NSEvent.removeMonitor(pickerMonitor) }
        if let resignActiveObserver { NotificationCenter.default.removeObserver(resignActiveObserver) }
        observers.forEach(NotificationCenter.default.removeObserver)
        transientObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func isAnchored(to view: NSView) -> Bool { anchorView === view }

    /// Runs `body`, a menu from another control, without closing for losing
    /// key: a Control-click makes the browser window key first, and the
    /// losing-key check it queued runs inside the menu. Afterwards an
    /// attached card takes key back if the window kept it, or closes as it
    /// would have if the menu's command moved key elsewhere.
    func keepingOpen(_ body: () -> Void) {
        keptOpen += 1
        body()
        keptOpen -= 1
        guard keptOpen == 0, let panel, !closing, !isDetached, panel.isVisible else { return }
        if NSApp.isActive, let parent = anchorWindow, NSApp.keyWindow === parent {
            panel.makeKey()
        } else if !Self.holdsKey(panel) {
            close()
        }
    }

    /// Whether the key window is `panel` or a window it opened.
    private static func holdsKey(_ panel: NSWindow) -> Bool {
        var key = NSApp.keyWindow
        while let window = key {
            if window === panel { return true }
            key = window.parent
        }
        return false
    }

    /// Extension `id`'s tile on this card.
    func tile(for id: String) -> NSView? { Self.view(SiteControlCenterAlternateClick.identifier(id), in: host.view) }

    /// Runs `show` with a menu for extension `id` that hangs from this card
    /// like a submenu, level with `tile`, which stays lit until `show`
    /// returns. False when `tile` is not on the open card.
    func presentExtensionMenu(beside tile: NSView, for id: String, _ show: (PArcContextMenu) -> Void) -> Bool {
        guard let panel, !closing, tile.window === panel else { return false }
        let row = panel.convertToScreen(tile.convert(tile.bounds, to: nil))
        let edges = panel.convertToScreen(card.convert(card.bounds, to: nil))
        // The menu looks for room as the card does; a torn-off card's only on screen.
        let screen = SiteControlCenterPlacement.screen(at: CGPoint(x: row.midX, y: row.midY)) ?? panel.screen?.visibleFrame
        var regions = screen.map { [$0] } ?? []
        if let window = anchorWindow, !isDetached {
            regions = SiteControlCenterPlacement.regions(window: window.frame, screen: screen)
        }
        let menu = PArcContextMenu(anchor: NSRect(x: edges.minX, y: row.minY, width: edges.width, height: row.height),
                                  regions: regions, parent: panel, colors: model.colors.menu)
        extensionMenu = menu
        model.menuExtension = id
        show(menu)
        model.menuExtension = nil
        return true
    }

    private static func view(_ identifier: NSUserInterfaceItemIdentifier, in view: NSView) -> NSView? {
        if view.identifier == identifier { return view }
        for subview in view.subviews { if let found = Self.view(identifier, in: subview) { return found } }
        return nil
    }

    ///
    private var contentSize: NSSize {
        let size = host.sizeThatFits(in: NSSize(width: SiteControlCenterMetrics.width, height: .greatestFiniteMagnitude))
        return NSSize(width: SiteControlCenterMetrics.width, height: ceil(size.height))
    }

    /// A pending delayed show counts, so a second click closes rather than stacks.
    var isShown: Bool { (panel != nil && !closing) || pendingShow != nil }

    private func applyTheme() {
        let colors = SiteControlCenterColors(theme: theme)
        model.colors = colors
        card.colors = colors.menu
        chrome?.colors = colors.menu
        if let panel { TooltipController.controller(for: panel).palette = TooltipColorPalette(theme: theme) }
    }

    ///
    /// or 100 ms when the pill's button is missing or hidden) behind a token;
    /// `close` or a newer show makes the pending one stale. Toolbar and
    /// hidden-sidebar hosts show at once. `preferredEdge` names the side of
    /// `rect` in `view`'s coordinates, as for a popover.
    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge,
              after delay: DispatchTimeInterval? = nil, expectedWindow: NSWindow?, when valid: @escaping () -> Bool) {
        guard !closing, view.window === expectedWindow, valid() else { close(); return }
        if let expectedWindow, let press = Self.closingPresses.removeValue(forKey: ObjectIdentifier(expectedWindow)),
           NSApp.currentEvent.map({ Self.isMouse($0) && $0.eventNumber == press }) == true {
            close(); return
        }
        let originalWindow = expectedWindow
        anchorView = view
        anchorWindow = originalWindow
        if resignActiveObserver == nil {
            resignActiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                object: NSApp, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stopPicker() }
                }
        }
        let below = (preferredEdge == .maxY) == view.isFlipped
        guard let delay else {
            guard let originalWindow, view.window === originalWindow, valid() else { close(); return }
            pendingShow = nil; present(relativeTo: rect, of: view, below: below); return
        }
        let token = UUID(); pendingShow = token
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak view, weak originalWindow] in
            MainActor.assumeIsolated {
                guard let self, self.pendingShow == token else { return }
                self.pendingShow = nil
                //
                // also retains the original owner through the delayed show.
                guard let view, let originalWindow, view.window === originalWindow, valid() else { self.close(); return }
                self.present(relativeTo: rect, of: view, below: below)
            }
        }
    }

    /// The plus HUD's key child window, tail and opening motion, in the
    /// parent's appearance (a private window's dark), as a popover takes it.
    private func present(relativeTo rect: NSRect, of view: NSView, below: Bool) {
        guard panel == nil, let parent = view.window else { close(); return }
        let anchor = view.convert(rect, to: nil)
        let size = contentSize
        let button = parent.convertToScreen(anchor)
        let placed = SiteControlCenterPlacement.windowFrame(anchor: button, card: size, below: below, parent: parent.frame,
            screen: SiteControlCenterPlacement.screen(at: CGPoint(x: button.midX, y: button.midY)) ?? parent.screen?.visibleFrame)
        card.frame.size = size
        let chrome = PArcMenuChrome(content: card, size: size, colors: model.colors.menu, tailX: placed.tailX,
                                   tailOnTop: placed.below)
        let panel = SiteControlCenterWindow(contentRect: placed.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.appearance = parent.effectiveAppearance
        panel.setAccessibilityRole(.popover)
        panel.setAccessibilityLabel("Site Control Center")
        panel.contentView = chrome
        panel.onResignKey = { [weak self] in self?.lostFocus() }
        panel.onDragOut = { [weak self] press in self?.detach(dragging: press) }
        self.panel = panel
        self.chrome = chrome
        placement = (rect, anchor, placed.below)
        TooltipController.controller(for: panel).palette = TooltipColorPalette(theme: theme)
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        // The hosted buttons take Tab and Full Keyboard Access; Escape
        // reaches the card through the responder chain.
        panel.makeFirstResponder(host.view)
        observe(parent)
        SidebarPlusMenuMotion.animateOpen(chrome, about: chrome.tailTip)
    }

    /// SwiftUI applies a model change later in this run loop pass, so the
    /// hosted size is measured on the next one, in every mode (menus track).
    private func scheduleSizeCheck() {
        guard sizeCheck == nil else { return }
        let timer = Timer(timeInterval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sizeCheck = nil
                self?.updateSize()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sizeCheck = timer
    }

    /// Rows and extensions arrive after opening; the card keeps its tail on
    /// the button, where the button is now, and grows away from it, flipping
    /// and clamping as at opening. A detached card keeps its top edge.
    private func updateSize() {
        guard let panel, let placement, !closing, let parent = anchorWindow else { return }
        let size = contentSize
        guard size != card.frame.size else { return }
        guard !isDetached, let chrome else {
            var frame = panel.frame
            frame.origin.y += frame.height - size.height
            frame.size.height = size.height
            panel.setFrame(frame, display: true)
            return
        }
        let anchor = anchorView.flatMap { $0.window === parent ? $0.convert(placement.rect, to: nil) : nil } ?? placement.opened
        let button = parent.convertToScreen(anchor)
        let placed = SiteControlCenterPlacement.windowFrame(anchor: button, card: size, below: placement.below,
            parent: parent.frame,
            screen: SiteControlCenterPlacement.screen(at: CGPoint(x: button.midX, y: button.midY)) ?? parent.screen?.visibleFrame)
        if placed.below != chrome.tailOnTop || placed.tailX != chrome.tailX {
            let next = PArcMenuChrome(content: card, size: size, colors: model.colors.menu, tailX: placed.tailX, tailOnTop: placed.below)
            panel.contentView = next
            self.chrome = next
            self.placement = (placement.rect, placement.opened, placed.below)
            // Replacing the content view drops the hosted buttons' focus.
            panel.makeFirstResponder(host.view)
        }
        panel.setFrame(placed.frame, display: true)
        self.chrome?.needsDisplay = true
    }

    ///
    /// detached window of its own, so AppKit's applies: the card leaves its
    /// button, loses its tail, stops closing on outside clicks, resizes and
    /// deactivation, and moves on its own until closed. Escape, the window
    /// closing and the owner's dismissals still close it.
    private func detach(dragging press: NSEvent) {
        guard let panel, let chrome, !closing, !isDetached else { return }
        isDetached = true
        stopPicker()
        transientObservers.forEach(NotificationCenter.default.removeObserver)
        transientObservers.removeAll()
        anchorWindow?.removeChildWindow(panel)
        var frame = panel.frame
        if !chrome.tailOnTop { frame.origin.y += SidebarPlusMenuPlacement.tailHeight }
        frame.size.height -= SidebarPlusMenuPlacement.tailHeight
        card.removeFromSuperview()
        card.frame = NSRect(origin: .zero, size: frame.size)
        card.autoresizingMask = [.width, .height]
        panel.contentView = card
        self.chrome = nil
        panel.setFrame(frame, display: true)
        panel.makeFirstResponder(host.view)
        panel.hasShadow = true
        onDetach?()
        if NSEvent.pressedMouseButtons & 1 != 0 { panel.performDrag(with: press) }
    }

    /// The plus HUD's dismissals: the parent closing, miniaturizing or
    /// beginning a sheet closes at once; a resize or deactivation animates.
    private func observe(_ parent: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification,
                     NSWindow.willBeginSheetNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close(animated: false) }
            })
        }
        for (name, object) in [(NSWindow.didResizeNotification, parent as AnyObject?),
                               (NSApplication.didResignActiveNotification, nil)] {
            transientObservers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
    }

    /// The plus HUD's attemptCloseUponLosingFocus. A window the card itself
    /// opened (a share picker) keeps it; a press on the card's own button is
    /// remembered so that press does not reopen it.
    private func lostFocus() {
        guard let panel, !closing, !isDetached, keptOpen == 0 else { return }
        if let event = NSApp.currentEvent, event.type == .leftMouseDown, let anchor = anchorView, let window = anchor.window,
           event.window === window, anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) {
            Self.closingPresses[ObjectIdentifier(window)] = event.eventNumber
        }
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel, !self.closing, !self.isDetached, self.keptOpen == 0,
                  !Self.holdsKey(panel) else { return }
            self.close()
        }
    }

    private static func isMouse(_ event: NSEvent) -> Bool {
        [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(event.type)
    }

    ///
    /// right/down/E go forward; Return or Command release selects. Keypad
    /// Enter is not Return. Other key-downs cancel and are consumed.
    enum PickerInput: Equatable {
        case previous, next, select, cancel
        static func resolve(type: NSEvent.EventType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Self {
            guard modifiers.contains(.command) else { return .select }
            guard type == .keyDown else { return .cancel }
            switch keyCode {
            case 123, 126: return .previous
            case 124, 125, 14: return .next
            case 36: return .select
            default: return .cancel
            }
        }
    }

    /// Monitors belong to the exact anchor and its card's window, including
    /// the short delayed-show interval. They never consume another window's
    /// input or select after application deactivation.
    private func owns(_ event: NSEvent) -> Bool {
        guard NSApp.isActive, let anchorWindow, anchorView?.window === anchorWindow,
              anchorWindow.attachedSheet == nil else { return false }
        let contentWindow = host.view.window
        let key = NSApp.keyWindow
        guard key === anchorWindow || (contentWindow != nil && key === contentWindow) else { return false }
        // Some flagsChanged events carry no window; the already-validated key
        // owner is authoritative for that modifier transition only.
        return (event.window == nil && event.type == .flagsChanged)
            || event.window === anchorWindow || (contentWindow != nil && event.window === contentWindow)
    }

    func beginPicker() {
        guard isShown, !model.extensions.isEmpty else { return }
        // Re-entry moves selection without installing a second monitor or
        // replacing the gesture's original immutable dispatch leases.
        if pickerMonitor != nil { model.moveFocus(1); return }
        guard let select = preparePickerSelection?() else { return }
        pickerSelection = select
        model.moveFocus(1)
        pickerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard self.isShown, self.owns(event) else { self.stopPicker(); return event }
            switch PickerInput.resolve(type: event.type, keyCode: event.keyCode, modifiers: event.modifierFlags) {
            case .previous: self.model.moveFocus(-1); return nil
            case .next: self.model.moveFocus(1); return nil
            case .select: self.endPicker(select: true); return nil
            case .cancel:
                self.endPicker(select: false)
                return event.type == .keyDown ? nil : event
            }
        }
    }

    private func stopPicker() {
        if let pickerMonitor { NSEvent.removeMonitor(pickerMonitor) }
        pickerMonitor = nil
        pickerSelection = nil
        model.focusedExtension = nil
    }

    private func endPicker(select: Bool) {
        let focused = model.focusedExtension
        let perform = pickerSelection
        stopPicker()
        if select, let focused, model.extensions.contains(where: { $0.id == focused }), let perform {
            perform(focused)
        } else { close() }
    }

    /// A button's rectangle in the hosted view's own coordinates.
    func rect(for button: SiteControlCenterModel.Button) -> (NSRect, NSView)? {
        guard let frame = model.buttonFrames[button] else { return nil }
        let view = host.view
        let y = view.isFlipped ? frame.minY : view.bounds.height - frame.maxY
        return (NSRect(x: frame.minX, y: y, width: frame.width, height: frame.height), view)
    }

    /// The window's dismissal coordinator owns any after-close action.
    /// This controller owns only the presentation: `onClose` as the card
    /// starts closing, with the parent key again, and `onDidClose` once its
    /// window is gone.
    func close() { close(animated: true) }

    private func close(animated: Bool) {
        pendingShow = nil
        guard !closing else { return }
        closing = true
        extensionMenu?.cancel()
        guard let panel else { finish(); return }
        isAwaitingNativeClose = true
        closingLifetime = self
        panel.ignoresMouseEvents = true
        (observers + transientObservers).forEach(NotificationCenter.default.removeObserver)
        observers.removeAll(); transientObservers.removeAll()
        let parent = anchorWindow
        if panel.isKeyWindow, let parent, parent.isVisible, NSApp.isActive { parent.makeKey() }
        finish()
        let remove = { [weak self, weak parent] in
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self?.didClose()
        }
        guard animated, let chrome, panel.isVisible, SidebarPlusMenuMotion.animateClose(chrome, about: chrome.tailTip, completion: remove) else {
            remove()
            return
        }
    }

    private func didClose() {
        panel = nil
        chrome = nil
        isAwaitingNativeClose = false
        let didClose = onDidClose
        onDidClose = nil
        didClose?()
        closingLifetime = nil
    }

    private func finish() {
        stopPicker()
        if let resignActiveObserver { NotificationCenter.default.removeObserver(resignActiveObserver) }
        resignActiveObserver = nil
        anchorView = nil; anchorWindow = nil
        guard let onClose else { return }
        self.onClose = nil
        preparePickerSelection = nil
        model.invalidate()
        onClose()
    }
}
