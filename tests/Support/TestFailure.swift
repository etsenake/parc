import Foundation

func failTest(_ message: String, file: StaticString = #file, line: UInt = #line) -> Never {
    fflush(nil)
    FileHandle.standardError.write(Data("\(file):\(line): \(message)\n".utf8))
    exit(1)
}

private func described(_ kind: String, _ message: String) -> String {
    message.isEmpty ? kind : "\(kind): \(message)"
}

func precondition(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = String(),
                  file: StaticString = #file, line: UInt = #line) {
    if !condition() { failTest(described("Precondition failed", message()), file: file, line: line) }
}

func preconditionFailure(_ message: @autoclosure () -> String = String(),
                         file: StaticString = #file, line: UInt = #line) -> Never {
    failTest(described("Fatal error", message()), file: file, line: line)
}

func fatalError(_ message: @autoclosure () -> String = String(),
                file: StaticString = #file, line: UInt = #line) -> Never {
    failTest(described("Fatal error", message()), file: file, line: line)
}

func assert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = String(),
            file: StaticString = #file, line: UInt = #line) {
    if !condition() { failTest(described("Assertion failed", message()), file: file, line: line) }
}

func assertionFailure(_ message: @autoclosure () -> String = String(),
                      file: StaticString = #file, line: UInt = #line) {
    failTest(described("Fatal error", message()), file: file, line: line)
}

private func exitOnUncaughtExceptions() {
    NSSetUncaughtExceptionHandler { exception in
        fflush(nil)
        FileHandle.standardError.write(Data("Uncaught \(exception.name.rawValue): \(exception.reason ?? "no reason")\n".utf8))
        exit(1)
    }
}

func exitOnFailure(file: StaticString = #file, line: UInt = #line, _ body: () throws -> Void) {
    exitOnUncaughtExceptions()
    do { try body() } catch { failTest("Error raised at top level: \(String(reflecting: error))", file: file, line: line) }
}

func exitOnFailure(isolation: isolated (any Actor)? = #isolation, file: StaticString = #file, line: UInt = #line,
                   _ body: () async throws -> Void) async {
    exitOnUncaughtExceptions()
    do { try await body() } catch { failTest("Error raised at top level: \(String(reflecting: error))", file: file, line: line) }
}
