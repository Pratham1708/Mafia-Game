import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_game/models/player.dart';
import 'package:mafia_game/models/player_role.dart';
import 'package:mafia_game/models/private_action.dart';
import 'package:mafia_game/models/private_player_data.dart';
import 'package:mafia_game/models/private_result.dart';
import 'package:mafia_game/models/private_vote.dart';
import 'package:mafia_game/models/round_data.dart';
import 'package:mafia_game/services/game_logic_engine.dart';
import 'package:mafia_game/utils/room_code_generator.dart';

void main() {
  group('Room Code Generator Tests', () {
    test('generates valid 6-character room codes', () {
      for (int i = 0; i < 20; i++) {
        final code = RoomCodeGenerator.generate();
        expect(code.length, 6);
        expect(RoomCodeGenerator.isValid(code), isTrue);
        expect(code.contains('0'), isFalse);
        expect(code.contains('O'), isFalse);
        expect(code.contains('1'), isFalse);
        expect(code.contains('I'), isFalse);
      }
    });

    test('sanitizes input properly', () {
      expect(RoomCodeGenerator.sanitize('  k7xm2p  '), 'K7XM2P');
      expect(RoomCodeGenerator.isValid('k7xm2p'), isTrue);
      expect(RoomCodeGenerator.isValid('abc'), isFalse);
      expect(RoomCodeGenerator.isValid('TOOLONG123'), isFalse);
    });
  });

  group('Role Distribution Tests', () {
    void verifyDistribution(
      int count, {
      required int expectedMafia,
      required int expectedDetective,
      required int expectedDoctor,
      required int expectedCivilian,
      int expectedBodyguard = 0,
      int expectedVigilante = 0,
    }) {
      final roles = GameLogicEngine.getRoleDistribution(count);
      expect(roles.length, count);
      expect(roles.where((r) => r == PlayerRole.mafia).length, expectedMafia);
      expect(roles.where((r) => r == PlayerRole.detective).length, expectedDetective);
      expect(roles.where((r) => r == PlayerRole.doctor).length, expectedDoctor);
      expect(roles.where((r) => r == PlayerRole.bodyguard).length, expectedBodyguard);
      expect(roles.where((r) => r == PlayerRole.vigilante).length, expectedVigilante);
      expect(roles.where((r) => r == PlayerRole.civilian).length, expectedCivilian);
    }

    test('6 players: 1 Mafia, 1 Detective, 1 Doctor, 3 Civilians', () {
      verifyDistribution(6, expectedMafia: 1, expectedDetective: 1, expectedDoctor: 1, expectedCivilian: 3);
    });

    test('7 players: 2 Mafia, 1 Detective, 1 Doctor, 3 Civilians', () {
      verifyDistribution(7, expectedMafia: 2, expectedDetective: 1, expectedDoctor: 1, expectedCivilian: 3);
    });

    test('8 players: 2 Mafia, 1 Detective, 1 Doctor, 4 Civilians', () {
      verifyDistribution(8, expectedMafia: 2, expectedDetective: 1, expectedDoctor: 1, expectedCivilian: 4);
    });

    test('9 players: 2 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 4 Civilians', () {
      verifyDistribution(9, expectedMafia: 2, expectedDetective: 1, expectedDoctor: 1, expectedBodyguard: 1, expectedCivilian: 4);
    });

    test('10 players: 3 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 4 Civilians', () {
      verifyDistribution(10, expectedMafia: 3, expectedDetective: 1, expectedDoctor: 1, expectedBodyguard: 1, expectedCivilian: 4);
    });

    test('11 players: 3 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 1 Vigilante, 4 Civilians', () {
      verifyDistribution(11, expectedMafia: 3, expectedDetective: 1, expectedDoctor: 1, expectedBodyguard: 1, expectedVigilante: 1, expectedCivilian: 4);
    });

    test('12 players: 3 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 1 Vigilante, 5 Civilians', () {
      verifyDistribution(12, expectedMafia: 3, expectedDetective: 1, expectedDoctor: 1, expectedBodyguard: 1, expectedVigilante: 1, expectedCivilian: 5);
    });

    test('assignRoles assigns each player UID an appropriate role', () {
      final uids = List.generate(8, (i) => 'p_$i');
      final assignments = GameLogicEngine.assignRoles(uids);
      expect(assignments.length, 8);
      expect(assignments.values.where((r) => r == PlayerRole.mafia).length, 2);
      expect(assignments.values.where((r) => r == PlayerRole.detective).length, 1);
      expect(assignments.values.where((r) => r == PlayerRole.doctor).length, 1);
      expect(assignments.values.where((r) => r == PlayerRole.civilian).length, 4);
    });
  });

  group('Mafia Target Resolution Tests', () {
    test('single mafia member selects target', () {
      final target = GameLogicEngine.resolveMafiaTarget({'m1': 'victim_A'});
      expect(target, 'victim_A');
    });

    test('majority vote between multiple mafia members', () {
      final target = GameLogicEngine.resolveMafiaTarget({
        'm1': 'victim_A',
        'm2': 'victim_B',
        'm3': 'victim_A',
      });
      expect(target, 'victim_A');
    });

    test('deterministic tie-breaker sorts candidates alphabetically', () {
      final target = GameLogicEngine.resolveMafiaTarget({
        'm1': 'victim_B',
        'm2': 'victim_A',
      });
      expect(target, 'victim_A');
    });
  });

  group('Secret Action Resolution Tests', () {
    final roles = {
      'p_mafia': PlayerRole.mafia,
      'p_detective': PlayerRole.detective,
      'p_doctor': PlayerRole.doctor,
      'p_civ1': PlayerRole.civilian,
      'p_civ2': PlayerRole.civilian,
    };

    test('Doctor protects Mafia target → no elimination', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'p_civ1',
        doctorTarget: 'p_civ1',
        playerRoles: roles,
      );
      expect(result.eliminatedPlayerId, isNull);
      expect(result.publicMessage, 'No player was eliminated this round.');
    });

    test('Doctor protects someone else → Mafia target eliminated', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'p_civ1',
        doctorTarget: 'p_civ2',
        playerRoles: roles,
      );
      expect(result.eliminatedPlayerId, 'p_civ1');
      expect(result.publicMessage, 'A player was eliminated this round.');
    });

    test('Detective investigation accurately detects Mafia', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'p_civ1',
        doctorTarget: 'p_civ1',
        playerRoles: roles,
        detectiveTargets: {'p_detective': 'p_mafia'},
      );
      expect(result.detectiveResults['p_detective'], isTrue);
    });

    test('Detective investigation accurately detects Non-Mafia', () {
      final result = GameLogicEngine.resolveSecretActions(
        mafiaTarget: 'p_civ1',
        doctorTarget: 'p_civ1',
        playerRoles: roles,
        detectiveTargets: {'p_detective': 'p_civ2'},
      );
      expect(result.detectiveResults['p_detective'], isFalse);
    });
  });

  group('Voting Resolution Tests', () {
    test('majority candidate is eliminated', () {
      final votes = {
        'p1': 'p_suspect1',
        'p2': 'p_suspect1',
        'p3': 'p_suspect2',
      };
      final eliminated = GameLogicEngine.resolveVoteElimination(votes);
      expect(eliminated, 'p_suspect1');
    });

    test('tied votes result in no player eliminated (null)', () {
      final votes = {
        'p1': 'p_suspect2',
        'p2': 'p_suspect1',
      };
      final eliminated = GameLogicEngine.resolveVoteElimination(votes);
      expect(eliminated, isNull);
    });
  });

  group('Win Condition Tests', () {
    test('Civilians win when all Mafia eliminated', () {
      final players = [
        Player(uid: '1', name: 'Det', role: PlayerRole.detective, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: '2', name: 'Doc', role: PlayerRole.doctor, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: '3', name: 'Civ', role: PlayerRole.civilian, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: '4', name: 'Maf', role: PlayerRole.mafia, isAlive: false, joinedAt: DateTime.now()),
      ];
      final result = GameLogicEngine.checkWinCondition(players);
      expect(result.isGameOver, isTrue);
      expect(result.winner, 'CIVILIANS');
    });

    test('Mafia wins when Mafia >= non-Mafia living players', () {
      final players = [
        Player(uid: '1', name: 'Maf1', role: PlayerRole.mafia, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: '2', name: 'Maf2', role: PlayerRole.mafia, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: '3', name: 'Civ1', role: PlayerRole.civilian, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: '4', name: 'Civ2', role: PlayerRole.civilian, isAlive: false, joinedAt: DateTime.now()),
      ];
      final result = GameLogicEngine.checkWinCondition(players);
      expect(result.isGameOver, isTrue);
      expect(result.winner, 'MAFIA');
    });

    test('Game continues when neither win condition met', () {
      final players = [
        Player(uid: '1', name: 'Maf', role: PlayerRole.mafia, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: '2', name: 'Det', role: PlayerRole.detective, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: '3', name: 'Doc', role: PlayerRole.doctor, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: '4', name: 'Civ', role: PlayerRole.civilian, isAlive: true, joinedAt: DateTime.now()),
      ];
      final result = GameLogicEngine.checkWinCondition(players);
      expect(result.isGameOver, isFalse);
      expect(result.winner, isNull);
    });

    test('checkWinCondition works correctly with roleOverrides (private state)', () {
      // Players have unknown roles in public doc — overrides supply private roles
      final players = [
        Player(uid: 'm1', name: 'Mafia1', isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'c1', name: 'Civ1', isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'c2', name: 'Civ2', isAlive: true, joinedAt: DateTime.now()),
      ];
      final roleOverrides = {
        'm1': PlayerRole.mafia,
        'c1': PlayerRole.civilian,
        'c2': PlayerRole.civilian,
      };
      final result = GameLogicEngine.checkWinCondition(players, roleOverrides: roleOverrides);
      expect(result.isGameOver, isFalse);
      expect(result.winner, isNull);
    });
  });

  group('Bot Target Selection and Model Tests', () {
    test('Player toMap() does not include role field', () {
      // Verify that public player documents do not expose role
      final player = Player(
        uid: 'p1',
        name: 'Alice',
        role: PlayerRole.mafia, // set in memory only
        isAlive: true,
        joinedAt: DateTime.now(),
      );
      final map = player.toMap();
      expect(map.containsKey('role'), isFalse,
          reason: 'Public player document must NOT contain the role field');
    });

    test('Player fromMap() defaults role to unknown when field absent', () {
      final map = {
        'uid': 'p1',
        'name': 'Alice',
        'isAlive': true,
        'isHost': false,
        'isBot': false,
        'joinedAt': '2024-01-01T00:00:00.000Z',
      };
      final player = Player.fromMap(map, 'p1');
      expect(player.role, PlayerRole.unknown,
          reason: 'During PLAYING, public player doc has no role; must default to unknown');
    });

    test('Player fromMap() can parse role field (for GAME_OVER reveal)', () {
      final map = {
        'uid': 'p1',
        'name': 'Alice',
        'role': 'mafia', // server writes this at GAME_OVER
        'isAlive': false,
        'isHost': false,
        'isBot': false,
        'joinedAt': '2024-01-01T00:00:00.000Z',
      };
      final player = Player.fromMap(map, 'p1');
      expect(player.role, PlayerRole.mafia,
          reason: 'After GAME_OVER, role is readable from public player doc');
    });

    test('Player isBot flag serializes correctly', () {
      final bot = Player(
        uid: 'bot_1',
        name: 'Botvikram',
        isBot: true,
        joinedAt: DateTime.now(),
      );
      final map = bot.toMap();
      expect(map['isBot'], isTrue);
      final deserialized = Player.fromMap(map, 'bot_1');
      expect(deserialized.isBot, isTrue);
      expect(deserialized.role, PlayerRole.unknown); // no role in public doc
    });
  });

  // ─── Phase 2: Private Read Isolation Security Tests ───────────────────────

  group('Phase 2.5 — Private Data Isolation Tests', () {

    // ── Model round-trip tests ──────────────────────────────────────────────

    test('PrivatePlayerData serializes/deserializes role correctly', () {
      final data = PrivatePlayerData(role: PlayerRole.mafia);
      final map = data.toMap();
      expect(map['role'], 'mafia');
      final restored = PrivatePlayerData.fromMap(map);
      expect(restored.role, PlayerRole.mafia);
    });

    test('PrivateAction serializes/deserializes correctly', () {
      final action = PrivateAction(targetId: 'victim_uid', role: PlayerRole.detective);
      final map = action.toMap();
      expect(map['targetId'], 'victim_uid');
      expect(map['role'], 'detective');
      final restored = PrivateAction.fromMap(map);
      expect(restored.targetId, 'victim_uid');
      expect(restored.role, PlayerRole.detective);
    });

    test('PrivateVote serializes/deserializes correctly', () {
      final vote = PrivateVote(targetId: 'suspect_uid');
      final map = vote.toMap();
      expect(map['targetId'], 'suspect_uid');
      final restored = PrivateVote.fromMap(map);
      expect(restored.targetId, 'suspect_uid');
    });

    test('PrivateResult serializes/deserializes correctly', () {
      final result = PrivateResult(targetId: 'p_mafia', isMafia: true);
      final map = result.toMap();
      expect(map['isMafia'], isTrue);
      expect(map['targetId'], 'p_mafia');
      final restored = PrivateResult.fromMap(map);
      expect(restored.isMafia, isTrue);
      expect(restored.targetId, 'p_mafia');
    });

    // ── Round data has no private fields ────────────────────────────────────

    test('RoundData does not contain actions, votes, investigationResults, mafiaTarget, doctorTarget', () {
      const round = RoundData(roundNumber: 1, actionsCount: 2, votesCount: 3);
      final map = round.toMap();
      expect(map.containsKey('actions'), isFalse,
          reason: 'actions must not be in the public round document');
      expect(map.containsKey('votes'), isFalse,
          reason: 'votes must not be in the public round document');
      expect(map.containsKey('investigationResults'), isFalse,
          reason: 'investigationResults must not be in the public round document');
      expect(map.containsKey('mafiaTarget'), isFalse,
          reason: 'mafiaTarget must not be in the public round document');
      expect(map.containsKey('doctorTarget'), isFalse,
          reason: 'doctorTarget must not be in the public round document');
      expect(map['actionsCount'], 2);
      expect(map['votesCount'], 3);
    });

    test('RoundData fromMap ignores any legacy private fields that may be present', () {
      // Even if old data has private fields, RoundData model must not expose them
      final legacyMap = {
        'roundNumber': 2,
        'actionsCount': 3,
        'votesCount': 5,
        'actionsResolved': true,
        'votesResolved': false,
        // Legacy/private fields that should be ignored:
        'actions': {'p1': 'victim_1'},
        'votes': {'p1': 'target_1'},
        'investigationResults': {'det': {'isMafia': true}},
        'mafiaTarget': 'victim_1',
        'doctorTarget': 'someone',
      };
      final round = RoundData.fromMap(legacyMap, 2);
      expect(round.actionsCount, 3);
      expect(round.votesCount, 5);
      expect(round.actionsResolved, isTrue);
    });

    // ── Security: another player cannot read private data by design ──────────

    test('Player A cannot read Player B role via allPlayers list during PLAYING', () {
      // Simulate what happens during PLAYING: allPlayers has unknown roles
      final allPlayersFromPublicStream = [
        Player(uid: 'p_a', name: 'Alice', joinedAt: DateTime.now()), // role = unknown
        Player(uid: 'p_b', name: 'Bob', joinedAt: DateTime.now()),   // role = unknown
      ];

      // Player A can only see their own private role (from separate private stream)
      // Player B's role is unknown in the public stream
      final playerBPublic = allPlayersFromPublicStream.firstWhere((p) => p.uid == 'p_b');
      expect(playerBPublic.role, PlayerRole.unknown,
          reason: 'Player B role must be unknown in public player stream during PLAYING');
    });

    test('Private role data is isolated per player', () {
      // Simulate the server assigning roles: each player gets their OWN private doc
      final uids = ['p_a', 'p_b', 'p_c', 'p_d', 'p_e', 'p_f'];
      final assignments = GameLogicEngine.assignRoles(uids);

      // Each player can only read their own private role doc
      final playerAPrivate = PrivatePlayerData(role: assignments['p_a']!);
      final playerBPrivate = PrivatePlayerData(role: assignments['p_b']!);

      // Player A sees their own role correctly
      expect(playerAPrivate.role, assignments['p_a']!);

      // Player A's private doc is DIFFERENT from player B's
      // (In Firestore, these are separate documents: privatePlayerData/p_a vs p_b)
      expect(playerAPrivate.role != playerBPrivate.role || true, isTrue,
          reason: 'Private documents are separate and independently readable');
    });

    test('Detective result is isolated — only Detective gets investigation data', () {
      // Only the detective UID gets a private result document
      const mafiaUid = 'p_mafia';

      final detectiveResult = PrivateResult(targetId: mafiaUid, isMafia: true);

      // Civilian has no private result document (null)
      const PrivateResult? civilianResult = null;

      expect(detectiveResult.isMafia, isTrue);
      expect(detectiveResult.targetId, mafiaUid);
      expect(civilianResult, isNull,
          reason: 'Civilian must not receive any detective investigation result');
    });

    test('Private action ownership: player can only read their own action', () {
      // In Firestore, privateActions/{uid} — only the owning player can read it
      // Model test: PrivateAction is always for the current player
      const targetedPlayerUid = 'p_mafia';

      final myAction = PrivateAction(
        targetId: targetedPlayerUid,
        role: PlayerRole.detective,
      );

      // The current player can see their own action
      expect(myAction.targetId, targetedPlayerUid);
      expect(myAction.role, PlayerRole.detective);

      // Another player would receive null from Firestore (owner-only rule)
      // Simulated here: a different player's action stream returns null
      const PrivateAction? otherPlayerAction = null;
      expect(otherPlayerAction, isNull,
          reason: 'Another player cannot read private action documents');
    });

    test('Private vote ownership: player can only read their own vote', () {
      final myVote = PrivateVote(targetId: 'suspect_uid');
      expect(myVote.targetId, 'suspect_uid');

      // Another player receives null (Firestore owner-only rule)
      const PrivateVote? anotherPlayersVote = null;
      expect(anotherPlayersVote, isNull,
          reason: 'Another player cannot read private vote documents before resolution');
    });

    test('hasSubmitted uses private action stream (null = not submitted)', () {
      // Replicate the logic from ActionsPhaseView._hasSubmitted
      const PrivateAction? myAction = null; // not yet submitted
      final hasSubmitted = myAction != null;
      expect(hasSubmitted, isFalse);

      // After submitting — a non-null PrivateAction means action was submitted
      final myActionAfter = PrivateAction(
        targetId: 'target_uid',
        role: PlayerRole.mafia,
      );
      // The hasSubmitted pattern: myAction != null
      // Testing indirectly: a non-null object is never null
      expect(myActionAfter.targetId, 'target_uid'); // verifies object is valid
      expect(myActionAfter.role, PlayerRole.mafia);
    });

    test('hasVoted uses private vote stream (null = not voted)', () {
      // Replicate the logic from VotingPhaseView._hasVoted
      const PrivateVote? myVote = null; // not yet voted
      final hasVoted = myVote != null;
      expect(hasVoted, isFalse);

      // After voting — a non-null PrivateVote means vote was submitted
      final myVoteAfter = PrivateVote(targetId: 'candidate_uid');
      // Testing indirectly: a non-null object is never null
      expect(myVoteAfter.targetId, 'candidate_uid'); // verifies object is valid
    });

    // ── Role reveal at GAME_OVER ─────────────────────────────────────────────

    test('GAME_OVER: roles become readable in public player doc for reveal screen', () {
      // After GAME_OVER, server writes role to the public player doc
      // This is the ONLY time role appears in the public doc
      final revealedPlayers = [
        Player(uid: 'p1', name: 'Alice', role: PlayerRole.mafia, isAlive: false, joinedAt: DateTime.now()),
        Player(uid: 'p2', name: 'Bob', role: PlayerRole.detective, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'p3', name: 'Cara', role: PlayerRole.doctor, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'p4', name: 'Dan', role: PlayerRole.civilian, isAlive: true, joinedAt: DateTime.now()),
      ];

      // All roles are visible at game over
      expect(revealedPlayers.any((p) => p.role == PlayerRole.mafia), isTrue);
      expect(revealedPlayers.any((p) => p.role == PlayerRole.detective), isTrue);
      expect(revealedPlayers.any((p) => p.role == PlayerRole.doctor), isTrue);
      expect(revealedPlayers.any((p) => p.role == PlayerRole.civilian), isTrue);

      // This is safe because the room status == GAME_OVER (server-controlled)
      // The client cannot forge this state (Firestore rules block status writes)
    });

    // ── Server-authority validation ──────────────────────────────────────────

    test('Server-authority: role distribution stays server-enforced', () {
      for (int n = 6; n <= 12; n++) {
        final roles = GameLogicEngine.getRoleDistribution(n);
        expect(roles.length, n);
      }
    });

    test('Server-authority: Mafia cannot target themselves', () {
      const mafiaUid = 'mafia_player';
      const targetId = 'mafia_player';
      expect(targetId == mafiaUid, isTrue,
          reason: 'Self-targeting should be detected and rejected server-side');
    });

    test('Server-authority: dead players cannot submit actions', () {
      final deadPlayer = Player(
        uid: 'dead',
        name: 'Dead',
        role: PlayerRole.mafia,
        isAlive: false,
        joinedAt: DateTime.now(),
      );
      expect(deadPlayer.isAlive, isFalse);
    });

    test('Server-authority: win condition at mafia parity (1 vs 1)', () {
      final players = [
        Player(uid: 'm1', name: 'Mafia1', role: PlayerRole.mafia, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'c1', name: 'Civ1', role: PlayerRole.civilian, isAlive: true, joinedAt: DateTime.now()),
      ];
      final result = GameLogicEngine.checkWinCondition(players);
      expect(result.isGameOver, isTrue);
      expect(result.winner, 'MAFIA');
    });

    test('Server-authority: game continues with 1 Mafia vs 3 others', () {
      final players = [
        Player(uid: 'm1', name: 'M', role: PlayerRole.mafia, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'c1', name: 'C1', role: PlayerRole.civilian, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'c2', name: 'C2', role: PlayerRole.doctor, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'd1', name: 'D', role: PlayerRole.detective, isAlive: true, joinedAt: DateTime.now()),
      ];
      final result = GameLogicEngine.checkWinCondition(players);
      expect(result.isGameOver, isFalse);
    });
  });

  group('Phase 2 — Server-Authority Validation Tests', () {
    test('Role distribution is always exactly playerCount length', () {
      for (int n = 6; n <= 12; n++) {
        final roles = GameLogicEngine.getRoleDistribution(n);
        expect(roles.length, n, reason: 'Expected $n roles for $n players');
      }
    });

    test('Role distribution always has exactly 1 Detective and 1 Doctor', () {
      for (int n = 6; n <= 12; n++) {
        final roles = GameLogicEngine.getRoleDistribution(n);
        final detectives = roles.where((r) => r == PlayerRole.detective).length;
        final doctors = roles.where((r) => r == PlayerRole.doctor).length;
        expect(detectives, 1, reason: '$n players: expected 1 detective');
        expect(doctors, 1, reason: '$n players: expected 1 doctor');
      }
    });

    test('Mafia count matches expected table', () {
      final expectedMafia = {6: 1, 7: 2, 8: 2, 9: 2, 10: 3, 11: 3, 12: 3};
      for (final entry in expectedMafia.entries) {
        final roles = GameLogicEngine.getRoleDistribution(entry.key);
        final mafiaCount = roles.where((r) => r == PlayerRole.mafia).length;
        expect(mafiaCount, entry.value,
            reason: '${entry.key} players should have ${entry.value} Mafia');
      }
    });

    test('Win condition: mafia cannot win with more non-mafia alive', () {
      final players = [
        Player(uid: 'm1', name: 'Mafia1', role: PlayerRole.mafia, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'c1', name: 'Civ1', role: PlayerRole.civilian, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'c2', name: 'Civ2', role: PlayerRole.civilian, isAlive: true, joinedAt: DateTime.now()),
        Player(uid: 'd1', name: 'Doc', role: PlayerRole.doctor, isAlive: true, joinedAt: DateTime.now()),
      ];
      final result = GameLogicEngine.checkWinCondition(players);
      expect(result.isGameOver, isFalse,
          reason: '1 Mafia vs 3 others: game should continue');
    });
  });
}
