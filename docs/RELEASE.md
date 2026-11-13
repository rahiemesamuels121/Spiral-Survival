# Spiral Quest 1.0.0 — release candidate

Version: `1.0.0+3`. The board, setup, turn cards, launcher icons and Android launch screen use the midnight, ivory and antique-gold palette. All game rules and offline save behavior remain supported.

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
