import AppKit
import ParcEngine

package enum ParcLaunch {
    @MainActor package static func run() -> Never {
        let application = ParcApplication.shared
        precondition(application is ParcApplication, "NSApplication was created before ParcApplication")
        application.setActivationPolicy(.regular)
        let applicationDelegate = AppDelegate()
        application.delegate = applicationDelegate
        switch applicationDelegate.prepare() {
        case .ready:
            DispatchQueue.main.async { applicationDelegate.openInitialWindow() }
            let result = PCBrowserEngine.run()
            applicationDelegate.finishShutdown()
            exit(result)
        case .exit(let code):
            exit(code)
        }
    }
}
