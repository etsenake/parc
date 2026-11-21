import AppKit
import SwiftUI

@MainActor
final class RecentTabSwitcherView: NSView {
    struct Template: Equatable {
        let image: NSImage
        let title: String?
    }
    struct Component: Identifiable, Equatable {
        let id: UUID
        let title: String
        var image: NSImage? = nil
        var template: Template? = nil
        var favicon: NSImage? = nil
        var isRecordingMedia = false
    }
    struct CustomInfo: Equatable {
        let icon: NSImage?
        let title: String
    }
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let spaceName: String
        let vertical: Bool
        var components: [Component]
        var customInfo: CustomInfo? = nil
        var overlay: Component? = nil
        var isHidden = false
        var slotSizes: [Int]? = nil
        var slots: [[Component]]? {
            guard let slotSizes, slotSizes.count > 1, slotSizes.allSatisfy({ $0 > 0 }),
                  slotSizes.contains(where: { $0 > 1 }), slotSizes.reduce(0, +) == components.count else { return nil }
            var start = 0
            return slotSizes.map { size in
                defer { start += size }
                return Array(components[start..<start + size])
            }
        }
    }
    enum Metrics {
        static let height: CGFloat = 190
        static let rowPadding: CGFloat = 16
        static let cardHeight = height - rowPadding * 2
        static let cardWidth = cardHeight * 1.15
        static let shadow = NSEdgeInsets(top: 120, left: 144, bottom: 168, right: 144)
        static func contentWidth(_ count: Int) -> CGFloat { CGFloat(count) * cardWidth + rowPadding * 2 }
    }
    var canInteract: (() -> Bool)?
    var onHover: ((Int) -> Void)?
    var onChoose: ((Int) -> Void)?
    var onVisibleItemsChanged: (() -> Void)?
    private let catalog = RecentSwitcherCatalog()
    private let focusState = RecentSwitcherFocus()
    private var host: RecentSwitcherHost!
    private var generation = UUID()
    private var retired = false
    private let schedulePublication: (DispatchWorkItem) -> Void
    private var publication: DispatchWorkItem?
    private var workspaceObserver: NSObjectProtocol?
    private(set) var itemFrames: [String: CGRect] = [:]
    private(set) var visibleItemIndexes: Set<Int> = []
    var focusedID: String? { focusState.focusedID }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override convenience init(frame: NSRect) {
        self.init(frame: frame, schedulePublication: { DispatchQueue.main.async(execute: $0) })
    }

    init(frame: NSRect, schedulePublication: @escaping (DispatchWorkItem) -> Void) {
        self.schedulePublication = schedulePublication
        super.init(frame: frame)
        catalog.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        host = RecentSwitcherHost(rootView: RecentSwitcherContent(catalog: catalog, focus: focusState,
            hover: { [weak self] id in self?.hover(id) },
            choose: { [weak self] id in self?.choose(id) },
            frames: { [weak self] frames in self?.publish(frames: frames) }))
        host.frame = bounds; host.autoresizingMask = [.width, .height]
        addSubview(host)
        setAccessibilityRole(.group); setAccessibilityLabel("Recent Items")
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.retired else { return }
                    let next = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    if self.catalog.reduceMotion != next { self.catalog.reduceMotion = next }
                }
            }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        publication?.cancel()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }
    static func panelFrame(itemCount: Int, parent: NSRect, screen: NSRect) -> NSRect {
        let width = min(Metrics.contentWidth(itemCount), max(1, min(parent.width, screen.width) - 80))
        let content = NSRect(x: max(screen.minX + 40, min(parent.midX - width / 2, screen.maxX - width - 40)),
                             y: max(screen.minY + 40, min(parent.midY - Metrics.height / 2, screen.maxY - Metrics.height - 40)),
                             width: width, height: Metrics.height)
        return NSRect(x: content.minX - Metrics.shadow.left, y: content.minY - Metrics.shadow.bottom,
                      width: width + Metrics.shadow.left + Metrics.shadow.right,
                      height: Metrics.height + Metrics.shadow.top + Metrics.shadow.bottom)
    }
    var contentRect: NSRect {
        NSRect(x: Metrics.shadow.left, y: Metrics.shadow.top,
               width: max(0, bounds.width - Metrics.shadow.left - Metrics.shadow.right), height: Metrics.height)
    }
    func configure(isDark: Bool, focus: NSColor, hover: NSColor, maxContrast: NSColor, cutout: NSColor) {
        guard !retired else { return }
        let focusColor = isDark ? hover : focus
        if catalog.isDark != isDark { catalog.isDark = isDark }
        if catalog.focusColor != focusColor { catalog.focusColor = focusColor }
        if catalog.maxContrastColor != maxContrast { catalog.maxContrastColor = maxContrast }
        if catalog.cutoutColor != cutout { catalog.cutoutColor = cutout }
    }
    func setItems(_ items: [Item], focused: Int) {
        guard !retired else { return }
        let old = catalog.items.flatMap { $0.components + ($0.overlay.map { [$0] } ?? []) }
        let images = Dictionary(old.map { ($0.id, $0.image) }, uniquingKeysWith: { first, _ in first })
        let favicons = Dictionary(old.map { ($0.id, $0.favicon) }, uniquingKeysWith: { first, _ in first })
        func carry(_ component: Component) -> Component {
            var result = component
            if result.image == nil { result.image = images[component.id] ?? nil }
            if result.favicon == nil { result.favicon = favicons[component.id] ?? nil }
            return result
        }
        let next = items.map { item -> Item in
            var result = item
            result.components = item.components.map(carry)
            result.overlay = item.overlay.map(carry)
            return result
        }
        if catalog.items != next { catalog.items = next }
        focus(focused)
    }
    func focus(_ index: Int) {
        guard !retired else { return }
        let id = catalog.items.indices.contains(index) && !catalog.items[index].isHidden ? catalog.items[index].id : nil
        if focusState.focusedID != id { focusState.focusedID = id }
    }
    func updatePreview(_ image: NSImage?, component: UUID) {
        update(component) { $0.image = image }
    }
    func updateFavicon(_ image: NSImage?, component: UUID) {
        update(component) { $0.favicon = image }
    }
    private func update(_ component: UUID, _ change: (inout Component) -> Void) {
        guard !retired else { return }
        var items = catalog.items
        for item in items.indices {
            if let index = items[item].components.firstIndex(where: { $0.id == component }) {
                var next = items[item].components[index]
                change(&next)
                guard next != items[item].components[index] else { return }
                items[item].components[index] = next
                catalog.items = items
                return
            }
            if items[item].overlay?.id == component {
                var next = items[item].overlay!
                change(&next)
                guard next != items[item].overlay else { return }
                items[item].overlay = next
                catalog.items = items
                return
            }
        }
    }
    private var available: Bool {
        guard !retired, let window, window.isVisible, !isHiddenOrHasHiddenAncestor else { return false }
        return canInteract?() == true
    }
    private func index(_ id: String) -> Int? { catalog.items.firstIndex { $0.id == id && !$0.isHidden } }
    func hover(_ id: String) {
        guard available, let index = index(id) else { return }
        onHover?(index)
    }
    func choose(_ id: String) {
        guard available, let index = index(id) else { return }
        onChoose?(index)
    }
    func publish(frames: [String: CGRect]) {
        publication?.cancel()
        let token = generation
        let work = DispatchWorkItem { [weak self, weak originalWindow = window] in
            guard let self, !self.retired, self.generation == token,
                  let originalWindow, self.window === originalWindow else { return }
            let ids = Set(self.catalog.items.map(\.id))
            let nextFrames = frames.filter { ids.contains($0.key) }
            if self.itemFrames != nextFrames { self.itemFrames = nextFrames }
            let viewport = CGRect(origin: .zero, size: self.contentRect.size)
            let visible = Set(self.catalog.items.indices.filter { index in
                !self.catalog.items[index].isHidden
                    && self.itemFrames[self.catalog.items[index].id]?.intersects(viewport) == true
            })
            if visible != self.visibleItemIndexes {
                self.visibleItemIndexes = visible
                self.onVisibleItemsChanged?()
            }
        }
        publication = work
        schedulePublication(work)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { generation = UUID(); publication?.cancel(); publication = nil }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidHide() {
        super.viewDidHide(); generation = UUID(); publication?.cancel(); publication = nil
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        guard available, contentRect.contains(local) else { return nil }
        return super.hitTest(point)
    }
    func retire() {
        retired = true; generation = UUID(); publication?.cancel(); publication = nil
        canInteract = nil; onHover = nil; onChoose = nil; onVisibleItemsChanged = nil
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
    }
}

