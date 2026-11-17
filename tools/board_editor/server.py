#!/usr/bin/env python3
"""Dependency-free, loopback-only board editor. No game builds or cloud calls."""
from __future__ import annotations
import argparse
import copy
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import secrets
import tempfile
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit
import webbrowser
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TYPES = ('start normal sea surf boat antidote rawMeat lion snake cash police fine jail '
         'goToJail mine portal setBack moveForward shop event confusion star hospital secretSociety fire trapDoor finish').split()
ARTWORK = ('none spiral boat water skull antidote snake cash police jail mine portal back forward shop '
           'dice star stop jet fire diamond train surf lion rawMeat hospital secretSociety trapDoor confusion startFlag').split()


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def validate(board):
    errors = []
    if not isinstance(board, dict):
        return ['The board must be a JSON object.']
    if board.get('version') != 2:
        errors.append('The board file must use version 2.')
    if not isinstance(board.get('id'), str) or not 1 <= len(board['id']) <= 100:
        errors.append('The board needs an ID of 1–100 characters.')
    tiles = board.get('tiles')
    if not isinstance(tiles, list) or len(tiles) != 120:
        return errors + ['This game needs exactly 120 tiles.']
    if board.get('startIndex') != 0 or board.get('finishIndex') != 119:
        errors.append('START must be tile 0 and FINISH must be tile 119.')
    for i, tile in enumerate(tiles):
        prefix = f'Tile {i}: '
        if not isinstance(tile, dict):
            errors.append(prefix + 'must be an object.')
            continue
        kind = tile.get('type')
        if not isinstance(kind, str):
            kind = ''
        if type(tile.get('index')) is not int or tile['index'] != i:
            errors.append(prefix + 'route indices must stay in order.')
        if kind not in TYPES:
            errors.append(prefix + 'unknown effect.')
        if (i == 0 and kind != 'start') or (i == 119 and kind != 'finish') or (0 < i < 119 and kind in ('start', 'finish')):
            errors.append(prefix + 'START and FINISH are locked to the route endpoints.')
        if not isinstance(tile.get('label', ''), str) or len(tile.get('label', '')) > 80:
            errors.append(prefix + 'label must be at most 80 characters.')
        for axis in ('x', 'y'):
            if not number(tile.get(axis)) or not 0 <= tile[axis] <= 1:
                errors.append(prefix + f'{axis.upper()} must be between 0% and 100%.')
        amount = tile.get('amount', 0)
        if type(amount) is not int or not 0 <= amount <= 1_000_000:
            errors.append(prefix + 'amount must be a whole number between 0 and 1000000.')
        elif kind in ('setBack', 'moveForward') and amount < 1:
            errors.append(prefix + 'movement needs at least one space.')
        destination = tile.get('destination')
        if destination is not None and (type(destination) is not int or not 0 <= destination < 120):
            errors.append(prefix + 'destination must be a tile number from 0 to 119.')
        if tile.get('mineColor', 'red') not in ('red', 'blue', 'green'):
            errors.append(prefix + 'unknown mine color.')
        required = 'hospital' if kind == 'mine' and tile.get('mineColor', 'red') != 'red' else {'snake': 'antidote', 'goToJail': 'jail', 'fire': 'hospital', 'trapDoor': 'hospital', 'lion': 'hospital'}.get(kind)
        if required and (type(destination) is not int or not 0 <= destination < 120 or not isinstance(tiles[destination], dict) or tiles[destination].get('type') != required):
            errors.append(prefix + f'choose a {required.upper()} destination.')
        if kind == 'police' and not any(isinstance(t, dict) and t.get('type') == 'jail' for t in tiles):
            errors.append(prefix + 'police requires at least one JAIL on the board.')
        if tile.get('artwork') is not None and tile['artwork'] not in ARTWORK:
            errors.append(prefix + 'unknown illustration.')
        if tile.get('consumesAntidote') is not None and type(tile['consumesAntidote']) is not bool:
            errors.append(prefix + 'antidote consumption must be true or false.')
        for key in ('fillColor', 'textColor'):
            if tile.get(key) is not None and (type(tile[key]) is not int or not 0 <= tile[key] <= 0xffffffff):
                errors.append(prefix + 'colors must be valid 32-bit colors.')
        for key in ('width', 'height'):
            if tile.get(key) is not None and (not number(tile[key]) or not .02 <= tile[key] <= .2):
                errors.append(prefix + 'legacy dimensions must be between 2% and 20%.')
    return errors


def prepared(board):
    result = copy.deepcopy(board)
    errors = validate(result)
    if errors:
        raise ValueError('\n'.join(errors))
    json.dumps(result, allow_nan=False)  # Reject non-standard JSON in extra metadata too.
    # Only tile contents/layout affect room compatibility, not file formatting.
    canonical = json.dumps(result['tiles'], sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False).encode()
    result['onlineBoardId'] = 'spiral-quest-board-' + hashlib.sha256(canonical).hexdigest()[:12]
    return result


def encoded(board):
    return (json.dumps(board, indent=2, ensure_ascii=True, allow_nan=False) + '\n').encode()


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


