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
