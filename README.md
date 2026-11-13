# Spiral Quest 1.0

An offline Flutter + Flame board game for 2–5 players sharing one Android device. The board has 120 equally spaced tiles in a square spiral. Roll, follow the route, resolve the tile, then pass the device. An exact roll is required to finish.

The board editor and Android board import/export channel have been removed from the app. Existing saved boards and matches remain supported, including one-time rule and layout migrations.

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
