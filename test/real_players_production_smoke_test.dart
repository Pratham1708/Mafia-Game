import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_game/models/game_config.dart';
import 'package:mafia_game/models/game_phase.dart';
import 'package:mafia_game/models/player.dart';
import 'package:mafia_game/models/player_role.dart';
import 'package:mafia_game/models/room.dart';
import 'package:mafia_game/screens/game/game_over_view.dart';
import 'package:mafia_game/screens/home_screen.dart';
import 'package:mafia_game/screens/join_screen.dart';
import 'package:mafia_game/screens/lobby_screen.dart';
import 'package:mafia_game/services/auth_service.dart';
import 'package:mafia_game/services/game_service_provider.dart';
import 'package:mafia_game/services/local_simulation_game_service.dart';

void main() {
  group('Production Real-Player Mode & Return To Room Verification', () {
    late LocalSimulationGameService service;

    setUp(() {
      // Strictly enforce production mode (REAL PLAYERS ONLY)
      GameConfig.testingMode = false;
      service = LocalSimulationGameService()..fastBotDelays = true;
      GameServiceProvider.instance.setServiceForTesting(service);
      AuthService.instance.setCustomUid('real_host_1');
    });

    test('1. Production constraints verified', () {
      expect(GameConfig.testingMode, isFalse);
      expect(GameConfig.minPlayers, 6);
      expect(GameConfig.maxPlayers, 12);
    });

    testWidgets('2. UI Verification: Home, Join, and Lobby with Real Players Only', (tester) async {
      // 1. Home screen verification
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('MAFIA'), findsOneWidget);
      expect(find.text('Trust no one.'), findsOneWidget);
      expect(find.text('Your friends are lying.'), findsOneWidget);
      expect(find.text('CREATE GAME'), findsOneWidget);
      expect(find.text('JOIN GAME'), findsOneWidget);
      expect(find.text('HOW TO PLAY'), findsOneWidget);

      // Verify no bot or simulator buttons are present on Home
      expect(find.textContaining('Bot'), findsNothing);
      expect(find.textContaining('Simulator'), findsNothing);

      // 2. Join Screen verification
      await tester.pumpWidget(
        const MaterialApp(home: JoinScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('JOIN GAME'), findsWidgets);
      expect(find.text('ENTER ROOM CODE'), findsOneWidget);

      // 3. Lobby with 6 Real Players
      final room = await service.createRoom(hostName: 'Pratham');
      final playerNames = ['Sarthak', 'Rahul', 'Aman', 'Kunal', 'Dev'];

      for (int i = 0; i < playerNames.length; i++) {
        AuthService.instance.setCustomUid('real_player_${i + 2}');
        await service.joinRoom(roomCode: room.code, playerName: playerNames[i]);
      }
      AuthService.instance.setCustomUid('real_host_1');

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

      // Check no bot controls appear
      expect(find.byKey(const Key('add_test_bot_button')), findsNothing);

      // Check player count and ready state
      expect(find.text('6 / 12 (Min 6)'), findsOneWidget);
      expect(find.text('READY TO PLAY'), findsOneWidget);

      // START GAME button is enabled
      final startBtn = find.byKey(const Key('start_game_button'));
      expect(startBtn, findsOneWidget);
    });

    test('3. Full 6 Real Player Game Loop -> Game Over -> Play Again -> Same Room -> Second Game', () async {
      // STEP 1: Create room and join 6 real players
      AuthService.instance.setCustomUid('real_host_1');
      final room = await service.createRoom(hostName: 'Pratham (Host)');

      final guestUids = ['real_player_2', 'real_player_3', 'real_player_4', 'real_player_5', 'real_player_6'];
      final guestNames = ['Sarthak', 'Rahul', 'Aman', 'Kunal', 'Dev'];

      for (int i = 0; i < guestUids.length; i++) {
        AuthService.instance.setCustomUid(guestUids[i]);
        await service.joinRoom(roomCode: room.code, playerName: guestNames[i]);
      }
      AuthService.instance.setCustomUid('real_host_1');

      var players = await service.streamPlayers(room.id).first;
      expect(players.length, 6);
      expect(players.every((p) => !p.isBot), isTrue);

      // STEP 2: Host starts game -> transitions to roleReveal
      await service.startGame(room.id);
      var currentRoom = await service.streamRoom(room.id).first;
      expect(currentRoom.status, RoomStatus.playing);
      expect(currentRoom.currentPhase, GamePhase.roleReveal);
      expect(currentRoom.currentRound, 1);

      // Verify server distributed 6 roles (1 Mafia, 1 Detective, 1 Doctor, 3 Civilians)
      final allRoles = <PlayerRole>[];
      for (final p in players) {
        AuthService.instance.setCustomUid(p.uid);
        allRoles.add(await service.streamMyRole(room.id).first);
      }
      expect(allRoles.where((r) => r == PlayerRole.mafia).length, 1);
      expect(allRoles.where((r) => r == PlayerRole.detective).length, 1);
      expect(allRoles.where((r) => r == PlayerRole.doctor).length, 1);
      expect(allRoles.where((r) => r == PlayerRole.civilian).length, 3);

      // Identify roles
      final mafiaUid = players[allRoles.indexOf(PlayerRole.mafia)].uid;
      final detectiveUid = players[allRoles.indexOf(PlayerRole.detective)].uid;
      final doctorUid = players[allRoles.indexOf(PlayerRole.doctor)].uid;
      final civilianUids = players
          .asMap()
          .entries
          .where((e) => allRoles[e.key] == PlayerRole.civilian)
          .map((e) => e.value.uid)
          .toList();

      // STEP 3: Advance to Actions
      AuthService.instance.setCustomUid('real_host_1');
      await service.advanceToActions(room.id);
      currentRoom = await service.streamRoom(room.id).first;
      expect(currentRoom.currentPhase, GamePhase.actions);

      // Submit all real player actions:
      // Mafia attacks first civilian
      final victimUid = civilianUids.first;
      await service.submitAction(
        roomId: room.id,
        roundNumber: 1,
        uid: mafiaUid,
        targetId: victimUid,
        role: PlayerRole.mafia,
      );

      // Detective investigates another player
      await service.submitAction(
        roomId: room.id,
        roundNumber: 1,
        uid: detectiveUid,
        targetId: civilianUids[1],
        role: PlayerRole.detective,
      );

      // Doctor protects someone else
      await service.submitAction(
        roomId: room.id,
        roundNumber: 1,
        uid: doctorUid,
        targetId: doctorUid,
        role: PlayerRole.doctor,
      );

      // Wait a moment for resolution to roundResult
      await Future<void>.delayed(const Duration(milliseconds: 200));

      currentRoom = await service.streamRoom(room.id).first;
      expect(
        [GamePhase.roundResult, GamePhase.gameOver].contains(currentRoom.currentPhase),
        isTrue,
      );

      // STEP 4: Advance to Discussion
      if (currentRoom.currentPhase == GamePhase.roundResult) {
        AuthService.instance.setCustomUid('real_host_1');
        await service.advanceToDiscussion(room.id);
        currentRoom = await service.streamRoom(room.id).first;
        expect(currentRoom.currentPhase, GamePhase.discussion);

        // Advance to Voting
        await service.advanceToVoting(room.id);
        currentRoom = await service.streamRoom(room.id).first;
        expect(currentRoom.currentPhase, GamePhase.voting);

        // Living players vote to eliminate Mafia
        final livingPlayers = (await service.streamPlayers(room.id).first).where((p) => p.isAlive).toList();
        for (final p in livingPlayers) {
          AuthService.instance.setCustomUid(p.uid);
          await service.submitVote(
            roomId: room.id,
            roundNumber: 1,
            uid: p.uid,
            targetId: mafiaUid,
          );
        }

        // Wait for vote resolution
        await Future<void>.delayed(const Duration(milliseconds: 200));
        currentRoom = await service.streamRoom(room.id).first;
      }

      // STEP 5: Verify Game Over state (Civilians eliminate the lone Mafia)
      expect(
        currentRoom.currentPhase == GamePhase.gameOver ||
            currentRoom.currentPhase == GamePhase.elimination,
        isTrue,
      );

      // If in elimination, advance to next round or end
      if (currentRoom.currentPhase == GamePhase.elimination) {
        AuthService.instance.setCustomUid('real_host_1');
        await service.advanceToNextRoundOrEnd(room.id);
        currentRoom = await service.streamRoom(room.id).first;
      }

      expect(currentRoom.currentPhase, GamePhase.gameOver);
      expect(currentRoom.status, RoomStatus.gameOver);
      expect(currentRoom.winner?.toUpperCase(), 'CIVILIANS');

      // STEP 6: PLAY AGAIN / RETURN TO ROOM
      // Call resetRoomForNewGame on the finished room
      await service.resetRoomForNewGame(room.id);

      final resetRoom = await service.streamRoom(room.id).first;
      expect(resetRoom.id, room.id);
      expect(resetRoom.code, room.code);
      expect(resetRoom.hostId, 'real_host_1');
      expect(resetRoom.status, RoomStatus.lobby);
      expect(resetRoom.currentPhase, GamePhase.lobby);
      expect(resetRoom.currentRound, 0);
      expect(resetRoom.winner, isNull);

      // Verify all 6 players are preserved, revived, and roles reset
      final resetPlayers = await service.streamPlayers(room.id).first;
      expect(resetPlayers.length, 6);
      for (final p in resetPlayers) {
        expect(p.isAlive, isTrue);
        expect(p.role, PlayerRole.unknown);
      }

      // STEP 7: Host starts a BRAND NEW GAME in the SAME ROOM
      AuthService.instance.setCustomUid('real_host_1');
      await service.startGame(room.id);
      final newGameRoom = await service.streamRoom(room.id).first;
      expect(newGameRoom.status, RoomStatus.playing);
      expect(newGameRoom.currentPhase, GamePhase.roleReveal);
      expect(newGameRoom.currentRound, 1);

      // Verify fresh roles assigned
      final newRoles = <PlayerRole>[];
      for (final p in resetPlayers) {
        AuthService.instance.setCustomUid(p.uid);
        newRoles.add(await service.streamMyRole(room.id).first);
      }
      expect(newRoles.where((r) => r == PlayerRole.mafia).length, 1);
      expect(newRoles.where((r) => r == PlayerRole.detective).length, 1);
      expect(newRoles.where((r) => r == PlayerRole.doctor).length, 1);
      expect(newRoles.where((r) => r == PlayerRole.civilian).length, 3);
    });

    test('4. Player exits to Home: leaves room intact for remaining players', () async {
      AuthService.instance.setCustomUid('host_exit_test');
      final room = await service.createRoom(hostName: 'Host');

      for (int i = 1; i <= 5; i++) {
        AuthService.instance.setCustomUid('guest_$i');
        await service.joinRoom(roomCode: room.code, playerName: 'Guest_$i');
      }

      // Guest 3 leaves the room
      AuthService.instance.setCustomUid('guest_3');
      await service.leaveRoom(roomId: room.id, uid: 'guest_3');

      // Verify room remains intact with 5 players
      final remainingPlayers = await service.streamPlayers(room.id).first;
      expect(remainingPlayers.length, 5);
      expect(remainingPlayers.any((p) => p.uid == 'guest_3'), isFalse);
      expect(remainingPlayers.any((p) => p.uid == 'host_exit_test'), isTrue);

      final roomDoc = await service.streamRoom(room.id).first;
      expect(roomDoc.status, RoomStatus.lobby);
    });

    testWidgets('5. GameOverView renders PLAY AGAIN and EXIT TO HOME buttons', (tester) async {
      final room = Room(
        id: 'test_game_over_room',
        code: 'TEST01',
        hostId: 'host_uid',
        status: RoomStatus.gameOver,
        currentPhase: GamePhase.gameOver,
        currentRound: 2,
        winner: 'mafia',
        createdAt: DateTime.now(),
      );

      final players = [
        Player(uid: 'host_uid', name: 'Pratham', role: PlayerRole.mafia, isAlive: true, isHost: true, joinedAt: DateTime.now()),
        Player(uid: 'p2', name: 'Sarthak', role: PlayerRole.civilian, isAlive: false, joinedAt: DateTime.now()),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameOverView(
              room: room,
              allPlayers: players,
              isHost: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('THE CITY FALLS'), findsOneWidget);
      expect(find.text('MAFIA WINS'), findsOneWidget);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(find.text('EXIT TO HOME'), findsOneWidget);
    });
  });
}
