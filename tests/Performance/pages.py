# Adapted from Ardia's apps/browser/scripts/perf/xbench.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import math
import re
import threading
from urllib.parse import parse_qsl, urlsplit

PAGE_SCRIPT = """
window.__ac = { vis: [[Date.now(), document.visibilityState]], shown: [], fcp: null, frame: null, ticks: 0 };
requestAnimationFrame(() => (__ac.frame = Date.now()));
new PerformanceObserver((list) => {
  for (const e of list.getEntries()) if (e.name === "first-contentful-paint") __ac.fcp = performance.timeOrigin + e.startTime;
}).observe({ type: "paint", buffered: true });
document.addEventListener("visibilitychange", () => {
  const t = Date.now();
  __ac.vis.push([t, document.visibilityState]);
  if (document.visibilityState === "visible")
    requestAnimationFrame(() => requestAnimationFrame(() => __ac.shown.push([t, Date.now()])));
});
setInterval(() => __ac.ticks++, 1000);
"""

STYLE = ("<style>body{font:15px/1.5 -apple-system,sans-serif;margin:0;padding:24px 48px;background:#fbfaf8;color:#222}\n"
         ".g{display:grid;grid-template-columns:repeat(10,1fr);gap:8px;margin:16px 0}"
         ".b{height:48px;border-radius:10px;display:grid;place-items:center}\n"
         "h1{font-size:32px}</style>")


def page_number(page_id: str) -> float:
    digits = re.sub(r"[^0-9]", "", page_id)
    return float(digits) if digits else 0.0


def hue(index: int, page_id: str) -> str:
    value = (index * 37 + page_number(page_id) * 11) % 360
    return str(int(value)) if math.isfinite(value) else "NaN"


def static_page(page_id: str) -> str:
    paras = "".join(
        f"<p>Paragraph {i} of page {page_id}. The quick brown fox jumps over the lazy dog; pack my box with five dozen liquor jugs. "
        f'Sphinx of black quartz, judge my vow. <a href="#p{i}">anchor {i}</a></p>' for i in range(120))
    boxes = "".join(f'<div class=b style="background:hsl({hue(i, page_id)} 60% 70%)">{i}</div>' for i in range(60))
    return (f"<!doctype html><meta charset=utf-8><title>Bench {page_id}</title>\n" + STYLE
            + f"<h1>Bench page {page_id}</h1><div class=g>{boxes}</div>{paras}<script>{PAGE_SCRIPT}</script>")


def page_for(target: str) -> str | None:
    url = urlsplit(target)
    if url.path != "/static":
        return None
    page_id = next((value for key, value in parse_qsl(url.query, keep_blank_values=True) if key == "id"), "0")
    return static_page(page_id)


class PageHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 5

    def do_GET(self):
        html = page_for(self.path)
        if html is None:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


class PageServer:
    def __init__(self, port: int):
        self.server = ThreadingHTTPServer(("127.0.0.1", port), PageHandler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    @property
    def port(self) -> int:
        return self.server.server_address[1]

    @property
    def base(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def url(self, page_id: str) -> str:
        return f"{self.base}/static?id={page_id}"

    def close(self):
        self.server.shutdown()
        self.server.server_close()
