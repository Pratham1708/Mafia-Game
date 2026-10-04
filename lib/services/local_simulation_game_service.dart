import 'dart:async';
import 'dart:math';
import '../models/chat_message.dart';
import '../models/game_phase.dart';
import '../models/player.dart';
import '../models/player_role.dart';
import '../models/private_action.dart';
import '../models/private_player_data.dart';
import '../models/private_result.dart';
import '../models/private_vote.dart';
import '../models/room.dart';
import '../models/round_data.dart';
import '../models/game_config.dart';
import '../utils/room_code_generator.dart';
import 'auth_service.dart';
import 'game_logic_engine.dart';
import 'game_service_interface.dart';

/// In-memory reactive implementation of [IGameService] for local testing.
///
/// Private data (roles, actions, votes, detective results) is kept in separate
/// in-memory maps that mirror the Firestore private subcollection structure.
/// This ensures the local simulation correctly models the read-isolation design
/// even without real Firestore security rules.
class LocalSimulationGameService implements IGameService {
  /// When true, bot action and vote delays are shortened for instantaneous test execution.
  bool fastBotDelays = false;

  // ─── Public state ──────────────────────────────────────────────────────────
  final Map<String, Room> _rooms = {};
  final Map<String, List<Player>> _players = {};
  final Map<String, Map<int, RoundData>> _rounds = {};

  // ─── Private state (mirrors Firestore private subcollections) ─────────────
  // roles: roomId → uid → PlayerRole
  final Map<String, Map<String, PlayerRole>> _privateRoles = {};
  // actions: roomId → roundNumber → uid → PrivateAction
  final Map<String, Map<int, Map<String, PrivateAction>>> _privateActions = {};
  // votes: roomId → roundNumber → uid → PrivateVote
  final Map<String, Map<int, Map<String, PrivateVote>>> _privateVotes = {};
  // detective results: roomId → roundNumber → detectiveUid → PrivateResult
  final Map<String, Map<int, Map<String, PrivateResult>>> _privateResults = {};
  // vigilante ability usage: roomId → uid → bool
  final Map<String, Map<String, bool>> _vigilanteUsedAbility = {};

  // ─── Realtime Chat state ───────────────────────────────────────────────────
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, List<ChatMessage>> _spectatorMessages = {};

  // ─── Stream controllers ────────────────────────────────────────────────────
  final Map<String, StreamController<Room>> _roomControllers = {};
  final Map<String, StreamController<List<Player>>> _playerControllers = {};
  final Map<String, StreamController<List<ChatMessage>>> _messageControllers =
      {};
  final Map<String, StreamController<List<ChatMessage>>>
      _spectatorMessageControllers = {};
  final Map<String, Map<int, StreamController<RoundData>>> _roundControllers =
      {};
  final Map<String, StreamController<PlayerRole>> _myRoleControllers = {};
  final Map<String, StreamController<PrivatePlayerData?>>
      _myPlayerDataControllers = {};
  final Map<String, Map<int, StreamController<PrivateAction?>>>
      _myActionControllers = {};
  final Map<String, Map<int, StreamController<PrivateResult?>>>
      _myResultControllers = {};
  final Map<String, Map<int, StreamController<PrivateVote?>>>
      _myVoteControllers = {};

  // ─── Controller accessors ──────────────────────────────────────────────────

  StreamController<Room> _getRoomController(String roomId) => _roomControllers
      .putIfAbsent(roomId, () => StreamController<Room>.broadcast());

  StreamController<List<Player>> _getPlayerController(String roomId) =>
      _playerControllers.putIfAbsent(
          roomId, () => StreamController<List<Player>>.broadcast());

  StreamController<List<ChatMessage>> _getMessageController(String roomId) =>
      _messageControllers.putIfAbsent(
          roomId, () => StreamController<List<ChatMessage>>.broadcast());

  StreamController<List<ChatMessage>> _getSpectatorMessageController(
          String roomId) =>
      _spectatorMessageControllers.putIfAbsent(
          roomId, () => StreamController<List<ChatMessage>>.broadcast());

  StreamController<RoundData> _getRoundController(String roomId, int rn) {
    final roomMap = _roundControllers.putIfAbsent(roomId, () => {});
    return roomMap.putIfAbsent(
        rn, () => StreamController<RoundData>.broadcast());
  }

  StreamController<PlayerRole> _getMyRoleController(String roomId) =>
      _myRoleControllers.putIfAbsent(
          roomId, () => StreamController<PlayerRole>.broadcast());

  StreamController<PrivatePlayerData?> _getMyPlayerDataController(
          String roomId) =>
      _myPlayerDataControllers.putIfAbsent(
          roomId, () => StreamController<PrivatePlayerData?>.broadcast());

  StreamController<PrivateAction?> _getMyActionController(
      String roomId, int rn) {
    final roomMap = _myActionControllers.putIfAbsent(roomId, () => {});
    return roomMap.putIfAbsent(
        rn, () => StreamController<PrivateAction?>.broadcast());
  }

  StreamController<PrivateResult?> _getMyResultController(
      String roomId, int rn) {
    final roomMap = _myResultControllers.putIfAbsent(roomId, () => {});
    return roomMap.putIfAbsent(
        rn, () => StreamController<PrivateResult?>.broadcast());
  }

  StreamController<PrivateVote?> _getMyVoteController(String roomId, int rn) {
    final roomMap = _myVoteControllers.putIfAbsent(roomId, () => {});
    return roomMap.putIfAbsent(
        rn, () => StreamController<PrivateVote?>.broadcast());
  }

