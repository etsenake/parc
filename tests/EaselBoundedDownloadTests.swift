import Foundation

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var declared: Int64 = -1
    nonisolated(unsafe) static var chunks = 0
    nonisolated(unsafe) static var chunkSize = 0
    nonisolated(unsafe) static var sent = 0
    nonisolated(unsafe) static var stopped = false
    private var running = true

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.sent = 0
        Self.stopped = false
        var headers: [String: String] = [:]
        if Self.declared >= 0 { headers["Content-Length"] = String(Self.declared) }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        DispatchQueue.global().async {
            for _ in 0..<Self.chunks {
                guard self.running else { return }
                self.client?.urlProtocol(self, didLoad: Data(repeating: 7, count: Self.chunkSize))
                Self.sent += 1
                Thread.sleep(forTimeInterval: 0.01)
            }
            if self.running { self.client?.urlProtocolDidFinishLoading(self) }
        }
    }

    override func stopLoading() {
        running = false
        Self.stopped = true
    }
}

@main
struct EaselBoundedDownloadTests {
    static func outcome(limit: Int) async -> String {
        do {
            let data = try await EaselBoundedDownload.fetch(URL(string: "https://example.test/file")!, limit: limit, protocolClasses: [StubProtocol.self])
            return "ok \(data.count)"
        } catch let failure as EaselBoundedDownload.Failure {
            return "\(failure)"
        } catch {
            return "other"
        }
    }

    static func main() async {
        func expect(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
        StubProtocol.status = 200; StubProtocol.declared = 5000; StubProtocol.chunks = 5; StubProtocol.chunkSize = 1000
        expect(await outcome(limit: 5000) == "ok 5000", "a download at the limit succeeds")
        StubProtocol.declared = 9_000_000; StubProtocol.chunks = 50
        expect(await outcome(limit: 5000) == "tooLarge", "a declared size over the limit is refused")
        expect(StubProtocol.sent < 5, "no body is read after a refused length")
        StubProtocol.declared = -1; StubProtocol.chunks = 200; StubProtocol.chunkSize = 1000
        expect(await outcome(limit: 5000) == "tooLarge", "an undeclared stream is cut off at the limit")
        expect(StubProtocol.sent < 100 && StubProtocol.stopped, "the transfer is aborted early")
        StubProtocol.status = 404; StubProtocol.declared = 10; StubProtocol.chunks = 1; StubProtocol.chunkSize = 10
        expect(await outcome(limit: 5000) == "badResponse", "an error status fails")
        StubProtocol.status = 200; StubProtocol.declared = 0; StubProtocol.chunks = 0
        expect(await outcome(limit: 5000) == "empty", "an empty body fails")
        print("EaselBoundedDownloadTests passed")
    }
}
