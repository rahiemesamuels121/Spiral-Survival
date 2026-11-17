# Spiral Survival 1.2.3 — lobby soundtrack

Version: `1.2.3+17`. Signed universal APK: `dist/spiral-survival-1.2.3-signed.apk`. Android 7.0+. APK SHA-256: `40d09544f044edc370acbd0b61f77cc0282682a054b6bbd01a0869c2f1c447f5`. Signature and 16 KB alignment verified.

The supplied `lobby.mp3` loops across the main menu, local/computer setup and online lobby. Native Android MediaPlayer prepares the bundled track asynchronously, respects audio focus and pauses when backgrounded. All match routes stop music, including resume and online games; dialogs over a match cannot restart it. Speaker controls fit alongside existing controls, preserve Help access and remember mute state. Preferences load before playback, preventing an initial sound when mute was saved. Audio resources are released on leaving the lobby. No audio dependency or new permission is needed.

Validation: 401 Flutter tests pass, including route/dialog behavior, mute persistence, background state and mute controls. Final targeted audio/preview checks pass and static analysis is clean. Exact MP3 bytes and uncompressed packaging were checked in the final APK, together with the native channel and MediaPlayer APIs. Menu/lobby previews were visually inspected. Physical-device listening and audio-interruption checks were not performed. Saves, signing identity and room protocol remain compatible; Firebase rules are unchanged.

# Spiral Survival 1.2.2 — sky-blue birds

Version: `1.2.2+16`. Signed universal APK: `dist/spiral-survival-1.2.2-signed.apk`. Android 7.0+. APK SHA-256: `1c586a1fca56c0e569c3c59b5ba5a98606f4b53102607b13580e7feb23008744`. Signature and 16 KB alignment verified. The bird scheduler explicitly uses Dart’s asynchronous timer, fixing the three compile errors caused by the Flame Timer name collision. Birds return in palette sky blue (`#64C9EE`) every 10–20 seconds, flying for six seconds. A single scheduled timer wakes the scene for each flock; idle rendering continues to stop between flights. Birds stop behind overlays, while the app is backgrounded and when reduced motion is enabled. Timers are cancelled when the game is removed.

Hospital generation is unchanged: each hospital starts with two kits and gains one every five elapsed minutes without a cap, including when nobody occupies the tile. The shop UI refresh timer only updates its visible countdown; it does not control stock generation.

Validation: 397 Flutter tests pass, including idle wake-up, flight completion, reduced motion, hidden/background scenes and hospital stock behavior. Static analysis is clean. No physical-device performance benchmark was performed. Existing saves, package/signing identity and room protocol remain compatible; no Firebase rules change is required.

# Spiral Survival 1.2.1 — idle rendering optimization

Version: `1.2.1+15`. Signed universal APK: `dist/spiral-survival-1.2.1-signed.apk`. Android 7.0+. APK SHA-256: `389358da38ffc0051bad8964e1204b10f20e6fac146fef614a3720469cf70589`. Signature and 16 KB alignment verified. Birds and their scheduling are removed. Branding and the tropical scene remain, with board and backdrop zooming together.

The game now stops the Flame frame ticker once the scene is still and resumes for controller updates, zooming, panning, resize and camera animation. Hidden scenes remain paused when game updates arrive. Forest rendering is skipped when the board covers the whole viewport, and terrain clipping geometry is cached. Hospital stock refresh timers run only while the hospital shop is displayed and stop during Help.

Validation: 395 Flutter tests passed. A frame-count regression check confirms zero board redraws across 60 idle frames, then verifies input wake-up, hidden-update handling and movement completion. Computer turns, Help, movement, zoom and board pixel checks pass. Static analysis is clean, and updated portrait/landscape previews pass. Physical-device FPS, thermal and battery benchmarks were not performed; no measured device-speed gain is claimed. Saves, signing identity and online room protocol remain compatible; no Firebase rules update is required.

# Spiral Survival 1.2.0 — supplied branding and living scenery

Version: `1.2.0+14`. Signed universal APK: `dist/spiral-survival-1.2.0-signed.apk`. Android 7.0+. APK SHA-256: `980de5e0f5a0735cf696c485de86c175e7694df82aa3ba6719e68e5651f99706`. Signature and 16 KB alignment verified. The supplied artwork now appears in the main menu, online lobby, Android launcher and splash screen. The visible app and board names are Spiral Survival. Menus use the artwork's midnight blue and amber colors; forest ground, stones and flowers carry blue, warm stone and lava accents.

The forest now shares the board camera, so zooming and panning move the entire game scene together while controls stay accessible. Small cosmetic bird flocks start 10–20 seconds apart and cross for six seconds. They use the existing game clock, pause with it, respect reduced motion and do not affect turns or online state.

Validation: 397 Flutter tests passed, including timing and reduced-motion checks; static analysis is clean. Main menu, online lobby, portrait, landscape and zoom/bird previews were visually inspected. Physical-device performance testing was not performed. The Android package/signing identity, saved-game keys and room protocol are retained for upgrades. No Firebase rules changes are needed.

