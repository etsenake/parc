import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

enum MiniPlayerTestsSupport {
    @MainActor final class MiniPlayerFixture {
        let window: NSWindow
        let deck = MiniPlayerDeck(frame: CGRect(x: 0, y: 0, width: 212, height: 230))
        private(set) var engines: [String: ParcMiniPlayerEngineFixture] = [:]
        private(set) var revealed: [String] = []
        private(set) var collapses: [(delay: TimeInterval, job: @MainActor () -> Void)] = []
        var relinks = 0

        init(_ ids: [String]) throws {
            _ = NSApplication.shared
            window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(deck)
            deck.after = { [weak self] delay, job in self?.collapses.append((delay, job)) }
            deck.onKeyViewsChanged = { [weak self] in self?.relinks += 1 }
            try update(ids)
        }

        func engine(_ id: String) -> ParcMiniPlayerEngineFixture {
            if let fixture = engines[id] { return fixture }
            let new = ParcMiniPlayerEngineFixture(identifier: id, title: id)
            engines[id] = new
            return new
        }

        func update(_ ids: [String]) throws {
            let items = try ids.map { id in
                let engine = self.engine(id)
                let page = try #require(engine.page as? PCNativePage)
                let state = try #require(engine.state as? PCNativeMediaState)
                return MiniPlayerItem(page: page, state: state, icon: nil, host: MiniPlayerHostLease(window),
                    valid: { true }, reveal: { [weak self] in self?.revealed.append(id) })
            }
            deck.update(items)
            layout()
        }

        func layout() {
            deck.frame.size.height = deck.desiredHeight
            deck.layoutSubtreeIfNeeded()
        }

        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }

        func button(_ label: String, in root: NSView? = nil, visible: Bool = false) throws -> ActionButton {
            try #require(descendants(root ?? deck).compactMap { $0 as? ActionButton }.first {
                $0.accessibilityLabel() == label && (!visible || !$0.isHiddenOrHasHiddenAncestor)
            })
        }

        func row(_ id: String) throws -> MiniPlayerRow {
            try #require(descendants(deck).compactMap { $0 as? MiniPlayerRow }.first { row in
                descendants(row).contains { ($0 as? ActionButton)?.accessibilityLabel() == "Back to Tab — \(id)" }
            })
        }

        func toggleExpansion(_ label: String = "Show All Mini Players (2)") throws {
            let button = try button(label)
            button.actionBlock?()
            layout()
        }

        func toggleVolume(in id: String) throws {
            let button = try button("Adjust Tab Volume", in: row(id))
            button.actionBlock?()
            layout()
        }

        func volume(in id: String) throws -> NSSlider {
            let row = try row(id)
            return try #require(descendants(row).compactMap { $0 as? NSSlider }.first)
        }

        func key(_ code: UInt16, _ characters: String) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
    }
}
