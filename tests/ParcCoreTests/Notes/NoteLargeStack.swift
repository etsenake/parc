import Foundation

private final class LargeStackResult<Value>: @unchecked Sendable {
    var value: Value?
}

func runOnLargeStack<Value>(_ work: @escaping @Sendable () -> Value) -> Value {
    let finished = DispatchSemaphore(value: 0)
    let result = LargeStackResult<Value>()
    let thread = Thread {
        result.value = work()
        finished.signal()
    }
    thread.stackSize = 64 << 20
    thread.start()
    finished.wait()
    return result.value!
}
