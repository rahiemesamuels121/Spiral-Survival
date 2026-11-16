"""Run: python3 -B -m unittest discover -s tools/board_editor -p 'test_*.py'."""
import copy
import hashlib
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from server import ROOT, EditorServer, Store, prepared, validate


class EditorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / 'assets/boards/spiral_board_map.json'
        self.path.parent.mkdir(parents=True)
        self.original = (ROOT / 'assets/boards/spiral_board_map.json').read_bytes()
        self.path.write_bytes(self.original)
        self.board = json.loads(self.original)
        self.store = Store(self.root)

    def changed(self, amount=25):
        board = copy.deepcopy(self.board)
        board['tiles'][1].update(type='cash', label='CASH', amount=amount)
        return board

    def test_current_board_is_compatible_and_export_does_not_mutate_it(self):
        self.assertEqual(validate(self.board), [])
        source = self.changed()
        before = copy.deepcopy(source)
        exported = prepared(source)
        self.assertTrue(exported['onlineBoardId'].startswith('spiral-quest-board-'))
        self.assertEqual(exported['version'], 2)
        self.assertEqual(self.path.read_bytes(), self.original)
        self.assertEqual(source, before)

    def test_rejects_broken_rule_destinations_and_route_endpoints(self):
        for index, changes in [(87, {'destination': 89}), (0, {'type': 'normal'}), (119, {'type': 'star'}), (1, {'index': 42}), (1, {'x': float('nan')}), (1, {'amount': True}), (1, {'fillColor': -1}), (85, {'mineColor': 'orange'}), (98, {'destination': 10})]:
            with self.subTest(index=index, changes=changes):
                board = copy.deepcopy(self.board)
                board['tiles'][index].update(changes)
                self.assertTrue(validate(board))
                with self.assertRaises(ValueError):
                    prepared(board)

    def test_save_creates_exact_backup_and_updates_csv(self):
        before = self.store.read()
        result = self.store.save(self.changed(), before['digest'])
        self.assertEqual((self.root / result['backup']).read_bytes(), self.original)
        self.assertEqual(result['board']['tiles'][1]['amount'], 25)
        self.assertIn('1,spiral-leg-0,0.066,0.128,CASH,cash,25,,0', self.store.csv_path.read_text())
        self.assertEqual(result['digest'], hashlib.sha256(self.path.read_bytes()).hexdigest())

    def test_stale_editor_cannot_overwrite_newer_changes(self):
        before = self.store.read()
        saved = self.store.save(self.changed(), before['digest'])
        with self.assertRaises(FileExistsError):
            self.store.save(self.changed(50), before['digest'])
        self.assertEqual(self.store.read()['digest'], saved['digest'])
        self.assertEqual(len(list(self.store.backups.glob('*.json'))), 1)

    def test_simultaneous_saves_have_one_winner_and_one_backup(self):
        digest = self.store.read()['digest']
        barrier = threading.Barrier(2)
        def save(amount):
            barrier.wait()
            try:
                self.store.save(self.changed(amount), digest)
                return 'saved'
            except FileExistsError:
                return 'conflict'
        with ThreadPoolExecutor(max_workers=2) as executor:
            self.assertCountEqual(list(executor.map(save, [25, 50])), ['saved', 'conflict'])
        self.assertEqual(len(list(self.store.backups.glob('*.json'))), 1)

    def test_online_revision_changes_only_when_tiles_change(self):
        first = prepared(self.board)['onlineBoardId']
        metadata = copy.deepcopy(self.board)
        metadata['title'] = 'Another title'
        self.assertEqual(first, prepared(metadata)['onlineBoardId'])
        self.assertNotEqual(first, prepared(self.changed())['onlineBoardId'])

    def test_http_validation_csrf_and_origin_checks(self):
        server = EditorServer(('127.0.0.1', 0), self.root)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        port = server.server_port
        def request(method, path, body=None, token=None, origin=None, host=None):
            client = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
            headers = {'Content-Type': 'application/json'}
            if token is not None:
                headers['X-Editor-Token'] = token
            if origin:
                headers['Origin'] = origin
            if host:
                headers['Host'] = host
            client.request(method, path, None if body is None else json.dumps(body), headers)
            response = client.getresponse()
            result = (response.status, response.read(), response.getheader('Content-Security-Policy'))
            client.close()
            return result
        status, page, csp = request('GET', '/')
        self.assertEqual(status, 200)
        self.assertIn(server.token.encode(), page)
        self.assertIn("frame-ancestors 'none'", csp)
        body = {'board': self.changed(), 'expectedDigest': self.store.read()['digest']}
        self.assertEqual(request('POST', '/api/save', body)[0], 403)
        self.assertEqual(request('POST', '/api/save', body, server.token, 'https://other.example')[0], 403)
        self.assertEqual(request('GET', '/api/board', host='evil.example')[0], 403)
        self.assertEqual(request('GET', '/../firebase_client.json')[0], 404)
        status, exported, _ = request('POST', '/api/export', body, server.token)
        self.assertEqual(status, 200)
        self.assertIn('onlineBoardId', json.loads(exported)['board'])
        self.assertEqual(self.path.read_bytes(), self.original)
        self.assertEqual(request('POST', '/api/save', body, server.token)[0], 200)
        self.assertEqual(request('POST', '/api/save', body, server.token)[0], 409)


if __name__ == '__main__':
    unittest.main()
