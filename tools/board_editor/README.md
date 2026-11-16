# Board Workshop

A small local helper for editing the Spiral Quest board. No installation, Flutter SDK, npm packages or internet connection is needed to use it. It requires Python 3 and a modern browser. The helper files total about 75 KB; the editor stays separate from the Android game.

## Open it

On this Mac, double-click **Open Board Editor.command** in this folder. Keep the Terminal window open while editing. It opens `http://127.0.0.1:8765` in your browser. If the same editor is already running, the launcher opens it again.

Or run from the project folder:

```sh
python3 tools/board_editor/server.py
```

Press Ctrl+C in its Terminal window to stop the helper. To use another local port, add `--port 8766`.

## Edit your board

- Click a tile, or enter its number and click **Go**.
- Choose the effect, label, amount and destination, then **Apply tile changes**. Moving to another tile also applies valid pending form fields.
- Use **Swap tiles** to exchange effects, labels, illustrations and colors without moving the tiles.
- Expand **Position & illustration** to change coordinates, artwork or colors.
- Turn on **Move tiles** to drag a tile. **Snap to grid** keeps the regular 62-unit spacing. Drag empty space to pan; scroll or use the buttons to zoom.
- **Restore spiral layout** restores the symmetrical grid while keeping tile contents.
- START and FINISH roles stay locked. Required destinations are checked: snakes need an antidote, and lions/fire/trap doors need a hospital. Unfinished rule links are highlighted and block saving until fixed.
- **Undo / Redo** keeps the last 80 changes. Browser drafts are restored when reopening the same local address if the source board is unchanged.

The preview uses illustrations extracted from the game's vector artwork. Fallback symbols cover illustrations not present on the current board. Game-specific behavior, such as the hospital's fixed ten-coin charge, is described next to the effect rather than exposed as an unsupported setting.

## Save

**Save to game** updates only these source files:

- `assets/boards/spiral_board_map.json`
- `docs/board_tiles.csv`

Before each save, the exact previous JSON is backed up in `tools/board_editor/backups/`. To recover one, open that JSON in the helper and save it to the game. The helper refuses to overwrite a board that changed in another tab or program since it was loaded.

**Save a copy** downloads a valid JSON board without changing the project. **Open JSON** imports a copy for editing; it only affects the project if you later choose **Save to game**.

Saving edits source files. It does **not** modify an already installed game, create APKs, deploy Firebase settings or change active rooms. Build the game later to use the new board. Local board IDs remain stable; online board IDs are generated from tile contents/layout to stop builds with different boards from sharing a room. All online players need the same edited build and a new room. Old device-specific custom boards remain separate from the built-in board.

The game renders directly from JSON. Static SVG/PNG development previews can be regenerated separately with `flutter test tools/export_vector_board.dart`; the helper does not require or invoke Flutter.

## Developer verification

The server binds only to `127.0.0.1`. It has no remote dependencies, blocks foreign origins/hosts, requires a per-session write token, accepts only board JSON and cannot write arbitrary paths. All tests use temporary copies or mock source writes.

```sh
python3 -B -m unittest discover -s tools/board_editor -p 'test_*.py' -v
```

Optional UI-logic tests use jsdom as a development-only test dependency. It is not needed to run the helper:

```sh
npm install --prefix /tmp/spiral-board-editor-qa jsdom
# Start the helper separately, then:
NODE_PATH=/tmp/spiral-board-editor-qa/node_modules node tools/board_editor/test_editor.cjs
```
