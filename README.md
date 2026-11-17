# Spiral Survival 1.2.3

## Lobby soundtrack — 1.2.3

The supplied `lobby.mp3` loops across the main menu, local/computer setup and online lobby. It stops for matches and while the app is backgrounded. A speaker button on each lobby/setup screen toggles music and remembers the mute preference. The track is bundled for offline playback, plays at a moderate level through the device media volume, and respects Android audio focus. No audio package or new permission is needed.

## Blue birds — 1.2.2

Bird flocks return in palette sky blue (`#64C9EE`). One timer schedules flights 10–20 seconds apart; idle rendering stops between six-second flights. Hidden scenes, backgrounded apps and reduced-motion settings disable the birds. Hospital kits still replenish by elapsed time every five minutes, whether anyone is on the tile or not. Only the visible shop countdown uses a UI refresh timer.

## Rendering and power use — 1.2.1

Bird animation has been removed. The scene stops its frame ticker once the board and camera settle, then wakes for input and controller updates. Hidden screens remain paused when online updates arrive. Forest drawing is skipped when the board covers the viewport, and its clipping geometry is reused. Hospital countdown refreshes run only while the hospital shop is visible. The tropical background continues to zoom and pan with the board.

## Spiral Survival branding — 1.2.0

The supplied Spiral Survival artwork brands the main menu, online lobby, Android launcher and splash screen. The midnight blue, amber and red palette carries through setup and menus. The tropical forest and board share one zoom/pan transform. Package IDs and saved-game keys stay compatible with previous signed releases.

A Flutter + Flame board game with offline pass-and-play, offline VS Computer and private online rooms for 2–5 players. Local play uses one shared Android device; online rooms use a device for each player. Gameplay supports portrait and landscape, with controls adapting when the device rotates. Online setup for the `spiral-survival-c4ff0` Firebase project is documented in [multiplayer setup](docs/MULTIPLAYER.md). Each room supports at most five players.

The board has 120 equally spaced tiles in a square spiral. Roll, follow the route, resolve the tile, then pass the device. An exact roll is required to finish.

The in-game board editor and Android board import/export channel remain removed from the app. A separate, dependency-free local helper is now available: [Board Workshop](tools/board_editor/README.md). Double-click `tools/board_editor/Open Board Editor.command` to open it. Existing saved boards and matches remain supported, including one-time rule and layout migrations.

## Run and verify

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

For smaller, optimized Android builds, generate a separate release APK for each ARM architecture:

