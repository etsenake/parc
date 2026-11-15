# Adapted from Ardia's apps/browser/scripts/perf/xbench.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.
import base64
import hashlib
import http.client
import json
import os
import socket
import struct
import time
from urllib.parse import urlsplit

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
CONNECTING, OPEN, CLOSED = 0, 1, 3


class WebSocketClosed(ConnectionError):
    pass


def mask(data: bytes, key: bytes) -> bytes:
    if not data:
        return data
    size = len(data)
    pad = (key * (size // 4 + 1))[:size]
    return (int.from_bytes(data, "big") ^ int.from_bytes(pad, "big")).to_bytes(size, "big")


def frame(opcode: int, payload: bytes, key: bytes) -> bytes:
    size = len(payload)
    if size < 126:
        head = struct.pack("!BB", 0x80 | opcode, 0x80 | size)
    elif size < 1 << 16:
        head = struct.pack("!BBH", 0x80 | opcode, 0x80 | 126, size)
    else:
        head = struct.pack("!BBQ", 0x80 | opcode, 0x80 | 127, size)
    return head + key + mask(payload, key)


def parse_frame(buffer: bytearray):
    if len(buffer) < 2:
        return None
    first, second = buffer[0], buffer[1]
    size = second & 0x7F
    offset = 2
    if size == 126:
        if len(buffer) < 4:
            return None
        size = struct.unpack("!H", buffer[2:4])[0]
        offset = 4
    elif size == 127:
        if len(buffer) < 10:
            return None
        size = struct.unpack("!Q", buffer[2:10])[0]
        if size >> 63:
            raise WebSocketClosed("websocket frame length is invalid")
        offset = 10
    masked = bool(second & 0x80)
    key = bytes(buffer[offset:offset + 4]) if masked else b""
    offset += 4 if masked else 0
    if len(buffer) < offset + size:
        return None
    payload = bytes(buffer[offset:offset + size])
    del buffer[:offset + size]
    return bool(first & 0x80), first & 0x0F, mask(payload, key) if masked else payload


def accept_key(key: str) -> str:
    return base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()


class WebSocket:
    def __init__(self, url: str, timeout: float):
        parts = urlsplit(url)
        if parts.scheme != "ws" or not parts.hostname:
            raise ConnectionError(f"not a ws:// URL: {url}")
        deadline = time.monotonic() + timeout
        self.buffer = bytearray()
        self.state = CONNECTING
        self.sock = socket.create_connection((parts.hostname, parts.port or 80), timeout=timeout)
        try:
            self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            key = base64.b64encode(os.urandom(16)).decode()
            path = (parts.path or "/") + (f"?{parts.query}" if parts.query else "")
            request = (f"GET {path} HTTP/1.1\r\nHost: {parts.netloc}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                       f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
            self.sock.sendall(request.encode())
            while b"\r\n\r\n" not in self.buffer:
                self.fill(deadline)
            head, _, rest = bytes(self.buffer).partition(b"\r\n\r\n")
            self.buffer = bytearray(rest)
            lines = head.decode("latin-1").split("\r\n")
            status = lines[0].split(" ")
            headers = {name.strip().lower(): value.strip() for name, _, value in (line.partition(":") for line in lines[1:])}
            if len(status) < 2 or status[1] != "101" or headers.get("sec-websocket-accept") != accept_key(key):
                raise ConnectionError(f"websocket {url} refused: {lines[0]}")
        except BaseException:
            self.sock.close()
            self.state = CLOSED
            raise
        self.state = OPEN

    def fill(self, deadline: float):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("websocket read timed out")
        self.sock.settimeout(remaining)
        data = self.sock.recv(1 << 16)
        if not data:
            self.state = CLOSED
            raise WebSocketClosed("websocket closed")
        self.buffer.extend(data)

    def send(self, opcode: int, payload: bytes):
        self.sock.settimeout(5)
        self.sock.sendall(frame(opcode, payload, os.urandom(4)))

    def send_text(self, text: str):
        try:
            self.send(0x1, text.encode())
        except OSError:
            self.state = CLOSED
            raise

    def receive(self, deadline: float) -> str:
        parts, kind = [], None
        while True:
            try:
                parsed = parse_frame(self.buffer)
            except WebSocketClosed:
                self.state = CLOSED
                raise
            if parsed is None:
                try:
                    self.fill(deadline)
                except TimeoutError:
                    raise
                except OSError:
                    self.state = CLOSED
                    raise
                continue
            fin, opcode, payload = parsed
            if opcode == 0x8:
                self.close()
                raise WebSocketClosed("websocket closed")
            if opcode == 0x9:
                try:
                    self.send(0xA, payload)
                except OSError:
                    self.state = CLOSED
                    raise
                continue
            if opcode == 0xA:
                continue
            if opcode in (0x1, 0x2):
                kind, parts = opcode, [payload]
            elif opcode == 0x0 and kind is not None:
                parts.append(payload)
            if fin and kind is not None:
                data = b"".join(parts)
                return data.decode("utf-8", "replace") if kind == 0x1 else data.decode("latin-1")

    def close(self):
        if self.state == OPEN:
            try:
                self.send(0x8, b"")
            except OSError:
                pass
        self.state = CLOSED
        try:
            self.sock.close()
        except OSError:
            pass


class Socket:
    def __init__(self, url):
        self.url = url
        self.ws = None
        self.failed = False
        self.seq = 0

    @property
    def ready_state(self) -> int:
        if self.failed:
            return CLOSED
        return self.ws.state if self.ws else CONNECTING

    def ready(self):
        if self.ws is None and not self.failed:
            try:
                self.ws = WebSocket(self.url, 4.0)
            except TimeoutError:
                self.failed = True
                raise ConnectionError(f"websocket {self.url} timed out")
            except Exception:
                self.failed = True
        if self.failed or self.ws is None:
            raise ConnectionError(f"websocket {self.url} failed")

    def send(self, method: str, params=None, timeout: int = 8000) -> dict:
        self.ready()
        self.seq += 1
        ident = self.seq
        deadline = time.monotonic() + timeout / 1000

        def failed(error: OSError) -> dict:
            closed = isinstance(error, WebSocketClosed)
            return {"error": {"message": "websocket closed" if closed else f"{method} timed out"}}

        try:
            self.ws.send_text(json.dumps({"id": ident, "method": method, "params": params or {}}))
        except OSError as error:
            return failed(error)
        while True:
            try:
                text = self.ws.receive(deadline)
            except OSError as error:
                return failed(error)
            try:
                message = json.loads(text)
            except ValueError:
                continue
            if isinstance(message, dict) and message.get("id") == ident:
                return message

    def close(self):
        if self.ws:
            self.ws.close()


STATE_EXPRESSION = ("JSON.stringify(Object.assign({}, window.__ac, { visibility: document.visibilityState, "
                    "w: innerWidth, h: innerHeight, origin: performance.timeOrigin }))")


def _value(response):
    result = (response or {}).get("result") or {}
    return (result.get("result") or {}).get("value")


class Cdp:
    def __init__(self, port: int):
        self.port = port
        self.sockets = {}
        self.root = None
        self.version = None

    def get(self, path: str):
        try:
            connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=2.5)
            try:
                connection.request("GET", path)
                return json.loads(connection.getresponse().read())
            finally:
                connection.close()
        except Exception:
            return None

    def pages(self) -> list:
        listed = self.get("/json/list")
        return [t for t in (listed if isinstance(listed, list) else []) if isinstance(t, dict) and t.get("type") == "page"]

    def browser(self):
        if self.root and self.root.ready_state == OPEN:
            return self.root
        version = self.get("/json/version")
        if not isinstance(version, dict) or not version.get("webSocketDebuggerUrl"):
            return None
        self.version = version
        self.root = Socket(version["webSocketDebuggerUrl"])
        self.root.ready()
        return self.root

    def call(self, method: str, params=None):
        root = self.browser()
        if not root:
            raise RuntimeError("no CDP browser endpoint")
        response = root.send(method, params or {})
        if response.get("error"):
            raise RuntimeError(f"{method}: {response['error'].get('message')}")
        return response.get("result")

    def target_socket(self, target: dict) -> Socket:
        socket_ = self.sockets.get(target["id"])
        if not socket_ or socket_.ready_state > OPEN:
            socket_ = Socket(target.get("webSocketDebuggerUrl"))
            self.sockets[target["id"]] = socket_
        return socket_

    def state(self, target: dict):
        if target is None:
            raise RuntimeError("no such target")
        socket_ = self.target_socket(target)
        try:
            response = socket_.send("Runtime.evaluate", {"expression": STATE_EXPRESSION, "returnByValue": True}, 3000)
            value = _value(response)
            return json.loads(value if value is not None else "null")
        except Exception:
            self.sockets.pop(target["id"], None)
            return None

    def evaluate(self, target: dict, expression: str, timeout: int = 3000):
        try:
            socket_ = self.target_socket(target)
            response = socket_.send("Runtime.evaluate", {"expression": expression, "awaitPromise": True, "returnByValue": True}, timeout)
            return _value(response)
        except Exception:
            return None

    def find(self, page_id: str):
        return next((t for t in self.pages() if str(t.get("url", "")).endswith(f"id={page_id}")), None)

    def page(self, page_id: str, timeout: float, accept=None):
        accept = accept or (lambda s: s.get("fcp"))
        end = time.time() * 1000 + timeout
        while time.time() * 1000 < end:
            target = self.find(page_id)
            state = self.state(target) if target else None
            if state and accept(state):
                return {"target": target, "state": state}
            time.sleep(0.02)
        return None

    def close(self):
        for socket_ in self.sockets.values():
            socket_.close()
        self.sockets.clear()
        if self.root:
            self.root.close()
        self.root = None
