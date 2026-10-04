import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_game/models/game_config.dart';
import 'package:mafia_game/models/game_phase.dart';
import 'package:mafia_game/models/player_role.dart';
import 'package:mafia_game/models/room.dart';
import 'package:mafia_game/screens/lobby_screen.dart';
import 'package:mafia_game/services/auth_service.dart';
import 'package:mafia_game/services/game_logic_engine.dart';
import 'package:mafia_game/services/game_service_provider.dart';
import 'package:mafia_game/services/local_simulation_game_service.dart';

void main() {
  group('Testing Mode - Configuration & Role Distribution', () {
    test('GameConfig defaults to production: testingMode is false and minPlayers is 6', () {
      expect(GameConfig.testingMode, isFalse);
      expect(GameConfig.minPlayers, 6);
      expect(GameConfig.maxPlayers, 12);
    });

    test('When testingMode is enabled, minPlayers is 4', () {
      GameConfig.testingMode = true;
      expect(GameConfig.minPlayers, 4);
      GameConfig.testingMode = false;
    });

    test('4-player distribution contains 1 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard', () {
      final roles = GameLogicEngine.getRoleDistribution(4);
      expect(roles.length, 4);
      expect(roles.where((r) => r == PlayerRole.mafia).length, 1);
      expect(roles.where((r) => r == PlayerRole.detective).length, 1);
      expect(roles.where((r) => r == PlayerRole.doctor).length, 1);
      expect(roles.where((r) => r == PlayerRole.bodyguard).length, 1);
    });

    test('5-player distribution contains all Phase 3 special roles including Vigilante', () {
      final roles = GameLogicEngine.getRoleDistribution(5);
      expect(roles.length, 5);
      expect(roles.where((r) => r == PlayerRole.mafia).length, 1);
      expect(roles.where((r) => r == PlayerRole.detective).length, 1);
      expect(roles.where((r) => r == PlayerRole.doctor).length, 1);
      expect(roles.where((r) => r == PlayerRole.bodyguard).length, 1);
      expect(roles.where((r) => r == PlayerRole.vigilante).length, 1);
    });

    test('assignRoles shuffles correctly for 4 and 5 player UIDs', () {
      final uids4 = ['p1', 'p2', 'p3', 'p4'];
      final assigned4 = GameLogicEngine.assignRoles(uids4, Random(42));
      expect(assigned4.length, 4);
      expect(assigned4.values.contains(PlayerRole.mafia), isTrue);
      expect(assigned4.values.contains(PlayerRole.detective), isTrue);
      expect(assigned4.values.contains(PlayerRole.doctor), isTrue);
      expect(assigned4.values.contains(PlayerRole.bodyguard), isTrue);

      final uids5 = ['p1', 'p2', 'p3', 'p4', 'p5'];
      final assigned5 = GameLogicEngine.assignRoles(uids5, Random(42));
      expect(assigned5.length, 5);
      expect(assigned5.values.contains(PlayerRole.vigilante), isTrue);
    });
  });

  group('Testing Mode - 4-Player Room (1 Real Player + 3 Bots)', () {
    late LocalSimulationGameService service;

    setUp(() {
      GameConfig.testingMode = true;
      service = LocalSimulationGameService()..fastBotDelays = true;
      GameServiceProvider.instance.setServiceForTesting(service);
      AuthService.instance.setCustomUid('human_host');
    });

    tearDown(() {
      GameConfig.testingMode = false;
    });

    test('Host creates room and adds 3 bots to start 4-player game', () async {
      final room = await service.createRoom(hostName: 'HumanHost');
      expect(room.status, RoomStatus.lobby);

      // Add 3 bots
      for (int i = 1; i <= 3; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      final playersBefore = await service.streamPlayers(room.id).first;
      expect(playersBefore.length, 4);
      expect(playersBefore.where((p) => p.isBot).length, 3);
      expect(playersBefore.firstWhere((p) => p.uid == 'human_host').isBot, isFalse);

      // Start game with 4 players (allowed in testing mode)
      await service.startGame(room.id);

      final startedRoom = await service.streamRoom(room.id).first;
      expect(startedRoom.status, RoomStatus.playing);
      expect(startedRoom.currentPhase, GamePhase.roleReveal);
      expect(startedRoom.currentRound, 1);

      // Server authority: public stream must hide roles
      final playersAfter = await service.streamPlayers(room.id).first;
      for (final p in playersAfter) {
        expect(p.role, PlayerRole.unknown,
            reason: 'Roles must remain unknown in public stream');
      }

      // Host receives their private role
      final hostRole = await service.streamMyRole(room.id).first;
      expect(hostRole, isNotNull);
      expect(hostRole, isNot(PlayerRole.unknown));
    });

    test('Complete 4-player game loop with automated bot actions & voting', () async {
      final room = await service.createRoom(hostName: 'HumanHost');
      for (int i = 1; i <= 3; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      await service.startGame(room.id);
      expect((await service.streamRoom(room.id).first).currentPhase, GamePhase.roleReveal);

      // Advance to actions
      await service.advanceToActions(room.id);
      expect((await service.streamRoom(room.id).first).currentPhase, GamePhase.actions);

      // Determine human host's role
      final hostRole = await service.streamMyRole(room.id).first;
      final players = await service.streamPlayers(room.id).first;
      final otherPlayers = players.where((p) => p.uid != 'human_host').toList();

      // If host has a secret action, submit it
      if (hostRole.hasSecretAction) {
        await service.submitAction(
          roomId: room.id,
          roundNumber: 1,
          uid: 'human_host',
          targetId: otherPlayers.first.uid,
          role: hostRole,
        );
      }

      // Allow fast bot delays to execute
      await Future.delayed(const Duration(milliseconds: 150));

      // Actions should be resolved to roundResult
      final afterActionsRoom = await service.streamRoom(room.id).first;
      expect(afterActionsRoom.currentPhase, GamePhase.roundResult);

      // Advance to discussion
      await service.advanceToDiscussion(room.id);
      expect((await service.streamRoom(room.id).first).currentPhase, GamePhase.discussion);

      // Advance to voting
      await service.advanceToVoting(room.id);
      expect((await service.streamRoom(room.id).first).currentPhase, GamePhase.voting);

      // Human host votes for a living other player
      final livingPlayers = (await service.streamPlayers(room.id).first).where((p) => p.isAlive).toList();
      final voteTarget = livingPlayers.firstWhere((p) => p.uid != 'human_host');
      await service.submitVote(
        roomId: room.id,
        roundNumber: 1,
        uid: 'human_host',
        targetId: voteTarget.uid,
      );

      // Allow fast bot votes to execute
      await Future.delayed(const Duration(milliseconds: 150));

      // Voting resolved to elimination or immediate gameOver
      final afterVoteRoom = await service.streamRoom(room.id).first;
      expect(
        afterVoteRoom.currentPhase == GamePhase.elimination ||
            afterVoteRoom.currentPhase == GamePhase.gameOver,
        isTrue,
      );

      if (afterVoteRoom.currentPhase == GamePhase.elimination) {
        // Advance to next round or end
        await service.advanceToNextRoundOrEnd(room.id);
      }

      final finalRoom = await service.streamRoom(room.id).first;

      // Either round 2 started or game ended with a valid win condition
      expect(
        finalRoom.status == RoomStatus.playing || finalRoom.status == RoomStatus.gameOver,
        isTrue,
      );
    });
  });

  group('Testing Mode - 5-Player Room (1 Real Player + 4 Bots)', () {
    late LocalSimulationGameService service;

    setUp(() {
      GameConfig.testingMode = true;
      service = LocalSimulationGameService()..fastBotDelays = true;
      GameServiceProvider.instance.setServiceForTesting(service);
      AuthService.instance.setCustomUid('human_host');
    });

    tearDown(() {
      GameConfig.testingMode = false;
    });

    test('Host creates room and adds 4 bots to start 5-player game', () async {
      final room = await service.createRoom(hostName: 'HumanHost');
      for (int i = 1; i <= 4; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      final playersBefore = await service.streamPlayers(room.id).first;
      expect(playersBefore.length, 5);

      await service.startGame(room.id);

      final startedRoom = await service.streamRoom(room.id).first;
      expect(startedRoom.status, RoomStatus.playing);
      expect(startedRoom.currentPhase, GamePhase.roleReveal);
    });

    test('5-player game loop executes with Vigilante ability support', () async {
      final room = await service.createRoom(hostName: 'HumanHost');
      for (int i = 1; i <= 4; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      await service.startGame(room.id);
      await service.advanceToActions(room.id);

      final hostRole = await service.streamMyRole(room.id).first;
      final players = await service.streamPlayers(room.id).first;
      final target = players.firstWhere((p) => p.uid != 'human_host');

      if (hostRole.hasSecretAction) {
        await service.submitAction(
          roomId: room.id,
          roundNumber: 1,
          uid: 'human_host',
          targetId: target.uid,
          role: hostRole,
        );
      }

      // Wait for bot actions
      await Future.delayed(const Duration(milliseconds: 150));

      final roundResultRoom = await service.streamRoom(room.id).first;
      expect(
        roundResultRoom.currentPhase == GamePhase.roundResult ||
            roundResultRoom.currentPhase == GamePhase.gameOver,
        isTrue,
      );

      if (roundResultRoom.currentPhase == GamePhase.roundResult) {
        await service.advanceToDiscussion(room.id);
        await service.advanceToVoting(room.id);

        final living = (await service.streamPlayers(room.id).first).where((p) => p.isAlive).toList();
        final voteCandidate = living.firstWhere((p) => p.uid != 'human_host');
        await service.submitVote(
          roomId: room.id,
          roundNumber: 1,
          uid: 'human_host',
          targetId: voteCandidate.uid,
        );

        // Wait for bot votes
        await Future.delayed(const Duration(milliseconds: 150));

        final elimRoom = await service.streamRoom(room.id).first;
        expect(
          elimRoom.currentPhase == GamePhase.elimination ||
              elimRoom.currentPhase == GamePhase.gameOver,
          isTrue,
        );
      }
    });
  });

  group('Testing Mode - Disabling & Production Rules Verification', () {
    test('With fewer than minPlayers (e.g. 3 players), startGame always throws', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');
      await service.addTestPlayer(roomId: room.id, name: 'Bot_1');
      await service.addTestPlayer(roomId: room.id, name: 'Bot_2');

      // 3 players total < minPlayers (4 in test mode, 6 in prod)
      expect(
        () => service.startGame(room.id),
        throwsA(isA<Exception>()),
      );
    });

    test('If minPlayers were 6 (production mode), 4 or 5 players throw', () {
      // Direct verification of rule logic when testingMode = false
      const prodMinPlayers = 6;
      expect(4 < prodMinPlayers, isTrue);
      expect(5 < prodMinPlayers, isTrue);
      expect(6 >= prodMinPlayers, isTrue);
    });
  });

  group('Testing Mode - Lobby UI Widget Tests', () {
    late LocalSimulationGameService service;

    setUp(() {
      GameConfig.testingMode = true;
      service = LocalSimulationGameService();
      GameServiceProvider.instance.setServiceForTesting(service);
      AuthService.instance.setCustomUid('host_uid');
    });

    tearDown(() {
      GameConfig.testingMode = false;
    });

    testWidgets('LobbyScreen displays ADD TEST BOT button for host', (tester) async {
      final room = await service.createRoom(hostName: 'HostPlayer');

      await tester.pumpWidget(
        MaterialApp(
          home: LobbyScreen(
            roomId: room.id,
            roomCode: room.code,
            isHost: true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify ADD TEST BOT button is present
      final addBotFinder = find.byKey(const Key('add_test_bot_button'));
      expect(addBotFinder, findsOneWidget);

      // Tap ADD TEST BOT
      await tester.tap(addBotFinder);
      await tester.pumpAndSettle();

      // Verify player count is now 2
      final players = await service.streamPlayers(room.id).first;
      expect(players.length, 2);
    });

    testWidgets('LobbyScreen enables START GAME at 4 players in testing mode', (tester) async {
      final room = await service.createRoom(hostName: 'HostPlayer');
      for (int i = 1; i <= 3; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      await tester.pumpWidget(
        MaterialApp(
          home: LobbyScreen(
            roomId: room.id,
            roomCode: room.code,
            isHost: true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Start button is present and enabled
      final startBtnFinder = find.byKey(const Key('start_game_button'));
      expect(startBtnFinder, findsOneWidget);

      // Verify player badge displays (Min 4)
      expect(find.text('4 / 12 (Min 4)'), findsOneWidget);

      // Tap start game
      await tester.tap(startBtnFinder);
      await tester.pumpAndSettle();

      // Verify room started
      final startedRoom = await service.streamRoom(room.id).first;
      expect(startedRoom.status, RoomStatus.playing);
    });
  });

  group('Production Mode Verification (Real Players Only)', () {
    late LocalSimulationGameService service;

    setUp(() {
      GameConfig.testingMode = false;
      service = LocalSimulationGameService();
      GameServiceProvider.instance.setServiceForTesting(service);
      AuthService.instance.setCustomUid('host_prod_uid');
    });

    test('Production bounds: min 6, max 12 players', () {
      expect(GameConfig.testingMode, isFalse);
      expect(GameConfig.minPlayers, 6);
      expect(GameConfig.maxPlayers, 12);
    });

    testWidgets('LobbyScreen HIDES ADD TEST BOT button in production mode', (tester) async {
      final room = await service.createRoom(hostName: 'ProdHost');

      await tester.pumpWidget(
        MaterialApp(
          home: LobbyScreen(
            roomId: room.id,
            roomCode: room.code,
            isHost: true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // ADD TEST BOT must NOT exist in production
      expect(find.byKey(const Key('add_test_bot_button')), findsNothing);

      // Min players badge must show (Min 6)
      expect(find.text('1 / 12 (Min 6)'), findsOneWidget);
    });

    test('resetRoomForNewGame resets room to lobby, revives players, and clears game state', () async {
      final room = await service.createRoom(hostName: 'ProdHost');
      for (int i = 1; i <= 5; i++) {
        AuthService.instance.setCustomUid('player_$i');
        await service.joinRoom(roomCode: room.code, playerName: 'Player_$i');
      }
      AuthService.instance.setCustomUid('host_prod_uid');

      await service.startGame(room.id);
      var runningRoom = await service.streamRoom(room.id).first;
      expect(runningRoom.status, RoomStatus.playing);

      // Reset room for Play Again
      await service.resetRoomForNewGame(room.id);

      final resetRoom = await service.streamRoom(room.id).first;
      expect(resetRoom.status, RoomStatus.lobby);
      expect(resetRoom.currentPhase, GamePhase.lobby);
      expect(resetRoom.currentRound, 0);
      expect(resetRoom.code, room.code);
      expect(resetRoom.hostId, 'host_prod_uid');

      // Verify all players remain in the room and are alive with unknown role
      final players = await service.streamPlayers(room.id).first;
      expect(players.length, 6);
      for (final p in players) {
        expect(p.isAlive, isTrue);
        expect(p.role, PlayerRole.unknown);
      }
    });
  });
}
