import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/theme.dart';
import '../../../firebase_config.dart';
import '../../game/application/game_controller.dart';
import '../../game/domain/board_definition.dart';
import '../../game/domain/game_session.dart';
import '../../game/domain/player_icon.dart';
import '../domain/private_room_state.dart';
import '../domain/room_protocol.dart';

class RoomService extends ChangeNotifier {
  RoomService(this.board);
  final BoardDefinition board;
  FirebaseFirestore? _db;
  String? uid;
  OnlineRoom? room;
  String? error;
  bool connected = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _requestsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _privateSub;
  Map<String, dynamic>? _privateView;
  bool get privateViewReady =>
      room == null ||
      room!.state.isEmpty ||
      (jsonDecode(room!.state) as Map)['privateViews'] != true ||
      _privateView?['revision'] == room!.revision;

  String get visibleOutcome =>
      privateViewReady && _privateView?['outcome'] is String
      ? _privateView!['outcome'] as String
      : room?.outcome ?? '';

  GameSession? get visibleSession {
    final current = room;
    if (current == null || current.state.isEmpty) return null;
    final state = jsonDecode(current.state) as Map<String, dynamic>;
    return GameSession.fromJson(
      privateViewReady && _privateView != null
          ? applyPrivateView(state, _privateView!)
          : state,
    );
  }

  Timer? _heartbeat;
  Timer? _liveness;
  bool _disposed = false;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  final Set<String> _processing = {};
  late final _preferences = SharedPreferencesAsync();
  static const _lastRoomKey = 'spiral_online_room';
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bool get isHost => room?.hostId == uid;
  DocumentReference<Map<String, dynamic>> get _ref =>
      _db!.collection('rooms').doc(room!.code);

