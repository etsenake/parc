import AppKit
import QuartzCore
import SwiftUI

@MainActor protocol DisplayFrameDriving: AnyObject {
    var isRunning: Bool { get }
    func start(in view: NSView, onFrame: @escaping () -> Bool)
    func stop()
}

@MainActor final class ViewDisplayFrameDriver: NSObject, DisplayFrameDriving {
    private var onFrame: (() -> Bool)?
    private var link: AnyObject?
    private var timer: Timer?
    var isRunning: Bool { link != nil || timer != nil }
    func start(in view: NSView, onFrame: @escaping () -> Bool) {
        guard !isRunning else { return }
        self.onFrame = onFrame
        if #available(macOS 14.0, *) {
            let link = view.displayLink(target: self, selector: #selector(displayFrame(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.timerFrame() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
    func stop() {
        if #available(macOS 14.0, *) { (link as? CADisplayLink)?.invalidate() }
        link = nil; timer?.invalidate(); timer = nil; onFrame = nil
    }
    @available(macOS 14.0, *)
    @objc private func displayFrame(_: CADisplayLink) {
        if onFrame?() != true { stop() }
    }
    private func timerFrame() {
        if onFrame?() != true { stop() }
    }
}
