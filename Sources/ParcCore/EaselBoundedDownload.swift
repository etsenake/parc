import Foundation

package final class EaselBoundedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    package enum Failure: Error, Equatable { case tooLarge, badResponse, empty }

    package static func fetch(_ url: URL, limit: Int, protocolClasses: [AnyClass]? = nil) async throws -> Data {
        let job = EaselBoundedDownload(limit: limit)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        let session = URLSession(configuration: configuration, delegate: job, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                job.begin(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private let limit: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var received = Data()
    private var failure: Failure?

    init(limit: Int) { self.limit = limit }

    private func begin(_ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    package func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            failure = .badResponse
            completionHandler(.cancel)
            return
        }
        if response.expectedContentLength > Int64(limit) {
            failure = .tooLarge
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    package func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if received.count + data.count > limit {
            failure = .tooLarge
            dataTask.cancel()
            return
        }
        received.append(data)
    }

    package func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let failure { finish(.failure(failure)); return }
        if let error { finish(.failure(error)); return }
        finish(received.isEmpty ? .failure(Failure.empty) : .success(received))
    }
}
