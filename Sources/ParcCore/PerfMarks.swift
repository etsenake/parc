import Foundation

final class PerfMarks: Sendable {
    static let shared = TestInstance.current.perfMarksPath.flatMap(PerfMarks.init(path:))
    private static let afterDisplayOrder = 2_000_001

    private let descriptor: Int32

    init?(path: String) {
        let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return nil }
        self.descriptor = descriptor
    }

    func mark(_ name: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["mark"] = name
        record["t"] = Date().timeIntervalSince1970 * 1000
        guard var line = try? JSONSerialization.data(withJSONObject: record, options: .sortedKeys) else { return }
        line.append(0x0A)
        _ = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    }

    func markAfterDisplay(_ name: String, _ fields: [String: Any] = [:], within seconds: TimeInterval = 5,
                          when condition: @escaping @MainActor () -> Bool) {
        let activities = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue
        let deadline = Date().addingTimeInterval(seconds)
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, Self.afterDisplayOrder) { [self] observer, _ in
            MainActor.assumeIsolated {
                if condition() {
                    CFRunLoopObserverInvalidate(observer)
                    mark(name, fields)
                } else if Date() >= deadline {
                    CFRunLoopObserverInvalidate(observer)
                }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
