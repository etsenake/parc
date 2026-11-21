extension PortraitCaptureView {
    func harnessFraction(_ value: Double) {
        slider.doubleValue = value
        options.background = .color; options.fraction = value
        refresh()
    }
    var harnessSlider: NSSlider { slider }
}
