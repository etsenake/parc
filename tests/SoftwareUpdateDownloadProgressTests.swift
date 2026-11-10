import AppKit

/// Exercises real status controls without a window, web view, updater or network.
@main @MainActor
struct SoftwareUpdateDownloadProgressTests {
    static var checks = 0

    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(value(), message)
    }

    static func main() {
        downloadCounts()
        stableCounter()
        progressTransitions()
        print("SoftwareUpdateDownloadProgressTests: \(checks) checks passed")
    }

    static func downloadCounts() {
        var download = SoftwareUpdateDownloadProgress()
        check(download.display.fraction == nil, "An unknown size cannot report a fraction")
        download.receive(32_768)
        check(download.display.fraction == nil && !download.display.text.contains(" of "),
              "Receiving data before the size must not show a full bar or invent a total")
        download.expect(227_500_000)
        download.receive(202_800_000 - 32_768)
        check(download.receivedLength == 202_800_000, "Chunk lengths accumulate exactly once")
        check(abs(download.display.fraction! - 202.8 / 227.5) < 0.000001,
              "The reported 202.8 of 227.5 MB is an 89 percent bar")
        download.expect(0)
        check(download.expectedLength == 227_500_000 && download.display.fraction! < 1,
              "A repeated unknown size cannot erase the known total or jump to complete")
        download.expect(227_500_000)
        check(download.receivedLength == 202_800_000, "Repeated size callbacks do not reset received bytes")
        download.receive(24_700_000)
        check(download.display.fraction == 1, "Receiving the expected bytes fills the bar")
        download.receive(1_000_000)
        check(download.display.fraction == 1, "An underestimated size never overfills the bar")
        download.expect(250_000_000)
        check(download.display.fraction == Double(download.receivedLength) / 250_000_000,
              "An authoritative size correction keeps the count and fraction consistent")
        download = SoftwareUpdateDownloadProgress()
        check(download.receivedLength == 0 && download.display.fraction == nil, "A new transfer starts fresh")
        download.receive(.max)
        download.receive(1)
        check(download.receivedLength == .max, "Invalid counters cannot wrap back to zero or trap")
    }

    static func stableCounter() {
        let view = SoftwareUpdateStatusView(icon: NSImage(size: NSSize(width: 64, height: 64)))
        var download = SoftwareUpdateDownloadProgress()
        download.expect(227_500_000)
        var fieldFrame: NSRect?
        var barFrame: NSRect?
        var lastFraction = 0.0
        for total: UInt64 in [0, 100_000, 9_900_000, 10_000_000, 11_100_000, 88_800_000,
                              99_900_000, 100_000_000, 111_100_000, 200_000_000, 202_800_000, 227_500_000] {
            download.receive(total - download.receivedLength)
            let display = download.display
            view.show(status: display.text, action: "Cancel", progress: display.fraction,
                      widthTemplate: display.widthTemplate)
            view.layoutSubtreeIfNeeded()
            check(view.status.stringValue == display.text, "The view shows the latest accumulated count")
            check(view.status.alignment == .right, "The count grows to the left of a stationary suffix")
            check(view.progress.doubleValue == display.fraction, "The label and bar use the same snapshot")
            check(view.progress.doubleValue >= lastFraction, "Ordered chunks only move progress forward")
            if let fieldFrame, let barFrame {
                check(view.status.frame == fieldFrame && view.progress.frame == barFrame,
                      "Digit and unit boundaries must not move either control")
            }
            fieldFrame = view.status.frame
            barFrame = view.progress.frame
            lastFraction = view.progress.doubleValue
        }
        check(view.progress.frame.width == 206 && view.progress.frame.minX == 32,
              "The bar keeps the recovered 32-point insets")
        check(view.action.frame.size == NSSize(width: 170, height: 48), "Cancel keeps its existing size")
        let font = view.status.font!
        let widths = (0...9).map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
        check(widths.allSatisfy { abs($0 - widths[0]) < 0.001 }, "All counter digits have the same advance")
        func textWidth(_ count: UInt64) -> CGFloat {
            var progress = SoftwareUpdateDownloadProgress()
            progress.expect(227_500_000)
            progress.receive(count)
            return (progress.display.text as NSString).size(withAttributes: [.font: font]).width
        }
        check(textWidth(200_000_000) == textWidth(202_800_000),
              "Whole MB values keep their fractional zero so the label does not wobble")
        check(textWidth(11_100_000) == textWidth(88_800_000), "Changing digits leaves the text width unchanged")
    }

    static func progressTransitions() {
        let indicator = TrackedProgressIndicator()
        let view = SoftwareUpdateStatusView(icon: NSImage(size: NSSize(width: 64, height: 64)), progress: indicator)
        view.show(status: "Downloading...", action: "Cancel", progress: nil)
        view.show(status: "Downloading...", action: "Cancel", progress: nil)
        check(indicator.starts == 1, "An unknown size starts its animation only once")
        indicator.modeWrites = 0
        indicator.stops = 0
        view.show(status: "Downloading", action: "Cancel", progress: 0)
        // AppKit can stop internally while changing mode. Once determinate,
        // advancing the value must not issue any further stop or mode writes.
        let transitionStops = indicator.stops
        for value in [0.1, 0.4, 202.8 / 227.5, 1.0] {
            view.show(status: "Downloading", action: "Cancel", progress: value)
            check(!indicator.isIndeterminate && indicator.doubleValue == value, "Progress remains determinate and accurate")
        }
        check(indicator.stops == transitionStops && indicator.modeWrites == 1,
              "A determinate download must not stop or reset its animation mode on each chunk")
        view.show(status: "Preparing…", action: "Cancel", progress: nil, enabled: false)
        check(indicator.isIndeterminate && indicator.starts == 2 && !view.action.isEnabled,
              "Preparing starts a separate indeterminate stage with Cancel disabled")
        view.show(status: "Preparing…", action: "Cancel", progress: 0.2, enabled: false)
        check(indicator.doubleValue == 0.2 && !indicator.isIndeterminate,
              "Extraction starts its own measured progress, not the download's full bar")
        view.show(status: "Ready to Install", action: "Install and Relaunch", progress: 1)
        check(indicator.doubleValue == 1 && view.action.isEnabled, "Ready fills the bar and enables installation")
    }
}

@MainActor private final class TrackedProgressIndicator: NSProgressIndicator {
    var starts = 0
    var stops = 0
    var modeWrites = 0
    override var isIndeterminate: Bool {
        get { super.isIndeterminate }
        set { modeWrites += 1; super.isIndeterminate = newValue }
    }
    override func startAnimation(_ sender: Any?) { starts += 1; super.startAnimation(sender) }
    override func stopAnimation(_ sender: Any?) { stops += 1; super.stopAnimation(sender) }
}