```sh
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

Fresh build outputs are in `build/app/outputs/flutter-apk/`. Verified ARM release candidates are kept in `dist/`. See [release configuration](docs/RELEASE.md) for production signing and the final publisher application ID.

## Tropical forest terrain — 1.1.9

The exposed space around the board now shows a tropical forest floor with palms, broad leaves, ferns, mossy rocks and a winding stream. The board's tiles and original artwork are unchanged. The terrain fills both portrait and landscape layouts, including the side space visible when zooming out. It is recorded as a native vector picture once per viewport size, clipped out beneath the opaque board, and disposed on exit. It adds no image downloads, bitmap asset or animated background work.

Portrait and landscape previews are in `docs/tropical_forest_portrait_preview.png` and `docs/tropical_forest_landscape_preview.png`. Regenerate with `flutter test tools/export_ui_previews.dart`.

## Screen timeout — 1.1.8

An open match keeps the Android screen on during gameplay, decisions, handoffs and the in-game help page. Leaving the match restores normal screen timeout. This uses the visible activity's keep-screen-on flag, so backgrounding the app does not hold a background wake lock. It does not change the user's brightness setting or system timeout preference.

## Secret Society landing access fix — 1.1.7

When a Secret Agent lands within three route spaces ahead of or behind Secret Society (spaces 57–63 around tile 60), their turn stays open with a visible **SECRET SOCIETY · $150** control and an **END TURN** button. Normal spaces do not open a result popup. Special-tile effects resolve first, then nearby access becomes available. Hiring after movement does not allow an attack with the same turn; keep the contract until a later turn. This optional access state is saved and supported online and by computer opponents. All online players need version 1.1.7 and a new room; the already-deployed Firebase rules support the fix.

## Character classes

Choose a character during local setup or in the online waiting lobby. There are only three choices, and the class is locked when the match starts:

- **Cat Whisperer (paw):** pass lions without raw meat, injury or consuming health kits.
- **Secret Agent (badge):** access Secret Society from up to 3 route spaces away before rolling or after landing nearby; +3 weapon range, giving Stabber 8 spaces and Pew pew 13; $50 off each Secret Society purchase. The hitman costs $150 instead of $200. Hospital and ordinary weapon-shop prices are unchanged.
- **Swimmer (pool):** cross sea/water and SURF spaces without a boat. SURF at space 91 is now a water hazard for other characters.

Computer opponents also receive classes. Existing saved matches keep legacy cosmetic avatars; these older options cannot be selected for new games. New online rooms use a character-rules board revision so older builds cannot join. The updated Firebase rules were deployed and verified on November 16, 2026: lobby edits affect only the sender's character, freeze on start, and in-game avatar-change requests are rejected.

## Computer opponents and Help

The main menu has **PASS & PLAY**, **VS COMPUTER** and **ONLINE**. Choose a mode first. Local modes open a separate screen for player/opponent count, names and avatars; Online opens room and lobby character selection. Choose **VS COMPUTER**, then enter your name and select 1–4 computer opponents. Computers use the same dice and rules, make their own treatment, shop, police, portal and attack choices, and return control to you without a pass-device prompt. The computer prioritizes opponents farther along the route and keeps a small supply budget; there are no difficulty settings or advantages to its dice. Local saves retain the computer seats and resume their turns automatically.

**HOW TO PLAY & TILE GUIDE** is available from the main menu and the in-game Players and inventory panel. It explains modes, turns, winning, supplies, weapons and board controls. The searchable tile guide covers every supported tile type, including all mine colors, hospital stock and Secret Society contracts, and lists matching spaces on the current board. Computer decisions pause while the inventory panel or Help is open; the board also pauses while Help covers it.

## Hospital stock and Secret Society

Each hospital starts with two health kits and produces one every five real minutes, without a stock cap. Supply purchases share that hospital's stock across players. Empty stock disables kit purchases; antidotes and paid injury treatment remain available. Saved matches retain stock and refill timing, including time spent away from the app.

Space 60 is now **Secret Society**. Land there to hire the single hitman for $200 and place him on any numbered space. Secret Agents can also hire from up to 3 route spaces away in either direction, before rolling or after landing nearby, using the labeled Secret Society control, and pay $150. Only the hirer sees his marker and private contract controls. Before rolling on a later turn, the hirer can choose one opponent within 20 route spaces in either direction. A kill returns the target to START, gives no cash or stars, releases the hitman for another hire and ends the hirer’s turn without movement. A hitman hired after landing must wait until a later turn to attack. The hirer's identity and placement are omitted from public messages.

Online play uses separate host authority and player-private documents so opponents do not receive contract details or account balances. The host remains trusted and can inspect the full state. The updated `firestore.rules` are deployed and verified against the local source; all players must use the new build and create a new room. Existing local matches and saved boards remain supported.

## Attack or move

A qualifying roll is used either for a weapon attack or for movement, never both. Rolls of 4–5 allow same-space attacks; a 6 allows targets within the weapon's range from the current space. The choice appears before movement. Buying a weapon after moving does not allow an attack with the same roll. Hitman kills also end the turn without movement. Normal tile landings animate and continue without a result popup, including online games.

## Board source

- `assets/boards/spiral_board_map.json` is the only bundled board asset.
- `lib/features/game/vector/` draws the board and tile illustrations.
- `assets/boards/spiral_board.svg` and `docs/vector_board_preview.png` are development exports, excluded from the app bundle.
- `docs/board_tiles.csv` lists the route and rules.

Regenerate the SVG and preview after changing the board:

```sh
flutter test tools/export_vector_board.dart
```

See [board rules](docs/BOARD_MAPPING.md) and [weapons](docs/WEAPONS.md).

## Low-end device optimizations

The static board is recorded once as a native vector picture and replayed during movement and camera gestures. This avoids rebuilding paints, gradients, paths and text layouts every frame, without a large bitmap cache or loss of zoom sharpness. Native pictures are disposed when removed and recreated on remount.

Portal movement effects use simple strokes rather than blur filters and shader glows. The game loop pauses behind full-screen result, choice and handoff screens. Result illustrations reuse vector scenes and paints. Saves use immutable JSON snapshots, skip duplicate snapshots, and preserve write order. Saved-board migrations write the final upgraded board once rather than serializing every intermediate upgrade.

Performance on physical low-end devices still requires release-mode testing; automated rendering checks verify that the cached board preserves the original pixels.

The premium interface uses midnight navy, antique gold and warm ivory, with semantic tile colors and numbered player markers. Android launcher and launch-screen artwork match the game. Regenerate launcher icons with `flutter test tools/export_app_icon.dart` and UI previews with `flutter test tools/export_ui_previews.dart`.

Normal `flutter run` and `flutter build` commands include the generated Firebase client defaults. Extra Dart defines are optional overrides. The Firebase backend is deployed and billing remains disabled.
