import AppKit

extension EaselCanvasView {
    func textMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard context.target != .canvas else { return [] }
        let holders = context.items.filter { $0.kind.holdsText }
        guard !holders.isEmpty else { return [] }
        let targets = Set(context.items.map(\.id))
        weak let owner = self
        let act: (@escaping (EaselCanvasView) -> Void) -> () -> Void = { action in
            {
                guard let canvas = owner else { return }
                let present = targets.intersection(Set(canvas.session.document.items.map(\.id)))
                guard !present.isEmpty else { return }
                if canvas.selection != present { canvas.selection = present }
                action(canvas)
            }
        }
        var rows: [EaselMenuRow] = []
        if context.items.count == 1, let item = context.items.first, EaselObjectLink.canLink(item) {
            let link = EaselObjectLink.link(of: item)
            rows.append(EaselMenuRow(id: "text.link", title: link == nil ? TextFormatCommand.addLinkTitle : TextFormatCommand.editLinkTitle,
                                     symbol: "link", shortcut: "⌘K", isEnabled: !item.isLocked, separatorBefore: true,
                                     perform: act { _ = $0.editObjectLink() }))
            if let link {
                rows.append(EaselMenuRow(id: "text.link.open", title: "Open Link", symbol: "arrow.up.forward.square",
                                         perform: act { $0.onOpenURL?(link) }))
                rows.append(EaselMenuRow(id: "text.link.remove", title: "Remove Link", symbol: "minus.circle", isEnabled: !item.isLocked,
                                         perform: act { _ = $0.removeObjectLink() }))
            }
        }
        let current = EaselTextSizing.sharedAlignment(holders)
        rows.append(EaselMenuRow(id: "text.align", title: "Align Text", symbol: Self.alignmentSymbol(current ?? .left),
                                 isEnabled: EaselTextSizing.canAlign(holders), separatorBefore: rows.isEmpty,
                                 children: EaselTextStyle.Alignment.allCases.map { alignment in
            EaselMenuRow(id: "text.align." + alignment.rawValue, title: alignment.title, symbol: Self.alignmentSymbol(alignment),
                         shortcut: alignment.shortcut, isChecked: alignment == current, perform: act { _ = $0.alignText(alignment) })
        }))
        let dark = NoteTheme.isDark(effectiveAppearance)
        rows.append(EaselMenuRow(id: "text.color", title: "Text Color", symbol: "paintpalette", isEnabled: EaselTextSizing.canAlign(holders),
                                 children: EaselPalette.colors(for: .ink).compactMap { color in
            guard let hex = EaselPalette.hex(color, role: .ink) else { return nil }
            return EaselMenuRow(id: "text.color." + color.id, title: color.title(dark: dark), perform: act { _ = $0.applyTextColor(hex) })
        }))
        if fixedCanvasSize == nil, holders.contains(where: { $0.kind == .text && !$0.isLocked && !EaselTextSizing.isAutoWidth($0) }) {
            rows.append(EaselMenuRow(id: "text.autoWidth", title: "Auto Width", symbol: "arrow.left.and.right",
                                     perform: act { _ = $0.restoreTextAutoWidth() }))
        }
        return rows
    }

    @discardableResult
    func applyTextColor(_ hex: String) -> Bool {
        guard !session.isClosed, !session.isDeleted, EaselPalette.normalized(hex) != nil else { return false }
        if let editor {
            guard editor.isEditable, !editor.hasMarkedText() else { return false }
            editor.applyTextColor(EaselInk.color(hex, adaptive: adaptsInk))
            refreshTextControls()
            return true
        }
        let original = session.document
        guard let next = EaselTextColor.recolouring(original, ids: selection, hex: hex, runs: { item, color in
            try? EaselRichTextCodec.snapshot(EaselRichTextCodec.attributed(item.text, richText: nil, style: item.resolvedTextStyle, color: color))
        }) else { return false }
        return commit("Text color") { document in
            guard document == original else { return }
            document = next
        }
    }

    static func alignmentSymbol(_ alignment: EaselTextStyle.Alignment) -> String {
        switch alignment {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
}