  // ─── Notify helpers ────────────────────────────────────────────────────────

  void _notifyRoom(String roomId) {
    final room = _rooms[roomId];
    if (room != null) _getRoomController(roomId).add(room);
  }

  void _notifyPlayers(String roomId) {
    final players = _players[roomId];
    if (players != null) {
      _getPlayerController(roomId).add(List.unmodifiable(players));
    }
  }

  void _notifyMessages(String roomId) {
    final msgs = _messages[roomId] ?? [];
    _getMessageController(roomId).add(List.unmodifiable(msgs));
  }

  void _notifySpectatorMessages(String roomId) {
    final msgs = _spectatorMessages[roomId] ?? [];
    _getSpectatorMessageController(roomId).add(List.unmodifiable(msgs));
  }

  void _notifyRound(String roomId, int roundNumber) {
    final round = _rounds[roomId]?[roundNumber];
    if (round != null) _getRoundController(roomId, roundNumber).add(round);
  }

  void _notifyMyRole(String roomId, String uid) {
    final role = _privateRoles[roomId]?[uid] ?? PlayerRole.unknown;
    _getMyRoleController(roomId).add(role);
  }

  void _notifyMyPlayerData(String roomId, String uid) {
    final role = _privateRoles[roomId]?[uid] ?? PlayerRole.unknown;
    final used = _vigilanteUsedAbility[roomId]?[uid] ?? false;
    _getMyPlayerDataController(roomId).add(
      PrivatePlayerData(role: role, hasUsedAbility: used),
    );
  }

  void _notifyMyAction(String roomId, int rn, String uid) {
    final action = _privateActions[roomId]?[rn]?[uid];
    _getMyActionController(roomId, rn).add(action);
  }

  void _notifyMyResult(String roomId, int rn, String uid) {
    final result = _privateResults[roomId]?[rn]?[uid];
    _getMyResultController(roomId, rn).add(result);
  }

  void _notifyMyVote(String roomId, int rn, String uid) {
    final vote = _privateVotes[roomId]?[rn]?[uid];
    _getMyVoteController(roomId, rn).add(vote);
  }

  // ─── Room lifecycle ────────────────────────────────────────────────────────

  @override
  Future<Room> createRoom({required String hostName}) async {
    final uid = AuthService.instance.currentUid ?? 'local_host';
    final roomId = 'room_${Random().nextInt(999999)}';
    final code = RoomCodeGenerator.generate();

    final room = Room(
      id: roomId,
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
      name: hostName,
      isAlive: true,
      isHost: true,
      joinedAt: DateTime.now(),
    );

    _rooms[roomId] = room;
    _players[roomId] = [hostPlayer];
    _rounds[roomId] = {};
    _privateRoles[roomId] = {};

    _notifyRoom(roomId);
    _notifyPlayers(roomId);
    return room;
  }

  @override
  Future<Room> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    final uid = AuthService.instance.currentUid ?? 'local_user';
    final sanitizedCode = RoomCodeGenerator.sanitize(roomCode);
    if (!RoomCodeGenerator.isValid(sanitizedCode)) {
      throw Exception('Check the room code and try again.');
    }

    final validName = AuthService.validateDisplayName(playerName);
    if (validName == null) {
      throw Exception('Name must be between 2 and 20 characters.');
    }

    final entry = _rooms.entries.cast<MapEntry<String, Room>?>().firstWhere(
          (e) => e?.value.code == sanitizedCode,
          orElse: () => null,
        );

    if (entry == null) {
      throw Exception('Check the room code and try again.');
    }

    final roomId = entry.key;
    final room = entry.value;
    if (room.status == RoomStatus.gameOver) {
      throw Exception('This game has already ended.');
    }

    final players = _players[roomId] ?? [];
    final isExistingPlayer = players.any((p) => p.uid == uid);

    if (isExistingPlayer) {
      // Reconnect active player
      return room;
    }

    if (room.status != RoomStatus.lobby) {
      throw Exception('This game has already started.');
    }

    if (players.length >= room.maxPlayers) {
      throw Exception('This room already has 12 players.');
    }