@MainActor private final class RecentSwitcherCatalog: ObservableObject {
    @Published var items: [RecentTabSwitcherView.Item] = []
    @Published var isDark = false
    @Published var focusColor = NSColor.clear
    @Published var maxContrastColor = NSColor.black
    @Published var cutoutColor = NSColor.white
    @Published var reduceMotion = false
}

@MainActor private final class RecentSwitcherFocus: ObservableObject {
    @Published var focusedID: String?
}

@MainActor private final class RecentSwitcherHost: NSHostingView<RecentSwitcherContent> {
    override var acceptsFirstResponder: Bool { false }
}

private struct RecentSwitcherFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct RecentSwitcherContent: View {
    @ObservedObject var catalog: RecentSwitcherCatalog
    let focus: RecentSwitcherFocus
    let hover: (String) -> Void
    let choose: (String) -> Void
    let frames: ([String: CGRect]) -> Void
    private var shadow: Color {
        Color(.displayP3, red: 0.082, green: 0.110, blue: 0.196, opacity: catalog.isDark ? 0.8 : 0.3)
    }
    var body: some View {
        ScrollViewReader { proxy in
            RecentSwitcherRow(catalog: catalog, focus: focus, hover: hover, choose: choose, frames: frames)
                .background {
                    RecentSwitcherScrollBridge(focus: focus, reduceMotion: catalog.reduceMotion, proxy: proxy)
                }
        }
        .frame(height: 190)
        .background(RecentSwitcherMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: shadow, radius: 48, x: 0, y: -24)
        .padding(.init(top: 120, leading: 144, bottom: 168, trailing: 144))
        .environment(\.colorScheme, catalog.isDark ? .dark : .light)
        .transaction { if catalog.reduceMotion { $0.animation = nil } }
    }
}

