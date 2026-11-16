# Firebase online rooms — spiral-survival-c4ff0

The app now supports private 8-character room codes, anonymous player identities, 2–5 players per room, host-started matches, synchronized turns and same-device reconnection. Local pass-and-play and its saved match remain separate.

## Connect this Firebase project

The project ID is already set to `spiral-survival-c4ff0`. The supplied Android client configuration has been validated and converted to firebase_client.json locally. Anonymous Authentication is enabled, the default Firestore Standard database is live in us-east1 with freeTier=true, and the included rules and index exclusions are deployed. Billing remains disabled.

1. In Firebase Project settings, register the Android package `com.example.spiral_pass_play` (or first choose your final publisher ID). Download that app's `google-services.json`.
2. From this project directory, run:

   ```sh
   dart tools/configure_firebase.dart /absolute/path/to/google-services.json
   ```

   This verifies the project and package, then produces `lib/firebase_client_defaults.dart` and `firebase_client.json` with public client identifiers. An Admin SDK/service-account key is neither needed nor accepted.

3. In Firebase Authentication, enable **Anonymous** sign-in. Create the default **Cloud Firestore Standard** database if it does not exist. Keep the project on the Spark plan; this implementation does not use Cloud Functions, Cloud Storage, phone authentication or paid TTL cleanup.
4. Sign in to Firebase CLI and deploy the included rules and index exclusions. These rules cover game rooms only; merge them with any rules already serving other apps in this project before deployment:

   ```sh
   npx firebase-tools login
   npx firebase-tools deploy --only auth,firestore --project spiral-survival-c4ff0
   ```

5. Build the connected app:

   ```sh
   flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
   ```

The Flutter app initializes Firebase directly from the generated public defaults, so standard run/build commands work without extra flags or a Google Services Gradle plugin. Keep firebase_client_defaults.dart with the app source. Never use signing passwords or service-account keys as client configuration.

## Play

Choose **PLAY ONLINE**, enter your name, and create a room or enter a friend's room code. The host can start with 2–5 players. A sixth player is rejected by both a Firestore transaction and security rules, including simultaneous joins. Seats freeze once the game starts. Reconnect on the same installation to reclaim the same anonymous identity and seat.

The host must keep the room open. Going back from the game to the lobby keeps hosting; closing the room ends it for everyone. Guests can disconnect during a match and reconnect, but their seat is retained. If a guest never returns, the match waits at that seat. Host departure pauses play; this version does not elect another host.

Each player sees their own cash, debt and carried items in the game interface, including while another player takes a turn. Other players' rows show their names and board positions. Hospital, shopping, police, weapon and portal decisions appear only on the acting player's device. Online move result cards show every player's roll and its effects, including changes caused by special tiles. Ordinary moves also have a result card showing the starting and ending spaces. Inventory panels continue to show only the viewer's totals.

Players can use the face button to change their own board icon, even outside their turn. The host applies the `playerIcon` request only to the sender's seat and broadcasts the saved icon to everyone. Icons do not consume turns or alter gameplay.

Online result screens dismiss independently on each device. **CONTINUE** closes only that player's local result; it does not send a game action or wait for other players to continue. The next player can dismiss their result and take their turn while someone else is still reading. Choices that affect play, such as treatment, purchases, police penalties and portal cards, still require the acting player's decision.

## Authority and synchronization

Guests submit a small action document under their own authenticated UID. They cannot write game state, choose dice, impersonate another seat or act outside their turn. The host applies the existing Dart rules and commits the result plus a movement instruction atomically with request deletion. Revisions reject stale commands and duplicate races. Each device applies the latest authoritative state immediately and queues committed movements and result screens locally; token positions are not streamed every frame. Slower devices finish their queued movement animations in order without delaying other players' turns.

The host is trusted in this friend-room design and can control the authoritative state. It is not a competitive anti-cheat server. Cash and inventory privacy applies to the game interface: synchronization still sends the full match state to connected clients, and the host can inspect it. This does not provide cryptographic secrecy or per-player server isolation. Room codes are private invitations, not passwords for confidential data; authenticated players who know a code can read that room. Room directory queries and arbitrary database access are denied.

## Spark usage

Firestore's published free quotas are currently 50,000 reads/day, 20,000 writes/day, 1 GiB stored and 10 GiB/month outbound transfer. These are project-wide limits, not a promise of unlimited free rooms. Sources: [Firestore quotas](https://firebase.google.com/docs/firestore/quotas), [Firebase plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans).

Each game action normally uses one request write, one room-state write and one request deletion, plus transaction reads and room listeners. Only the host listens to pending requests. One host heartbeat every 45 seconds keeps reconnection status current. Room state and outcome fields are excluded from indexing. Rooms expire after 24 hours and reject further play; expiration does not automatically delete documents, because managed TTL deletion is not in the free quota. Periodically delete old closed/expired rooms and their request subcollections from the console.

## Hospital supplies update

Hospital treatment and supply purchases use the host-authoritative rules shared with local games. The `medicalBuy` and `healthPack` commands are allowed by the updated `firestore.rules`, deployed on November 15, 2026. The previous deployed rules rejected those commands, blocking online purchases and pack treatment. All players in a room should run the same game build. Local pass-and-play does not require a backend update.

## Tests and emulators

```sh
flutter analyze
flutter test
npm --prefix test/firebase install
npx firebase-tools emulators:exec --only firestore --project demo-spiral-survival "npm --prefix test/firebase test"
```

Security tests use the official emulator and a demo project, never the live database. Java 21 is required by the current emulator. The tests cover concurrent joins, maximum capacity, frozen seats, owner-only requests, stale revisions and unauthorized room/state edits.

For an Android emulator run of the full app, enable the Auth and Firestore emulators with `npx firebase-tools emulators:start --only auth,firestore --project spiral-survival-c4ff0`, then supply `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2` alongside the client configuration. This flag is for local testing only; omit it from distributed builds.


## Verified live deployment — 2026-11-13

- Project: `spiral-survival-c4ff0`; Android package: `com.example.spiral_pass_play`.
- Default database: Firestore Standard, `us-east1`, free tier; point-in-time recovery disabled.
- Anonymous sign-in enabled; billing confirmed disabled after provisioning.
- Deployed room rules match the local `firestore.rules` exactly.
- 200 Flutter tests and 24 Firestore emulator security checks passed.
- 11 live checks passed using six isolated anonymous clients: five concurrent seats, sixth-player rejection, state protection, turn-owner restrictions, atomic command acknowledgement and synchronized state reads.
- The temporary live room and all six temporary Auth identities were removed after testing.
- `dist/` contains Firebase-configured ARM APKs; their embedded client project and API key were verified against the provided configuration. Production store signing still needs to be configured separately.

The optional `test/firebase/live_room_test.mjs` repeats these checks against the live project. It creates and removes its own test room and six anonymous identities, so it consumes a small amount of project quota. Run it only when you intend live testing:

```sh
FIREBASE_CLIENT_CONFIG="$PWD/firebase_client.json" npm --prefix test/firebase run test:live
```
