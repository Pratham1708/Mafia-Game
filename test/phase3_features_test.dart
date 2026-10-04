import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_game/models/game_phase.dart';
import 'package:mafia_game/models/player_role.dart';
import 'package:mafia_game/services/auth_service.dart';
import 'package:mafia_game/services/game_logic_engine.dart';
import 'package:mafia_game/services/local_simulation_game_service.dart';

void main() {
  setUp(() {
    AuthService.instance.setCustomUid('host_uid');
  });

  // ─── PART 1: Expanded Roles & Interaction Logic ─────────────────────────────

  group('Phase 3 — Expanded Roles Engine Tests', () {
    test('Bodyguard intercepts Mafia attack on protected player', () {
      final roles = {
        'mafia': PlayerRole.mafia,
        'doc': PlayerRole.doctor,
        'bg': PlayerRole.bodyguard,
        'target': PlayerRole.civilian,
      };

      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'target',
        doctorTarget: null,
        bodyguardTarget: 'target',
        bodyguardUid: 'bg',
        playerRoles: roles,
      );

      expect(result.bodyguardIntercepted, isTrue);
      expect(result.eliminatedPlayerIds.contains('bg'), isTrue,
          reason: 'Bodyguard intercepts attack and takes the lethal blow');
      expect(result.eliminatedPlayerIds.contains('target'), isFalse,
          reason: 'Protected target survives Mafia attack');
    });

    test('Doctor saves Bodyguard who intercepted Mafia attack', () {
      final roles = {
        'mafia': PlayerRole.mafia,
        'doc': PlayerRole.doctor,
        'bg': PlayerRole.bodyguard,
        'target': PlayerRole.civilian,
      };

      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'target',
        doctorTarget: 'bg', // Doctor protected the Bodyguard!
        bodyguardTarget: 'target',
        bodyguardUid: 'bg',
        playerRoles: roles,
      );

      expect(result.bodyguardIntercepted, isTrue);
      expect(result.eliminatedPlayerIds, isEmpty,
          reason: 'Doctor saved Bodyguard, target was intercepted: nobody dies');
    });

    test('Vigilante single-use elimination shot eliminates target', () {
      final roles = {
        'vig': PlayerRole.vigilante,
        'suspect': PlayerRole.mafia,
      };

      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: null,
        doctorTarget: null,
        vigilanteTarget: 'suspect',
        vigilanteUid: 'vig',
        vigilanteAlreadyUsed: false,
        playerRoles: roles,
      );

      expect(result.vigilanteUsedAbility, isTrue);
      expect(result.eliminatedPlayerIds.contains('suspect'), isTrue);
    });

    test('Vigilante cannot eliminate when ability already consumed', () {
      final roles = {
        'vig': PlayerRole.vigilante,
        'suspect': PlayerRole.mafia,
      };

      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: null,
        doctorTarget: null,
        vigilanteTarget: 'suspect',
        vigilanteUid: 'vig',
        vigilanteAlreadyUsed: true, // Already used!
        playerRoles: roles,
      );

      expect(result.vigilanteUsedAbility, isFalse);
      expect(result.eliminatedPlayerIds, isEmpty,
          reason: 'Ability was already consumed');
    });

    test('Doctor protects Vigilante target from elimination', () {
      final roles = {
        'vig': PlayerRole.vigilante,
        'target': PlayerRole.civilian,
      };

      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: null,
        doctorTarget: 'target', // Doctor shielded target
        vigilanteTarget: 'target',
        vigilanteUid: 'vig',
        vigilanteAlreadyUsed: false,
        playerRoles: roles,
      );

      expect(result.vigilanteUsedAbility, isTrue);
      expect(result.eliminatedPlayerIds, isEmpty,
          reason: 'Doctor shielded the Vigilante target');
    });

    test('Vigilante skips/holds fire this round', () {
      final roles = {
        'vig': PlayerRole.vigilante,
        'target': PlayerRole.civilian,
      };

      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: null,
        doctorTarget: null,
        vigilanteTarget: 'skip',
        vigilanteUid: 'vig',
        vigilanteAlreadyUsed: false,
        playerRoles: roles,
      );

      expect(result.vigilanteUsedAbility, isFalse,
          reason: 'Holding fire does not consume ability');
      expect(result.eliminatedPlayerIds, isEmpty);
    });

    test('Complex interaction: Mafia attacks A, BG protects A, Vig shoots Mafia, Doc heals Mafia', () {
      final roles = {
        'mafia': PlayerRole.mafia,
        'doc': PlayerRole.doctor,
        'bg': PlayerRole.bodyguard,
        'vig': PlayerRole.vigilante,
        'targetA': PlayerRole.civilian,
      };

      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'targetA',
        doctorTarget: 'mafia', // Doc accidentally heals Mafia
        bodyguardTarget: 'targetA',
        bodyguardUid: 'bg',
        vigilanteTarget: 'mafia',
        vigilanteUid: 'vig',
        playerRoles: roles,
      );

      // BG intercepts Mafia strike on targetA -> BG dies
      expect(result.bodyguardIntercepted, isTrue);
      expect(result.eliminatedPlayerIds.contains('bg'), isTrue);
      expect(result.eliminatedPlayerIds.contains('targetA'), isFalse);

      // Vig attacks Mafia, but Doc shielded Mafia -> Mafia survives!
      expect(result.eliminatedPlayerIds.contains('mafia'), isFalse);
    });

    test('Detective investigation returns private result accurately', () {
      final roles = {
        'det': PlayerRole.detective,
        'm1': PlayerRole.mafia,
        'c1': PlayerRole.civilian,
      };

      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: null,
        doctorTarget: null,
        playerRoles: roles,
        detectiveTargets: {'det': 'm1'},
      );

      expect(result.detectiveResults['det'], isTrue, reason: 'm1 is Mafia');

      final result2 = GameLogicEngine.resolveSecretActions(
        mafiaTarget: null,
        doctorTarget: null,
        playerRoles: roles,
        detectiveTargets: {'det': 'c1'},
      );

      expect(result2.detectiveResults['det'], isFalse, reason: 'c1 is Civilian');
    });
  });

  // ─── PART 2: Discussion Phase & Real-Time Chat ──────────────────────────────

  group('Phase 3 — Discussion Phase & Realtime Chat Tests', () {
    test('advanceToDiscussion transitions room to discussion phase with server timer', () async {
      final service = LocalSimulationGameService();
      final room = await service.createRoom(hostName: 'Host');

      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      await service.startGame(room.id);
      await service.advanceToActions(room.id);

      // Advance to discussion
      await service.advanceToDiscussion(room.id);
      final updatedRoom = await service.streamRoom(room.id).first;

      expect(updatedRoom.currentPhase, GamePhase.discussion);
      expect(updatedRoom.discussionEndTimestamp, isNotNull);
      expect(
        updatedRoom.discussionEndTimestamp!.isAfter(DateTime.now()),
        isTrue,
        reason: 'Discussion end timestamp must be in the future',
      );
    });

    test('Living player can send chat messages during discussion', () async {
      final service = LocalSimulationGameService();
      final room = await service.createRoom(hostName: 'Host');

      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      await service.startGame(room.id);
      await service.advanceToActions(room.id);
      await service.advanceToDiscussion(room.id);

      await service.sendMessage(
        roomId: room.id,
        message: 'I think Bot_1 is acting very suspicious!',
      );

      final messages = await service.streamMessages(room.id).first;
      expect(messages.length, 1);
      expect(messages.first.message, 'I think Bot_1 is acting very suspicious!');
      expect(messages.first.senderId, 'host_uid');
      expect(messages.first.isSpectator, isFalse);
    });

    test('Empty or excessively long message is rejected', () async {
      final service = LocalSimulationGameService();
      final room = await service.createRoom(hostName: 'Host');

      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      await service.startGame(room.id);
      await service.advanceToActions(room.id);
      await service.advanceToDiscussion(room.id);

      // Empty message
      expect(
        () => service.sendMessage(roomId: room.id, message: '   '),
        throwsA(isA<Exception>()),
      );

      // Over 500 characters
      final longMsg = 'a' * 501;
      expect(
        () => service.sendMessage(roomId: room.id, message: longMsg),
        throwsA(isA<Exception>()),
      );
    });

    test('Dead player cannot send living discussion chat', () async {
      final service = LocalSimulationGameService();
      final room = await service.createRoom(hostName: 'Host');

      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      await service.startGame(room.id);
      await service.advanceToActions(room.id);
      await service.advanceToDiscussion(room.id);

      // Switch to a dead player's UID
      AuthService.instance.setCustomUid('dead_uid');
      // dead_uid is not even in room or alive
      expect(
        () => service.sendMessage(roomId: room.id, message: 'Ghost speaking!'),
        throwsA(isA<Exception>()),
      );
    });

    test('Dead player can send spectator chat and living cannot read it', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host_uid');
      final room = await service.createRoom(hostName: 'Host');

      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      await service.startGame(room.id);
      await service.advanceToActions(room.id);
      await service.advanceToDiscussion(room.id);

      // Simulate a dead player
      final players = await service.streamPlayers(room.id).first;
      final victim = players.firstWhere((p) => p.uid != 'host_uid');
      service.setPlayerAliveForTesting(room.id, victim.uid, false);

      // Send spectator message as victim
      AuthService.instance.setCustomUid(victim.uid);
      await service.sendSpectatorMessage(
        roomId: room.id,
        message: 'GG town, I was just a civilian!',
      );

      final specMessages = await service.streamSpectatorMessages(room.id).first;
      expect(specMessages.length, 1);
      expect(specMessages.first.message, 'GG town, I was just a civilian!');
      expect(specMessages.first.isSpectator, isTrue);

      // Living discussion messages do NOT contain spectator message
      final livingMessages = await service.streamMessages(room.id).first;
      expect(livingMessages.any((m) => m.message.contains('GG town')), isFalse,
          reason: 'Spectator chat must be isolated from living discussion');
    });
  });

  // ─── PART 3: Full Flows for 6, 9, 10, 12 Players ────────────────────────────

  group('Phase 3 — Full Multi-Player Game Loops', () {
    test('Complete 6-player flow: 1 Mafia, 1 Detective, 1 Doctor, 3 Civilians', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('p_0');
      final room = await service.createRoom(hostName: 'Player_0');

      for (int i = 1; i < 6; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Player_$i');
      }

      await service.startGame(room.id);
      var current = await service.streamRoom(room.id).first;
      expect(current.currentPhase, GamePhase.roleReveal);

      await service.advanceToActions(room.id);
      current = await service.streamRoom(room.id).first;
      expect([GamePhase.actions, GamePhase.roundResult, GamePhase.discussion, GamePhase.gameOver]
          .contains(current.currentPhase), isTrue);
    });

    test('Complete 9-player flow: includes 1 Bodyguard', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('p_0');
      final room = await service.createRoom(hostName: 'Player_0');

      for (int i = 1; i < 9; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Player_$i');
      }

      await service.startGame(room.id);
      final roles = GameLogicEngine.getRoleDistribution(9);
      expect(roles.where((r) => r == PlayerRole.bodyguard).length, 1);
      expect(roles.where((r) => r == PlayerRole.mafia).length, 2);
    });

    test('Complete 10-player flow: 3 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 4 Civilians', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('p_0');
      final room = await service.createRoom(hostName: 'Player_0');

      for (int i = 1; i < 10; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Player_$i');
      }

      await service.startGame(room.id);
      final roles = GameLogicEngine.getRoleDistribution(10);
      expect(roles.where((r) => r == PlayerRole.mafia).length, 3);
      expect(roles.where((r) => r == PlayerRole.bodyguard).length, 1);
      expect(roles.where((r) => r == PlayerRole.vigilante).length, 0);
    });

    test('Complete 12-player flow: includes 1 Bodyguard and 1 Vigilante', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('p_0');
      final room = await service.createRoom(hostName: 'Player_0');

      for (int i = 1; i < 12; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Player_$i');
      }

      await service.startGame(room.id);
      final roles = GameLogicEngine.getRoleDistribution(12);
      expect(roles.where((r) => r == PlayerRole.mafia).length, 3);
      expect(roles.where((r) => r == PlayerRole.detective).length, 1);
      expect(roles.where((r) => r == PlayerRole.doctor).length, 1);
      expect(roles.where((r) => r == PlayerRole.bodyguard).length, 1);
      expect(roles.where((r) => r == PlayerRole.vigilante).length, 1);
      expect(roles.where((r) => r == PlayerRole.civilian).length, 5);
    });
  });
}
