import AppKit
import ObjectiveC

@MainActor enum WindowGuard {
    static func install() {
        _ = dlopen("/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/TextInputUIMacHelper", RTLD_NOW)
        if let cursor: AnyClass = NSClassFromString("TUINSCursorUIController"),
           let shared = class_getClassMethod(cursor, NSSelectorFromString("sharedInstance")) {
            let none: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
            method_setImplementation(shared, imp_implementationWithBlock(none))
        }
        let cls: AnyClass = NSWindow.self
        let selector = #selector(NSWindow.init(contentRect:styleMask:backing:defer:))
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        let block: @convention(block) (AnyObject, NSRect, UInt, UInt, Bool) -> AnyObject? = { object, _, _, _, _ in
            FileHandle.standardError.write(Data(("WINDOW BLOCKED: \(type(of: object))\n" + Thread.callStackSymbols.prefix(40).joined(separator: "\n") + "\n").utf8))
            exit(3)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}

@MainActor enum InputGuard {
    static func install() {
        func instance(_ cls: AnyClass, _ name: String, _ block: Any) {
            guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)) else { fatalError("no -\(name)") }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        func type(_ cls: AnyClass, _ name: String, _ block: Any) {
            guard let method = class_getClassMethod(cls, NSSelectorFromString(name)) else { fatalError("no +\(name)") }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        let current: @convention(block) (NSApplication) -> NSEvent? = { _ in
            var event: NSEvent?
            MainActor.assumeIsolated { event = FilmInput.shared.currentEvent }
            return event
        }
        instance(NSApplication.self, "currentEvent", current)
        let pressed: @convention(block) (AnyClass) -> Int = { _ in MainActor.assumeIsolated { FilmInput.shared.pressed ? 1 : 0 } }
        type(NSEvent.self, "pressedMouseButtons", pressed)
        let location: @convention(block) (AnyClass) -> NSPoint = { _ in MainActor.assumeIsolated { FilmInput.shared.screenLocation } }
        type(NSEvent.self, "mouseLocation", location)
        let flags: @convention(block) (AnyClass) -> UInt = { _ in 0 }
        type(NSEvent.self, "modifierFlags", flags)
        let set: @convention(block) (NSCursor) -> Void = { cursor in MainActor.assumeIsolated { FilmInput.shared.cursorSet(cursor) } }
        instance(NSCursor.self, "set", set)
        let push: @convention(block) (NSCursor) -> Void = { cursor in MainActor.assumeIsolated { FilmInput.shared.cursorStack.append(cursor) } }
        instance(NSCursor.self, "push", push)
        let pop: @convention(block) (AnyObject) -> Void = { _ in MainActor.assumeIsolated { _ = FilmInput.shared.cursorStack.popLast() } }
        instance(NSCursor.self, "pop", pop)
        type(NSCursor.self, "pop", pop)
        let rect: @convention(block) (NSView, NSRect, NSCursor) -> Void = { view, rect, cursor in
            MainActor.assumeIsolated { FilmInput.shared.cursorRects.append((view, rect, cursor)) }
        }
        instance(NSView.self, "addCursorRect:cursor:", rect)
    }
}