private struct RecentSwitcherScrollBridge: View {
    @ObservedObject var focus: RecentSwitcherFocus
    let reduceMotion: Bool
    let proxy: ScrollViewProxy
    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onChange(of: focus.focusedID) { id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear { if let id = focus.focusedID { proxy.scrollTo(id) } }
    }
}

private struct RecentSwitcherRow: View {
    @ObservedObject var catalog: RecentSwitcherCatalog
    let focus: RecentSwitcherFocus
    let hover: (String) -> Void
    let choose: (String) -> Void
    let frames: ([String: CGRect]) -> Void
    @State private var cardFrames: [String: CGRect] = [:]
    private let viewportSpace = "recent-switcher-viewport"
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(catalog.items.enumerated()), id: \.element.id) { index, item in
                    RecentSwitcherCard(item: item, focus: focus,
                                       isDark: catalog.isDark, reduceMotion: catalog.reduceMotion,
                                       maxContrast: catalog.maxContrastColor, cutout: catalog.cutoutColor)
                        .opacity(item.isHidden ? 0 : 1)
                        .animation(catalog.reduceMotion ? nil : .spring(response: 0.15, dampingFraction: 0.95, blendDuration: 0), value: item.isHidden)
                        .frame(width: RecentTabSwitcherView.Metrics.cardWidth,
                               height: RecentTabSwitcherView.Metrics.cardHeight)
                        .contentShape(Rectangle())
                        .onHover { inside in if inside { hover(item.id) } }
                        .onTapGesture { choose(item.id) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(item.title)
                        .accessibilityHint(item.spaceName)
                        .modifier(RecentSwitcherSelectionValue(focus: focus, id: item.id))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { choose(item.id) }
                        .accessibilityHidden(item.isHidden)
                        .allowsHitTesting(!item.isHidden)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: RecentSwitcherFrames.self,
                                value: [item.id: geometry.frame(in: .named(viewportSpace))])
                        })
                        .id(item.id)
                        .animation(catalog.reduceMotion ? nil : .spring(response: 0.15, dampingFraction: 0.95, blendDuration: 0), value: index)
                }
            }
            .background(alignment: .topLeading) {
                RecentSwitcherFocusFill(focus: focus, isDark: catalog.isDark,
                                        color: catalog.focusColor, frames: cardFrames)
            }
            .padding(16)
        }
        .coordinateSpace(name: viewportSpace)
        .onPreferenceChange(RecentSwitcherFrames.self) { value in
            let next: [String: CGRect]
            if let first = catalog.items.first, let origin = value[first.id]?.minX {
                next = value.mapValues { $0.offsetBy(dx: -origin, dy: 0) }
            } else {
                next = [:]
            }
            if next != cardFrames { cardFrames = next }
            frames(value)
        }
    }
}

