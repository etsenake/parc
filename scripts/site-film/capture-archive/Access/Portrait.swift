extension PortraitCaptureView {
    func harnessFraction(_ value: Double) {
        slider.doubleValue = value
        options.background = .color; options.fraction = value
        refresh()
    }
    var harnessPreview: NSImageView { preview }
    var harnessMaterial: NSView { material }
    var harnessSlider: NSSlider { slider }
}