    players.add(Player(
      uid: uid,
      name: validName,
      isAlive: true,
      isHost: false,
      joinedAt: DateTime.now(),
    ));
    _notifyPlayers(roomId);
    return room;
  }

  @override
  Future<void> leaveRoom({required String roomId, required String uid}) async {
    final players = _players[roomId];
    if (players == null) return;

    final room = _rooms[roomId];
    if (room != null && room.hostId == uid) {
      final remaining = players.where((p) => p.uid != uid).toList();
      if (remaining.isEmpty) {
        _rooms.remove(roomId);
        _players.remove(roomId);
        _rounds.remove(roomId);
        _privateRoles.remove(roomId);
        return;
      }
      // Safe host transfer to the next remaining player
      final newHost = remaining.first.copyWith(isHost: true);
      final updatedPlayers = [
        newHost,
        ...remaining.skip(1),
      ];
      _players[roomId] = updatedPlayers;
      final updatedRoom = room.copyWith(hostId: newHost.uid);
      _rooms[roomId] = updatedRoom;
      _notifyRoom(roomId);
      _notifyPlayers(roomId);
      return;
    }

    players.removeWhere((p) => p.uid == uid);
    if (players.isEmpty) {
      _rooms.remove(roomId);
      _players.remove(roomId);
      _rounds.remove(roomId);
      _privateRoles.remove(roomId);
      return;
    }
    _notifyPlayers(roomId);
  }

  @override
  Future<void> claimHost(String roomId) async {
    final uid = AuthService.instance.currentUid ?? 'local_user';
    final room = _rooms[roomId];
    if (room == null)
      throw Exception('Room not found. Check the room code and try again.');
    if (room.status == RoomStatus.gameOver) {
      throw Exception('Cannot change host after game over.');
    }

    final players = _players[roomId];
    if (players == null || !players.any((p) => p.uid == uid)) {
      throw Exception('You are not a member of this room.');
    }

    final claimant = players.firstWhere((p) => p.uid == uid);
    if (!claimant.isAlive) {
      throw Exception('Eliminated players cannot claim host.');
    }

    if (room.hostId == uid) return;

    final updatedPlayers = players.map((p) {
      if (p.uid == uid) {
        return p.copyWith(isHost: true);
      } else if (p.isHost) {
        return p.copyWith(isHost: false);
      }
      return p;
    }).toList();

    _players[roomId] = updatedPlayers;
    _rooms[roomId] = room.copyWith(hostId: uid);
    _notifyRoom(roomId);
    _notifyPlayers(roomId);
  }

  // ─── Public streams ────────────────────────────────────────────────────────

  @override
  Stream<Room> streamRoom(String roomId) {
    final controller = _getRoomController(roomId);
    final room = _rooms[roomId];
    if (room != null) Future.microtask(() => controller.add(room));
    return controller.stream;
  }

  @override
  Stream<List<Player>> streamPlayers(String roomId) {
    final controller = _getPlayerController(roomId);
    final players = _players[roomId];
    if (players != null) {
      Future.microtask(() => controller.add(List.unmodifiable(players)));
    }
    return controller.stream;
  }

  @override
  Stream<RoundData> streamRound(String roomId, int roundNumber) {
    final controller = _getRoundController(roomId, roundNumber);
    final round =
        _rounds[roomId]?[roundNumber] ?? RoundData(roundNumber: roundNumber);
    Future.microtask(() => controller.add(round));
    return controller.stream;
  }

  @override
  Stream<List<ChatMessage>> streamMessages(String roomId) {
    final controller = _getMessageController(roomId);
    final msgs = _messages[roomId] ?? [];
    Future.microtask(() => controller.add(List.unmodifiable(msgs)));
    return controller.stream;
  }

  @override
  Stream<List<ChatMessage>> streamSpectatorMessages(String roomId) {
    final controller = _getSpectatorMessageController(roomId);
    final msgs = _spectatorMessages[roomId] ?? [];
    Future.microtask(() => controller.add(List.unmodifiable(msgs)));
    return controller.stream;
  }

  // ─── Private streams (current player only) ────────────────────────────────

  @override
  Stream<PlayerRole> streamMyRole(String roomId) {
    final uid = AuthService.instance.currentUid ?? 'local_host';
    final controller = _getMyRoleController(roomId);
    final role = _privateRoles[roomId]?[uid] ?? PlayerRole.unknown;
    Future.microtask(() => controller.add(role));
    return controller.stream;
  }

  @override
  Stream<PrivatePlayerData?> streamMyPlayerData(String roomId) {
    final uid = AuthService.instance.currentUid ?? 'local_host';
    final controller = _getMyPlayerDataController(roomId);
    final role = _privateRoles[roomId]?[uid] ?? PlayerRole.unknown;
    final used = _vigilanteUsedAbility[roomId]?[uid] ?? false;
    Future.microtask(() =>
        controller.add(PrivatePlayerData(role: role, hasUsedAbility: used)));
    return controller.stream;
  }

  @override
  Stream<PrivateAction?> streamMyAction(String roomId, int roundNumber) {
    final uid = AuthService.instance.currentUid ?? 'local_host';
    final controller = _getMyActionController(roomId, roundNumber);
    final action = _privateActions[roomId]?[roundNumber]?[uid];
    Future.microtask(() => controller.add(action));
    return controller.stream;
  }

  @override
  Stream<PrivateResult?> streamMyResult(String roomId, int roundNumber) {
    final uid = AuthService.instance.currentUid ?? 'local_host';
    final controller = _getMyResultController(roomId, roundNumber);
    final result = _privateResults[roomId]?[roundNumber]?[uid];
    Future.microtask(() => controller.add(result));
    return controller.stream;
  }

  @override
  Stream<PrivateVote?> streamMyVote(String roomId, int roundNumber) {
    final uid = AuthService.instance.currentUid ?? 'local_host';
    final controller = _getMyVoteController(roomId, roundNumber);
    final vote = _privateVotes[roomId]?[roundNumber]?[uid];
    Future.microtask(() => controller.add(vote));
    return controller.stream;
  }

  // ─── Game actions ──────────────────────────────────────────────────────────

  @override
  Future<void> startGame(String roomId) async {
    final room = _rooms[roomId];
    if (room == null) throw Exception('Room not found.');
    if (room.status == RoomStatus.gameOver) {
      throw Exception('This game has already ended.');
    }
    if (room.status != RoomStatus.lobby) {
      throw Exception('Game has already started.');
    }

    final players = _players[roomId] ?? [];
    if (players.length < GameConfig.minPlayers) {
      throw Exception(
          'At least ${GameConfig.minPlayers} players are required to start Mafia.');
    }
    if (players.length > 12) {
      throw Exception('Maximum 12 players allowed.');
    }

    final assignments =
        GameLogicEngine.assignRoles(players.map((p) => p.uid).toList());

    // Write roles to private map (mirrors privatePlayerData Firestore collection)
    _privateRoles[roomId] = {};
    _vigilanteUsedAbility[roomId] = {};
    for (final p in players) {
      final role = assignments[p.uid] ?? PlayerRole.civilian;
      _privateRoles[roomId]![p.uid] = role;
    }

    _rounds[roomId] ??= {};
    _rounds[roomId]![1] = const RoundData(roundNumber: 1);

    _rooms[roomId] = room.copyWith(
      status: RoomStatus.playing,
      currentRound: 1,
      currentPhase: GamePhase.roleReveal,
      publicMessage: 'Game started! Memorize your secret role.',
    );

    // Notify current player of their private role
    final currentUid = AuthService.instance.currentUid ?? 'local_host';
    _notifyMyRole(roomId, currentUid);
    _notifyMyPlayerData(roomId, currentUid);
    _notifyPlayers(roomId);
    _notifyRound(roomId, 1);
    _notifyRoom(roomId);
  }

  @override
  Future<void> advanceToActions(String roomId) async {
    final room = _rooms[roomId];
    if (room == null) throw Exception('Room not found.');
    if (room.status == RoomStatus.lobby) {
      throw Exception('Cannot advance to actions before game has started.');
    }
    if (room.status == RoomStatus.gameOver) {
      throw Exception('This game has already ended.');
    }

    final durationSeconds = GameConfig.defaultActionsDurationSeconds;
    final endTimestamp = DateTime.now().add(Duration(seconds: durationSeconds));
    _rooms[roomId] = room.copyWith(
      currentPhase: GamePhase.actions,
      actionsEndTimestamp: endTimestamp,
      actionsDurationSeconds: durationSeconds,
      publicMessage:
          'Secret actions in progress. Choose your targets carefully.',
    );
    _notifyRoom(roomId);
    _simulateBotActions(roomId, room.currentRound);
  }

  @override
  Future<void> submitAction({
    required String roomId,
    required int roundNumber,
    required String uid,
    required String targetId,
    required PlayerRole role,
  }) async {
    final room = _rooms[roomId];
    if (room == null) return;

    if (role == PlayerRole.vigilante) {
      final used = _vigilanteUsedAbility[roomId]?[uid] ?? false;
      if (used) {
        throw Exception('Vigilante has already used their one-time ability.');
      }
      if (targetId.isNotEmpty && targetId != 'skip' && targetId == uid) {
        throw Exception('You cannot target yourself.');
      }
    } else if (role == PlayerRole.bodyguard ||
        role == PlayerRole.detective ||
        role == PlayerRole.mafia) {
      if (targetId == uid) {
        throw Exception('You cannot target yourself.');
      }
    }

    // Write private action
    _privateActions[roomId] ??= {};
    _privateActions[roomId]![roundNumber] ??= {};
    _privateActions[roomId]![roundNumber]![uid] =
        PrivateAction(targetId: targetId, role: role);

    // Update public round: increment count only
    final roundMap = _rounds[roomId] ?? {};
    final currentRound =
        roundMap[roundNumber] ?? RoundData(roundNumber: roundNumber);
    final newCount = _privateActions[roomId]![roundNumber]!.length;
    roundMap[roundNumber] = currentRound.copyWith(actionsCount: newCount);
    _rounds[roomId] = roundMap;
    _notifyRound(roomId, roundNumber);

    // Notify submitting player of their own private action
    _notifyMyAction(roomId, roundNumber, uid);

    // Check completion
    final players = _players[roomId] ?? [];
    final livingNeedingAction = players.where((p) {
      if (!p.isAlive) return false;
      final pRole = _privateRoles[roomId]?[p.uid] ?? PlayerRole.civilian;
      if (!pRole.hasSecretAction) return false;
      if (pRole == PlayerRole.vigilante &&
          (_vigilanteUsedAbility[roomId]?[p.uid] ?? false)) {
        return false;
      }
      return true;
    }).toList();

    final submittedUids = _privateActions[roomId]![roundNumber]!.keys.toSet();
    final allDone =
        livingNeedingAction.every((p) => submittedUids.contains(p.uid));

    if (allDone && !currentRound.actionsResolved) {
      _resolveActions(roomId, roundNumber);
    }
  }

  void _simulateBotActions(String roomId, int roundNumber) {
    final players = _players[roomId] ?? [];
    final currentUid = AuthService.instance.currentUid;
    final bots =
        players.where((p) => p.isAlive && p.uid != currentUid).toList();
    final livingTargets = players.where((p) => p.isAlive).toList();

    for (int i = 0; i < bots.length; i++) {
      final bot = bots[i];
      final botRole = _privateRoles[roomId]?[bot.uid] ?? PlayerRole.civilian;
      if (!botRole.hasSecretAction || livingTargets.isEmpty) continue;

      if (botRole == PlayerRole.vigilante) {
        if (_vigilanteUsedAbility[roomId]?[bot.uid] == true) continue;
        // Bot vigilante: 30% chance to shoot, else hold fire
        if (Random().nextDouble() < 0.3) {
          final candidates =
              livingTargets.where((p) => p.uid != bot.uid).toList();
          if (candidates.isNotEmpty) {
            final target = candidates[Random().nextInt(candidates.length)];
            final delay = fastBotDelays ? 10 : (600 + (i * 250));
            Future.delayed(Duration(milliseconds: delay), () {
              submitAction(
                roomId: roomId,
                roundNumber: roundNumber,
                uid: bot.uid,
                targetId: target.uid,
                role: botRole,
              );
            });
            continue;
          }
        }
        // Hold fire
        final delay = fastBotDelays ? 10 : (600 + (i * 250));
        Future.delayed(Duration(milliseconds: delay), () {
          submitAction(
            roomId: roomId,
            roundNumber: roundNumber,
            uid: bot.uid,
            targetId: 'skip',
            role: botRole,
          );
        });
        continue;
      }

      final possibleTargets = (botRole == PlayerRole.detective ||
              botRole == PlayerRole.bodyguard ||
              botRole == PlayerRole.mafia)
          ? livingTargets.where((p) => p.uid != bot.uid).toList()
          : livingTargets;

      if (possibleTargets.isNotEmpty) {
        final target =
            possibleTargets[Random().nextInt(possibleTargets.length)];
        final delay = fastBotDelays ? 10 : (600 + (i * 250));
        Future.delayed(Duration(milliseconds: delay), () {
          submitAction(
            roomId: roomId,
            roundNumber: roundNumber,
            uid: bot.uid,
            targetId: target.uid,
            role: botRole,
          );
        });
      }
    }
  }

  void _resolveActions(String roomId, int roundNumber) {
    final players = _players[roomId] ?? [];
    final round = _rounds[roomId]?[roundNumber];
    if (round == null) return;

    final playerRoles = {
      for (final p in players)
        p.uid: _privateRoles[roomId]?[p.uid] ?? PlayerRole.civilian
    };

    final actionsMap = _privateActions[roomId]?[roundNumber] ?? {};
    final mafiaVotes = <String, String>{};
    String? doctorTarget;
    final detectiveTargets = <String, String>{};
    String? bodyguardTarget;
    String? bodyguardUid;
    String? vigilanteTarget;
    String? vigilanteUid;

    actionsMap.forEach((uid, action) {
      if (action.role == PlayerRole.mafia) {
        mafiaVotes[uid] = action.targetId;
      } else if (action.role == PlayerRole.doctor) {
        doctorTarget = action.targetId;
      } else if (action.role == PlayerRole.detective) {
        detectiveTargets[uid] = action.targetId;
      } else if (action.role == PlayerRole.bodyguard) {
        bodyguardTarget = action.targetId;
        bodyguardUid = uid;
      } else if (action.role == PlayerRole.vigilante) {
        vigilanteTarget = action.targetId;
        vigilanteUid = uid;
      }
    });

    final bool vigAlreadyUsed = vigilanteUid != null &&
        (_vigilanteUsedAbility[roomId]?[vigilanteUid] ?? false);

    final mafiaTarget = GameLogicEngine.resolveMafiaTarget(mafiaVotes);
    final result = GameLogicEngine.resolveSecretActions(
      mafiaTarget: mafiaTarget,
      doctorTarget: doctorTarget,
      bodyguardTarget: bodyguardTarget,
      bodyguardUid: bodyguardUid,
      vigilanteTarget: vigilanteTarget,
      vigilanteUid: vigilanteUid,
      vigilanteAlreadyUsed: vigAlreadyUsed,
      playerRoles: playerRoles,
      detectiveTargets: detectiveTargets,
    );

    if (result.vigilanteUsedAbility && vigilanteUid != null) {
      _vigilanteUsedAbility[roomId] ??= {};
      _vigilanteUsedAbility[roomId]![vigilanteUid!] = true;
      _notifyMyPlayerData(roomId, vigilanteUid!);
    }

    if (result.eliminatedPlayerIds.isNotEmpty) {
      for (int i = 0; i < players.length; i++) {
        if (result.eliminatedPlayerIds.contains(players[i].uid)) {
          players[i] = players[i].copyWith(isAlive: false);
        }
      }
      _notifyPlayers(roomId);
    }

    // Write private detective results
    _privateResults[roomId] ??= {};
    _privateResults[roomId]![roundNumber] ??= {};
    for (final entry in result.detectiveResults.entries) {
      final detectiveUid = entry.key;
      _privateResults[roomId]![roundNumber]![detectiveUid] = PrivateResult(
        targetId: detectiveTargets[detectiveUid] ?? '',
        isMafia: entry.value,
      );
      final currentUid = AuthService.instance.currentUid;
      if (detectiveUid == currentUid) {
        _notifyMyResult(roomId, roundNumber, detectiveUid);
      }
    }

    // Write Bodyguard interception result
    if (result.bodyguardIntercepted && bodyguardUid != null) {
      _privateResults[roomId] ??= {};
      _privateResults[roomId]![roundNumber] ??= {};
      _privateResults[roomId]![roundNumber]![bodyguardUid!] = PrivateResult(
        targetId: bodyguardTarget ?? '',
        isMafia: false,
        bodyguardIntercepted: true,
      );
      final currentUid = AuthService.instance.currentUid;
      if (bodyguardUid == currentUid) {
        _notifyMyResult(roomId, roundNumber, bodyguardUid!);
      }
    }

    // Update public round
    _rounds[roomId]![roundNumber] = round.copyWith(
      actionsResolved: true,
      actionsCount: actionsMap.length,
      eliminatedInActions: result.eliminatedPlayerId,
      eliminatedPlayerIds: result.eliminatedPlayerIds,
    );
    _notifyRound(roomId, roundNumber);

    final livingPlayers = players.where((p) => p.isAlive).toList();
    final winCheck = GameLogicEngine.checkWinCondition(livingPlayers,
        roleOverrides: playerRoles);

    if (winCheck.isGameOver) {
      for (int i = 0; i < players.length; i++) {
        final role = playerRoles[players[i].uid] ?? PlayerRole.civilian;
        players[i] = players[i].copyWith(role: role);
      }
      _notifyPlayers(roomId);
      _rooms[roomId] = _rooms[roomId]!.copyWith(
        status: RoomStatus.gameOver,
        currentPhase: GamePhase.gameOver,
        winner: winCheck.winner,
        eliminatedThisRound: result.eliminatedPlayerId,
        publicMessage: '${result.publicMessage} ${winCheck.reason}',
      );
    } else {
      _rooms[roomId] = _rooms[roomId]!.copyWith(
        currentPhase: GamePhase.roundResult,
        eliminatedThisRound: result.eliminatedPlayerId,
        publicMessage: result.publicMessage,
      );
    }
    _notifyRoom(roomId);
  }

  @override
  Future<void> advanceToDiscussion(String roomId) async {
    final room = _rooms[roomId];
    if (room == null) throw Exception('Room not found.');
    if (room.status == RoomStatus.lobby) {
      throw Exception('Cannot advance to discussion before game has started.');
    }
    if (room.status == RoomStatus.gameOver) {
      throw Exception('This game has already ended.');
    }

    final endTimestamp = DateTime.now().add(const Duration(seconds: 60));
    _rooms[roomId] = room.copyWith(
      currentPhase: GamePhase.discussion,
      discussionEndTimestamp: endTimestamp,
      discussionDurationSeconds: 60,
      publicMessage: 'Discussion phase. Discuss with your fellow players.',
    );
    _notifyRoom(roomId);
  }

  @override
  Future<void> sendMessage(
      {required String roomId, required String message}) async {
    final room = _rooms[roomId];
    if (room == null) throw Exception('Room not found.');
    if (room.currentPhase != GamePhase.discussion) {
      throw Exception(
          'Discussion chat is only open during the discussion phase.');
    }

    final currentUid = AuthService.instance.currentUid ??
        (_players[roomId]?.any((p) => p.uid == 'local_host') == true
            ? 'local_host'
            : 'local_user');
    final players = _players[roomId] ?? [];
    final player = players
        .cast<Player?>()
        .firstWhere((p) => p?.uid == currentUid, orElse: () => null);
    if (player == null) throw Exception('You are not a member of this room.');
    if (!player.isAlive)
      throw Exception('Eliminated players cannot participate in discussion.');

    final trimmed = message.trim();
    if (trimmed.isEmpty || trimmed.length > 500) {
      throw Exception('Message must be between 1 and 500 characters.');
    }

    _messages[roomId] ??= [];
    final msg = ChatMessage(
      id: 'msg_${Random().nextInt(9999999)}',
      senderId: currentUid,
      senderName: player.name,
      message: trimmed,
      timestamp: DateTime.now(),
      isSpectator: false,
    );
    _messages[roomId]!.add(msg);
    _notifyMessages(roomId);
  }

  @override
  Future<void> sendSpectatorMessage(
      {required String roomId, required String message}) async {
    final room = _rooms[roomId];
    if (room == null) throw Exception('Room not found.');

    final currentUid = AuthService.instance.currentUid ??
        (_players[roomId]?.any((p) => p.uid == 'local_host') == true
            ? 'local_host'
            : 'local_user');
    final players = _players[roomId] ?? [];
    final player = players
        .cast<Player?>()
        .firstWhere((p) => p?.uid == currentUid, orElse: () => null);
    if (player == null) throw Exception('You are not a member of this room.');
    if (player.isAlive)
      throw Exception('Living players cannot send spectator messages.');

    final trimmed = message.trim();
    if (trimmed.isEmpty || trimmed.length > 500) {
      throw Exception('Message must be between 1 and 500 characters.');
    }

    _spectatorMessages[roomId] ??= [];
    final msg = ChatMessage(
      id: 'spec_${Random().nextInt(9999999)}',
      senderId: currentUid,
      senderName: player.name,
      message: trimmed,
      timestamp: DateTime.now(),
      isSpectator: true,
    );
    _spectatorMessages[roomId]!.add(msg);
    _notifySpectatorMessages(roomId);
  }

  @override
  Future<void> advanceToVoting(String roomId) async {
    final room = _rooms[roomId];
    if (room == null) throw Exception('Room not found.');
    if (room.status == RoomStatus.lobby) {
      throw Exception('Cannot advance to voting before game has started.');
    }
    if (room.status == RoomStatus.gameOver) {
      throw Exception('This game has already ended.');
    }
    if (room.currentPhase != GamePhase.roundResult &&
        room.currentPhase != GamePhase.discussion &&
        room.currentPhase != GamePhase.roleReveal) {
      throw Exception(
          'Cannot advance to voting from phase: ${room.currentPhase}');
    }

    final durationSeconds = GameConfig.defaultVotingDurationSeconds;
    final endTimestamp = DateTime.now().add(Duration(seconds: durationSeconds));
    _rooms[roomId] = room.copyWith(
      currentPhase: GamePhase.voting,
      votingEndTimestamp: endTimestamp,
      votingDurationSeconds: durationSeconds,
      publicMessage: 'Who do you think is Mafia? Cast your vote.',
    );
    _notifyRoom(roomId);
    _simulateBotVotes(roomId, room.currentRound);
  }

  @override
  Future<void> submitVote({
    required String roomId,
    required int roundNumber,
    required String uid,
    required String targetId,
  }) async {
    // Write private vote
    _privateVotes[roomId] ??= {};
    _privateVotes[roomId]![roundNumber] ??= {};
    _privateVotes[roomId]![roundNumber]![uid] = PrivateVote(targetId: targetId);

    // Update public round: count and votedUids
    final roundMap = _rounds[roomId] ?? {};
    final currentRound =
        roundMap[roundNumber] ?? RoundData(roundNumber: roundNumber);
    final newCount = _privateVotes[roomId]![roundNumber]!.length;
    final currentVotedUids = List<String>.from(currentRound.votedUids);
    if (!currentVotedUids.contains(uid)) {
      currentVotedUids.add(uid);
    }
    final newRound = currentRound.copyWith(
      votesCount: newCount,
      votedUids: currentVotedUids,
    );
    roundMap[roundNumber] = newRound;
    _rounds[roomId] = roundMap;
    _notifyRound(roomId, roundNumber);

    // Notify submitting player of their own private vote
    _notifyMyVote(roomId, roundNumber, uid);

    final players = _players[roomId] ?? [];
    final livingPlayers = players.where((p) => p.isAlive).toList();

    if (_privateVotes[roomId]![roundNumber]!.length >= livingPlayers.length &&
        !newRound.votesResolved) {
      _resolveVotes(roomId, roundNumber);
    }
  }

  void _simulateBotVotes(String roomId, int roundNumber) {
    final players = _players[roomId] ?? [];
    final currentUid = AuthService.instance.currentUid;
    final living = players.where((p) => p.isAlive).toList();
    final bots = living.where((p) => p.uid != currentUid).toList();

    for (int i = 0; i < bots.length; i++) {
      final bot = bots[i];
      final candidates = living.where((p) => p.uid != bot.uid).toList();
      if (candidates.isEmpty) continue;
      final target = candidates[Random().nextInt(candidates.length)];
      final delay = fastBotDelays ? 10 : (700 + (i * 250));
      Future.delayed(Duration(milliseconds: delay), () {
        submitVote(
          roomId: roomId,
          roundNumber: roundNumber,
          uid: bot.uid,
          targetId: target.uid,
        );
      });
    }
  }

  void _resolveVotes(String roomId, int roundNumber) {
    final players = _players[roomId] ?? [];
    final round = _rounds[roomId]?[roundNumber];
    if (round == null) return;

    final votesMap = <String, String>{};
    final voteTally = <String, int>{};
    _privateVotes[roomId]?[roundNumber]?.forEach((uid, vote) {
      votesMap[uid] = vote.targetId;
      voteTally[vote.targetId] = (voteTally[vote.targetId] ?? 0) + 1;
    });

    final eliminatedUid = GameLogicEngine.resolveVoteElimination(votesMap);
    final eliminatedPlayer = players
        .cast<Player?>()
        .firstWhere((p) => p?.uid == eliminatedUid, orElse: () => null);

    if (eliminatedUid != null) {
      for (int i = 0; i < players.length; i++) {
        if (players[i].uid == eliminatedUid) {
          players[i] = players[i].copyWith(isAlive: false);
          break;
        }
      }
      _notifyPlayers(roomId);
    }

    _rounds[roomId]![roundNumber] = round.copyWith(
      votesResolved: true,
      votesCount: votesMap.length,
      eliminatedInVote: eliminatedUid,
      voteTally: voteTally,
    );
    _notifyRound(roomId, roundNumber);

    final playerRoles = {
      for (final p in players)
        p.uid: _privateRoles[roomId]?[p.uid] ?? PlayerRole.civilian
    };
    final livingPlayers = players.where((p) => p.isAlive).toList();
    final winCheck = GameLogicEngine.checkWinCondition(livingPlayers,
        roleOverrides: playerRoles);

    if (winCheck.isGameOver) {
      // Reveal roles
      for (int i = 0; i < players.length; i++) {
        final role = playerRoles[players[i].uid] ?? PlayerRole.civilian;
        players[i] = players[i].copyWith(role: role);
      }
      _notifyPlayers(roomId);
      _rooms[roomId] = _rooms[roomId]!.copyWith(
        status: RoomStatus.gameOver,
        currentPhase: GamePhase.gameOver,
        winner: winCheck.winner,
        votedOutThisRound: eliminatedUid,
        publicMessage:
            '${eliminatedPlayer?.name ?? "A player"} was eliminated by vote. ${winCheck.reason}',
      );
    } else {
      _rooms[roomId] = _rooms[roomId]!.copyWith(
        currentPhase: GamePhase.elimination,
        votedOutThisRound: eliminatedUid,
        publicMessage: eliminatedUid != null
            ? '${eliminatedPlayer?.name ?? "A player"} was eliminated by vote.'
            : 'The vote was tied. No one was eliminated.',
      );
    }
    _notifyRoom(roomId);
  }

  @override
  Future<void> advanceToNextRoundOrEnd(String roomId) async {
    final room = _rooms[roomId];
    if (room == null) throw Exception('Room not found.');
    if (room.status == RoomStatus.lobby) {
      throw Exception('Cannot advance round before game has started.');
    }
    if (room.status == RoomStatus.gameOver) {
      throw Exception('This game has already ended.');
    }

    final players = _players[roomId] ?? [];
    final livingPlayers = players.where((p) => p.isAlive).toList();
    final playerRoles = {
      for (final p in players)
        p.uid: _privateRoles[roomId]?[p.uid] ?? PlayerRole.civilian
    };

    final winCheck = GameLogicEngine.checkWinCondition(livingPlayers,
        roleOverrides: playerRoles);
    if (winCheck.isGameOver) {
      // Reveal roles at game over
      for (int i = 0; i < players.length; i++) {
        final role = playerRoles[players[i].uid] ?? PlayerRole.civilian;
        players[i] = players[i].copyWith(role: role);
      }
      _notifyPlayers(roomId);
      _rooms[roomId] = room.copyWith(
        status: RoomStatus.gameOver,
        currentPhase: GamePhase.gameOver,
        winner: winCheck.winner,
        publicMessage: winCheck.reason,
      );
      _notifyRoom(roomId);
      return;
    }

    final nextRound = room.currentRound + 1;
    _rounds[roomId] ??= {};
    _rounds[roomId]![nextRound] = RoundData(roundNumber: nextRound);
    _privateActions[roomId] ??= {};
    _privateActions[roomId]![nextRound] = {};
    _privateVotes[roomId] ??= {};
    _privateVotes[roomId]![nextRound] = {};
    _privateResults[roomId] ??= {};
    _privateResults[roomId]![nextRound] = {};

    final durationSeconds = GameConfig.defaultActionsDurationSeconds;
    final endTimestamp = DateTime.now().add(Duration(seconds: durationSeconds));
    _rooms[roomId] = room.copyWith(
      currentRound: nextRound,
      currentPhase: GamePhase.actions,
      actionsEndTimestamp: endTimestamp,
      actionsDurationSeconds: durationSeconds,
      eliminatedThisRound: null,
      votedOutThisRound: null,
      publicMessage: 'Round $nextRound: Secret actions in progress.',
    );

    _notifyRound(roomId, nextRound);
    _notifyRoom(roomId);
    _simulateBotActions(roomId, nextRound);
  }

  @override
  Future<void> resolveVotesOnTimeout(String roomId, int roundNumber) async {
    final room = _rooms[roomId];
    if (room == null || room.currentPhase != GamePhase.voting) return;
    final round = _rounds[roomId]?[roundNumber];
    if (round == null || round.votesResolved) return;
    _resolveVotes(roomId, roundNumber);
  }

  @override
  Future<void> resolveActionsOnTimeout(String roomId, int roundNumber) async {
    final room = _rooms[roomId];
    if (room == null || room.currentPhase != GamePhase.actions) return;
    final round = _rounds[roomId]?[roundNumber];
    if (round == null || round.actionsResolved) return;
    _resolveActions(roomId, roundNumber);
  }

  @override
  Future<void> addTestPlayer({
    required String roomId,
    required String name,
  }) async {
    final players = _players[roomId] ?? [];
    final newUid = 'test_${Random().nextInt(999999)}';
    players.add(Player(
      uid: newUid,
      name: name,
      isAlive: true,
      isHost: false,
      isBot: true,
      joinedAt: DateTime.now(),
    ));
    _players[roomId] = players;
    _notifyPlayers(roomId);
  }

  /// For testing room state transitions.
  void forceRoomState(Room room) {
    _rooms[room.id] = room;
    _notifyRoom(room.id);
  }

  /// For testing player alive state transitions.
  void setPlayerAliveForTesting(String roomId, String uid, bool isAlive) {
    final players = _players[roomId];
    if (players != null) {
      for (int i = 0; i < players.length; i++) {
        if (players[i].uid == uid) {
          players[i] = players[i].copyWith(isAlive: isAlive);
          break;
        }
      }
      _notifyPlayers(roomId);
    }
  }

  @override
  Future<void> resetRoomForNewGame(String roomId) async {
    final room = _rooms[roomId];
    if (room == null) throw Exception('Room not found.');

    // Idempotency: if already fully reset to lobby, return early.
    if (room.status == RoomStatus.lobby &&
        room.currentPhase == GamePhase.lobby &&
        room.currentRound == 0) {
      return;
    }

    _rooms[roomId] = Room(
      id: room.id,
      code: room.code,
      hostId: room.hostId,
      status: RoomStatus.lobby,
      currentPhase: GamePhase.lobby,
      currentRound: 0,
      createdAt: room.createdAt,
      maxPlayers: room.maxPlayers,
    );

    final currentPlayers = _players[roomId] ?? [];
    _players[roomId] = currentPlayers
        .map((p) => p.copyWith(
              isAlive: true,
              role: PlayerRole.unknown,
            ))
        .toList();

    _privateRoles[roomId]?.clear();
    _privateActions[roomId]?.clear();
    _privateVotes[roomId]?.clear();
    _privateResults[roomId]?.clear();
    _vigilanteUsedAbility[roomId]?.clear();
    _rounds[roomId]?.clear();
    _messages[roomId]?.clear();
    _spectatorMessages[roomId]?.clear();

    _notifyRoom(roomId);
    _notifyPlayers(roomId);
    _notifyMessages(roomId);
    _notifySpectatorMessages(roomId);
    final currentUid = AuthService.instance.currentUid ?? 'local_host';
    _notifyMyRole(roomId, currentUid);
  }
}