private struct RecentSwitcherFocusFill: View {
    @ObservedObject var focus: RecentSwitcherFocus
    let isDark: Bool
    let color: NSColor
    let frames: [String: CGRect]
    var body: some View {
        if let id = focus.focusedID, let rect = frames[id] {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: color).opacity(isDark ? 1 : 0.5))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: 0)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

private struct RecentSwitcherSelectionValue: ViewModifier {
    @ObservedObject var focus: RecentSwitcherFocus
    let id: String
    func body(content: Content) -> some View {
        content.accessibilityValue(focus.focusedID == id ? "Selected" : "")
    }
}

private struct RecentSwitcherMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover; view.state = .followsWindowActiveState
        view.blendingMode = .withinWindow; view.isEmphasized = false
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private enum RecentSwitcherColors {
    static func gray1(_ dark: Bool) -> Color { gray(dark ? 0.085 : 0.99) }
    static func gray2(_ dark: Bool) -> Color { gray(dark ? 0.11 : 0.973) }
    static func backing(_ dark: Bool) -> Color { gray(dark ? 0 : 1) }
    static func secondary(_ dark: Bool) -> Color { Color(.sRGB, white: dark ? 1 : 0, opacity: 0.5) }
    private static func gray(_ white: Double) -> Color { Color(.sRGB, white: white, opacity: 1) }
}

private struct RecentSwitcherCard: View {
    let item: RecentTabSwitcherView.Item
    let focus: RecentSwitcherFocus
    let isDark: Bool
    let reduceMotion: Bool
    let maxContrast: NSColor
    let cutout: NSColor
    var body: some View {
        VStack(spacing: 12) {
            preview
                .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 2)
                .shadow(color: .black.opacity(0.2), radius: 9, x: 0, y: 2)
            RecentSwitcherCaption(item: item, focus: focus, isDark: isDark,
                                  maxContrast: maxContrast, cutout: cutout)
        }
        .padding(12)
    }

    private var preview: some View {
        ZStack {
            components
            if let overlay = item.overlay {
                RecentSwitcherSnapshot(component: overlay, cornerRadius: 4, stroke: false,
                                       isDark: isDark, maxContrast: maxContrast)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            }
        }
    }
    private var components: some View {
        let single = item.components.count == 1
        let inset = !single || (item.components.first.map { $0.image == nil && $0.template != nil } ?? false)
        let radius: CGFloat = inset ? 4 : 6
        return Group {
            if let slots = item.slots {
                if item.vertical {
                    VStack(spacing: 4) {
                        ForEach(slots.indices, id: \.self) { slot in HStack(spacing: 4) { panes(slots[slot], radius: radius) } }
                    }
                } else {
                    HStack(spacing: 4) {
                        ForEach(slots.indices, id: \.self) { slot in VStack(spacing: 4) { panes(slots[slot], radius: radius) } }
                    }
                }
            } else if item.vertical {
                VStack(spacing: 4) { panes(item.components, radius: radius) }
            } else {
                HStack(spacing: 4) { panes(item.components, radius: radius) }
            }
        }
        .padding(inset ? 4 : 0)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(RecentSwitcherColors.gray1(isDark)))
    }
    private func panes(_ components: [RecentTabSwitcherView.Component], radius: CGFloat) -> some View {
        let single = item.components.count == 1
        return ForEach(components) { component in
            RecentSwitcherSnapshot(component: component, cornerRadius: radius, stroke: single,
                                   isDark: isDark, maxContrast: maxContrast)
                .overlay(item.overlay == nil ? Color.clear : Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(RecentSwitcherColors.backing(isDark)))
                .shadow(color: single ? .clear : .black.opacity(0.3), radius: 1, x: 0, y: 0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if component.isRecordingMedia {
                        RecentSwitcherRecordingDot(reduceMotion: reduceMotion).offset(x: -6, y: -6)
                    }
                }
        }
    }

}

