import AppKit
import SwiftUI

@MainActor
final class ShortcutKeycapView: NSView {
    enum Size { case small, large }
    enum Presentation { case binding, unassigned, introduction }
    var presentation: Presentation = .binding { didSet { refresh() } }
    var symbols: [String] = [] { didSet { refresh() } }
    var bindingDescription: String? { didSet { refresh() } }
    var isInConflict = false { didSet { refresh() } }
    var size: Size = .small { didSet { refresh() } }
    var alignment: Alignment = .trailing { didSet { refresh() } }
    private let host = NSHostingView(rootView: KeycapContent(symbols: [], size: .small,
        side: 27, isInConflict: false, alignment: .trailing, presentation: .binding))

    override init(frame: NSRect) {
        super.init(frame: frame)
        host.setAccessibilityElement(false); addSubview(host)
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() { super.layout(); host.frame = bounds; refresh() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }

    static func spacing(count: Int) -> CGFloat {
        switch count { case 2, 3: return 4; case 4, 5: return 3; default: return 0 }
    }
    static func smallWidth(symbols: [String]) -> CGFloat {
        symbols.reduce(0) { $0 + compactWidth($1) } + CGFloat(max(0, symbols.count - 1)) * spacing(count: symbols.count)
    }
    static func compactWidth(_ symbol: String) -> CGFloat {
        let base = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 11) } ?? base
        let width = ceil((symbol as NSString).size(withAttributes: [.font: font]).width)
        return width > 31 ? width + 8 : 27
    }
    static func largeSide(width: CGFloat, count: Int) -> CGFloat {
        min(64, max(0, (width - CGFloat(max(0, count - 1)) * spacing(count: count)) / CGFloat(max(1, count))))
    }
    private var displayedSymbols: [String] {
        presentation == .binding ? symbols : presentation == .unassigned ? ["", ""] : ["⌘", ""]
    }
    var keycapBounds: NSRect {
        let displayed = displayedSymbols, count = displayed.count
        guard count > 0 else { return .zero }
        let side: CGFloat = size == .small ? 27 : Self.largeSide(width: bounds.width, count: count)
        let width = size == .small ? Self.smallWidth(symbols: displayed)
            : side * CGFloat(count) + Self.spacing(count: count) * CGFloat(max(0, count - 1))
        let x = alignment == .leading ? bounds.minX : alignment == .trailing ? bounds.maxX - width : bounds.midX - width / 2
        return NSRect(x: x, y: bounds.midY - side / 2, width: width, height: side)
    }
    private func refresh() {
        let displayed = displayedSymbols
        let side: CGFloat = size == .small ? 27 : Self.largeSide(width: bounds.width, count: displayed.count)
        host.rootView = KeycapContent(symbols: displayed, size: size, side: side,
            isInConflict: isInConflict, alignment: alignment, presentation: presentation)
        setAccessibilityValue(presentation == .introduction ? "Customize keyboard shortcuts" : presentation == .unassigned ? "No shortcut" : bindingDescription ?? (symbols.isEmpty ? "No shortcut" : symbols.joined(separator: " ")))
    }
}

private struct KeycapContent: View {
    let symbols: [String]
    let size: ShortcutKeycapView.Size
    let side: CGFloat
    let isInConflict: Bool
    let alignment: Alignment
    let presentation: ShortcutKeycapView.Presentation
    var body: some View {
        HStack(spacing: ShortcutKeycapView.spacing(count: symbols.count)) {
            if symbols.isEmpty {
                Text("—").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                    KeycapFace(symbol: symbol,
                        compact: size == .small, count: symbols.count, side: side,
                        width: size == .small ? ShortcutKeycapView.compactWidth(symbol) : side,
                        wordKey: symbols.contains(where: { $0.count > 1 }),
                        isInConflict: isInConflict)
                        .overlay {
                            if presentation == .introduction && index == 1 {
                                Color.accentColor.frame(width: 50, height: 50)
                                    .mask(ShortcutSmileyRepresentable())
                            }
                        }
                }
            }
        }
        .opacity(presentation == .unassigned ? 0.3 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .accessibilityHidden(true)
    }
}

private struct KeycapFace: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let compact: Bool
    let count: Int
    let side: CGFloat
    let width: CGFloat
    let wordKey: Bool
    let isInConflict: Bool
    private var accent: Color { isInConflict ? Color(nsColor: .systemRed) : .accentColor }
    private var innerRadius: CGFloat { compact ? 3 : count <= 3 ? 8 : 6 }
    private var outerRadius: CGFloat { compact ? 4 : count <= 3 ? 12 : 8 }
    private var inset: CGFloat { compact ? 1 : count <= 3 ? 4 : count == 4 ? 3 : 2.5 }
    private var bottomInset: CGFloat { compact ? 3.5 : count <= 3 ? 9 : count == 4 ? 6.75 : 5.5 }
    private var fontSize: CGFloat {
        if compact { return wordKey ? 11 : 13 }
        if count <= 3 { return wordKey ? 26 : 32 }
        if count == 4 { return wordKey ? 20 : 26 }
        return wordKey ? 16 : 20
    }
    var body: some View {
        ZStack {
            ZStack {
                accent.opacity(0.85)
                LinearGradient(colors: [.clear, .black.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                    .blendMode(.multiply)
            }
            .clipShape(RoundedRectangle(cornerRadius: outerRadius, style: .continuous))
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .stroke(isInConflict ? accent.opacity(0.85) : accent, lineWidth: 1.5)
            ZStack {
                Color.white.opacity(colorScheme == .dark ? 0.5 : 0.7)
                LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0)], startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                    .stroke(.white.opacity(0.7), lineWidth: 1.5)
                Text(symbol).font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(isInConflict ? accent.opacity(0.8) : accent)
                    .minimumScaleFactor(0.01).lineLimit(1)
            }
            .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
            .padding(EdgeInsets(top: inset, leading: inset, bottom: bottomInset, trailing: inset))
        }
        .frame(width: width, height: side)
    }
}
