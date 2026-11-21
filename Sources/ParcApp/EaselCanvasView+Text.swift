import AppKit

extension EaselCanvasView {
    func textMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard context.target != .canvas else { return [] }
        let holders = context.items.filter { $0.kind.holdsText }
        guard !holders.isEmpty else { return [] }
        var rows: [EaselMenuRow] = []
        if context.items.count == 1, let item = context.items.first, EaselObjectLink.canLink(item) {
            let link = EaselObjectLink.link(of: item)
            rows.append(EaselMenuRow(id: "text.link", title: link == nil ? TextFormatCommand.addLinkTitle : TextFormatCommand.editLinkTitle,
                                     symbol: "link", shortcut: "⌘K", isEnabled: !item.isLocked, separatorBefore: true) { [weak self] in
                _ = self?.editObjectLink()
            })
            if let link {
                rows.append(EaselMenuRow(id: "text.link.open", title: "Open Link", symbol: "arrow.up.forward.square") { [weak self] in
                    self?.onOpenURL?(link)
                })
                rows.append(EaselMenuRow(id: "text.link.remove", title: "Remove Link", symbol: "minus.circle", isEnabled: !item.isLocked) { [weak self] in
                    _ = self?.removeObjectLink()
                })
            }
        }
        let current = EaselTextSizing.sharedAlignment(holders)
        rows.append(EaselMenuRow(id: "text.align", title: "Align Text", symbol: Self.alignmentSymbol(current ?? .left),
                                 isEnabled: EaselTextSizing.canAlign(holders), separatorBefore: rows.isEmpty,
                                 children: EaselTextStyle.Alignment.allCases.map { alignment in
            EaselMenuRow(id: "text.align." + alignment.rawValue, title: alignment.title, symbol: Self.alignmentSymbol(alignment),
                         shortcut: alignment.shortcut, isChecked: alignment == current) { [weak self] in
                _ = self?.alignText(alignment)
            }
        }))
        if holders.contains(where: { $0.kind == .text && !$0.isLocked && !EaselTextSizing.isAutoWidth($0) }) {
            rows.append(EaselMenuRow(id: "text.autoWidth", title: "Auto Width", symbol: "arrow.left.and.right") { [weak self] in
                _ = self?.restoreTextAutoWidth()
            })
        }
        return rows
    }

    static func alignmentSymbol(_ alignment: EaselTextStyle.Alignment) -> String {
        switch alignment {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
}
