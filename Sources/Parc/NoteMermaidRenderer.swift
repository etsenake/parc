import AppKit
import ParcCore
import WebKit

@MainActor
struct NoteMermaidArt {
    let drawing: NoteMermaidDrawing
    let image: NSImage

    var size: NSSize { NSSize(width: drawing.size.width, height: drawing.size.height) }
}

@MainActor
enum NoteMermaidResult {
    case art(NoteMermaidArt)
    case failure(String)
    case unavailable(String)

    var art: NoteMermaidArt? {
        if case .art(let art) = self { return art }
        return nil
    }

    var problem: String? {
        switch self {
        case .art: return nil
        case .failure(let message), .unavailable(let message): return message
        }
    }
}

extension NoteMermaidTheme {
    @MainActor
    static func note(appearance: NSAppearance, settings: NotePageSettings) -> NoteMermaidTheme {
        note(dark: NoteTheme.isDark(appearance), font: settings.font, small: settings.smallText)
    }
}

@MainActor
final class NoteMermaidRenderer: NSObject, WKNavigationDelegate {
    static let shared = NoteMermaidRenderer()
    static let viewport = NSSize(width: NoteTheme.pageColumnWidth, height: 600)
    static let idleLifetime: TimeInterval = 90
    static let script = "return await window.parcMermaid.render(id, source, config, faces);"
    static let missingMessage = "Parc's Mermaid kit is missing, so diagrams can't draw."
    static let crashMessage = "Mermaid crashed drawing this one. Try simplifying it."
    static let timeoutMessage = "Mermaid gave up on this one. It took too long to draw."
    static let oddReplyMessage = "Mermaid sent back something Parc couldn't read."

    typealias Completion = (NoteMermaidResult) -> Void

    private var cache = NoteMermaidCache<NoteMermaidResult>(capacity: 96, costLimit: 24 << 20)
    private var layouts = NoteMermaidCache<NoteMermaidResult>(capacity: 192, costLimit: 24 << 20)
    private var queue = NoteMermaidQueue()
    private var completions: [Int: Completion] = [:]
    private var lastClient = 0
    private var webView: WKWebView?
    private var harnessNavigation: WKNavigation?
    private var isReady = false
    private var generation = 0
    private var timeout: DispatchWorkItem?
    private var idle: DispatchWorkItem?
    private var retriedKey: String?

    func makeClient() -> Int {
        lastClient += 1
        return lastClient
    }

    func cached(_ request: NoteMermaidRequest) -> NoteMermaidResult? {
        cache.value(for: request.key)
    }

    func lastKnown(_ request: NoteMermaidRequest) -> NoteMermaidResult? {
        cache.peek(request.key) ?? layouts.peek(request.layoutKey)
    }

    func render(_ request: NoteMermaidRequest, client: Int, completion: @escaping Completion) {
        if let hit = cache.value(for: request.key) {
            cancel(client)
            completion(hit)
            return
        }
        completions[client] = completion
        queue.submit(request, client: client)
        pump()
    }

    func cancel(_ client: Int) {
        completions.removeValue(forKey: client)
        queue.withdraw(client)
    }

    func renderAll(_ requests: [NoteMermaidRequest], completion: @escaping ([String: NoteMermaidResult]) -> Void) {
        var unique: [String: NoteMermaidRequest] = [:]
        for request in requests { unique[request.key] = request }
        guard !unique.isEmpty else { completion([:]); return }
        var remaining = Set(unique.keys)
        var results: [String: NoteMermaidResult] = [:]
        for request in unique.values {
            render(request, client: makeClient()) { result in
                results[request.key] = result
                remaining.remove(request.key)
                if remaining.isEmpty { completion(results) }
            }
        }
    }

    private func pump() {
        idle?.cancel()
        idle = nil
        guard queue.isIdle else { return }
        guard !queue.pending.isEmpty else { scheduleIdleTeardown(); return }
        guard let web = preparedWebView(), isReady, let request = queue.start() else { return }
        run(request, in: web)
    }

