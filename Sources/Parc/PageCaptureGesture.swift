import AppKit

@MainActor
protocol CaptureGestureReceiver: AnyObject {
    func handleCaptureGesture(_ recognizer: NSPanGestureRecognizer)
}

extension PageCaptureController: CaptureGestureReceiver {}

@MainActor
final class PageCaptureGesture: NSObject, NSGestureRecognizerDelegate {
    struct Admission {
        let isCurrent: () -> Bool
        let begin: () -> (any CaptureGestureReceiver)?
    }
    private let prepare: (NSPoint) -> Admission?
    private let defaults: UserDefaults
    private var admission: Admission?
    private weak var capture: (any CaptureGestureReceiver)?
    private let pan: NSPanGestureRecognizer

    init(view: NSView, defaults: UserDefaults = .standard, pan: NSPanGestureRecognizer? = nil,
         prepare: @escaping (NSPoint) -> Admission?) {
        self.prepare = prepare; self.defaults = defaults; self.pan = pan ?? NSPanGestureRecognizer()
        super.init()
        self.pan.target = self; self.pan.action = #selector(changed(_:)); self.pan.delegate = self
        view.addGestureRecognizer(self.pan)
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        admission = nil; capture = nil
        guard gestureRecognizer === pan, event.type == .leftMouseDown,
              event.window === pan.view?.window,
              CaptureGesturePreference.permits(event.modifierFlags),
              CaptureGesturePreference.isEnabled(defaults: defaults) else { return false }
        admission = prepare(event.locationInWindow)
        return admission != nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        gestureRecognizer === pan && CaptureGesturePreference.isEnabled(defaults: defaults) && admission?.isCurrent() == true
    }

    @objc private func changed(_ recognizer: NSPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard CaptureGesturePreference.isEnabled(defaults: defaults), admission?.isCurrent() == true else { return }
            capture = admission?.begin(); admission = nil
            capture?.handleCaptureGesture(recognizer)
        case .changed: capture?.handleCaptureGesture(recognizer)
        case .ended, .cancelled, .failed:
            capture?.handleCaptureGesture(recognizer)
            capture = nil; admission = nil
        default: break
        }
    }
}