private struct RecentSwitcherCaption: View {
    let item: RecentTabSwitcherView.Item
    @ObservedObject var focus: RecentSwitcherFocus
    let isDark: Bool
    let maxContrast: NSColor
    let cutout: NSColor
    private var selected: Bool { focus.focusedID == item.id }
    private var captionColor: Color { isDark ? .white : .black.opacity(selected ? 1 : 0.7) }
    var body: some View {
        if let info = item.customInfo {
            HStack(spacing: 8) {
                if let icon = info.icon {
                    captionIcon(icon)
                } else {
                    Text("\(item.components.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(nsColor: maxContrast))
                        .frame(minWidth: 16, minHeight: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(nsColor: cutout)))
                }
                title(info.title)
            }
            .padding(.horizontal, 2)
        } else if item.components.count == 1, let component = item.components.first {
            HStack(spacing: 8) {
                favicon(component)
                title(component.title)
            }
            .padding(.horizontal, 2)
        } else {
            HStack(spacing: 4) {
                ForEach(item.components) { component in
                    favicon(component).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    private func favicon(_ component: RecentTabSwitcherView.Component) -> some View {
        captionIcon(component.favicon ?? RecentSwitcherArtwork.fallbackFavicon)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
    private func captionIcon(_ image: NSImage) -> some View {
        Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original)
            .resizable().aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .foregroundColor(RecentSwitcherColors.secondary(isDark))
    }
    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(captionColor).lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentSwitcherSnapshot: View {
    let component: RecentTabSwitcherView.Component
    let cornerRadius: CGFloat
    let stroke: Bool
    let isDark: Bool
    let maxContrast: NSColor
    var body: some View {
        if let image = component.image {
            GeometryReader { geometry in
                Image(nsImage: image).interpolation(.high).antialiased(true)
                    .resizable()
                    .frame(width: geometry.size.width, alignment: .topLeading)
            }
        } else if let template = component.template {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: maxContrast).opacity(0.05))
                Image(nsImage: template.image).renderingMode(.template).resizable()
                    .foregroundColor(Color(nsColor: maxContrast))
                if let title = template.title {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2).multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5).truncationMode(.tail)
                        .foregroundColor(Color(nsColor: maxContrast))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay {
                if stroke {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: maxContrast).opacity(0.1), lineWidth: 2)
                }
            }
        } else {
            RecentSwitcherColors.gray2(isDark)
        }
    }
}

private struct RecentSwitcherRecordingDot: View {
    let reduceMotion: Bool
    @State private var dim = false
    var body: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 20, height: 20)
            Circle().fill(Color(nsColor: .red)).frame(width: 14, height: 14)
                .opacity(dim ? 0.4 : 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
        .allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { updatePulse() }
        .onChange(of: reduceMotion) { _ in updatePulse() }
        .onDisappear { dim = false }
    }
    private func updatePulse() {
        withAnimation(nil) { dim = false }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { dim = true }
    }
}

@MainActor enum RecentSwitcherArtwork {
    static let directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("RecentSwitcher", isDirectory: true)
    private static var cache: [String: NSImage] = [:]
    static var note: NSImage? { template("NotePreviewThumbnail") }
    static var easel: NSImage? { template("EaselPreviewThumbnail") }
    static var incognito: NSImage? { template("IncognitoTabPreviewThumbnail") }
    private static func template(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let url = directory?.appendingPathComponent(name + ".pdf"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[name] = image
        return image
    }
    static let fallbackFavicon: NSImage = {
        let image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        return image
    }()
}