class Store:
    def __init__(self, root):
        self.root = Path(root)
        self.board_path = self.root / 'assets/boards/spiral_board_map.json'
        self.csv_path = self.root / 'docs/board_tiles.csv'
        self.backups = self.root / 'tools/board_editor/backups'
        self.lock = threading.Lock()

    def read(self):
        raw = self.board_path.read_bytes()
        return {'board': json.loads(raw), 'digest': hashlib.sha256(raw).hexdigest()}

    def save(self, board, expected):
        data = prepared(board)
        with self.lock:
            old = self.board_path.read_bytes()
            if not isinstance(expected, str) or hashlib.sha256(old).hexdigest() != expected:
                raise FileExistsError('The game board changed outside this editor. Download your edits, then reload the game board before saving.')
            stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')
            backup = self.backups / f'board-{stamp}-{secrets.token_hex(3)}.json'
            atomic_write(backup, old)
            headers = ['index', 'segment', 'x', 'y', 'label', 'type', 'amount', 'destination', 'consumesAntidote', 'mineColor']
            output = io.StringIO(newline='')
            writer = csv.DictWriter(output, fieldnames=headers, lineterminator='\n')
            writer.writeheader()
            for tile in data['tiles']:
                row = {key: '' if tile.get(key) is None else tile[key] for key in headers}
                row['consumesAntidote'] = int(bool(tile.get('consumesAntidote')))
                writer.writerow(row)
            atomic_write(self.board_path, encoded(data))
            atomic_write(self.csv_path, output.getvalue().encode())
            return {**self.read(), 'backup': str(backup.relative_to(self.root))}


class EditorServer(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, root=ROOT):
        self.store = Store(root)
        self.token = secrets.token_urlsafe(32)
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        if args and str(args[0]).startswith('5'):
            super().log_message(fmt, *args)

    def reply(self, status, data, content_type='application/json; charset=utf-8'):
        if isinstance(data, (dict, list)):
            data = json.dumps(data).encode()
        if isinstance(data, str):
            data = data.encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(data)

    def local_request(self):
        port = self.server.server_port
        allowed = {f'127.0.0.1:{port}', f'localhost:{port}'}
        if self.headers.get('Host') not in allowed:
            self.reply(403, {'error': 'Only local editor requests are accepted.'})
            return False
        origin = self.headers.get('Origin')
        if origin and origin not in {f'http://{host}' for host in allowed}:
            self.reply(403, {'error': 'Cross-origin requests are blocked.'})
            return False
        return True

    def do_GET(self):
        if not self.local_request():
            return
        path = urlsplit(self.path).path
        try:
            if path == '/api/info':
                identity = hashlib.sha256(str(self.server.store.root.resolve()).encode()).hexdigest()[:12]
                self.reply(200, {'application': 'spiral-board-workshop', 'project': identity})
            elif path == '/api/board':
                self.reply(200, self.server.store.read())
            elif path == '/':
                page = (HERE / 'index.html').read_text().replace('__EDITOR_TOKEN__', self.server.token)
                self.reply(200, page, 'text/html; charset=utf-8')
            elif path in ('/editor.js', '/editor.css', '/icons.svg'):
                mime = {'/editor.js': 'text/javascript; charset=utf-8', '/editor.css': 'text/css; charset=utf-8', '/icons.svg': 'image/svg+xml'}[path]
                self.reply(200, (HERE / path[1:]).read_bytes(), mime)
            elif path == '/favicon.ico':
                self.reply(204, b'')
            else:
                self.reply(404, {'error': 'Not found.'})
        except (OSError, ValueError):
            self.reply(500, {'error': 'Could not read the board files. Check the project folder.'})

    def do_POST(self):
        if not self.local_request():
            return
        if self.headers.get('X-Editor-Token') != self.server.token:
            self.reply(403, {'error': 'Reload the editor before saving.'})
            return
        if self.headers.get_content_type() != 'application/json':
            self.reply(415, {'error': 'Expected board JSON.'})
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 1_000_000:
                self.reply(413, {'error': 'Board JSON must be smaller than 1 MB.'})
                return
            body = json.loads(self.rfile.read(size))
            if not isinstance(body, dict):
                raise ValueError('Expected a board object.')
            path = urlsplit(self.path).path
            if path == '/api/save':
                self.reply(200, self.server.store.save(body.get('board'), body.get('expectedDigest')))
            elif path == '/api/export':
                self.reply(200, {'board': prepared(body.get('board'))})
            else:
                self.reply(404, {'error': 'Not found.'})
        except FileExistsError as error:
            self.reply(409, {'error': str(error)})
        except (ValueError, TypeError, RecursionError) as error:
            self.reply(400, {'error': str(error) or 'Invalid board JSON.'})
        except OSError:
            self.reply(500, {'error': 'Could not write the source files. Your edits are still in the browser; download a copy.'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--no-browser', action='store_true')
    args = parser.parse_args()
    try:
        server = EditorServer(('127.0.0.1', args.port))
    except OSError:
        url = f'http://127.0.0.1:{args.port}'
        if not args.no_browser:
            try:
                with urllib.request.urlopen(url + '/api/info', timeout=2) as response:
                    existing = json.load(response)
                identity = hashlib.sha256(str(ROOT.resolve()).encode()).hexdigest()[:12]
                if existing == {'application': 'spiral-board-workshop', 'project': identity}:
                    webbrowser.open(url)
                    print(f'Opened the running Board Workshop: {url}')
                    return
            except (OSError, ValueError):
                pass
        parser.exit(1, 'Port is in use. Close the previous editor or start with --port 8766.\n')
    url = f'http://127.0.0.1:{server.server_port}'
    print(f'Board Workshop: {url}\nKeep this window open. Press Ctrl+C to stop.\n', flush=True)
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