# Spiral Quest 1.1.9 — tropical forest terrain

Version: `1.1.9+13`. Install `dist/spiral-quest-1.1.9-signed.apk`. The universal APK supports Android 7.0+ and uses the existing release certificate. Signature and 16 KB alignment were verified. APK SHA-256: `fafdfe74f1e0dc00442648c9c95abdcc4b619afa01a88bcf31b7b9dce8a92b38`.

Exposed space around the board now has tropical forest terrain: palms, ferns, broad leaves, mossy rocks, small flowers and streams. The scenery is cached native vector art and leaves the board artwork unchanged. Portrait and landscape previews were visually inspected (`docs/tropical_forest_portrait_preview.png` and `docs/tropical_forest_landscape_preview.png`).

Validation: 394 Flutter tests passed, including the board pixel-comparison check; static analysis is clean. No physical-device performance testing was performed. Gameplay, keep-screen-on support and Firebase rules remain unchanged; rooms remain compatible with 1.1.7+.

# Spiral Quest 1.1.8 — keep the screen on during matches

Version: `1.1.8+12`. Install `dist/spiral-quest-1.1.8-signed.apk`. The universal APK supports Android 7.0+ and is signed with the existing release certificate. Signature and 16 KB alignment were verified. APK SHA-256: `9e2cd857af896c92da3ee318281bcacb1d20dcbb802a4de75ac3252eacf97472`.

The Android activity now applies `FLAG_KEEP_SCREEN_ON` when GameScreen opens and clears it when the match closes. The flag remains active during handoffs, choices, inventory and in-game Help. Normal timeout returns on exit, and Android does not keep the screen awake when the activity is no longer visible. This does not modify user brightness or timeout preferences and adds no wake-lock permission. Both halves of the platform bridge were checked in the packaged APK.

Validation: 394 Flutter tests passed, including local/online screen lifecycle and keep-awake during in-game Help; static analysis is clean. No physical-device timeout testing was performed. Gameplay protocol and the already-deployed Firebase rules are unchanged, so 1.1.7 rooms remain compatible.

# Spiral Quest 1.1.7 — Secret Society access after landing

Version: `1.1.7+11`. Signed universal APK: `dist/spiral-quest-1.1.7-signed.apk`. Android 7.0+. The signing certificate matches earlier signed releases, and APK signature and 16 KB native-library alignment were verified. APK SHA-256: `f6c91c9998cf77ebcc1edf9aa4aedb6f7ccf16df3edb45e74a5ba5c3033edcb0`.

The previous build ended a Secret Agent's turn immediately after landing nearby, so only pre-roll access was available through a small icon. Secret Agents now get a visible **SECRET SOCIETY · $150** control after landing within three route spaces ahead of or behind the society, plus **END TURN** to skip the optional access. Nearby special-tile effects resolve before this step. Normal spaces have no result popup. The step survives saves, works online and is handled automatically by computer opponents. Hiring after movement does not allow a kill that turn.

All online players need 1.1.7 and a new room (`characters-v3`). The existing deployed Firebase rules already allow the commands used by the fix. No new backend deployment was required. Validation: 394 Flutter tests passed; static analysis is clean. The compiled ARM64 application was checked for the new access state. Physical-device testing was not performed.

# Spiral Quest 1.1.6 — modes, characters and attack-or-move turns

Version: `1.1.6+10`. Install `dist/spiral-quest-1.1.6-signed.apk` (universal, 55.2 MB, Android 7.0+). It uses the existing Spiral Quest release certificate and can update prior builds signed with that certificate. Its SHA-256 checksum is in the adjacent `.sha256` file. Signature and 16 KB alignment were verified.

New matches offer only Cat Whisperer (paw), Secret Agent (badge), and Swimmer (pool). Choose during local setup or the online waiting lobby; characters lock at match start. The in-game character button only shows the selected ability. Online `playerIcon` mutation commands are rejected.

Cat Whisperers pass lions without supplies. Secret Agents gain 3 weapon-range spaces, access Secret Society from up to 3 route spaces away before rolling, and receive $50 off Secret Society purchases ($150 hitman). Swimmers cross sea and SURF without a boat; space 91 now has the Surf water-hazard effect. Legacy local saves retain readable cosmetic avatars.

The main menu now has Pass & Play, VS Computer and Online, with player counts and avatars on separate setup screens. These source changes also include portrait support, hospital stock, Secret Society contracts, VS Computer, and the searchable Help page. Older APKs listed below do not include these changes. The current `firestore.rules` were deployed and verified on November 16, 2026; every participant needs the new build and a new room.

The roll is now committed either to a weapon attack or to movement, with targets chosen from the current space before moving. A hitman kill also ends the turn and cannot follow movement. Newly bought weapons cannot attack after landing. Normal online moves animate without a result popup. The online rules revision is `characters-v2`; all participants need the same new build and a new room.

Validation: 383 Flutter tests, 55 Firestore emulator security checks, and 7 board-editor tests passed; static analysis is clean. A signed universal APK was produced and verified. Firebase rules were deployed on November 16, 2026, and read back to verify an exact source match. Physical-device testing was not performed.

