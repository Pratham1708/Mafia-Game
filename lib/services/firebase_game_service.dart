import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/game_config.dart';
import '../models/game_phase.dart';
import '../models/player.dart';
import '../models/player_role.dart';
import '../models/private_action.dart';
import '../models/private_player_data.dart';
import '../models/private_result.dart';
import '../models/private_vote.dart';
import '../models/room.dart';
import '../models/round_data.dart';
import '../utils/room_code_generator.dart';
import 'auth_service.dart';
import 'game_logic_engine.dart';
import 'game_service_interface.dart';

/// Firebase-backed game service — Spark/free plan edition.
///
/// ══════════════════════════════════════════════════════════════════
///  SPARK LIMITATION (accepted trade-off, documented per spec)
/// ══════════════════════════════════════════════════════════════════
/// Cloud Functions are NOT available on the Firebase Spark free plan.
/// All game-state mutations are performed directly by the Flutter client
/// using the Firestore client SDK. For MVP 1, Firestore Security Rules are
/// intentionally simple (authenticated-user access; see firestore.rules).
///
/// KNOWN MVP 1 LIMITATIONS (accepted, to be addressed in a future V2):
///   1. The host can potentially see private role/game data.
///   2. Client-side game resolution is trusted.
///   3. A malicious client may manipulate game state.
///   4. Firestore rules are permissive for any authenticated user.
///   5. Host authority is not cryptographically/server enforced.
///
/// SECURITY TRADE-OFFS vs the Cloud Functions architecture:
///   • Role assignment: The host client calls GameLogicEngine.assignRoles()
///     and batch-writes privatePlayerData/{uid}. The host therefore sees ALL
///     player roles at assignment time. This is unavoidable on Spark.
///   • Action/vote resolution: The host client reads all privateActions /
///     privateVotes and runs GameLogicEngine locally. The host sees all
///     submitted actions during resolution.
///   • Win-condition check: The host client runs GameLogicEngine.checkWinCondition
///     with the full role map. The host could theoretically declare a false win.
///   • Room cleanup: Firestore client SDK cannot recursively delete subcollections.
///     Best-effort cleanup is performed; orphaned private subcollection documents
///     may persist; they are harmless leftovers under the MVP rules.
///
/// MVP 1 RULES NOTE: the private-data separation below is preserved in the
/// data model only; isolation is NOT enforced by rules in MVP 1 so that a
/// future V2 can restore it without redesigning the game.
/// ══════════════════════════════════════════════════════════════════
///
/// Data architecture (unchanged from Phase 2):
///   PUBLIC  → rooms/{roomId}                                       (room members)
///   PUBLIC  → rooms/{roomId}/players/{uid}                         (room members; no role during PLAYING)
///   PUBLIC  → rooms/{roomId}/rounds/{N}                            (room members; counts only)
///   PRIVATE → rooms/{roomId}/privatePlayerData/{uid}               (owner + host read)
///   PRIVATE → rooms/{roomId}/rounds/{N}/privateActions/{uid}       (owner + host read)
///   PRIVATE → rooms/{roomId}/rounds/{N}/privateVotes/{uid}         (owner + host read)
///   PRIVATE → rooms/{roomId}/rounds/{N}/privateResults/{uid}       (owner-read only)
class FirebaseGameService implements IGameService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _roomsRef => _firestore.collection('rooms');

  // ── Concurrency guard for host resolution ──────────────────────────────────
  bool _isResolvingActions = false;
  bool _isResolvingVotes = false;

  // ── Internal host round-watch subscription ─────────────────────────────────
  StreamSubscription<DocumentSnapshot>? _roundWatchSubscription;
  String? _roundWatchRoomId;
  int? _roundWatchRoundNumber;

  // ─── Room lifecycle ────────────────────────────────────────────────────────

  @override
  Future<Room> createRoom({required String hostName}) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null)
      throw Exception('Session expired. Please rejoin the room.');

    final validName = AuthService.validateDisplayName(hostName);
    if (validName == null) {
      throw Exception('Name must be between 2 and 20 characters.');
    }

    String code = RoomCodeGenerator.generate();
    bool collision = true;
    int attempts = 0;
    while (collision && attempts < 5) {
      final query =
          await _roomsRef.where('roomCode', isEqualTo: code).limit(5).get();
      final hasActiveRoom = query.docs.any((d) {
        final st = (d.data() as Map<String, dynamic>)['status'] as String?;
        return st != 'GAME_OVER';
      });
      if (!hasActiveRoom) {
        collision = false;
      } else {
        code = RoomCodeGenerator.generate();
        attempts++;
      }
    }

    final roomDoc = _roomsRef.doc();
    final newRoom = Room(
      id: roomDoc.id,
      code: code,
      hostId: uid,
      status: RoomStatus.lobby,
      currentRound: 0,
      currentPhase: GamePhase.lobby,
      createdAt: DateTime.now(),
      maxPlayers: 12,
    );

    final hostPlayer = Player(
      uid: uid,
      name: validName,
      isAlive: true,
      isHost: true,
      joinedAt: DateTime.now(),
    );

    final roomPayload = newRoom.toMap();
    final hostPlayerPayload = hostPlayer.toMap();

    final batch = _firestore.batch();
    batch.set(roomDoc, roomPayload);
    batch.set(roomDoc.collection('players').doc(uid), hostPlayerPayload);

    await batch.commit();

    return newRoom;
  }

  @override
  Future<Room> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null)
      throw Exception('Session expired. Please rejoin the room.');

    final sanitizedCode = RoomCodeGenerator.sanitize(roomCode);
    if (!RoomCodeGenerator.isValid(sanitizedCode)) {
      throw Exception('Check the room code and try again.');
    }

    final validName = AuthService.validateDisplayName(playerName);
    if (validName == null) {
      throw Exception('Name must be between 2 and 20 characters.');
    }

    final query =
        await _roomsRef.where('roomCode', isEqualTo: sanitizedCode).get();

    if (query.docs.isEmpty) {
      throw Exception('Check the room code and try again.');
    }

    final activeDocs = query.docs.where((d) {
      final st = RoomStatus.fromString(
          (d.data() as Map<String, dynamic>)['status'] as String?);
      return st != RoomStatus.gameOver;
    }).toList();

    if (activeDocs.isEmpty) {
      throw Exception('This game has already ended.');
    }

    activeDocs.sort((a, b) {
      final aTime = (a.data() as Map<String, dynamic>)['createdAt'];
      final bTime = (b.data() as Map<String, dynamic>)['createdAt'];
      final aDate = aTime is Timestamp
          ? aTime.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = bTime is Timestamp
          ? bTime.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    final roomDoc = activeDocs.first;
    final room =
        Room.fromMap(roomDoc.data() as Map<String, dynamic>, roomDoc.id);

    final existingPlayerDoc =
        await roomDoc.reference.collection('players').doc(uid).get();

    if (existingPlayerDoc.exists) {
      return room;
    }

    if (room.status != RoomStatus.lobby) {
      throw Exception('This game has already started.');
    }

    final playersSnap = await roomDoc.reference.collection('players').get();
    if (playersSnap.docs.length >= room.maxPlayers) {
      throw Exception('This room already has 12 players.');
    }

    final nameTaken = playersSnap.docs.any((d) {
      final existingName = (d.data()['name'] as String?)?.trim().toLowerCase();
      return existingName == validName.toLowerCase();
    });
    if (nameTaken) {
      throw Exception('A player with that name is already in the room.');
    }

    final newPlayer = Player(
      uid: uid,
      name: validName,
      isAlive: true,
      isHost: false,
      joinedAt: DateTime.now(),
    );
    await roomDoc.reference
        .collection('players')
        .doc(uid)
        .set(newPlayer.toMap());

    return room;
  }

  @override
  Future<void> leaveRoom({required String roomId, required String uid}) async {
    try {
      final roomRef = _roomsRef.doc(roomId);
      final roomSnap = await roomRef.get();
      if (!roomSnap.exists) return;

      final roomData = roomSnap.data() as Map<String, dynamic>;
      final isHost = roomData['hostId'] == uid;

      final playersSnap = await roomRef.collection('players').get();
      final remaining = playersSnap.docs.where((d) => d.id != uid).toList();

      if (remaining.isEmpty) {
        // Last player leaving: delete room + all accessible subcollections
        final batch = _firestore.batch();
        batch.delete(roomRef.collection('players').doc(uid));
        batch.delete(roomRef);
        await batch.commit();
        // Best-effort cleanup of remaining subcollections (Spark limitation:
        // cannot recursively delete — orphaned private docs remain inaccessible)
        _cleanupRoomSubcollections(roomId).ignore();
        return;
      }

      final batch = _firestore.batch();
      batch.delete(roomRef.collection('players').doc(uid));

      if (isHost) {
        remaining.sort((a, b) {
          final aTime = a.data()['joinedAt'];
          final bTime = b.data()['joinedAt'];
          if (aTime is Timestamp && bTime is Timestamp) {
            return aTime.compareTo(bTime);
          }
          return 0;
        });
        final newHost = remaining.first;
        batch.update(roomRef, {
          'hostId': newHost.id,
          'publicMessage':
              '${newHost.data()['name'] ?? 'A player'} is now the host.'
        });
        batch.update(
            roomRef.collection('players').doc(newHost.id), {'isHost': true});
      }

      await batch.commit();
      _cancelRoundWatch();
    } catch (e) {
      debugPrint('Error leaving room: $e');
    }
  }

  /// Claims host privileges for the current user via a Firestore transaction.
  ///
  /// SPARK LIMITATION: Cannot verify server-side that the current host is
  /// actually disconnected/offline. The transaction verifies the caller is a
  /// living room member and sets hostId to themselves. Any living room member
  /// can claim host; this is the documented Spark limitation vs the Cloud
  /// Function implementation which could check host presence server-side.
  @override
  Future<void> claimHost(String roomId) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) throw Exception('Session expired.');

    await _firestore.runTransaction((tx) async {
      final roomRef = _roomsRef.doc(roomId);
      final roomSnap = await tx.get(roomRef);
      if (!roomSnap.exists) throw Exception('Room not found.');

      final roomData = roomSnap.data() as Map<String, dynamic>;
      if (roomData['status'] == 'GAME_OVER') {
        throw Exception('Cannot change host after game over.');
      }

      final currentHostId = roomData['hostId'] as String;
      if (currentHostId == uid) return; // Already host

      final playerSnap = await tx.get(roomRef.collection('players').doc(uid));
      if (!playerSnap.exists) {
        throw Exception('You are not a member of this room.');
      }
      if (playerSnap.data()!['isAlive'] != true) {
        throw Exception('Eliminated players cannot claim host.');
      }

      final playerName = playerSnap.data()!['name'] as String? ?? 'A player';

      // Transfer host
      tx.update(roomRef, {
        'hostId': uid,
        'publicMessage': '$playerName has taken over as room host.',
      });
      tx.update(roomRef.collection('players').doc(uid), {'isHost': true});

      // Unset old host's flag if they are still in the room
      final oldHostSnap =
          await tx.get(roomRef.collection('players').doc(currentHostId));
      if (oldHostSnap.exists) {
        tx.update(roomRef.collection('players').doc(currentHostId),
            {'isHost': false});
      }
    });
  }

  // ─── Public real-time streams ─────────────────────────────────────────────

  @override
  Stream<Room> streamRoom(String roomId) {
    return _roomsRef.doc(roomId).snapshots().map((snap) {
      if (!snap.exists) throw Exception('Room has been closed.');
      final isPending = snap.metadata.hasPendingWrites;
      final room = Room.fromMap(snap.data() as Map<String, dynamic>, snap.id);
      debugPrint(
          'ROOM SNAPSHOT [${isPending ? "LOCAL/PENDING" : "SERVER"}]: status=${room.status.name}, currentPhase=${room.currentPhase.name}, currentRound=${room.currentRound}');
      _maybeRequestBotAutomation(room);
      _maybeUpdateRoundWatch(room);
      return room;
    });
  }

  @override
  Stream<List<Player>> streamPlayers(String roomId) {
    return _roomsRef
        .doc(roomId)
        .collection('players')
        .orderBy('joinedAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Player.fromMap(doc.data(), doc.id))
            .toList());
  }

  @override
  Stream<RoundData> streamRound(String roomId, int roundNumber) {
    return _roomsRef
        .doc(roomId)
        .collection('rounds')
        .doc(roundNumber.toString())
        .snapshots()
        .map((snap) {
      if (!snap.exists) return RoundData(roundNumber: roundNumber);
      return RoundData.fromMap(
          snap.data() as Map<String, dynamic>, roundNumber);
    });
  }

  @override
  Stream<List<ChatMessage>> streamMessages(String roomId) {
    return _roomsRef
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChatMessage.fromMap(doc.data(), doc.id))
            .toList());
  }

  @override
  Stream<List<ChatMessage>> streamSpectatorMessages(String roomId) {
    return _roomsRef
        .doc(roomId)
        .collection('spectatorMessages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChatMessage.fromMap(doc.data(), doc.id))
            .toList());
  }

  // ─── Private data streams (owner-read only) ───────────────────────────────

  @override
  Stream<PlayerRole> streamMyRole(String roomId) {
    final uid = AuthService.instance.currentUid;
    if (uid == null) return const Stream.empty();

    return _roomsRef
        .doc(roomId)
        .collection('privatePlayerData')
        .doc(uid)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return PlayerRole.unknown;
      return PrivatePlayerData.fromMap(snap.data()!).role;
    });
  }

  @override
  Stream<PrivatePlayerData?> streamMyPlayerData(String roomId) {
    final uid = AuthService.instance.currentUid;
    if (uid == null) return const Stream.empty();

    return _roomsRef
        .doc(roomId)
        .collection('privatePlayerData')
        .doc(uid)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return PrivatePlayerData.fromMap(snap.data()!);
    });
  }

  @override
  Stream<PrivateAction?> streamMyAction(String roomId, int roundNumber) {
    final uid = AuthService.instance.currentUid;
    if (uid == null) return const Stream.empty();

    return _roomsRef
        .doc(roomId)
        .collection('rounds')
        .doc(roundNumber.toString())
        .collection('privateActions')
        .doc(uid)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return PrivateAction.fromMap(snap.data()!);
    });
  }

  @override
  Stream<PrivateResult?> streamMyResult(String roomId, int roundNumber) {
    final uid = AuthService.instance.currentUid;
    if (uid == null) return const Stream.empty();

    return _roomsRef
        .doc(roomId)
        .collection('rounds')
        .doc(roundNumber.toString())
        .collection('privateResults')
        .doc(uid)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return PrivateResult.fromMap(snap.data()!);
    });
  }

  @override
  Stream<PrivateVote?> streamMyVote(String roomId, int roundNumber) {
    final uid = AuthService.instance.currentUid;
    if (uid == null) return const Stream.empty();

    return _roomsRef
        .doc(roomId)
        .collection('rounds')
        .doc(roundNumber.toString())
        .collection('privateVotes')
        .doc(uid)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return PrivateVote.fromMap(snap.data()!);
    });
  }

  // ─── Game lifecycle (host-driven, direct Firestore writes) ────────────────

  /// Starts the game.
  ///
  /// SPARK: Host client assigns roles using GameLogicEngine (Random.secure()),
  /// batch-writes privatePlayerData/{uid} for every player, creates round 1,
  /// and transitions room to PLAYING / roleReveal.
  ///
  /// SECURITY NOTE: The host sees all role assignments. This is the accepted
  /// Spark trade-off replacing the server-authoritative Cloud Function.
  @override
  Future<void> startGame(String roomId) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) throw Exception('Session expired.');

    debugPrint('START GAME REQUEST: uid=$uid, roomId=$roomId');

    final roomRef = _roomsRef.doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) throw Exception('Room not found.');

    final roomData = roomSnap.data() as Map<String, dynamic>;
    if (roomData['hostId'] != uid) {
      throw Exception('Only the room host can start the game.');
    }
    final currentStatus = RoomStatus.fromString(roomData['status'] as String?);
    if (currentStatus != RoomStatus.lobby) {
      throw Exception('This game has already started.');
    }

    final playersSnap = await roomRef.collection('players').get();
    final players =
        playersSnap.docs.map((d) => Player.fromMap(d.data(), d.id)).toList();

    debugPrint(
        'ROOM BEFORE: status=${roomData['status']}, currentPhase=${roomData['currentPhase']}, currentRound=${roomData['currentRound']}, hostId=${roomData['hostId']}, playersCount=${players.length}');

    if (players.length < GameConfig.minPlayers) {
      throw Exception(
          'At least ${GameConfig.minPlayers} players are required to start.');
    }
    if (players.length > GameConfig.maxPlayers) {
      throw Exception('Too many players.');
    }

    final playerUids = players.map((p) => p.uid).toList();
    // Role assignment via GameLogicEngine (deterministic, Random.secure())
    // SPARK LIMITATION: host client executes this, so host sees all roles.
    final assignments = GameLogicEngine.assignRoles(playerUids);

    final batch = _firestore.batch();

    // Write each player's private role document
    for (final player in players) {
      final role = assignments[player.uid] ?? PlayerRole.civilian;
      batch.set(
        roomRef.collection('privatePlayerData').doc(player.uid),
        {'role': role.name, 'hasUsedAbility': false},
      );
    }

    // Create round 1 document
    batch.set(
      roomRef.collection('rounds').doc('1'),
      {
        'roundNumber': 1,
        'actionsCount': 0,
        'votesCount': 0,
        'eliminatedInActions': null,
        'eliminatedInVote': null,
        'actionsResolved': false,
        'votesResolved': false,
      },
    );

    // Transition room to PLAYING
    batch.update(roomRef, {
      'status': 'PLAYING',
      'currentRound': 1,
      'currentPhase': 'roleReveal',
      'publicMessage': 'Game started! Memorize your secret role.',
      'startedAt': FieldValue.serverTimestamp(),
      'eliminatedThisRound': null,
      'votedOutThisRound': null,
      'winner': null,
    });

    debugPrint(
        'START GAME WRITE: committing batch for roomId=$roomId (roles assigned for ${players.length} players, round=1, phase=roleReveal)');

    try {
      await batch.commit();
      debugPrint('ROOM AFTER: batch write succeeded for roomId=$roomId');
    } catch (e) {
      debugPrint('START GAME WRITE ERROR: $e');
      rethrow;
    }
  }

  @override
  Future<void> advanceToActions(String roomId) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) throw Exception('Session expired.');

    final roomRef = _roomsRef.doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) throw Exception('Room not found.');
    final roomData = roomSnap.data() as Map<String, dynamic>;

    if (roomData['hostId'] != uid) {
      throw Exception('Only the host can advance the phase.');
    }
    if (roomData['currentPhase'] != 'roleReveal') {
      throw Exception('Can only advance to actions from roleReveal phase.');
    }

    final durationSeconds = GameConfig.defaultActionsDurationSeconds;
    final endTimestamp = Timestamp.fromDate(
        DateTime.now().add(Duration(seconds: durationSeconds)));

    await roomRef.update({
      'currentPhase': 'actions',
      'actionsEndTimestamp': endTimestamp,
      'actionsDurationSeconds': durationSeconds,
      'publicMessage':
          'Round ${roomData['currentRound']}: Secret actions in progress.',
    });
  }

  /// Submits the current player's secret action for the round.
  ///
  /// Writes to privateActions/{uid} (owner-only doc) and increments
  /// actionsCount on the public round document. After writing, the host
  /// resolution watcher will trigger _maybeResolveActions.
  @override
  Future<void> submitAction({
    required String roomId,
    required int roundNumber,
    required String uid,
    required String targetId,
    required PlayerRole role,
  }) async {
    final roomRef = _roomsRef.doc(roomId);
    final roundRef = roomRef.collection('rounds').doc(roundNumber.toString());
    final actionRef = roundRef.collection('privateActions').doc(uid);

    // Idempotency: skip if already submitted
    final existing = await actionRef.get();
    if (existing.exists) return;

    final batch = _firestore.batch();
    batch.set(actionRef, {'targetId': targetId, 'role': role.name});
    batch.update(roundRef, {'actionsCount': FieldValue.increment(1)});
    await batch.commit();

    final roomSnap = await roomRef.get();
    final roomData = roomSnap.data() as Map<String, dynamic>?;
    if (roomData?['hostId'] == uid) {
      await _triggerBotActions(roomId, roundNumber);
    }

    // Host immediately checks if resolution is possible
    _maybeResolveActionsDebounced(roomId, roundNumber);
  }

  @override
  Future<void> advanceToDiscussion(String roomId) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) throw Exception('Session expired.');

    final roomRef = _roomsRef.doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) throw Exception('Room not found.');
    final roomData = roomSnap.data() as Map<String, dynamic>;

    if (roomData['hostId'] != uid) {
      throw Exception('Only the host can advance the phase.');
    }
    if (roomData['currentPhase'] != 'roundResult') {
      throw Exception('Can only advance to discussion from roundResult phase.');
    }

    final durationSeconds = GameConfig.defaultDiscussionDurationSeconds;
    final endTimestamp = Timestamp.fromDate(
        DateTime.now().add(Duration(seconds: durationSeconds)));

    await roomRef.update({
      'currentPhase': 'discussion',
      'discussionEndTimestamp': endTimestamp,
      'discussionDurationSeconds': durationSeconds,
      'publicMessage': 'Discussion phase. Talk it out — who is the Mafia?',
    });
  }

  /// Sends a chat message during the discussion phase.
  ///
  /// Direct Firestore write — no Cloud Function required.
  /// Firestore rules enforce: alive player, in room, discussion phase,
  /// sender identity, message length 1–500. Equivalent to Phase 2 CF.
  @override
  Future<void> sendMessage(
      {required String roomId, required String message}) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) throw Exception('Session expired.');
    final trimmed = message.trim();
    if (trimmed.isEmpty || trimmed.length > GameConfig.maxChatMessageLength) {
      throw Exception(
          'Message must be between 1 and ${GameConfig.maxChatMessageLength} characters.');
    }

    final roomRef = _roomsRef.doc(roomId);
    final playerSnap = await roomRef.collection('players').doc(uid).get();
    final senderName = (playerSnap.data()?['name'] as String?) ?? 'Player';

    await roomRef.collection('messages').doc().set({
      'senderId': uid,
      'senderName': senderName,
      'message': trimmed,
      'timestamp': FieldValue.serverTimestamp(),
      'isSpectator': false,
    });
  }

  /// Sends a spectator message (dead players only).
  ///
  /// Direct Firestore write — no Cloud Function required.
  /// Firestore rules enforce: dead player, in room, sender identity, length.
  @override
  Future<void> sendSpectatorMessage(
      {required String roomId, required String message}) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) throw Exception('Session expired.');
    final trimmed = message.trim();
    if (trimmed.isEmpty || trimmed.length > GameConfig.maxChatMessageLength) {
      throw Exception(
          'Message must be between 1 and ${GameConfig.maxChatMessageLength} characters.');
    }

    final roomRef = _roomsRef.doc(roomId);
    final playerSnap = await roomRef.collection('players').doc(uid).get();
    final senderName = (playerSnap.data()?['name'] as String?) ?? 'Spectator';

    await roomRef.collection('spectatorMessages').doc().set({
      'senderId': uid,
      'senderName': senderName,
      'message': trimmed,
      'timestamp': FieldValue.serverTimestamp(),
      'isSpectator': true,
    });
  }

  @override
  Future<void> advanceToVoting(String roomId) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) throw Exception('Session expired.');

    final roomRef = _roomsRef.doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) throw Exception('Room not found.');
    final roomData = roomSnap.data() as Map<String, dynamic>;

    if (roomData['hostId'] != uid) {
      throw Exception('Only the host can advance the phase.');
    }
    final phase = roomData['currentPhase'] as String?;
    if (phase != 'roundResult' && phase != 'discussion') {
      throw Exception(
          'Can only advance to voting from roundResult or discussion.');
    }

    final durationSeconds = GameConfig.defaultVotingDurationSeconds;
    final endTimestamp = Timestamp.fromDate(
        DateTime.now().add(Duration(seconds: durationSeconds)));

    await roomRef.update({
      'currentPhase': 'voting',
      'votingEndTimestamp': endTimestamp,
      'votingDurationSeconds': durationSeconds,
      'publicMessage': 'Voting phase. Who is the Mafia?',
    });
  }

  /// Submits the current player's vote.
  ///
  /// Direct Firestore write to privateVotes/{uid}.
  @override
  Future<void> submitVote({
    required String roomId,
    required int roundNumber,
    required String uid,
    required String targetId,
  }) async {
    final roomRef = _roomsRef.doc(roomId);
    final roundRef = roomRef.collection('rounds').doc(roundNumber.toString());
    final voteRef = roundRef.collection('privateVotes').doc(uid);

    final existing = await voteRef.get();
    if (existing.exists) return;

    final batch = _firestore.batch();
    batch.set(voteRef, {'targetId': targetId});
    batch.update(roundRef, {
      'votesCount': FieldValue.increment(1),
      'votedUids': FieldValue.arrayUnion([uid]),
    });
    await batch.commit();

    final roomSnap = await roomRef.get();
    final roomData = roomSnap.data() as Map<String, dynamic>?;
    if (roomData?['hostId'] == uid) {
      await _triggerBotVotes(roomId, roundNumber);
    }

    _maybeResolveVotesDebounced(roomId, roundNumber);
  }

  /// Advances from elimination/roundResult to next round or ends the game.
  ///
  /// Host client reads all living players' roles from privatePlayerData,
  /// runs GameLogicEngine.checkWinCondition, and either:
  ///   - Declares GAME_OVER (batch-writes roles to public docs, updates room)
  ///   - Creates the next round document and advances the round counter
  @override
  Future<void> advanceToNextRoundOrEnd(String roomId) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) throw Exception('Session expired.');

    final roomRef = _roomsRef.doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) throw Exception('Room not found.');
    final roomData = roomSnap.data() as Map<String, dynamic>;

    if (roomData['hostId'] != uid) {
      throw Exception('Only the host can advance the round.');
    }
    final phase = roomData['currentPhase'] as String?;
    if (phase != 'elimination' && phase != 'roundResult') {
      throw Exception(
          'Can only advance round from elimination or roundResult.');
    }

    final currentRound = (roomData['currentRound'] as num).toInt();

    // Load all players and their roles for win check
    final playersSnap = await roomRef.collection('players').get();
    final players =
        playersSnap.docs.map((d) => Player.fromMap(d.data(), d.id)).toList();
    final livingPlayers = players.where((p) => p.isAlive).toList();

    // Build full role map from privatePlayerData (host has read access)
    final Map<String, PlayerRole> roleMap =
        await _buildRoleMap(roomRef, players);

    final winCheck = GameLogicEngine.checkWinCondition(
      livingPlayers,
      roleOverrides: roleMap,
    );

    final batch = _firestore.batch();

    if (winCheck.isGameOver) {
      // Reveal all roles in public player documents for the reveal screen
      for (final player in players) {
        final role = roleMap[player.uid] ?? PlayerRole.civilian;
        batch.update(
          roomRef.collection('players').doc(player.uid),
          {'role': role.name},
        );
      }
      batch.update(roomRef, {
        'status': 'GAME_OVER',
        'currentPhase': 'gameOver',
        'winner': winCheck.winner,
        'publicMessage': winCheck.reason,
      });
    } else {
      final nextRound = currentRound + 1;
      batch.set(
        roomRef.collection('rounds').doc(nextRound.toString()),
        {
          'roundNumber': nextRound,
          'actionsCount': 0,
          'votesCount': 0,
          'eliminatedInActions': null,
          'eliminatedInVote': null,
          'actionsResolved': false,
          'votesResolved': false,
        },
      );
      final durationSeconds = GameConfig.defaultActionsDurationSeconds;
      final endTimestamp = Timestamp.fromDate(
          DateTime.now().add(Duration(seconds: durationSeconds)));
      batch.update(roomRef, {
        'currentRound': nextRound,
        'currentPhase': 'actions',
        'actionsEndTimestamp': endTimestamp,
        'actionsDurationSeconds': durationSeconds,
        'eliminatedThisRound': null,
        'votedOutThisRound': null,
        'publicMessage': 'Round $nextRound: Secret actions in progress.',
      });
    }

    await batch.commit();
    if (winCheck.isGameOver) {
      _cancelRoundWatch();
    }
  }

  // ─── Bot player creation ──────────────────────────────────────────────────

  @override
  Future<void> addTestPlayer(
      {required String roomId, required String name}) async {
    final roomRef = _roomsRef.doc(roomId);
    final newDoc = roomRef.collection('players').doc();
    final testPlayer = Player(
      uid: newDoc.id,
      name: name,
      isAlive: true,
      isHost: false,
      isBot: true,
      joinedAt: DateTime.now(),
    );
    await newDoc.set(testPlayer.toMap());
  }

  // ─── Host-driven bot automation (client-side) ─────────────────────────────

  /// Called on each Room stream event. If the current user is the host
  /// and the room is in actions or voting phase, trigger bot automation
  /// followed immediately by a resolution attempt.
  ///
  /// SPARK: This replaces the triggerBotActions / triggerBotVotes Cloud Functions.
  /// The host client generates random valid actions/votes for bots.
  void _maybeRequestBotAutomation(Room room) {
    final currentUid = AuthService.instance.currentUid;
    if (currentUid == null || room.hostId != currentUid) return;
    if (room.status != RoomStatus.playing) return;

    if (room.currentPhase == GamePhase.actions) {
      Future.delayed(const Duration(milliseconds: 800), () async {
        try {
          await _triggerBotActions(room.id, room.currentRound);
          await _maybeResolveActions(room.id, room.currentRound);
        } catch (e) {
          debugPrint('Bot actions/resolution error: $e');
        }
      });
    } else if (room.currentPhase == GamePhase.voting) {
      Future.delayed(const Duration(milliseconds: 800), () async {
        try {
          await _triggerBotVotes(room.id, room.currentRound);
          await _maybeResolveVotes(room.id, room.currentRound);
        } catch (e) {
          debugPrint('Bot votes/resolution error: $e');
        }
      });
    }
  }

  /// Generates and submits secret actions for all living bots.
  ///
  /// Reads bot roles from privatePlayerData (host has read access).
  /// Writes bot actions to privateActions/{botUid}.
  Future<void> _triggerBotActions(String roomId, int roundNumber) async {
    final roomRef = _roomsRef.doc(roomId);
    final roundRef = roomRef.collection('rounds').doc(roundNumber.toString());

    final roundSnap = await roundRef.get();
    if (!roundSnap.exists) return;
    if ((roundSnap.data()!['actionsResolved'] as bool?) == true) return;

    final playersSnap = await roomRef.collection('players').get();
    final players =
        playersSnap.docs.map((d) => Player.fromMap(d.data(), d.id)).toList();
    final livingPlayers = players.where((p) => p.isAlive).toList();
    final livingBots = livingPlayers.where((p) => p.isBot).toList();

    if (livingBots.isEmpty) return;

    final batch = _firestore.batch();
    int added = 0;

    for (final bot in livingBots) {
      final existing =
          await roundRef.collection('privateActions').doc(bot.uid).get();
      if (existing.exists) continue;

      final privSnap =
          await roomRef.collection('privatePlayerData').doc(bot.uid).get();
      if (!privSnap.exists) continue;

      final role = PlayerRole.fromString(privSnap.data()!['role'] as String?);
      if (!role.hasSecretAction) continue;

      // Vigilante: skip if already used ability
      if (role == PlayerRole.vigilante) {
        if (privSnap.data()!['hasUsedAbility'] == true) continue;
      }

      final candidates = livingPlayers.where((p) => p.uid != bot.uid).toList();
      if (candidates.isEmpty) continue;

      final target = candidates[Random().nextInt(candidates.length)];
      batch.set(
        roundRef.collection('privateActions').doc(bot.uid),
        {'targetId': target.uid, 'role': role.name},
      );
      added++;
    }

    if (added > 0) {
      batch.update(roundRef, {'actionsCount': FieldValue.increment(added)});
      await batch.commit();
    }
  }

  /// Generates and submits staggered random votes for all living bots.
  Future<void> _triggerBotVotes(String roomId, int roundNumber) async {
    final roomRef = _roomsRef.doc(roomId);
    final roundRef = roomRef.collection('rounds').doc(roundNumber.toString());

    final roundSnap = await roundRef.get();
    if (!roundSnap.exists) return;
    if ((roundSnap.data()!['votesResolved'] as bool?) == true) return;

    final playersSnap = await roomRef.collection('players').get();
    final players =
        playersSnap.docs.map((d) => Player.fromMap(d.data(), d.id)).toList();
    final livingPlayers = players.where((p) => p.isAlive).toList();
    final livingBots = livingPlayers.where((p) => p.isBot).toList();

    if (livingBots.isEmpty) return;

    int botIndex = 0;
    for (final bot in livingBots) {
      final existing =
          await roundRef.collection('privateVotes').doc(bot.uid).get();
      if (existing.exists) continue;

      final candidates = livingPlayers.where((p) => p.uid != bot.uid).toList();
      if (candidates.isEmpty) continue;

      final target = candidates[Random().nextInt(candidates.length)];
      final delayMs = 600 * botIndex;
      botIndex++;

      Future.delayed(Duration(milliseconds: delayMs), () async {
        try {
          final rSnap = await roundRef.get();
          if (!rSnap.exists ||
              (rSnap.data()?['votesResolved'] as bool?) == true) return;
          final bVoteRef = roundRef.collection('privateVotes').doc(bot.uid);
          final bVoteSnap = await bVoteRef.get();
          if (bVoteSnap.exists) return;

          final bBatch = _firestore.batch();
          bBatch.set(bVoteRef, {'targetId': target.uid});
          bBatch.update(roundRef, {
            'votesCount': FieldValue.increment(1),
            'votedUids': FieldValue.arrayUnion([bot.uid]),
          });
          await bBatch.commit();

          _maybeResolveVotesDebounced(roomId, roundNumber);
        } catch (e) {
          debugPrint('Staggered bot vote error for ${bot.uid}: $e');
        }
      });
    }
  }

  // ─── Host round-watch (triggers resolution when non-host players submit) ──

  /// Maintains a host-only listener on the current round document.
  /// When actionsCount or votesCount changes (e.g. a non-host human player
  /// submits), the host is triggered to attempt resolution.
  void _maybeUpdateRoundWatch(Room room) {
    final currentUid = AuthService.instance.currentUid;
    if (currentUid == null || room.hostId != currentUid) {
      _cancelRoundWatch();
      return;
    }
    if (room.status != RoomStatus.playing) {
      _cancelRoundWatch();
      return;
    }
    if (room.currentPhase != GamePhase.actions &&
        room.currentPhase != GamePhase.voting) {
      _cancelRoundWatch();
      return;
    }

    // If already watching this room+round, do nothing
    if (_roundWatchRoomId == room.id &&
        _roundWatchRoundNumber == room.currentRound) {
      return;
    }

    _cancelRoundWatch();
    _roundWatchRoomId = room.id;
    _roundWatchRoundNumber = room.currentRound;

    _roundWatchSubscription = _roomsRef
        .doc(room.id)
        .collection('rounds')
        .doc(room.currentRound.toString())
        .snapshots()
        .listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data()!;
      final actionsResolved = (data['actionsResolved'] as bool?) ?? false;
      final votesResolved = (data['votesResolved'] as bool?) ?? false;
      final actionsCount = (data['actionsCount'] as num?)?.toInt() ?? 0;
      final votesCount = (data['votesCount'] as num?)?.toInt() ?? 0;

      if (!actionsResolved && actionsCount > 0) {
        await _triggerBotActions(room.id, room.currentRound);
        await _maybeResolveActions(room.id, room.currentRound);
      }
      if (!votesResolved && votesCount > 0) {
        await _triggerBotVotes(room.id, room.currentRound);
        await _maybeResolveVotes(room.id, room.currentRound);
      }
    });
  }

  void _cancelRoundWatch() {
    _roundWatchSubscription?.cancel();
    _roundWatchSubscription = null;
    _roundWatchRoomId = null;
    _roundWatchRoundNumber = null;
  }

  // ─── Action resolution (host-authoritative) ───────────────────────────────

  void _maybeResolveActionsDebounced(String roomId, int roundNumber) {
    Future.delayed(const Duration(milliseconds: 300), () {
      _maybeResolveActions(roomId, roundNumber);
    });
  }

  void _maybeResolveVotesDebounced(String roomId, int roundNumber) {
    Future.delayed(const Duration(milliseconds: 300), () {
      _maybeResolveVotes(roomId, roundNumber);
    });
  }

  /// Resolves secret actions for the round if all required submissions are in.
  ///
  /// SPARK: This replaces the _maybeResolveActions internal Cloud Function helper.
  /// The host client reads all privateActions, builds the full role map, runs
  /// GameLogicEngine.resolveSecretActions, and batch-writes results to Firestore.
  Future<void> _maybeResolveActions(String roomId, int roundNumber,
      {bool forceTimeout = false}) async {
    if (_isResolvingActions) return;
    _isResolvingActions = true;
    try {
      final roomRef = _roomsRef.doc(roomId);
      final roundRef = roomRef.collection('rounds').doc(roundNumber.toString());

      // Check we are still the host and in actions phase
      final roomSnap = await roomRef.get();
      if (!roomSnap.exists) return;
      final roomData = roomSnap.data() as Map<String, dynamic>;
      final currentUid = AuthService.instance.currentUid;
      if (roomData['hostId'] != currentUid) return;
      if (roomData['currentPhase'] != 'actions') return;

      final roundSnap = await roundRef.get();
      if (!roundSnap.exists) return;
      if ((roundSnap.data()!['actionsResolved'] as bool?) == true) return;

      // Ensure any living bots submit their actions before checking resolution
      await _triggerBotActions(roomId, roundNumber);

      // Load players
      final playersSnap = await roomRef.collection('players').get();
      final players =
          playersSnap.docs.map((d) => Player.fromMap(d.data(), d.id)).toList();
      final livingPlayers = players.where((p) => p.isAlive).toList();

      // Build role map
      final roleMap = await _buildRoleMap(roomRef, players);

      // Determine which living players must submit actions
      final requiredSubmitters = <String>[];
      for (final player in livingPlayers) {
        final role = roleMap[player.uid] ?? PlayerRole.civilian;
        if (!role.hasSecretAction) continue;
        if (role == PlayerRole.vigilante) {
          final privSnap = await roomRef
              .collection('privatePlayerData')
              .doc(player.uid)
              .get();
          if ((privSnap.data()?['hasUsedAbility'] as bool?) == true) continue;
        }
        requiredSubmitters.add(player.uid);
      }

      // Check all required actions submitted
      final submittedSnap = await roundRef.collection('privateActions').get();
      final submittedUids = submittedSnap.docs.map((d) => d.id).toSet();

      if (!forceTimeout) {
        if (!requiredSubmitters.every(submittedUids.contains)) return;
      }

      // Tally submitted actions
      final Map<String, String> mafiaVotes = {};
      String? doctorTarget;
      final Map<String, String> detectiveTargets = {};
      String? bodyguardTarget;
      String? bodyguardUid;
      String? vigilanteTarget;
      String? vigilanteUid;
      bool vigilanteAlreadyUsed = false;

      for (final doc in submittedSnap.docs) {
        final data = doc.data();
        final role = PlayerRole.fromString(data['role'] as String?);
        final targetId = data['targetId'] as String;

        switch (role) {
          case PlayerRole.mafia:
            mafiaVotes[doc.id] = targetId;
            break;
          case PlayerRole.doctor:
            doctorTarget = targetId;
            break;
          case PlayerRole.detective:
            detectiveTargets[doc.id] = targetId;
            break;
          case PlayerRole.bodyguard:
            bodyguardTarget = targetId;
            bodyguardUid = doc.id;
            break;
          case PlayerRole.vigilante:
            vigilanteTarget = targetId;
            vigilanteUid = doc.id;
            break;
          default:
            break;
        }
      }

      // Check Vigilante hasUsedAbility from privatePlayerData
      if (vigilanteUid != null) {
        final vigSnap = await roomRef
            .collection('privatePlayerData')
            .doc(vigilanteUid)
            .get();
        if ((vigSnap.data()?['hasUsedAbility'] as bool?) == true) {
          vigilanteAlreadyUsed = true;
        }
      }

      final mafiaTarget = GameLogicEngine.resolveMafiaTarget(mafiaVotes);

      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: mafiaTarget,
        doctorTarget: doctorTarget,
        bodyguardTarget: bodyguardTarget,
        bodyguardUid: bodyguardUid,
        vigilanteTarget: vigilanteTarget,
        vigilanteUid: vigilanteUid,
        vigilanteAlreadyUsed: vigilanteAlreadyUsed,
        playerRoles: roleMap,
        detectiveTargets: detectiveTargets,
      );

      final batch = _firestore.batch();

      // Consume Vigilante ability if used
      if (result.vigilanteUsedAbility && vigilanteUid != null) {
        batch.update(
          roomRef.collection('privatePlayerData').doc(vigilanteUid),
          {'hasUsedAbility': true},
        );
      }

      // Mark eliminated players
      for (final elimUid in result.eliminatedPlayerIds) {
        batch.update(
          roomRef.collection('players').doc(elimUid),
          {'isAlive': false},
        );
      }

      // Write Detective results to private subcollection (owner-read only)
      for (final entry in result.detectiveResults.entries) {
        final detectiveUid = entry.key;
        final isMafia = entry.value;
        batch.set(
          roundRef.collection('privateResults').doc(detectiveUid),
          {
            'targetId': detectiveTargets[detectiveUid],
            'isMafia': isMafia,
          },
        );
      }

      // Write Bodyguard interception result if occurred
      if (result.bodyguardIntercepted && bodyguardUid != null) {
        batch.set(
          roundRef.collection('privateResults').doc(bodyguardUid),
          {
            'targetId': bodyguardTarget ?? '',
            'isMafia': false,
            'bodyguardIntercepted': true,
          },
          SetOptions(merge: true),
        );
      }

      // Update public round doc with resolution summary
      batch.update(roundRef, {
        'actionsResolved': true,
        'eliminatedInActions': result.eliminatedPlayerId,
        'eliminatedPlayerIds': result.eliminatedPlayerIds,
      });

      // Win check after eliminations
      final updatedLiving = livingPlayers
          .where((p) => !result.eliminatedPlayerIds.contains(p.uid))
          .toList();
      final winCheck = GameLogicEngine.checkWinCondition(
        updatedLiving,
        roleOverrides: roleMap,
      );

      if (winCheck.isGameOver) {
        for (final player in players) {
          batch.update(
            roomRef.collection('players').doc(player.uid),
            {'role': (roleMap[player.uid] ?? PlayerRole.civilian).name},
          );
        }
        batch.update(roomRef, {
          'status': 'GAME_OVER',
          'currentPhase': 'gameOver',
          'winner': winCheck.winner,
          'eliminatedThisRound': result.eliminatedPlayerId,
          'publicMessage': '${result.publicMessage} ${winCheck.reason}',
        });
      } else {
        batch.update(roomRef, {
          'currentPhase': 'roundResult',
          'eliminatedThisRound': result.eliminatedPlayerId,
          'publicMessage': result.publicMessage,
        });
      }

      await batch.commit();
      if (winCheck.isGameOver) {
        _cancelRoundWatch();
      }
    } catch (e) {
      debugPrint('_maybeResolveActions error: $e');
    } finally {
      _isResolvingActions = false;
    }
  }

  /// Resolves the voting phase if all living players have voted.
  ///
  /// SPARK: Replaces the _maybeResolveVotes Cloud Function helper.
  Future<void> _maybeResolveVotes(String roomId, int roundNumber,
      {bool forceTimeout = false}) async {
    if (_isResolvingVotes) return;
    _isResolvingVotes = true;
    try {
      final roomRef = _roomsRef.doc(roomId);
      final roundRef = roomRef.collection('rounds').doc(roundNumber.toString());

      final roomSnap = await roomRef.get();
      if (!roomSnap.exists) return;
      final roomData = roomSnap.data() as Map<String, dynamic>;
      final currentUid = AuthService.instance.currentUid;
      if (roomData['hostId'] != currentUid) return;
      if (roomData['currentPhase'] != 'voting') return;

      final roundSnap = await roundRef.get();
      if (!roundSnap.exists) return;
      if ((roundSnap.data()!['votesResolved'] as bool?) == true) return;

      // Ensure any living bots have submitted their votes before checking resolution
      await _triggerBotVotes(roomId, roundNumber);

      final playersSnap = await roomRef.collection('players').get();
      final players =
          playersSnap.docs.map((d) => Player.fromMap(d.data(), d.id)).toList();
      final livingPlayers = players.where((p) => p.isAlive).toList();

      // Check all living players voted
      final votedSnap = await roundRef.collection('privateVotes').get();
      final votedUids = votedSnap.docs.map((d) => d.id).toSet();
      final livingUids = livingPlayers.map((p) => p.uid).toSet();

      if (!forceTimeout) {
        if (!livingUids.every(votedUids.contains)) return;
      }

      // Tally votes
      final Map<String, String> votes = {};
      final Map<String, int> voteTally = {};
      for (final doc in votedSnap.docs) {
        final targetId = doc.data()['targetId'] as String;
        votes[doc.id] = targetId;
        voteTally[targetId] = (voteTally[targetId] ?? 0) + 1;
      }

      final eliminatedId = GameLogicEngine.resolveVoteElimination(votes);

      final batch = _firestore.batch();

      if (eliminatedId != null) {
        batch.update(
          roomRef.collection('players').doc(eliminatedId),
          {'isAlive': false},
        );
      }

      batch.update(roundRef, {
        'votesResolved': true,
        'eliminatedInVote': eliminatedId,
        'voteTally': voteTally,
      });

      // Win check after vote elimination
      final roleMap = await _buildRoleMap(roomRef, players);
      final updatedLiving =
          livingPlayers.where((p) => p.uid != eliminatedId).toList();
      final winCheck = GameLogicEngine.checkWinCondition(
        updatedLiving,
        roleOverrides: roleMap,
      );

      if (winCheck.isGameOver) {
        for (final player in players) {
          batch.update(
            roomRef.collection('players').doc(player.uid),
            {'role': (roleMap[player.uid] ?? PlayerRole.civilian).name},
          );
        }
        batch.update(roomRef, {
          'status': 'GAME_OVER',
          'currentPhase': 'gameOver',
          'winner': winCheck.winner,
          'votedOutThisRound': eliminatedId,
          'publicMessage': winCheck.reason,
        });
      } else {
        batch.update(roomRef, {
          'currentPhase': 'elimination',
          'votedOutThisRound': eliminatedId,
          'publicMessage': eliminatedId != null
              ? 'The town has voted. A player has been eliminated.'
              : 'The vote was tied. No one was eliminated.',
        });
      }

      await batch.commit();
      if (winCheck.isGameOver) {
        _cancelRoundWatch();
      }
    } catch (e) {
      debugPrint('_maybeResolveVotes error: $e');
    } finally {
      _isResolvingVotes = false;
    }
  }

  @override
  Future<void> resolveVotesOnTimeout(String roomId, int roundNumber) async {
    final currentUid = AuthService.instance.currentUid;
    if (currentUid == null) return;
    final roomRef = _roomsRef.doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) return;
    final roomData = roomSnap.data() as Map<String, dynamic>;
    if (roomData['hostId'] != currentUid) return;
    if (roomData['currentPhase'] != 'voting') return;

    await _maybeResolveVotes(roomId, roundNumber, forceTimeout: true);
  }

  @override
  Future<void> resolveActionsOnTimeout(String roomId, int roundNumber) async {
    final currentUid = AuthService.instance.currentUid;
    if (currentUid == null) return;
    final roomRef = _roomsRef.doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) return;
    final roomData = roomSnap.data() as Map<String, dynamic>;
    if (roomData['hostId'] != currentUid) return;
    if (roomData['currentPhase'] != 'actions') return;

    await _maybeResolveActions(roomId, roundNumber, forceTimeout: true);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Builds a uid→PlayerRole map by reading all privatePlayerData documents.
  /// Host has read access to all privatePlayerData during gameplay.
  Future<Map<String, PlayerRole>> _buildRoleMap(
    DocumentReference roomRef,
    List<Player> players,
  ) async {
    final Map<String, PlayerRole> roleMap = {};
    for (final player in players) {
      try {
        final snap =
            await roomRef.collection('privatePlayerData').doc(player.uid).get();
        if (snap.exists) {
          roleMap[player.uid] =
              PlayerRole.fromString(snap.data()!['role'] as String?);
        } else {
          roleMap[player.uid] = PlayerRole.civilian;
        }
      } catch (e) {
        roleMap[player.uid] = PlayerRole.civilian;
      }
    }
    return roleMap;
  }

  /// Best-effort cleanup of Firestore subcollections when a room is abandoned.
  ///
  /// SPARK LIMITATION: The Firestore client SDK cannot recursively delete
  /// subcollections. This method deletes known top-level subcollections
  /// (players, messages, spectatorMessages, rounds) and round sub-docs.
  /// Orphaned privatePlayerData / privateActions / privateVotes / privateResults
  /// documents may persist but are inaccessible to other users per security rules.
  Future<void> _cleanupRoomSubcollections(String roomId) async {
    try {
      final roomRef = _roomsRef.doc(roomId);

      // Delete messages and spectatorMessages
      for (final sub in ['messages', 'spectatorMessages', 'players']) {
        final snap = await roomRef.collection(sub).get();
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        if (snap.docs.isNotEmpty) await batch.commit();
      }

      // Delete rounds and their private subcollections
      final roundsSnap = await roomRef.collection('rounds').get();
      for (final roundDoc in roundsSnap.docs) {
        for (final sub in [
          'privateActions',
          'privateVotes',
          'privateResults'
        ]) {
          final subSnap = await roundDoc.reference.collection(sub).get();
          final batch = _firestore.batch();
          for (final doc in subSnap.docs) {
            batch.delete(doc.reference);
          }
          if (subSnap.docs.isNotEmpty) await batch.commit();
        }
        await roundDoc.reference.delete();
      }

      // Delete privatePlayerData
      final privSnap = await roomRef.collection('privatePlayerData').get();
      final batch = _firestore.batch();
      for (final doc in privSnap.docs) {
        batch.delete(doc.reference);
      }
      if (privSnap.docs.isNotEmpty) await batch.commit();
    } catch (e) {
      debugPrint('Room cleanup error (best-effort, non-fatal): $e');
    }
  }

  @override
  Future<void> resetRoomForNewGame(String roomId) async {
    final roomRef = _roomsRef.doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) throw Exception('Room not found.');

    final roomData = roomSnap.data() as Map<String, dynamic>;
    final currentStatus = RoomStatus.fromString(roomData['status'] as String?);
    final currentPhase =
        GamePhase.fromString(roomData['currentPhase'] as String?);
    final currentRound = roomData['currentRound'] as int? ?? 0;

    // Idempotency: if already fully reset to lobby, return early.
    if (currentStatus == RoomStatus.lobby &&
        currentPhase == GamePhase.lobby &&
        currentRound == 0) {
      return;
    }

    final batch = _firestore.batch();

    // 1. Reset Room fields back to lobby
    batch.update(roomRef, {
      'status': 'LOBBY',
      'currentPhase': GamePhase.lobby.name,
      'currentRound': 0,
      'winner': FieldValue.delete(),
      'eliminatedThisRound': FieldValue.delete(),
      'votedOutThisRound': FieldValue.delete(),
      'publicMessage': FieldValue.delete(),
      'discussionEndTimestamp': FieldValue.delete(),
      'votingEndTimestamp': FieldValue.delete(),
      'actionsEndTimestamp': FieldValue.delete(),
    });

    // 2. Revive all players and reset public roles back to unknown (preserving host & players)
    final playersSnap = await roomRef.collection('players').get();
    for (final doc in playersSnap.docs) {
      batch.update(doc.reference, {
        'isAlive': true,
        'role': PlayerRole.unknown.name,
      });
    }

    // 3. Clear privatePlayerData docs so stale roles are gone
    final privateDataSnap = await roomRef.collection('privatePlayerData').get();
    for (final doc in privateDataSnap.docs) {
      batch.delete(doc.reference);
    }

    // 4. Delete discussion messages from previous game
    final messagesSnap = await roomRef.collection('messages').get();
    for (final doc in messagesSnap.docs) {
      batch.delete(doc.reference);
    }

    // 5. Delete spectator messages from previous game
    final spectatorMessagesSnap =
        await roomRef.collection('spectatorMessages').get();
    for (final doc in spectatorMessagesSnap.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();

    // 6. Delete previous rounds and their subcollections (actions, votes, private results)
    try {
      final roundsSnap = await roomRef.collection('rounds').get();
      for (final roundDoc in roundsSnap.docs) {
        for (final sub in [
          'actions',
          'votes',
          'privateActions',
          'privateVotes',
          'privateResults'
        ]) {
          final subSnap = await roundDoc.reference.collection(sub).get();
          if (subSnap.docs.isNotEmpty) {
            final subBatch = _firestore.batch();
            for (final doc in subSnap.docs) {
              subBatch.delete(doc.reference);
            }
            await subBatch.commit();
          }
        }
        await roundDoc.reference.delete();
      }
    } catch (e) {
      debugPrint('Rounds cleanup during reset (best-effort, non-fatal): $e');
    }
  }
}
