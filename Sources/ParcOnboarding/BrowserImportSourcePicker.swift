import AppKit
import SwiftUI
import ParcKit

struct BrowserImportSourcePicker: View {
    struct Source: Identifiable {
        let id: String
        let title: String
        let icon: NSImage
        var iconBackground: NSColor = .clear
        let selected: Bool
        let choose: () -> Void
    }
    struct Skip {
        let selected: Bool
        let choose: () -> Void
    }
    let layout: BrowserImportSourceCard.Layout
    let sources: [Source]
    var skip: Skip?
    var enabled = true
    let selectionColor: NSColor
    @Environment(\.colorScheme) private var colorScheme

    private struct Metrics { let rowHeight: CGFloat; let spacing: CGFloat }
    private var metrics: [Metrics] {
        switch layout {
        case .setup: return [.init(rowHeight: 92, spacing: 20), .init(rowHeight: 72, spacing: 14), .init(rowHeight: 56, spacing: 8)]
        case .window: return [.init(rowHeight: 48, spacing: 12), .init(rowHeight: 40, spacing: 8), .init(rowHeight: 34, spacing: 6)]
        }
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(metrics.indices.dropLast(), id: \.self) { stack(metrics[$0]) }
            BrowserImportScaledToFit { stack(metrics[metrics.count - 1]) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout == .setup ? .center : .top)
        .environment(\.colorScheme, layout == .setup ? .light : colorScheme)
        .disabled(!enabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose your previous browser")
    }

    private func stack(_ metrics: Metrics) -> some View {
        VStack(spacing: metrics.spacing) {
            ForEach(sources) { source in
                BrowserImportSourceCard(layout: layout, title: source.title, icon: source.icon,
                    iconBackground: source.iconBackground, selected: source.selected,
                    height: metrics.rowHeight, selectionColor: selectionColor, action: source.choose)
                    .opacity(enabled || source.selected ? 1 : 0.5)
            }
            if let skip {
                BrowserImportSourceCard(layout: layout, title: "No, I want to type in all my passwords again.", icon: nil,
                    uppercased: false, selected: skip.selected, height: metrics.rowHeight,
                    selectionColor: selectionColor, action: skip.choose)
                    .opacity(enabled || skip.selected ? 1 : 0.5)
            }
        }
        .frame(width: layout == .setup ? 278 : nil)
        .padding(.horizontal, layout == .setup ? 24 : 6)
        .padding(.vertical, layout == .setup ? 16 : 4)
        .frame(maxWidth: .infinity)
    }

    static func iconBackground(bundleIdentifier: String?) -> NSColor {
        switch bundleIdentifier {
        case "com.google.Chrome": return NSColor(parcHex: "FFCBB0")
        case "com.brave.Browser": return NSColor(red: 0.95, green: 0.76, blue: 0.09, alpha: 0.3)
        case "com.microsoft.edgemac": return NSColor(parcHex: "D7FFF2")
        case "org.mozilla.firefox": return NSColor(red: 0.99, green: 0.71, blue: 0.9, alpha: 1)
        case "com.operasoftware.Opera": return NSColor(parcHex: "FFE4E7")
        case "com.operasoftware.OperaGX": return NSColor(parcHex: "FECDD8")
        case "com.apple.Safari": return NSColor(red: 0.82, green: 0.87, blue: 1, alpha: 0.3)
        case "com.vivaldi.Vivaldi": return NSColor(parcHex: "FCD7D7")
        case BrowserImportCoordinator.arcBundleIdentifier: return NSColor(parcHex: "E3E6FC")
        default: return .white
        }
    }
}

private struct BrowserImportScaledToFit<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var height: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            content()
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { Color.clear.preference(key: BrowserImportFitHeight.self, value: $0.size.height) })
                .scaleEffect(height > geometry.size.height && height > 0 ? geometry.size.height / height : 1)
                .opacity(height > 0 ? 1 : 0)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onPreferenceChange(BrowserImportFitHeight.self) { height = $0 }
    }
}
private struct BrowserImportFitHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
