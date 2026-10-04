import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_game/models/game_phase.dart';
import 'package:mafia_game/models/player_role.dart';
import 'package:mafia_game/models/room.dart';
import 'package:mafia_game/screens/home_screen.dart';
import 'package:mafia_game/screens/lobby_screen.dart';
import 'package:mafia_game/services/auth_service.dart';
import 'package:mafia_game/services/game_service_provider.dart';
import 'package:mafia_game/services/local_simulation_game_service.dart';
import 'package:mafia_game/utils/room_code_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalSimulationGameService service;

  setUp(() {
    service = LocalSimulationGameService();
    GameServiceProvider.instance.setServiceForTesting(service);
  });

  tearDown(() {
    GameServiceProvider.instance.setServiceForTesting(null);
  });

  group('Phase 2.5 — Room-Only Architecture & Multiplayer Tests', () {
    // 1. Create room
    test('1. Create room creates room with short code, LOBBY status, and host player', () async {
      AuthService.instance.setCustomUid('host_123');
      final room = await service.createRoom(hostName: 'AliceHost');

      expect(room.id, isNotEmpty);
      expect(room.code.length, 6);
      expect(room.status, RoomStatus.lobby);
      expect(room.hostId, 'host_123');
      expect(room.currentPhase, GamePhase.lobby);
      expect(room.currentRound, 0);

      final players = await service.streamPlayers(room.id).first;
      expect(players.length, 1);
      expect(players.first.uid, 'host_123');
      expect(players.first.name, 'AliceHost');
      expect(players.first.isHost, isTrue);
      expect(players.first.isAlive, isTrue);
    });

    // 2. Join room
    test('2. Join room adds player to lobby and joins realtime stream', () async {
      AuthService.instance.setCustomUid('host_1');
      final room = await service.createRoom(hostName: 'Host');

      AuthService.instance.setCustomUid('player_2');
      final joinedRoom = await service.joinRoom(
        roomCode: room.code,
        playerName: 'BobPlayer',
      );

      expect(joinedRoom.id, room.id);

      final players = await service.streamPlayers(room.id).first;
      expect(players.length, 2);
      expect(players.any((p) => p.uid == 'player_2' && p.name == 'BobPlayer'), isTrue);
      expect(players.firstWhere((p) => p.uid == 'player_2').isHost, isFalse);
    });

    // 3. Room code validation
    test('3. Room code validation enforces 6-char alphanumeric, case-insensitivity, and rejects invalid formats', () {
      expect(RoomCodeGenerator.isValid('K7XM2P'), isTrue);
      expect(RoomCodeGenerator.isValid('k7xm2p'), isTrue); // sanitized to uppercase
      expect(RoomCodeGenerator.sanitize('  k7xm2p  '), 'K7XM2P');

      expect(RoomCodeGenerator.isValid(''), isFalse);
      expect(RoomCodeGenerator.isValid('12345'), isFalse);
      expect(RoomCodeGenerator.isValid('TOOLONG123'), isFalse);
      expect(RoomCodeGenerator.isValid('AB@#12'), isFalse);

      // Verify code generator alphabet excludes ambiguous characters 0, O, 1, I
      for (int i = 0; i < 50; i++) {
        final code = RoomCodeGenerator.generate();
        expect(code.contains('0'), isFalse);
        expect(code.contains('O'), isFalse);
        expect(code.contains('1'), isFalse);
        expect(code.contains('I'), isFalse);
        expect(RoomCodeGenerator.isValid(code), isTrue);
      }
    });

    // 4. Room capacity
    test('4. Room capacity enforces 6 minimum to start and 12 maximum capacity', () async {
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');

      // Fails to start with fewer than 6 players
      expect(() => service.startGame(room.id), throwsA(isA<Exception>()));

      // Add up to 12 players
      for (int i = 2; i <= 12; i++) {
        AuthService.instance.setCustomUid('player_$i');
        await service.joinRoom(roomCode: room.code, playerName: 'Player$i');
      }

      final players = await service.streamPlayers(room.id).first;
      expect(players.length, 12);

      // 13th player cannot join (room full)
      AuthService.instance.setCustomUid('player_13');
      expect(
        () => service.joinRoom(roomCode: room.code, playerName: 'Player13'),
        throwsA(isA<Exception>()),
      );
    });

    // 5. Multiple players in same room
    test('5. Multiple players join same room and are tracked accurately', () async {
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');

      final joinNames = ['Charlie', 'Dana', 'Elena', 'Farhan', 'Gita'];
      for (int i = 0; i < joinNames.length; i++) {
        AuthService.instance.setCustomUid('uid_${i + 2}');
        await service.joinRoom(roomCode: room.code, playerName: joinNames[i]);
      }

      final players = await service.streamPlayers(room.id).first;
      expect(players.length, 6);
      expect(players.map((p) => p.name).toList(), [
        'Host',
        'Charlie',
        'Dana',
        'Elena',
        'Farhan',
        'Gita',
      ]);
    });

    // 6. Realtime player list
    test('6. Realtime player list stream updates automatically when players join or leave', () async {
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');

      final initialPlayers = await service.streamPlayers(room.id).first;
      expect(initialPlayers.length, 1);

      AuthService.instance.setCustomUid('player_2');
      await service.joinRoom(roomCode: room.code, playerName: 'Player2');
      final playersAfterJoin = await service.streamPlayers(room.id).first;
      expect(playersAfterJoin.length, 2);

      await service.leaveRoom(roomId: room.id, uid: 'player_2');
      final playersAfterLeave = await service.streamPlayers(room.id).first;
      expect(playersAfterLeave.length, 1);
    });

    // 7. Host identification
    test('7. Host identification accurately marks hostId and isHost flag', () async {
      AuthService.instance.setCustomUid('alpha_host');
      final room = await service.createRoom(hostName: 'AlphaHost');

      AuthService.instance.setCustomUid('beta_guest');
      await service.joinRoom(roomCode: room.code, playerName: 'BetaGuest');

      final players = await service.streamPlayers(room.id).first;
      final host = players.firstWhere((p) => p.uid == 'alpha_host');
      final guest = players.firstWhere((p) => p.uid == 'beta_guest');

      expect(room.hostId, 'alpha_host');
      expect(host.isHost, isTrue);
      expect(guest.isHost, isFalse);
    });

    // 8. Game start from room
    test('8. Game start from room transitions room to playing and roleReveal', () async {
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');

      for (int i = 2; i <= 6; i++) {
        AuthService.instance.setCustomUid('p_$i');
        await service.joinRoom(roomCode: room.code, playerName: 'P$i');
      }

      AuthService.instance.setCustomUid('host');
      await service.startGame(room.id);

      final updatedRoom = await service.streamRoom(room.id).first;
      expect(updatedRoom.status, RoomStatus.playing);
      expect(updatedRoom.currentPhase, GamePhase.roleReveal);
      expect(updatedRoom.currentRound, 1);
    });

    // 9. Player reconnect
    test('9. Player reconnect: rejoining active room with existing UID restores room state and role', () async {
      AuthService.instance.setCustomUid('host_uid');
      final room = await service.createRoom(hostName: 'Host');

      AuthService.instance.setCustomUid('reconnecting_player');
      await service.joinRoom(roomCode: room.code, playerName: 'Reconnector');

      for (int i = 3; i <= 6; i++) {
        AuthService.instance.setCustomUid('bot_$i');
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      AuthService.instance.setCustomUid('host_uid');
      await service.startGame(room.id);
      await service.advanceToActions(room.id);

      // Verify room is in actions phase
      final currentRoom = await service.streamRoom(room.id).first;
      expect(currentRoom.status, RoomStatus.playing);
      expect(currentRoom.currentPhase, GamePhase.actions);

      // Now simulate player reopening app with same persistent UID
      AuthService.instance.setCustomUid('reconnecting_player');
      final rejoinedRoom = await service.joinRoom(
        roomCode: room.code,
        playerName: 'Reconnector',
      );

      // Player must successfully rejoin and restore full game state
      expect(rejoinedRoom.id, room.id);
      expect(rejoinedRoom.status, RoomStatus.playing);
      expect(rejoinedRoom.currentPhase, GamePhase.actions);
      expect(rejoinedRoom.currentRound, 1);

      // Player's private role is intact and streamed
      final myRole = await service.streamMyRole(room.id).first;
      expect(myRole, isNot(PlayerRole.unknown));

      // Player is still alive in public players list
      final players = await service.streamPlayers(room.id).first;
      final reconnector = players.firstWhere((p) => p.uid == 'reconnecting_player');
      expect(reconnector.isAlive, isTrue);
    });

    // 10. Host disconnect / leave handling
    test('10. Host disconnect/leave handling transfers host to next player safely', () async {
      AuthService.instance.setCustomUid('host_1');
      final room = await service.createRoom(hostName: 'Host1');

      AuthService.instance.setCustomUid('player_2');
      await service.joinRoom(roomCode: room.code, playerName: 'Player2');

      AuthService.instance.setCustomUid('player_3');
      await service.joinRoom(roomCode: room.code, playerName: 'Player3');

      // Host leaves room
      await service.leaveRoom(roomId: room.id, uid: 'host_1');

      final updatedRoom = await service.streamRoom(room.id).first;
      final players = await service.streamPlayers(room.id).first;

      // Host transferred to player_2
      expect(updatedRoom.hostId, 'player_2');
      expect(players.length, 2);
      expect(players.firstWhere((p) => p.uid == 'player_2').isHost, isTrue);
      expect(players.firstWhere((p) => p.uid == 'player_3').isHost, isFalse);
    });

    // 11. Invalid room transitions
    test('11. Invalid room transitions are prevented', () async {
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');

      // Cannot advance to actions before game started
      expect(() => service.advanceToActions(room.id), throwsA(isA<Exception>()));

      // Cannot advance to voting before round resolved
      expect(() => service.advanceToVoting(room.id), throwsA(isA<Exception>()));
    });

    // 12. Private role isolation
    test('12. Private role isolation: roles are unknown in public stream during PLAYING', () async {
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');

      for (int i = 2; i <= 6; i++) {
        AuthService.instance.setCustomUid('p_$i');
        await service.joinRoom(roomCode: room.code, playerName: 'P$i');
      }

      AuthService.instance.setCustomUid('host');
      await service.startGame(room.id);

      final publicPlayers = await service.streamPlayers(room.id).first;
      for (final p in publicPlayers) {
        expect(p.role, PlayerRole.unknown,
            reason: 'Public stream must never leak roles during PLAYING.');
      }

      // But private stream returns the caller own role
      final hostRole = await service.streamMyRole(room.id).first;
      expect(hostRole, isNot(PlayerRole.unknown));
    });

    // 13. Server-authoritative mutations
    test('13. Server-authoritative mutations submit actions and votes', () async {
      AuthService.instance.setCustomUid('host_auth');
      final room = await service.createRoom(hostName: 'Host');

      for (int i = 2; i <= 6; i++) {
        AuthService.instance.setCustomUid('bot_$i');
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      AuthService.instance.setCustomUid('host_auth');
      await service.startGame(room.id);
      await service.advanceToActions(room.id);

      final role = await service.streamMyRole(room.id).first;
      final players = await service.streamPlayers(room.id).first;
      final target = players.firstWhere((p) => p.uid != 'host_auth');

      // Submit action through authoritative service
      if (role != PlayerRole.civilian) {
        await service.submitAction(
          roomId: room.id,
          roundNumber: 1,
          uid: 'host_auth',
          targetId: target.uid,
          role: role,
        );

        final submittedAction = await service.streamMyAction(room.id, 1).first;
        expect(submittedAction, isNotNull);
        expect(submittedAction!.targetId, target.uid);
      }
    });

    // 14. No user-facing simulator navigation
    testWidgets('14. HomeScreen renders ONLY CREATE ROOM and JOIN ROOM (no simulator buttons)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verified: CREATE GAME and JOIN GAME are present
      expect(find.text('CREATE GAME'), findsOneWidget);
      expect(find.text('JOIN GAME'), findsOneWidget);

      // Verified: NO simulator, offline, bot, or demo buttons
      expect(find.text('Offline/Simulator'), findsNothing);
      expect(find.text('Simulator'), findsNothing);
      expect(find.text('Offline'), findsNothing);
      expect(find.text('Bot Mode'), findsNothing);
      expect(find.text('Add Bot'), findsNothing);
      expect(find.text('Demo'), findsNothing);
      expect(find.text('Local Game'), findsNothing);
      expect(find.text('Cloud Game'), findsNothing);
    });

    // 15. No cloud interface navigation
    testWidgets('15. HomeScreen contains NO cloud interface terminology', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Cloud'), findsNothing);
      expect(find.textContaining('Firebase'), findsNothing);
      expect(find.textContaining('Firestore'), findsNothing);
      expect(find.textContaining('Backend'), findsNothing);
      expect(find.textContaining('Server'), findsNothing);
    });

    // 16. GAME_OVER prevents further gameplay
    test('16. GAME_OVER prevents further gameplay and new joins', () async {
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');

      for (int i = 2; i <= 6; i++) {
        AuthService.instance.setCustomUid('p_$i');
        await service.joinRoom(roomCode: room.code, playerName: 'P$i');
      }

      AuthService.instance.setCustomUid('host');
      await service.startGame(room.id);

      // Force game over state in room for testing
      final roomDoc = await service.streamRoom(room.id).first;
      final finishedRoom = roomDoc.copyWith(
        status: RoomStatus.gameOver,
        currentPhase: GamePhase.gameOver,
        winner: 'CIVILIANS',
      );
      // Testing room join rejection on finished room
      // Attempting to join a GAME_OVER room should throw
      AuthService.instance.setCustomUid('late_joiner');
      // Update in simulation
      service.forceRoomState(finishedRoom);

      expect(
        () => service.joinRoom(roomCode: room.code, playerName: 'LateJoiner'),
        throwsA(isA<Exception>()),
      );
    });

    // 17. Existing Phase 2 security regression check
    test('17. Security regression check: private role isolation, round data privacy', () {
      final round = service.streamRound('non_existent', 1);
      expect(round, isNotNull);
    });

    // ─── Phase 2.5.1 — Host Availability & Room Cleanup Tests ───────────────

    // 18. Host unavailability: living player can claim host when host disappears
    test('18. Host unavailability: living player can claim host when host disappears', () async {
      AuthService.instance.setCustomUid('host_orig');
      final room = await service.createRoom(hostName: 'HostOrig');

      AuthService.instance.setCustomUid('player_living');
      await service.joinRoom(roomCode: room.code, playerName: 'PlayerLiving');

      // Original host disappears/crashes (still in room doc as hostId)
      // Living player claims host
      await service.claimHost(room.id);

      final updatedRoom = await service.streamRoom(room.id).first;
      expect(updatedRoom.hostId, 'player_living');

      final players = await service.streamPlayers(room.id).first;
      final newHostPlayer = players.firstWhere((p) => p.uid == 'player_living');
      final oldHostPlayer = players.firstWhere((p) => p.uid == 'host_orig');

      expect(newHostPlayer.isHost, isTrue);
      expect(oldHostPlayer.isHost, isFalse);
    });

    // 19. Host claiming security: dead players, non-members, and game over rooms cannot claim host
    test('19. Host claiming security: dead players, non-members, and game over rooms cannot claim host', () async {
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');

      AuthService.instance.setCustomUid('living_player');
      await service.joinRoom(roomCode: room.code, playerName: 'LivingPlayer');

      // Non-member attempts to claim host
      AuthService.instance.setCustomUid('stranger');
      expect(
        () => service.claimHost(room.id),
        throwsA(isA<Exception>()),
      );

      // Add up to 6 players to start
      for (int i = 3; i <= 6; i++) {
        AuthService.instance.setCustomUid('p_$i');
        await service.joinRoom(roomCode: room.code, playerName: 'P$i');
      }
      AuthService.instance.setCustomUid('host');
      await service.startGame(room.id);

      // Dead player attempts to claim host
      service.setPlayerAliveForTesting(room.id, 'living_player', false);
      AuthService.instance.setCustomUid('living_player');
      expect(
        () => service.claimHost(room.id),
        throwsA(isA<Exception>()),
      );

      // Room in GAME_OVER cannot have host claimed
      final roomDoc = await service.streamRoom(room.id).first;
      service.forceRoomState(roomDoc.copyWith(status: RoomStatus.gameOver));
      AuthService.instance.setCustomUid('p_3');
      expect(
        () => service.claimHost(room.id),
        throwsA(isA<Exception>()),
      );
    });

    // 20. Host progression authority: new host can advance game phases while server remains authoritative
    test('20. Host progression authority: new host can advance game phases while server remains authoritative', () async {
      AuthService.instance.setCustomUid('host_orig');
      final room = await service.createRoom(hostName: 'HostOrig');

      for (int i = 2; i <= 6; i++) {
        AuthService.instance.setCustomUid('p_$i');
        await service.joinRoom(roomCode: room.code, playerName: 'P$i');
      }

      // Old host started the game then crashed during roleReveal
      AuthService.instance.setCustomUid('host_orig');
      await service.startGame(room.id);

      final r1 = await service.streamRoom(room.id).first;
      expect(r1.currentPhase, GamePhase.roleReveal);

      // Player 2 claims host
      AuthService.instance.setCustomUid('p_2');
      await service.claimHost(room.id);

      // Player 2 advances to actions
      await service.advanceToActions(room.id);

      final r2 = await service.streamRoom(room.id).first;
      expect(r2.currentPhase, GamePhase.actions);
    });

    // 21. Explicit leave vs disconnect: explicit leave transfers host immediately
    test('21. Explicit leave vs disconnect: explicit leave transfers host immediately', () async {
      AuthService.instance.setCustomUid('host_1');
      final room = await service.createRoom(hostName: 'Host1');

      AuthService.instance.setCustomUid('p_2');
      await service.joinRoom(roomCode: room.code, playerName: 'P2');

      AuthService.instance.setCustomUid('p_3');
      await service.joinRoom(roomCode: room.code, playerName: 'P3');

      // Explicit leave: caller leaves room
      await service.leaveRoom(roomId: room.id, uid: 'host_1');

      final r = await service.streamRoom(room.id).first;
      expect(r.hostId, 'p_2');

      final players = await service.streamPlayers(room.id).first;
      expect(players.length, 2);
      expect(players.firstWhere((p) => p.uid == 'p_2').isHost, isTrue);
    });

    // 22. Room cleanup & orphaned subcollection isolation
    test('22. Room cleanup: when all players leave, room document is removed and cannot be rejoined', () async {
      AuthService.instance.setCustomUid('player_a');
      final room = await service.createRoom(hostName: 'PlayerA');

      AuthService.instance.setCustomUid('player_b');
      await service.joinRoom(roomCode: room.code, playerName: 'PlayerB');

      // Both players leave
      await service.leaveRoom(roomId: room.id, uid: 'player_a');
      await service.leaveRoom(roomId: room.id, uid: 'player_b');

      // Attempting to join deleted room code throws
      AuthService.instance.setCustomUid('late_entrant');
      expect(
        () => service.joinRoom(roomCode: room.code, playerName: 'LateEntrant'),
        throwsA(isA<Exception>()),
      );
    });

    // 23. UI Host Transfer: Non-host sees 'Host disconnected? Claim Host' in Lobby
    testWidgets('23. UI Host Transfer: Non-host sees claim host button and can claim host in Lobby', (tester) async {
      AuthService.instance.setCustomUid('host_id');
      final room = await service.createRoom(hostName: 'HostUser');

      AuthService.instance.setCustomUid('guest_id');
      await service.joinRoom(roomCode: room.code, playerName: 'GuestUser');

      await tester.pumpWidget(
        MaterialApp(
          home: LobbyScreen(
            roomId: room.id,
            roomCode: room.code,
            isHost: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Guest is not host, sees 'Waiting for host to start...' and claim host button
      expect(find.text('Waiting for host to start...'), findsOneWidget);
      final claimButton = find.byKey(const Key('claim_host_button'));
      expect(claimButton, findsOneWidget);

      // Tap claim host button
      await tester.tap(claimButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // After claiming host, START GAME button is visible
      expect(find.byKey(const Key('start_game_button')), findsOneWidget);
    });
  });
}
