import AppKit
import ParcCore
import ParcEngine

@MainActor
final class PopupTabHandoffCoordinator {
    private let restoreWaits = WindowRestoreWaits(timeout: 2)

    func request(_ input: String?, from source: BrowserWindowController,
                 windows: @escaping () -> [BrowserWindowController],
                 freshWindow: @escaping () -> BrowserWindowController?) {
        let origin = Origin(source)
        let candidates = windows()
        guard origin.isCurrent(in: candidates) else { return }
        let choice = PopupTabHandoff.choose(sourceIsPrivate: source.isPrivateBrowsing,
            candidates: candidates.indices.map { Self.candidate(candidates[$0], id: $0, for: origin) })
        guard case .existing(let index) = choice, let target = Target(candidates[index]) else {
            Self.openFresh(input, freshWindow); return
        }
        let window = target.window
        _ = WindowOwnerSequence.run(while: {
            let current = windows()
            return origin.isCurrent(in: current) && target.isCurrent(in: current) && window?.attachedSheet == nil
        }, steps: [
            { if window?.isMiniaturized == true { window?.deminiaturize(nil) } },
            { target.controller?.showWindow(nil) },
            { window?.makeKeyAndOrderFront(nil) }
        ])
        arrive(input, origin: origin, target: target, windows: windows, freshWindow: freshWindow, mayAwaitRestore: true)
    }

    private func arrive(_ input: String?, origin: Origin, target: Target,
                        windows: @escaping () -> [BrowserWindowController],
                        freshWindow: @escaping () -> BrowserWindowController?, mayAwaitRestore: Bool) {
        let current = windows()
        let destinationCurrent = target.isCurrent(in: current)
        let restoring = target.window?.isMiniaturized == true && target.window?.attachedSheet == nil
        let admits = destinationCurrent && !restoring && target.binding?.canAdmitHiddenPageTransferDestination == true
        switch PopupTabHandoff.arrival(sourceCurrent: origin.isCurrent(in: current), destinationCurrent: destinationCurrent,
                                       isMinimized: restoring, admitsHidden: admits, mayAwaitRestore: mayAwaitRestore) {
        case .deliver:
            if let destination = target.controller { Self.deliver(input, to: destination) }
        case .awaitRestore:
            guard let window = target.window else { return }
            restoreWaits.wait(for: window) { [weak self] in
                self?.arrive(input, origin: origin, target: target, windows: windows, freshWindow: freshWindow,
                             mayAwaitRestore: false)
            }
        case .freshWindow:
            Self.openFresh(input, freshWindow)
        case .abandon:
            break
        }
    }

    private static func candidate(_ controller: BrowserWindowController, id: Int,
                                  for origin: Origin) -> PopupTabHandoff.Candidate<Int> {
        var candidate = PopupTabHandoff.Candidate(id: id, isPrivate: controller.isPrivateBrowsing,
            sharesSession: origin.store != nil && controller.store === origin.store,
            acceptsTabs: controller.canAcceptBrowserTab(for: origin.profileID),
            isMinimized: false, admitsHidden: false, canRestore: false)
        guard candidate.sharesSession, candidate.acceptsTabs, let window = controller.window,
              let binding = Target.registeredBinding(of: controller, in: window) else { return candidate }
        candidate.isMinimized = window.isMiniaturized
        candidate.admitsHidden = !window.isMiniaturized && binding.canAdmitHiddenPageTransferDestination
        candidate.canRestore = window.isMiniaturized && window.attachedSheet == nil && NSApp.isActive
        return candidate
    }

    private static func openFresh(_ input: String?, _ freshWindow: () -> BrowserWindowController?) {
        guard let destination = freshWindow() else { return }
        destination.showWindow(nil)
        destination.window?.makeKeyAndOrderFront(nil)
        deliver(input, to: destination)
    }

    private static func deliver(_ input: String?, to destination: BrowserWindowController) {
        if let input { destination.openInput(input) } else { destination.newTab() }
    }

    @MainActor private struct Origin {
        weak var controller: BrowserWindowController?
        weak var window: NSWindow?
        weak var page: PCNativePage?
        weak var store: BrowserStore?
        let hadPage: Bool
        let profileID: UUID

        init(_ controller: BrowserWindowController) {
            self.controller = controller
            window = controller.window
            page = controller.selectedNativePage()
            store = controller.store
            hadPage = page != nil
            profileID = controller.activeProfileID
        }

        func isCurrent(in windows: [BrowserWindowController]) -> Bool {
            guard let controller, let window, let store, windows.contains(where: { $0 === controller }),
                  controller.isPopupWindow, controller.window === window, controller.store === store,
                  controller.activeProfileID == profileID, controller.hasReadyPresentation, !controller.isClosing,
                  !controller.wholeWindowClose, !controller.windowClosePending, !controller.windowCloseApproved else {
                return false
            }
            let selected = controller.selectedNativePage()
            guard hadPage else { return selected == nil }
            guard let page else { return false }
            return selected === page && !page.isClosed
        }
    }

    @MainActor private struct Target {
        weak var controller: BrowserWindowController?
        weak var window: NSWindow?
        weak var binding: PCNativeBrowserWindow?
        let spaceID: UUID
        let profileID: UUID

        init?(_ controller: BrowserWindowController) {
            guard let window = controller.window,
                  let binding = Self.registeredBinding(of: controller, in: window) else { return nil }
            self.controller = controller
            self.window = window
            self.binding = binding
            spaceID = controller.activeSpaceID
            profileID = controller.activeProfileID
        }

        static func registeredBinding(of controller: BrowserWindowController, in window: NSWindow) -> PCNativeBrowserWindow? {
            guard let binding = controller.nativeBinding, binding.window === window, binding.client === controller,
                  PCNativeBrowserApplication.window(forNativeWindow: window) === binding else { return nil }
            return binding
        }

        func isCurrent(in windows: [BrowserWindowController]) -> Bool {
            guard let controller, let window, let binding, windows.contains(where: { $0 === controller }),
                  controller.window === window, Self.registeredBinding(of: controller, in: window) === binding,
                  !controller.isPopupWindow, controller.activeSpaceID == spaceID,
                  controller.activeProfileID == profileID else { return false }
            return controller.canAcceptBrowserTab(for: profileID)
        }
    }
}
