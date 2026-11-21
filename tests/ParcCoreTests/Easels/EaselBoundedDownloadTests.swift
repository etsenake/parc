import Foundation
import Testing
@testable import ParcCore

struct EaselBoundedDownloadTests {
    private final class StubProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
            func value(_ name: String) -> Int { items.first { $0.name == name }?.value.flatMap(Int.init) ?? 0 }
            var headers: [String: String] = [:]
            if value("declared") >= 0 { headers["Content-Length"] = String(value("declared")) }
            let response = HTTPURLResponse(url: url, statusCode: value("status"), httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for _ in 0..<value("chunks") {
                client?.urlProtocol(self, didLoad: Data(repeating: 7, count: value("size")))
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    struct Transfer: CustomTestStringConvertible, Sendable {
        let name: String
        let status: Int
        let declared: Int
        let chunks: Int
        let size: Int
        let outcome: String
        var testDescription: String { name }
    }

    private static let limit = 5000

    private static func outcome(_ transfer: Transfer) async -> String {
        var components = URLComponents(string: "https://example.test/file")!
        components.queryItems = [("status", transfer.status), ("declared", transfer.declared), ("chunks", transfer.chunks), ("size", transfer.size)]
            .map { URLQueryItem(name: $0.0, value: String($0.1)) }
        do {
            let data = try await EaselBoundedDownload.fetch(components.url!, limit: limit, protocolClasses: [StubProtocol.self])
            return "ok \(data.count)"
        } catch let failure as EaselBoundedDownload.Failure {
            return "\(failure)"
        } catch {
            return "other"
        }
    }

    @Test(arguments: [
        Transfer(name: "a download at the limit succeeds", status: 200, declared: 5000, chunks: 5, size: 1000, outcome: "ok 5000"),
        Transfer(name: "a declared size over the limit is refused", status: 200, declared: 9_000_000, chunks: 50, size: 1000, outcome: "tooLarge"),
        Transfer(name: "an undeclared stream is cut off at the limit", status: 200, declared: -1, chunks: 200, size: 1000, outcome: "tooLarge"),
        Transfer(name: "an error status fails", status: 404, declared: 10, chunks: 1, size: 10, outcome: "badResponse"),
        Transfer(name: "an empty body fails", status: 200, declared: 0, chunks: 0, size: 0, outcome: "empty"),
    ])
    func downloadsEndInTheExpectedOutcome(transfer: Transfer) async {
        #expect(await Self.outcome(transfer) == transfer.outcome)
    }

    private final class Disposition: @unchecked Sendable {
        var value: URLSession.ResponseDisposition?
    }

    private static func withTask(_ body: (URLSession, URLSessionDataTask) -> Void) {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        body(session, session.dataTask(with: URL(string: "https://example.test/file")!))
    }

    private static func disposition(declared: Int) -> URLSession.ResponseDisposition? {
        let delegate = EaselBoundedDownload(limit: limit)
        let disposition = Disposition()
        withTask { session, task in
            let response = HTTPURLResponse(url: URL(string: "https://example.test/file")!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Length": String(declared)])!
            delegate.urlSession(session, dataTask: task, didReceive: response) { disposition.value = $0 }
        }
        return disposition.value
    }

    @Test func noBodyIsReadAfterARefusedLength() {
        #expect(Self.disposition(declared: 9_000_000) == .cancel)
    }

    @Test func aDeclaredLengthWithinTheLimitIsRead() {
        #expect(Self.disposition(declared: Self.limit) == .allow)
    }

    @Test func theTransferIsAbortedOnceTheStreamPassesTheLimit() {
        let delegate = EaselBoundedDownload(limit: Self.limit)
        Self.withTask { session, task in
            for _ in 0..<5 { delegate.urlSession(session, dataTask: task, didReceive: Data(repeating: 7, count: 1000)) }
            #expect(task.state == .suspended)
            delegate.urlSession(session, dataTask: task, didReceive: Data(repeating: 7, count: 1))
            #expect(task.state != .suspended)
        }
    }
}
