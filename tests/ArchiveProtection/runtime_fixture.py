#!/usr/bin/env python3
"""Loopback-only fixture for native archive protection; no external resources."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from argparse import ArgumentParser
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
from uuid import uuid4
from array import array
import io
import math
import wave


def seed_profile(directory, port):
    """Create a fresh disposable session; never overwrite an existing profile."""
    directory.mkdir(parents=True, exist_ok=False)
    now = datetime.now(timezone.utc)
    date = lambda hours: (now - timedelta(hours=hours)).strftime('%Y-%m-%dT%H:%M:%SZ')
    identifier = lambda: str(uuid4()).upper()
    work, personal, studio, home = [identifier() for _ in range(4)]
    tabs = []
    for title, age, kind, unread, profile, space in [
        ('Current page', 48, 'today', False, work, studio),
        ('Overdue 48 hours', 48, 'today', False, work, studio),
        ('Recent 18 hours', 18, 'today', False, work, studio),
        ('Unread 48 hours', 48, 'today', True, work, studio),
        ('Pinned 48 hours', 48, 'pinned', False, work, studio),
        ('Favorite 48 hours', 48, 'favorite', False, work, studio),
        ('Personal 18 hours', 18, 'today', False, personal, home),
    ]:
        url = f'http://127.0.0.1:{port}/clean'
        tabs.append(dict(id=identifier(), spaceID=space, profileID=profile,
                         url=url, title=title, kind=kind, createdAt=date(72),
                         lastAccessed=date(age), savedURL=url, savedTitle=title,
                         isMuted=False, isUnread=unread))
    selected = [tabs[0]['id']]
    state = dict(version=1, activeSpaceID=studio,
                 profiles=[dict(id=work, name='Work', autoArchiveHours=24),
                           dict(id=personal, name='Personal', autoArchiveHours=12)],
                 spaces=[dict(id=studio, name='Studio', symbol='circle.fill', color='B9B5D4', profileID=work),
                         dict(id=home, name='Home', symbol='house.fill', color='C8D4B5', profileID=personal)],
                 tabs=tabs, selectedTabIDs=selected, selectionBySpace={studio: selected},
                 autoArchiveStartedAt=date(72), folders=[], splitLayouts=[], history=[],
                 downloads=[], recentlyClosedIDs=[],
                 settings=dict(onboardingComplete=True, restoreSession=True,
                               sidebarWidth=240, searchEngine='https://duckduckgo.com/?q='))
    (directory / 'session.json').write_text(json.dumps(state, indent=2) + '\n')
    print(f'Disposable profile: {directory}', flush=True)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.path == '/tone.wav':
            audio = io.BytesIO()
            with wave.open(audio, 'wb') as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(8000)
                second = array('h', (int(500 * math.sin(2 * math.pi * 220 * i / 8000)) for i in range(8000)))
                output.writeframes(second.tobytes() * 120)
            data = audio.getvalue()
            self.send_response(200)
            self.send_header('Content-Type', 'audio/wav')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path not in ('/', '/form', '/clean', '/media', '/appearance'):
            self.send_error(404)
            return
        form = self.path == '/form'
        title = 'Archive form fixture' if form else 'Archive clean fixture'
        controls = ('<label>Draft text <input aria-label="Draft text" placeholder="Type a local test draft"></label>'
                    '<p>Your text stays in this page. There is no submit action.</p>' if form else
                    '<p>This page has no editable fields or media.</p>')
        if self.path == '/media':
            title = 'Archive media fixture'
            controls = '''<audio id="tone" src="/tone.wav" preload="none"></audio>
                <p>A quiet generated tone tests active and paused native media protection.</p>
                <button id="play">Play tone</button> <button id="pause">Pause tone</button>
                <button id="stop">Stop tone</button><p id="status" role="status">Not started</p>
                <script>
                const tone = document.getElementById('tone'), status = document.getElementById('status');
                document.getElementById('play').onclick = async () => {
                    if (!tone.getAttribute('src')) tone.src = '/tone.wav';
                    await tone.play(); navigator.mediaSession.playbackState = 'playing'; status.textContent = 'Playing';
                };
                document.getElementById('pause').onclick = () => {
                    tone.pause(); navigator.mediaSession.playbackState = 'paused'; status.textContent = 'Paused';
                };
                document.getElementById('stop').onclick = () => {
                    tone.pause(); tone.removeAttribute('src'); tone.load();
                    navigator.mediaSession.playbackState = 'none'; status.textContent = 'Stopped';
                };
                </script>'''
        if self.path == '/appearance':
            title = 'Document appearance fixture'
            controls = '''<p>This document supplies no canvas background.</p>
                <p id="preference"></p>
                <div style="padding:1rem;background:white;color:black">Explicit light CSS: black text on white</div>
                <div style="padding:1rem;background:#202124;color:#f1f3f4">Explicit dark CSS: light text on dark</div>
                <button id="dark">Use CSS dark color scheme</button>
                <button id="light">Use CSS light color scheme</button>
                <p id="scheme">CSS color scheme: normal</p>
                <script>
                const query = matchMedia('(prefers-color-scheme: dark)');
                const report = () => document.getElementById('preference').textContent =
                    'System color preference: ' + (query.matches ? 'dark' : 'light');
                query.addEventListener('change', report); report();
                for (const name of ['dark', 'light']) document.getElementById(name).onclick = () => {
                    document.documentElement.style.colorScheme = name;
                    document.getElementById('scheme').textContent = 'CSS color scheme: ' + name;
                };
                </script>'''
        page = ('<!doctype html><meta charset="utf-8"><title>' + title + '</title>'
                '<style>body{font:18px system-ui;max-width:44rem;margin:4rem auto;line-height:1.6}'
                'input{font:inherit;padding:.5rem;width:22rem}a{margin-right:2rem}</style>'
                '<h1>' + title + '</h1>' + controls +
                '<p><a href="/clean">Clean page</a><a href="/form">Form page</a><a href="/media">Media page</a></p>').encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(page)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(page)


if __name__ == '__main__':
    parser = ArgumentParser(description=__doc__)
    parser.add_argument('--seed-profile', type=Path,
                        help='Create a new disposable session with aged tabs and two archive policies.')
    parser.add_argument('--port', type=int, default=0, help='Loopback port; defaults to an available port.')
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    if args.seed_profile:
        seed_profile(args.seed_profile, server.server_port)
    print(f'Clean fixture: http://127.0.0.1:{server.server_port}/clean', flush=True)
    print(f'Form fixture: http://127.0.0.1:{server.server_port}/form', flush=True)
    print(f'Media fixture: http://127.0.0.1:{server.server_port}/media', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