  Future<void> connect() async {
    if (_db != null) return;
    if (!FirebaseConfig.configured) {
      throw StateError(
        'Online play is not enabled in this build. Local play is still available.',
      );
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: FirebaseConfig.options);
    }
    if (Firebase.app().options.projectId != FirebaseConfig.projectId) {
      throw StateError('This build cannot connect to online rooms.');
    }
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    db.settings = const Settings(persistenceEnabled: false);
    if (FirebaseConfig.emulatorHost.isNotEmpty) {
      await auth.useAuthEmulator(FirebaseConfig.emulatorHost, 9099);
      db.useFirestoreEmulator(FirebaseConfig.emulatorHost, 8080);
    }
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
    if (user == null) throw StateError('Could not sign in. Try again.');
    uid = user.uid;
    _db = db;
  }

  String _name(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 16) {
      throw StateError('Enter a name between 1 and 16 characters.');
    }
    return name;
  }

  Future<void> create(String name, {PlayerIcon avatar = PlayerIcon.paw}) async {
    if (!avatar.isSelectable) throw StateError('Choose a character.');
    await connect();
    final random = Random.secure();
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = List.generate(
        8,
        (_) => _alphabet[random.nextInt(_alphabet.length)],
      ).join();
      final ref = _db!.collection('rooms').doc(code);
      final created = await _db!.runTransaction((tx) async {
        if ((await tx.get(ref)).exists) return false;
        tx.set(ref, {
          'hostId': uid,
          'members': {uid!: _name(name)},
          'avatars': {uid!: avatar.name},
          'playerOrder': [uid!],
          'status': 'waiting',
          'activeUid': '',
          'revision': 0,
          'boardId': board.id,
          'state': '',
          'outcome': '',
          'lastRequestId': '',
          'lastError': '',
          'hostSeen': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(hours: 24)),
          ),
        });
        return true;
      });
      if (created) {
        await _watch(code);
        return;
      }
    }
    throw StateError('Could not create a unique room. Try again.');
  }

  Future<void> join(
    String code,
    String name, {
    PlayerIcon avatar = PlayerIcon.paw,
  }) async {
    if (!avatar.isSelectable) throw StateError('Choose a character.');
    await connect();
    final normalized = code.replaceAll(' ', '').toUpperCase();
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(normalized)) {
      throw StateError('Enter the 8-character room code.');
    }
    final ref = _db!.collection('rooms').doc(normalized);
    // Security rules can reject a stale membership map before the SDK reports
    // a transaction conflict. Re-read and retry; never relax the five-seat rule.
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await _db!.runTransaction((tx) async {
          final snapshot = await tx.get(ref);
          if (!snapshot.exists) {
            throw StateError('Room not found. Check the code.');
          }
          final data = snapshot.data()!;
          if (data['boardId'] != board.id) {
            throw StateError(
              'This room uses another board version. Update the game first.',
            );
          }
          final members = Map<String, String>.from(data['members'] as Map);
          if ((data['expiresAt'] as Timestamp).toDate().isBefore(
                DateTime.now(),
              ) ||
              data['status'] == 'closed') {
            throw StateError('This room has closed. Create another room.');
          }
          if (members.containsKey(uid)) return; // Reconnect to the same seat.
          if (data['status'] != 'waiting') {
            throw StateError('This game has already started.');
          }
          if (members.length >= maxRoomPlayers) {
            throw StateError('This room is full. Maximum 5 players.');
          }
          final playerName = _name(name);
          if (members.values.any(
            (n) => n.toLowerCase() == playerName.toLowerCase(),
          )) {
            throw StateError('That name is taken in this room.');
          }
          members[uid!] = playerName;
          tx.update(ref, {
            'members': members,
            'avatars': {
              ...Map<String, String>.from(data['avatars'] as Map),
              uid!: avatar.name,
            },
            'playerOrder': [...data['playerOrder'] as List, uid!],
          });
        });
        break;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied' || attempt == 4) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 40 * (attempt + 1)));
      }
    }
    await _watch(normalized);
  }

  Future<bool> resume() async {
    final code = await _preferences.getString(_lastRoomKey);
    if (code == null) return false;
    await connect();
    final snapshot = await _db!
        .collection('rooms')
        .doc(code)
        .get(const GetOptions(source: Source.server));
    final data = snapshot.data();
    if (data == null ||
        !(data['members'] as Map).containsKey(uid) ||
        data['status'] == 'closed' ||
        (data['expiresAt'] as Timestamp).toDate().isBefore(DateTime.now())) {
      await _preferences.remove(_lastRoomKey);
      return false;
    }
    if (data['boardId'] != board.id) {
      throw StateError(
        'This room uses another board version. Update the game first.',
      );
    }
    await _watch(code);
    return true;
  }

  Future<void> _watch(String code) async {
    if (_disposed) throw StateError('Room was closed.');
    _liveness?.cancel();
    _liveness = Timer.periodic(const Duration(seconds: 15), (_) => _emit());
    await _roomSub?.cancel();
    await _privateSub?.cancel();
    _privateView = null;
    _privateSub = _db!
        .collection('rooms')
        .doc(code)
        .collection('private')
        .doc(uid!)
        .snapshots()
        .listen(
          (snapshot) {
            _privateView = snapshot.data();
            _emit();
          },
          onError: (Object e) {
            _privateView = null;
            error = 'Could not load your private game details. Reconnect.';
            _emit();
          },
        );
    await _preferences.setString(_lastRoomKey, code);
    final first = Completer<void>();
    _roomSub = _db!
        .collection('rooms')
        .doc(code)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            final data = snapshot.data();
            if (data == null) {
              error = 'This room has closed.';
              connected = false;
              _emit();
              if (!first.isCompleted) first.complete();
              return;
            }
            connected =
                !snapshot.metadata.isFromCache &&
                !snapshot.metadata.hasPendingWrites;
            if (connected) error = null;
            room = OnlineRoom(
              code: code,
              hostId: data['hostId'] as String,
              members: Map<String, String>.from(data['members'] as Map),
              avatars: {
                for (final entry in (data['avatars'] as Map? ?? {}).entries)
                  entry.key as String: PlayerIcon.values.byName(
                    entry.value as String,
                  ),
              },
              playerOrder: List<String>.from(data['playerOrder'] as List),
              status: data['status'] as String,
              revision: data['revision'] as int,
              state: data['state'] as String,
              outcome: data['outcome'] as String,
              lastRequestId: data['lastRequestId'] as String,
              lastError: data['lastError'] as String,
              hostSeen:
                  (data['hostSeen'] as Timestamp?)?.toDate() ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              expiresAt: (data['expiresAt'] as Timestamp).toDate(),
            );
            if (isHost && _requestsSub == null) _startHosting();
            if (!first.isCompleted && connected) first.complete();
            _emit();
          },
          onError: (Object e) {
            connected = false;
            error = 'Connection lost. Check your internet and reconnect.';
            if (!first.isCompleted) first.completeError(e);
            _emit();
          },
        );
    await first.future.timeout(const Duration(seconds: 15));
  }

  void _startHosting() {
    _requestsSub = _ref
        .collection('requests')
        .snapshots()
        .listen(
          (snapshot) {
            for (final doc in snapshot.docs) {
              if (_processing.add(doc.id)) unawaited(_process(doc.reference));
            }
          },
          onError: (Object e) {
            error = 'Could not receive player actions. Reconnect to the room.';
            _emit();
          },
        );
    _heartbeat = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_pulse()),
    );
    unawaited(_pulse());
  }

  Future<void> _pulse() async {
    try {
      if (isHost && room?.status != 'closed') {
        await _ref.update({'hostSeen': FieldValue.serverTimestamp()});
      }
    } catch (_) {
      connected = false;
      _emit();
    }
  }

  Future<void> chooseAvatar(PlayerIcon avatar) async {
    if (!avatar.isSelectable || uid == null || room == null || !connected) {
      throw StateError('Choose a character while connected to the lobby.');
    }
    await _db!.runTransaction((tx) async {
      final snapshot = await tx.get(_ref);
      final data = snapshot.data()!;
      if (data['status'] != 'waiting' ||
          !(data['members'] as Map).containsKey(uid)) {
        throw StateError('Characters are locked once the game starts.');
      }
      final avatars = Map<String, dynamic>.from(data['avatars'] as Map);
      avatars[uid!] = avatar.name;
      tx.update(_ref, {'avatars': avatars});
    });
  }

  Future<void> start() async {
    if (!isHost || !connected) {
      throw StateError('Only the connected host can start.');
    }
    await _db!.runTransaction((tx) async {
      final snapshot = await tx.get(_ref);
      final data = snapshot.data()!;
      final order = List<String>.from(data['playerOrder'] as List);
      if (data['hostId'] != uid ||
          data['status'] != 'waiting' ||
          order.length < 2 ||
          order.length > 5) {
        throw StateError('Start requires 2–5 players in the lobby.');
      }
      final members = Map<String, String>.from(data['members'] as Map);
      final game = GameController.newGame(
        names: order.map((id) => members[id]!).toList(),
        colors: AppTheme.playerColors.map((c) => c.toARGB32()).toList(),
        board: board,
        icons: [
          for (final id in order)
            PlayerIcon.values.byName((data['avatars'] as Map)[id] as String),
        ],
      );
      final state = _writeViews(tx, game.session.toJson(), 1, order: order);
      game.dispose();
      tx.update(_ref, {
        'status': 'playing',
        'activeUid': order.first,
        'state': state,
        'revision': 1,
        'hostSeen': FieldValue.serverTimestamp(),
      });
    });
  }

  String _writeViews(
    Transaction tx,
    Map<String, dynamic> state,
    int revision, {
    required List<String> order,
    String outcome = '',
  }) {
    tx.set(_ref.collection('authority').doc('state'), {
      'state': jsonEncode(state),
    });
    final players = (state['players'] as List).cast<Map>();
    for (var i = 0; i < players.length; i++) {
      tx.set(_ref.collection('private').doc(order[i]), {
        'revision': revision,
        'outcome': playerOutcome(outcome, players[i]['id'] as String),
        ...privateSessionView(state, players[i]['id'] as String),
      });
    }
    return jsonEncode(publicSession(state));
  }

  Future<void> _process(
    DocumentReference<Map<String, dynamic>> requestRef,
  ) async {
    try {
      await _db!.runTransaction((tx) async {
        final request = await tx.get(requestRef);
        final snapshot = await tx.get(_ref);
        final authority = await tx.get(
          _ref.collection('authority').doc('state'),
        );
        if (!request.exists || !snapshot.exists) return;
        final data = request.data()!;
        final latest = snapshot.data()!;
        if (latest['hostId'] != uid) return;
        final members = Map<String, String>.from(latest['members'] as Map);
        final current = OnlineRoom(
          code: room!.code,
          hostId: uid!,
          members: members,
          playerOrder: List<String>.from(latest['playerOrder'] as List),
          status: latest['status'] as String,
          revision: latest['revision'] as int,
          state:
              authority.data()?['state'] as String? ??
              latest['state'] as String,
          outcome: latest['outcome'] as String,
          lastRequestId: latest['lastRequestId'] as String,
          lastError: latest['lastError'] as String,
          hostSeen: DateTime.now(),
          expiresAt: (latest['expiresAt'] as Timestamp).toDate(),
        );
        final update = <String, dynamic>{
          'lastRequestId': data['requestId'],
          'lastError': '',
          'hostSeen': FieldValue.serverTimestamp(),
        };
        try {
          final result = executeRoomCommand(
            room: current,
            senderId: requestRef.id,
            expectedRevision: data['expectedRevision'] as int,
            action: data['action'] as String,
            args: Map<String, dynamic>.from(data['args'] as Map),
            board: board,
          );
          update.addAll({
            'state': _writeViews(
              tx,
              jsonDecode(result.state) as Map<String, dynamic>,
              current.revision + 1,
              outcome: result.outcome,
              order: current.playerOrder,
            ),
            'outcome': publicOutcome(result.outcome),
            'revision': current.revision + 1,
            'activeUid':
                current.playerOrder[(jsonDecode(result.state)
                        as Map<String, dynamic>)['currentPlayerIndex']
                    as int],
          });
        } catch (_) {
          update['lastError'] =
              'That action is no longer available. Try again on your turn.';
        }
        tx.update(_ref, update);
        tx.delete(requestRef);
      });
    } catch (_) {
      error = 'Could not process a turn. Check the connection.';
      _emit();
    } finally {
      _processing.remove(requestRef.id);
    }
  }

  Future<void> send(String action, Map<String, dynamic> args) async {
    if (!connected ||
        room == null ||
        !room!.hostAvailable ||
        room!.activeUid != uid) {
      throw StateError('Wait for your turn and a connection to the host.');
    }
    final requestId =
        '${uid}_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';
    final ack = Completer<void>();
    void changed() {
      if (room?.lastRequestId == requestId && !ack.isCompleted) {
        if (room!.lastError.isEmpty) {
          ack.complete();
        } else {
          ack.completeError(StateError(room!.lastError));
        }
      }
    }

    addListener(changed);
    try {
      await _ref
          .collection('requests')
          .doc(uid)
          .set({
            'requestId': requestId,
            'action': action,
            'args': args,
            'expectedRevision': room!.revision,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 12));
      await ack.future.timeout(const Duration(seconds: 15));
    } finally {
      removeListener(changed);
    }
  }

  Future<void> leave() async {
    if (room == null) return;
    if (isHost) {
      await _ref.update({
        'status': 'closed',
        'hostSeen': FieldValue.serverTimestamp(),
      });
    } else if (room!.status == 'waiting') {
      await _db!.runTransaction((tx) async {
        final snapshot = await tx.get(_ref);
        final data = snapshot.data()!;
        if (data['status'] != 'waiting') return;
        final members = Map<String, String>.from(data['members'] as Map)
          ..remove(uid);
        final order = List<String>.from(data['playerOrder'] as List)
          ..remove(uid);
        final avatars = Map<String, dynamic>.from(data['avatars'] as Map)
          ..remove(uid);
        tx.update(_ref, {
          'members': members,
          'avatars': avatars,
          'playerOrder': order,
        });
      });
    }
    await _preferences.remove(_lastRoomKey);
  }

  @override
  void dispose() {
    _disposed = true;
    _liveness?.cancel();
    _heartbeat?.cancel();
    unawaited(_roomSub?.cancel());
    unawaited(_privateSub?.cancel());
    unawaited(_requestsSub?.cancel());
    super.dispose();
  }
}
