#!/usr/bin/env python3
"""Local, nonsecret browser persistence fixture; never inspect Keychain material."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from http.cookies import CookieError, SimpleCookie
import json
from pathlib import Path
import secrets
import sqlite3

COOKIE_NAME = "parc_keychain_persistence_fixture"


def inspect_profile(profile: Path) -> int:
    profile = profile.expanduser().resolve(strict=True)
    reports = []
    for database in sorted(profile.rglob("Cookies")):
        if not database.is_file() or database.is_symlink():
            continue
        if not database.resolve().is_relative_to(profile):
            continue
        with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as connection:
            count, encrypted, plaintext = connection.execute(
                "SELECT count(*), coalesce(sum(length(encrypted_value)>0),0), "
                "coalesce(sum(length(value)>0),0) FROM cookies "
                "WHERE host_key='127.0.0.1' AND name=?", (COOKIE_NAME,)
            ).fetchone()
        reports.append({"database": str(database.relative_to(profile)),
                        "fixtureRows": count, "encryptedRows": encrypted,
                        "plaintextRows": plaintext})
    print(json.dumps({"databases": reports}, indent=2))
    return 0 if (sum(row["fixtureRows"] for row in reports) > 0 and
                 all(row["encryptedRows"] == row["fixtureRows"] and row["plaintextRows"] == 0
                     for row in reports)) else 1


def serve(port: int) -> None:
    token = secrets.token_hex(24)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, _format, *_args):
            pass

        def do_GET(self):
            if self.path == "/set":
                self.send_response(303)
                self.send_header("Location", "/check")
                self.send_header("Set-Cookie", f"{COOKIE_NAME}={token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=86400")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if self.path not in ("/", "/check"):
                self.send_error(404)
                return
            cookies = SimpleCookie()
            try:
                cookies.load(self.headers.get("Cookie", ""))
                item = cookies.get(COOKIE_NAME)
                valid = item is not None and secrets.compare_digest(item.value, token)
            except (CookieError, TypeError, ValueError):
                valid = False
            status = "PASS: server received the saved cookie" if valid else "No valid saved cookie received"
            body = ("<!doctype html><meta charset=utf-8><title>Parc Keychain persistence test</title>"
                    "<style>body{font:18px system-ui;max-width:48rem;margin:4rem auto;line-height:1.6}"
                    "a{display:inline-block;margin-right:2rem}</style>"
                    "<h1>Parc Keychain persistence test</h1>"
                    f"<p role=status>{status}</p>"
                    "<p><a href=/set>Save test cookie</a><a href=/check>Check saved cookie</a></p>"
                    "<p>Save once, quit Parc normally, then reopen the same profile and choose Check saved cookie. "
                    "Do not choose Save again after restarting.</p>"
                    "<p>The cookie is HttpOnly and persistent. This page never displays its value. "
                    "Keep the local fixture server running throughout the test.</p>").encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Fixture URL: http://127.0.0.1:{server.server_port}/", flush=True)
    print("Keep this server running until the browser restart check is complete.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=0, help="loopback HTTP port; default chooses a free port")
    parser.add_argument("--inspect-profile", type=Path, help="read-only cookie storage aggregate after normal browser quit")
    args = parser.parse_args()
    if args.inspect_profile:
        return inspect_profile(args.inspect_profile)
    serve(args.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
