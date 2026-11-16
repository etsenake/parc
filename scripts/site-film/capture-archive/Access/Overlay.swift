extension PageCaptureOverlay {
    var harnessPicture: NSImageView { picture }
    var harnessSelection: NSRect? { selection }
    var harnessActionTitles: [String] { buttons.map(\.title) }
    var harnessPaletteFrame: NSRect { palette.frame }
    func harnessRowFrame(_ index: Int) -> NSRect { convert(buttons[index].bounds, from: buttons[index]) }
    func harnessChoose(_ index: Int) { selectedAction = index; updateSelectedAction() }
    func harnessGrayscale(_ shown: Bool) { elementLens.harnessGrayscale(shown) }
    func harnessPress(_ index: Int, _ pressed: Bool) { buttons[index].harnessPressed(pressed) }
}

extension CaptureElementLens {
    func harnessGrayscale(_ shown: Bool) { grayscale.isHidden = !shown }
}

extension CaptureActionButton {
    func harnessPressed(_ value: Bool) { pressed = value; needsDisplay = true }
}

extension PageCaptureOverlay {
    func harnessHover(_ index: Int?) { for (i, button) in buttons.enumerated() { button.harnessHovered(i == index) } }
}

extension CaptureActionButton {
    func harnessHovered(_ value: Bool) { if hovered != value { hovered = value; needsDisplay = true } }
}

extension PageCaptureOverlay {
    var harnessLensShown: Bool { !elementLens.isHidden && selecting }
}