    private func preparedWebView() -> WKWebView? {
        if let webView { return webView }
        guard let resources = Bundle.main.resourceURL,
              let harness = Bundle.main.url(forResource: "harness", withExtension: "html", subdirectory: "NoteMermaid") else {
            failEveryone(Self.missingMessage)
            return nil
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        if #available(macOS 14.0, *) { configuration.preferences.inactiveSchedulingPolicy = .none }
        let web = WKWebView(frame: NSRect(origin: .zero, size: Self.viewport), configuration: configuration)
        if web.responds(to: NSSelectorFromString("_setDrawsBackground:")) { web.setValue(false, forKey: "drawsBackground") }
        web.navigationDelegate = self
        webView = web
        isReady = false
        harnessNavigation = web.loadFileURL(harness, allowingReadAccessTo: resources)
        return web
    }

    private func run(_ request: NoteMermaidRequest, in web: WKWebView) {
        generation &+= 1
        let token = generation
        scheduleTimeout(token)
        let arguments: [String: Any] = ["id": request.elementID, "source": request.source,
                                        "config": request.configurationJSON, "faces": request.theme.facesJSON]
        web.callAsyncJavaScript(Self.script, arguments: arguments, in: nil, in: .page) { [weak self, weak web] result in
            MainActor.assumeIsolated {
                guard let self, let web, token == self.generation else { return }
                switch result {
                case .failure(let error):
                    self.complete(request, .unavailable(error.localizedDescription))
                case .success(let value):
                    guard let parsed = NoteMermaidOutcome.parse(value) else {
                        self.complete(request, .unavailable(Self.oddReplyMessage))
                        return
                    }
                    guard let drawing = parsed.outcome.drawing else {
                        self.complete(request, parsed.outcome)
                        return
                    }
                    self.capture(request, drawing: drawing, origin: parsed.origin, in: web, token: token)
                }
            }
        }
    }

    private func capture(_ request: NoteMermaidRequest, drawing: NoteMermaidDrawing, origin: CGPoint, in web: WKWebView, token: Int) {
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(origin: origin, size: drawing.size)
        if #available(macOS 14.0, *) { configuration.allowTransparentBackground = true }
        web.createPDF(configuration: configuration) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, token == self.generation else { return }
                switch result {
                case .failure(let error):
                    self.complete(request, .unavailable(error.localizedDescription))
                case .success(let data):
                    var complete = drawing
                    complete.pdf = data
                    self.complete(request, .drawing(complete))
                }
            }
        }
    }

    private func complete(_ request: NoteMermaidRequest, _ outcome: NoteMermaidOutcome) {
        timeout?.cancel()
        timeout = nil
        let result = Self.result(for: outcome)
        if case .art = result { retriedKey = nil }
        if outcome.isCacheable, result.art != nil || outcome.drawing == nil {
            cache.insert(result, for: request.key, cost: outcome.cost)
            layouts.insert(result, for: request.layoutKey, cost: outcome.cost)
        }
        for client in queue.finish(request.key) {
            completions.removeValue(forKey: client)?(result)
        }
        pump()
    }

    private static func result(for outcome: NoteMermaidOutcome) -> NoteMermaidResult {
        switch outcome {
        case .drawing(let drawing):
            guard let image = NSImage(data: drawing.pdf), image.isValid else { return .unavailable(oddReplyMessage) }
            image.size = NSSize(width: drawing.size.width, height: drawing.size.height)
            return .art(NoteMermaidArt(drawing: drawing, image: image))
        case .failure(let message):
            return .failure(message)
        case .unavailable(let message):
            return .unavailable(message)
        }
    }

    private func scheduleTimeout(_ token: Int) {
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token, let request = self.queue.running else { return }
                self.discardWebView()
                self.complete(request, .failure(Self.timeoutMessage))
            }
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NoteMermaid.renderTimeout, execute: work)
    }

    private func scheduleIdleTeardown() {
        guard webView != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.queue.isIdle, self.queue.pending.isEmpty else { return }
                self.discardWebView()
            }
        }
        idle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleLifetime, execute: work)
    }

    private func discardWebView() {
        generation &+= 1
        timeout?.cancel()
        timeout = nil
        if let webView {
            webView.navigationDelegate = nil
            webView.stopLoading()
        }
        webView = nil
        harnessNavigation = nil
        isReady = false
    }

    private func failEveryone(_ message: String) {
        let clients = queue.failAll()
        for client in clients { completions.removeValue(forKey: client)?(.unavailable(message)) }
    }

    private func harnessFailed(_ web: WKWebView) {
        guard web === webView else { return }
        discardWebView()
        failEveryone(Self.missingMessage)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, navigation === harnessNavigation else { return }
        isReady = true
        pump()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        harnessFailed(webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        harnessFailed(webView)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let harness = url?.isFileURL == true && url?.lastPathComponent == "harness.html"
        decisionHandler(harness && navigationAction.targetFrame?.isMainFrame == true && !isReady ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        let running = queue.running
        discardWebView()
        guard let running else { pump(); return }
        if retriedKey == running.key {
            retriedKey = nil
            complete(running, .failure(Self.crashMessage))
        } else {
            retriedKey = running.key
            queue.requeueRunning()
            pump()
        }
    }
}