# Spiral Quest 1.1.5 — customizable player icons

Version: `1.1.5+9`. Install `dist/spiral-quest-1.1.5-signed.apk`. Tap a player's circle during local setup or the face button in a game to choose Number, Star, Rocket, Shield, Paw, Lightning, Diamond or Flag. Icons appear on board tokens and player rows, and persist in saved games. Older saves retain numbered tokens.

Online players change their own icon, including outside their turn. The host commits and broadcasts the change without moving tokens, advancing turns, or dismissing results. The tested `playerIcon` command is deployed to Firestore; invalid icons, other-player targets and forged UIDs are rejected. All players should use this version.

Validation: all 320 Flutter tests passed; static analysis is clean; all 33 emulator security checks and 20 live checks passed. The temporary live room and six test accounts were removed. APK signature, version and 16 KB alignment were verified. Physical-device testing was not performed.

# Spiral Quest 1.1.4 — visible online moves and swapped mines

Version: `1.1.4+8`. Install `dist/spiral-quest-1.1.4-signed.apk`. Online players can read each player's move results and tile effects, including ordinary moves. Each device dismisses its own cards with CONTINUE; other players can keep reading while the next player proceeds. Real treatment, shopping, police and portal choices remain with the acting player.

Mine 85 is now green (health pack or hospital); mine 98 is blue (50% death or treatable injury); mine 109 remains red (death). Existing saved custom boards receive this swap once, and new online rooms use the updated board revision. All online players should install this build.

Validation: all 314 Flutter tests passed and static analysis is clean. Tests cover both viewers seeing move details, independently dismissed cards, ordinary-move results, queued turns and saved-board migration. The board exports were regenerated. Physical-device testing was not performed.

# Spiral Quest 1.1.3 — hospital supplies and colored mines

Version: `1.1.3+7`. Install `dist/spiral-quest-1.1.3-signed.apk`, a universal Android APK signed with the existing Spiral Quest release certificate. Its SHA-256 is recorded beside the APK. Earlier APKs remain available under their original filenames.

Hospital purchases update inventory and cash immediately, show confirmation, and explain missing cash. The second to last mine (98) is green: consume one health pack or go to hospital. Mine 85 is broken blue: equal chances of death or a treatable injury. Mine 109 is red and always kills, returning the player to START. All online players need this build and a new room with its updated board revision.

The live Firestore rules now allow hospital purchases and health-pack treatment. The change was limited to those two command names and the item argument; turn ownership and host-authoritative prices remain enforced. All 29 emulator security checks passed before deployment. All 16 live checks then passed, including medical purchases, pack treatment, turn ownership and price protection. The temporary test room and six test accounts were removed.

Validation: 313 Flutter tests passed; static analysis is clean; 7 board editor server tests passed. The board SVG and PNG preview were regenerated and inspected. APK signing and 16 KB alignment were verified. Physical-device testing was not performed.

# Spiral Quest 1.1.2 — release candidate

Version: `1.1.2+6`. The board, setup, turn cards, launcher icons and Android launch screen use the midnight, ivory and antique-gold palette. All game rules and offline save behavior remain supported.

## Installable candidates

`dist/app-armeabi-v7a-release.apk` supports 32-bit ARM devices; `dist/app-arm64-v8a-release.apk` supports 64-bit ARM devices. These are optimized release builds. Without `android/key.properties`, they use the existing development signing identity so local installations can update.

## Final publisher configuration

Choose the publisher's permanent `applicationId` in `android/app/build.gradle.kts` before the first store release. The current identifier is still `com.example.spiral_pass_play`, retained for existing installs and saved games. Changing it creates a separate Android app.

Copy `android/key.properties.example` to `android/key.properties` and enter the production keystore path, alias and passwords locally. The credentials file and keystore extensions are ignored by version control. The build uses production signing automatically when all four properties are present. Keep the keystore and its passwords backed up privately.

Then build the store artifact:

```sh
flutter build appbundle --release
```

Without production signing, this command still uses the development identity and does not produce a store-ready submission. Do not upload that candidate as the production release.

## Verification

Run `flutter analyze` and `flutter test`. The suite covers gameplay, resumed choices, purchases, exact finishing, board pixel equivalence and interface color contrast. Development preview tools render the board, setup, result cards and app icon; see the PNG files in `docs/`.

Before distributing the final signed build, verify it on a physical low-end Android device: start and resume a match, roll and move, choose hospital treatment, buy a weapon, and finish a game. Physical-device performance has not been measured in this workspace.

## Online rooms

Version 1.1 adds Firebase five-player rooms. See [multiplayer configuration](MULTIPLAYER.md). The Android configuration has been applied to the APKs in dist/. Anonymous sign-in, the free-tier Firestore database and room security rules are live in spiral-survival-c4ff0. Live testing verified the five-player cap and synchronized turn commits. Final publisher signing and physical-device release QA remain separate.

Version 1.1.2 embeds the public Firebase client defaults, fixing online availability in ordinary builds that omit Dart defines.
