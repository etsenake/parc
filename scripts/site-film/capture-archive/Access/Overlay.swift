extension PageCaptureOverlay {
    var harnessPicture: NSImageView { picture }
    var harnessSelection: NSRect? { selection }
    var harnessActionTitles: [String] { palette.rows.map(\.title) }
    var harnessPaletteFrame: NSRect { palette.card.frame }
    func harnessRowFrame(_ index: Int) -> NSRect {
        guard palette.rows.indices.contains(index), let row = palette.view.list.rowFrame(forItemID: palette.rows[index].id) else { return .zero }
        return convert(row, from: palette.view.list)
    }
    func harnessChoose(_ index: Int) { palette.view.list.highlightedIndex = index }
    func harnessGrayscale(_ shown: Bool) { elementLens.harnessGrayscale(shown) }
    func harnessPress(_ index: Int, _ pressed: Bool) { palette.view.list.highlightedIndex = pressed ? index : nil }
}

extension CaptureElementLens {
    func harnessGrayscale(_ shown: Bool) { grayscale.isHidden = !shown }
}

extension PageCaptureOverlay {
    func harnessHover(_ index: Int?) { palette.view.list.highlightedIndex = index }
}

extension PageCaptureOverlay {
    var harnessLensShown: Bool { !elementLens.isHidden && selecting }
}
