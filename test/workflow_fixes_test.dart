import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_game/models/game_phase.dart';
import 'package:mafia_game/models/player.dart';
import 'package:mafia_game/models/player_role.dart';
import 'package:mafia_game/models/private_result.dart';
import 'package:mafia_game/models/round_data.dart';
import 'package:mafia_game/services/game_logic_engine.dart';
import 'package:mafia_game/services/local_simulation_game_service.dart';

void main() {
  group('Workflow Fixes — Discussion', () {
    late LocalSimulationGameService service;
    late String roomId;

    setUp(() async {
      service = LocalSimulationGameService();
      final room = await service.createRoom(hostName: 'Host');
      roomId = room.id;
      // Add 5 more players for a 6 player game
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: roomId, name: 'Player $i');
      }
      await service.startGame(roomId);
      await service.advanceToActions(roomId);
    });

    test('alive player can send discussion message', () async {
      await service.advanceToDiscussion(roomId);

      // Living host sends message
      await service.sendMessage(roomId: roomId, message: 'Hello town!');
      final messages = await service.streamMessages(roomId).first;
      expect(messages.length, 1);
      expect(messages.first.message, 'Hello town!');
      expect(messages.first.isSpectator, false);
    });

    test('dead player cannot send discussion message', () async {
      // Eliminate host player
      service.setPlayerAliveForTesting(roomId, 'local_host', false);
      await service.advanceToDiscussion(roomId);

      // Attempting to send message should throw
      expect(
        () => service.sendMessage(roomId: roomId, message: 'I am dead'),
        throwsA(isA<Exception>()),
      );
    });

    test('dead player can read the shared living discussion feed', () async {
      await service.advanceToDiscussion(roomId);

      // Living player sends message
      await service.sendMessage(roomId: roomId, message: 'Living player message');

      // Eliminate host player to become spectator
      service.setPlayerAliveForTesting(roomId, 'local_host', false);

      // Spectator reads the shared living streamMessages feed
      final messages = await service.streamMessages(roomId).first;
      expect(messages.length, 1);
      expect(messages.first.message, 'Living player message');
    });
  });

  group('Workflow Fixes — Discussion Timer & Idempotency', () {
    late LocalSimulationGameService service;
    late String roomId;

    setUp(() async {
      service = LocalSimulationGameService();
      final room = await service.createRoom(hostName: 'Host');
      roomId = room.id;
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: roomId, name: 'Player $i');
      }
      await service.startGame(roomId);
      await service.advanceToActions(roomId);
      await service.advanceToDiscussion(roomId);
    });

    test('advanceToVoting transitions room from discussion to voting', () async {
      await service.advanceToVoting(roomId);
      final room = await service.streamRoom(roomId).first;
      expect(room.currentPhase, GamePhase.voting);
      expect(room.votingEndTimestamp, isNotNull);
      expect(room.votingDurationSeconds, greaterThan(0));
    });

    test('advanceToVoting is idempotent and rejects invalid transitions', () async {
      await service.advanceToVoting(roomId);
      final room = await service.streamRoom(roomId).first;
      expect(room.currentPhase, GamePhase.voting);

      // Re-invoking advanceToVoting when already in voting phase should be rejected
      expect(() => service.advanceToVoting(roomId), throwsA(isA<Exception>()));
    });
  });

  group('Workflow Fixes — Round Result & Bodyguard Interception', () {
    test('RoundData tracks multiple secret-action eliminations', () {
      final round = RoundData(
        roundNumber: 1,
        eliminatedPlayerIds: ['player_1', 'player_2'],
      );

      expect(round.eliminatedPlayerIds.length, 2);
      expect(round.eliminatedPlayerIds, contains('player_1'));
      expect(round.eliminatedPlayerIds, contains('player_2'));

      final map = round.toMap();
      final fromMap = RoundData.fromMap(map, 1);
      expect(fromMap.eliminatedPlayerIds, equals(['player_1', 'player_2']));
    });

    test('Bodyguard interception: Bodyguard dies, target survives, interception recorded', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'player_target',
        doctorTarget: null,
        bodyguardTarget: 'player_target',
        bodyguardUid: 'player_bg',
        playerRoles: {
          'player_target': PlayerRole.civilian,
          'player_bg': PlayerRole.bodyguard,
          'player_mafia': PlayerRole.mafia,
        },
      );

      expect(result.bodyguardIntercepted, isTrue);
      expect(result.eliminatedPlayerIds, contains('player_bg'));
      expect(result.eliminatedPlayerIds, isNot(contains('player_target')));
    });

    test('Bodyguard interception with Doctor saving Bodyguard: Bodyguard survives', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'player_target',
        doctorTarget: 'player_bg', // Doctor protects the Bodyguard!
        bodyguardTarget: 'player_target',
        bodyguardUid: 'player_bg',
        playerRoles: {
          'player_target': PlayerRole.civilian,
          'player_bg': PlayerRole.bodyguard,
          'player_doc': PlayerRole.doctor,
        },
      );

      expect(result.bodyguardIntercepted, isTrue);
      expect(result.eliminatedPlayerIds, isEmpty);
    });

    test('PrivateResult serializes bodyguardIntercepted flag', () {
      final priv = PrivateResult(
        targetId: 'player_target',
        isMafia: false,
        bodyguardIntercepted: true,
      );

      final map = priv.toMap();
      expect(map['bodyguardIntercepted'], isTrue);

      final fromMap = PrivateResult.fromMap(map);
      expect(fromMap.bodyguardIntercepted, isTrue);
      expect(fromMap.targetId, 'player_target');
    });
  });

  group('Workflow Fixes — Voting & Ties', () {
    test('tied votes result in null (no player eliminated)', () {
      final votes = {
        'voter1': 'target_a',
        'voter2': 'target_a',
        'voter3': 'target_b',
        'voter4': 'target_b',
      };

      final eliminated = GameLogicEngine.resolveVoteElimination(votes);
      expect(eliminated, isNull);
    });

    test('majority / plurality vote eliminates the top target', () {
      final votes = {
        'voter1': 'target_a',
        'voter2': 'target_a',
        'voter3': 'target_b',
      };

      final eliminated = GameLogicEngine.resolveVoteElimination(votes);
      expect(eliminated, 'target_a');
    });

    test('RoundData tracks votedUids without duplicates and stores voteTally', () {
      final round = RoundData(
        roundNumber: 1,
        votedUids: ['uid_1', 'uid_2'],
        voteTally: {'target_a': 2, 'target_b': 1},
      );

      expect(round.votedUids, equals(['uid_1', 'uid_2']));
      expect(round.voteTally['target_a'], 2);

      final map = round.toMap();
      final fromMap = RoundData.fromMap(map, 1);
      expect(fromMap.votedUids, equals(['uid_1', 'uid_2']));
      expect(fromMap.voteTally, equals({'target_a': 2, 'target_b': 1}));
    });
  });

  group('Workflow Fixes — Bot Voting & Timeouts', () {
    late LocalSimulationGameService service;
    late String roomId;

    setUp(() async {
      service = LocalSimulationGameService();
      service.fastBotDelays = true;
      final room = await service.createRoom(hostName: 'Host');
      roomId = room.id;
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: roomId, name: 'Bot $i');
      }
      await service.startGame(roomId);
    });

    test('voting timeout forces vote resolution with abstentions', () async {
      await service.advanceToActions(roomId);
      // Wait for actions to resolve in fast mode
      await Future.delayed(const Duration(milliseconds: 100));
      await service.advanceToVoting(roomId);

      // Force vote timeout
      await service.resolveVotesOnTimeout(roomId, 1);
      final room = await service.streamRoom(roomId).first;
      expect(
        room.currentPhase == GamePhase.elimination ||
            room.currentPhase == GamePhase.gameOver,
        isTrue,
      );
    });
  });

  group('Regression Verification — Core Game Rules Unchanged', () {
    test('Mafia attack succeeds when no doctor or bodyguard', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'player_civ',
        doctorTarget: null,
        playerRoles: {
          'player_civ': PlayerRole.civilian,
          'player_mafia': PlayerRole.mafia,
        },
      );
      expect(result.eliminatedPlayerIds, contains('player_civ'));
    });

    test('Doctor saves target from Mafia attack', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'player_civ',
        doctorTarget: 'player_civ',
        playerRoles: {
          'player_civ': PlayerRole.civilian,
          'player_doc': PlayerRole.doctor,
          'player_mafia': PlayerRole.mafia,
        },
      );
      expect(result.eliminatedPlayerIds, isEmpty);
    });

    test('Vigilante can eliminate another player once per game', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: null,
        doctorTarget: null,
        vigilanteTarget: 'player_mafia',
        vigilanteUid: 'player_vig',
        vigilanteAlreadyUsed: false,
        playerRoles: {
          'player_vig': PlayerRole.vigilante,
          'player_mafia': PlayerRole.mafia,
        },
      );
      expect(result.vigilanteUsedAbility, isTrue);
      expect(result.eliminatedPlayerIds, contains('player_mafia'));
    });

    test('Vigilante already used ability cannot eliminate', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: null,
        doctorTarget: null,
        vigilanteTarget: 'player_mafia',
        vigilanteUid: 'player_vig',
        vigilanteAlreadyUsed: true,
        playerRoles: {
          'player_vig': PlayerRole.vigilante,
          'player_mafia': PlayerRole.mafia,
        },
      );
      expect(result.vigilanteUsedAbility, isFalse);
      expect(result.eliminatedPlayerIds, isEmpty);
    });

    test('Detective correctly identifies Mafia vs Non-Mafia', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: null,
        doctorTarget: null,
        detectiveTargets: {
          'det1': 'player_mafia',
          'det2': 'player_civ',
        },
        playerRoles: {
          'player_mafia': PlayerRole.mafia,
          'player_civ': PlayerRole.civilian,
        },
      );
      expect(result.detectiveResults['det1'], isTrue);
      expect(result.detectiveResults['det2'], isFalse);
    });

    test('Win conditions remain unchanged', () {
      final now = DateTime.now();
      // 0 Mafia alive -> Civilians win
      final civWin = GameLogicEngine.checkWinCondition([
        Player(uid: '1', name: 'Civ 1', isAlive: true, role: PlayerRole.civilian, joinedAt: now),
        Player(uid: '2', name: 'Civ 2', isAlive: true, role: PlayerRole.civilian, joinedAt: now),
      ]);
      expect(civWin.isGameOver, isTrue);
      expect(civWin.winner, 'CIVILIANS');

      // Mafia >= non-Mafia living -> Mafia win
      final mafiaWin = GameLogicEngine.checkWinCondition([
        Player(uid: '1', name: 'Mafia 1', isAlive: true, role: PlayerRole.mafia, joinedAt: now),
        Player(uid: '2', name: 'Civ 1', isAlive: true, role: PlayerRole.civilian, joinedAt: now),
      ]);
      expect(mafiaWin.isGameOver, isTrue);
      expect(mafiaWin.winner, 'MAFIA');

      // Game continues if Mafia < non-Mafia living and Mafia > 0
      final playing = GameLogicEngine.checkWinCondition([
        Player(uid: '1', name: 'Mafia 1', isAlive: true, role: PlayerRole.mafia, joinedAt: now),
        Player(uid: '2', name: 'Civ 1', isAlive: true, role: PlayerRole.civilian, joinedAt: now),
        Player(uid: '3', name: 'Civ 2', isAlive: true, role: PlayerRole.civilian, joinedAt: now),
      ]);
      expect(playing.isGameOver, isFalse);
    });
  });
}
