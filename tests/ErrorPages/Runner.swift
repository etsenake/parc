import AppKit
import WebKit

struct Step: Decodable {
    let js: String
    let wait: Double?
}

struct Job: Decodable {
    let name: String
    let page: String
    let dark: Bool
    let width: Double
    let height: Double
    let history: Bool
    let subframe: Bool
    let steps: [Step]
    let snapshot: String?
}

let probe = """
(() => {
  const calls = [];
  const errors = [];
  const violations = [];
  const controller = (owner) => new Proxy({}, {
    get(target, name) {
      if (typeof name !== 'string' || name === 'then' || name === 'toJSON') return undefined;
      return (...args) => { calls.push([owner, name, ...args]); };
    },
  });
  window.errorPageController = controller('net');
  window.certificateErrorPageController = controller('cert');
  window.addEventListener('error', (event) => errors.push(String(event.message)));
  window.addEventListener('unhandledrejection', (event) => errors.push('rejection: ' + event.reason));
  document.addEventListener('securitypolicyviolation', (event) => violations.push(event.violatedDirective));
  window.__backs = 0;
  history.back = () => { window.__backs += 1; };
  window.__report = () => ({
    title: document.title,
    text: document.body ? document.body.innerText : '',
    errors, violations, calls, backs: window.__backs, extra: window.__extra || {},
  });
})();
"""

final class Runner: NSObject, WKNavigationDelegate {
    let jobs: [Job]
    var results: [[String: Any]] = []
    var index = 0
    var view: WKWebView?
    var done = false

    init(jobs: [Job]) { self.jobs = jobs }

    func start() { next() }

    func next() {
        guard index < jobs.count else { done = true; return }
        let job = jobs[index]
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: probe, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if job.history {
            controller.addUserScript(WKUserScript(source: "Object.defineProperty(history, 'length', {get: () => 2});",
                                                  injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        configuration.userContentController = controller
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: job.width, height: job.height), configuration: configuration)
        web.appearance = NSAppearance(named: job.dark ? .darkAqua : .aqua)
        web.navigationDelegate = self
        view = web
        var html = (try? String(contentsOfFile: job.page, encoding: .utf8)) ?? ""
        if job.subframe {
            let escaped = html.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            html = "<!doctype html><body style=\"margin:0\"><iframe style=\"border:0;width:100%;height:100vh\" srcdoc=\"\(escaped)\"></iframe></body>"
        }
        web.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.run(step: 0) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        record(["error": "navigation failed: \(error)"])
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        record(["error": "page failed to load: \(error)"])
    }

    func target() -> String {
        jobs[index].subframe ? "document.querySelector('iframe').contentWindow" : "window"
    }

    func run(step: Int) {
        let job = jobs[index]
        guard let web = view else { return }
        if step < job.steps.count {
            let source = "(function() { with (\(target())) { \(job.steps[step].js) } })(); true"
            web.evaluateJavaScript(source) { _, error in
                let delay = job.steps[step].wait ?? 0.05
                if let error {
                    self.record(["error": "step \(step) failed: \(error)"])
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.run(step: step + 1) }
            }
            return
        }
        web.evaluateJavaScript("JSON.stringify(\(target()).__report())") { value, error in
            var report: [String: Any] = [:]
            if let text = value as? String, let data = text.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                report = object
            } else {
                report["error"] = "report failed: \(String(describing: error))"
            }
            guard let path = job.snapshot else { self.record(report); return }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = NSRect(x: 0, y: 0, width: job.width, height: job.height)
            web.takeSnapshot(with: configuration) { image, _ in
                if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                } else {
                    report["snapshotError"] = true
                }
                self.record(report)
            }
        }
    }

    func record(_ report: [String: Any]) {
        var report = report
        report["name"] = jobs[index].name
        results.append(report)
        view = nil
        index += 1
        DispatchQueue.main.async { self.next() }
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let data = FileManager.default.contents(atPath: arguments[1]),
      let jobs = try? JSONDecoder().decode([Job].self, from: data) else {
    FileHandle.standardError.write("usage: runner jobs.json results.json\n".data(using: .utf8)!)
    exit(2)
}
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let runner = Runner(jobs: jobs)
runner.start()
let deadline = Date().addingTimeInterval(Double(jobs.count) * 15 + 30)
while !runner.done && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
let output = try JSONSerialization.data(withJSONObject: runner.results, options: [.prettyPrinted, .sortedKeys])
try output.write(to: URL(fileURLWithPath: arguments[2]))
exit(runner.done ? 0 : 1)
