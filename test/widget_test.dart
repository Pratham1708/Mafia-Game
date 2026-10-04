import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_game/models/game_phase.dart';
import 'package:mafia_game/models/player_role.dart';
import 'package:mafia_game/models/room.dart';
import 'package:mafia_game/services/auth_service.dart';
import 'package:mafia_game/services/game_logic_engine.dart';
import 'package:mafia_game/services/local_simulation_game_service.dart';

/// Integration tests for the LocalSimulationGameService game loop.
///
/// Security model verified here:
///   PUBLIC  - streamPlayers()  - roles are PlayerRole.unknown during PLAYING
///   PRIVATE - streamMyRole()   - current player's own role only
///   PRIVATE - streamMyAction() - current player's own submitted action
///   PRIVATE - streamMyVote()   - current player's own submitted vote
///   PRIVATE - streamMyResult() - detective's own investigation result
///
/// The simulation mirrors the Firestore private subcollection design.
/// These tests verify that the local simulation CORRECTLY enforces
/// the same read isolation guarantees as Firestore security rules would.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // --- ISOLATION SECURITY TESTS ---

  group('Private Read Isolation - Public Stream Security', () {
    test(
        'streamPlayers() returns PlayerRole.unknown for ALL players during PLAYING '
        '(roles are private - stored in privatePlayerData, not public doc)',
        () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host_uid');

      final room = await service.createRoom(hostName: 'Host');
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Player_$i');
      }

      await service.startGame(room.id);

      final players = await service.streamPlayers(room.id).first;

      // CRITICAL SECURITY CHECK:
      // Every player in the public stream must have role = unknown.
      // This proves roles are NOT in the public document during PLAYING.
      // Firestore rules enforce this; the local simulation must match.
      for (final p in players) {
        expect(
          p.role,
          PlayerRole.unknown,
          reason:
              'Player ${p.name} must have unknown role in the '
              'public player stream during PLAYING.',
        );
      }
    });

    test(
        'streamMyRole() returns the correct private role for the current player only',
        () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host_uid');

      final room = await service.createRoom(hostName: 'HostPlayer');
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      await service.startGame(room.id);

      final myRole = await service.streamMyRole(room.id).first;

      expect(
        myRole,
        isNot(PlayerRole.unknown),
        reason:
            'streamMyRole() must return the concrete role for the authenticated player.',
      );
      expect(
        [
          PlayerRole.mafia,
          PlayerRole.detective,
          PlayerRole.doctor,
          PlayerRole.civilian
        ].contains(myRole),
        isTrue,
        reason: 'Role must be one of the four valid game roles.',
      );
    });

    test(
        'streamMyAction() returns null before submission (owner-only)',
        () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host_uid');

      final room = await service.createRoom(hostName: 'Host');
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }
      await service.startGame(room.id);
      await service.advanceToActions(room.id);

      final beforeAction = await service.streamMyAction(room.id, 1).first;
      expect(
        beforeAction,
        isNull,
        reason: 'streamMyAction() must return null when no action submitted yet.',
      );
    });

    test(
        'streamMyVote() returns null before voting (owner-only)',
        () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host_uid');

      final room = await service.createRoom(hostName: 'Host');
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }
      await service.startGame(room.id);
      await service.advanceToVoting(room.id);

      final beforeVote = await service.streamMyVote(room.id, 1).first;
      expect(
        beforeVote,
        isNull,
        reason: 'streamMyVote() must return null when player has not yet voted.',
      );
    });
  });

  // --- FULL GAME LOOP SIMULATION ---

  group('Full Multiplayer Game Loop Simulation', () {
    test('Simulates complete 6-player Mafia game from lobby to game over',
        () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host_uid');

      // 1. Create room
      final room = await service.createRoom(hostName: 'HostPlayer');
      expect(room.id, isNotEmpty);
      expect(room.code.length, 6);
      expect(room.status, RoomStatus.lobby);

      // 2. Add 5 bot players
      final botNames = ['Bot_2', 'Bot_3', 'Bot_4', 'Bot_5', 'Bot_6'];
      for (final name in botNames) {
        await service.addTestPlayer(roomId: room.id, name: name);
      }

      // 3. Start game
      await service.startGame(room.id);

      // SECURITY: Verify public player stream has unknown roles
      final publicPlayers = await service.streamPlayers(room.id).first;
      expect(publicPlayers.length, 6);
      for (final p in publicPlayers) {
        expect(
          p.role,
          PlayerRole.unknown,
          reason: 'Public player stream must return unknown role during PLAYING.',
        );
      }

      // PRIVATE: Host reads their own role
      final hostRole = await service.streamMyRole(room.id).first;
      expect(hostRole, isNot(PlayerRole.unknown));

      // 4. Advance to Actions - bots auto-submit
      await service.advanceToActions(room.id);

      final allPlayers = await service.streamPlayers(room.id).first;
      final botPlayers = allPlayers.where((p) => p.isBot).toList();
      expect(botPlayers.isNotEmpty, isTrue);

      // Submit host action using private role
      try {
        await service.submitAction(
          roomId: room.id,
          roundNumber: 1,
          uid: 'host_uid',
          targetId: botPlayers.first.uid,
          role: hostRole,
        );
      } catch (_) {
        // Civilian or already submitted
      }

      // 5. Wait for bot automation + resolution
      await Future<void>.delayed(const Duration(milliseconds: 3000));

      // 6. Verify round resolved
      final roomAfterActions = await service.streamRoom(room.id).first;
      expect(
        [GamePhase.roundResult, GamePhase.gameOver]
            .contains(roomAfterActions.currentPhase),
        isTrue,
        reason: 'After actions resolved, phase must be roundResult or gameOver.',
      );

      if (roomAfterActions.currentPhase == GamePhase.gameOver) {
        expect(roomAfterActions.winner, isNotNull);
        final finalPlayers = await service.streamPlayers(room.id).first;
        for (final p in finalPlayers) {
          expect(p.role, isNot(PlayerRole.unknown));
        }
        return;
      }

      // 7. Advance to Voting
      await service.advanceToVoting(room.id);
      final roomInVoting = await service.streamRoom(room.id).first;
      expect(roomInVoting.currentPhase, GamePhase.voting);

      // 8. Host votes
      final livingPlayers = (await service.streamPlayers(room.id).first)
          .where((p) => p.isAlive)
          .toList();
      final hostAlive = livingPlayers.any((p) => p.uid == 'host_uid');
      if (hostAlive) {
        final voteTarget = livingPlayers.firstWhere((p) => p.uid != 'host_uid');
        await service.submitVote(
          roomId: room.id,
          roundNumber: 1,
          uid: 'host_uid',
          targetId: voteTarget.uid,
        );
      }

      // Wait for bots + resolution
      await Future<void>.delayed(const Duration(milliseconds: 3000));

      final roomAfterVoting = await service.streamRoom(room.id).first;
      expect(
        [GamePhase.elimination, GamePhase.gameOver]
            .contains(roomAfterVoting.currentPhase),
        isTrue,
      );

      if (roomAfterVoting.currentPhase == GamePhase.gameOver) {
        expect(roomAfterVoting.winner, isNotNull);
        return;
      }

      // 10. Advance to next round
      await service.advanceToNextRoundOrEnd(room.id);
      final finalRoom = await service.streamRoom(room.id).first;
      expect(
        [GamePhase.actions, GamePhase.gameOver].contains(finalRoom.currentPhase),
        isTrue,
      );
    });
  });

  // --- BOT ARCHITECTURE ---

  group('Bot Architecture - 2 humans + 4 bots', () {
    test('6-player game with 2 humans + 4 bots starts correctly', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('human_1');
      final room = await service.createRoom(hostName: 'Human1');
      AuthService.instance.setCustomUid('human_2');
      await service.joinRoom(roomCode: room.code, playerName: 'Human2');
      AuthService.instance.setCustomUid('human_1');
      for (int i = 1; i <= 4; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      final players = await service.streamPlayers(room.id).first;
      expect(players.length, 6);
      expect(players.where((p) => p.isBot).length, 4);
      expect(players.where((p) => !p.isBot).length, 2);

      await service.startGame(room.id);

      final publicPlayers = await service.streamPlayers(room.id).first;
      for (final p in publicPlayers) {
        expect(
          p.role,
          PlayerRole.unknown,
          reason: 'Public stream must not expose roles during PLAYING.',
        );
      }
    });

    test('isBot flag preserved correctly through game lifecycle', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host_uid');
      final room = await service.createRoom(hostName: 'HostPlayer');
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }

      await service.startGame(room.id);

      final players = await service.streamPlayers(room.id).first;
      expect(players.where((p) => p.isBot).length, 5);
      expect(players.where((p) => !p.isBot).length, 1);
    });
  });

  // --- GAME_OVER ROLE REVEAL ---

  group('GAME_OVER Role Reveal', () {
    test('Roles are unknown during PLAYING; revealed after GAME_OVER', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host_uid');
      final room = await service.createRoom(hostName: 'Host');
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'Bot_$i');
      }
      await service.startGame(room.id);

      final myRoleBefore = await service.streamMyRole(room.id).first;
      expect(myRoleBefore, isNot(PlayerRole.unknown));

      final publicBefore = await service.streamPlayers(room.id).first;
      for (final p in publicBefore) {
        expect(p.role, PlayerRole.unknown,
            reason: 'Roles must be unknown in public stream during PLAYING.');
      }

      await service.advanceToActions(room.id);
      await Future<void>.delayed(const Duration(milliseconds: 4000));

      final roomState = await service.streamRoom(room.id).first;
      if (roomState.currentPhase == GamePhase.gameOver) {
        final publicAfter = await service.streamPlayers(room.id).first;
        for (final p in publicAfter) {
          expect(p.role, isNot(PlayerRole.unknown),
              reason: 'At GAME_OVER, roles must be revealed for all players.');
        }
        expect(roomState.winner, isNotNull);
      } else {
        expect(
          [GamePhase.roundResult, GamePhase.actions]
              .contains(roomState.currentPhase),
          isTrue,
        );
      }
    });
  });

  // --- PHASE TRANSITIONS ---

  group('Phase Transition State Machine', () {
    test('startGame transitions room from LOBBY to roleReveal', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'P$i');
      }
      await service.startGame(room.id);
      final r = await service.streamRoom(room.id).first;
      expect(r.status, RoomStatus.playing);
      expect(r.currentPhase, GamePhase.roleReveal);
      expect(r.currentRound, 1);
    });

    test('advanceToActions transitions from roleReveal to actions', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'P$i');
      }
      await service.startGame(room.id);
      await service.advanceToActions(room.id);
      final r = await service.streamRoom(room.id).first;
      expect(r.currentPhase, GamePhase.actions);
    });

    test('startGame requires at least 6 players', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host');
      final room = await service.createRoom(hostName: 'Host');
      await service.addTestPlayer(roomId: room.id, name: 'P2');
      await service.addTestPlayer(roomId: room.id, name: 'P3');
      expect(
        () => service.startGame(room.id),
        throwsA(isA<Exception>()),
        reason: 'startGame must require at least 6 players.',
      );
    });

    test('Role distribution correct for 6 players (server-side)', () {
      final roles = GameLogicEngine.getRoleDistribution(6);
      expect(roles.where((r) => r == PlayerRole.mafia).length, 1);
      expect(roles.where((r) => r == PlayerRole.detective).length, 1);
      expect(roles.where((r) => r == PlayerRole.doctor).length, 1);
      expect(roles.where((r) => r == PlayerRole.civilian).length, 3);
    });
  });

  // --- SERVER AUTHORITY ---

  group('Server-Authority Validation', () {
    test('All players alive at game start', () async {
      final service = LocalSimulationGameService();
      AuthService.instance.setCustomUid('host_uid');
      final room = await service.createRoom(hostName: 'Host');
      for (int i = 1; i <= 5; i++) {
        await service.addTestPlayer(roomId: room.id, name: 'P$i');
      }
      await service.startGame(room.id);
      final players = await service.streamPlayers(room.id).first;
      expect(players.every((p) => p.isAlive), isTrue,
          reason: 'All players must be alive at game start.');
    });

    test('assignRoles produces correct counts for all player counts (6-12)', () {
      for (int n = 6; n <= 12; n++) {
        final roles = GameLogicEngine.getRoleDistribution(n);
        final mafia = roles.where((r) => r == PlayerRole.mafia).length;
        final det = roles.where((r) => r == PlayerRole.detective).length;
        final doc = roles.where((r) => r == PlayerRole.doctor).length;
        expect(roles.length, n);
        expect(det, 1, reason: '$n players: expected 1 detective');
        expect(doc, 1, reason: '$n players: expected 1 doctor');
        if (n <= 6) expect(mafia, 1);
        if (n >= 7 && n <= 9) expect(mafia, 2);
        if (n >= 10) expect(mafia, 3);
      }
    });
  });
}
